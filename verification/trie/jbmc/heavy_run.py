#!/usr/bin/env python3
"""Resource-limited execution of heavy verification tools (JBMC, CBMC, Lean/lake).

Enforces the machine limits mechanically:
- one heavy-tool lock shared by every runner: at most HEAVY_JBMC_SLOTS JBMC processes at once OR one
  Lean/lake process, never mixed, never while a gradle process is running; the lock is a directory of
  slot files (default $TRIE_VERIFY/.tools/heavy-lock, override HEAVY_LOCK_DIR) holding the owner pid,
  and slots of dead owners are reclaimed; the whole check-and-acquire runs under an advisory flock on
  the lock directory itself, so two callers can never both pass the checks on the same empty queue;
- no new start while the 1-minute load average > HEAVY_MAX_LOAD or macOS memory pressure is warn or
  critical (sysctl kern.memorystatus_vm_pressure_level >= 2), or, when HEAVY_MIN_FREE_GB is set, while
  free+inactive memory (vm_stat) is below it, or, when HEAVY_MIN_FREE_PCT is set, while the system-wide
  free memory percentage (kern.memorystatus_level) is below it, or, when HEAVY_MIN_FREE_PCT_ADMIT is set,
  while it is below that admission threshold (each evaluation logged to HEAVY_ADMIT_LOG): the caller waits;
- every process runs under `nice -n 19` and, unless HEAVY_NO_TASKPOLICY=1, `taskpolicy -b` (background
  QoS: efficiency cores only on Apple silicon);
- a watchdog kills it above HEAVY_RSS_GB of resident memory (result "EXCEEDED_MEMORY", not a verdict)
  or after the timeout (result "TIMEOUT").

Defaults are this machine's limits (2 JBMC slots, 6 GB, load 8, 300 s); a second executor passes its
own through the environment. CLI, for other runners (e.g. the Lean build):
    heavy_run.py --tool lean [--timeout S] -- lake build
exit code: the tool's, or 124 on timeout, 137 on memory kill.
"""
import fcntl, json, os, subprocess, sys, tempfile, threading, time

TRIE_VERIFY = os.environ.get("TRIE_VERIFY", os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
LOCK_DIR = os.environ.get("HEAVY_LOCK_DIR", os.path.join(TRIE_VERIFY, ".tools", "heavy-lock"))
JBMC_SLOTS = int(os.environ.get("HEAVY_JBMC_SLOTS", "2"))
RSS_LIMIT_KB = int(float(os.environ.get("HEAVY_RSS_GB", "6")) * 1024 * 1024)
MAX_LOAD = float(os.environ.get("HEAVY_MAX_LOAD", "8"))
TIMEOUT = int(os.environ.get("HEAVY_TIMEOUT", "300"))
# optional memory admission: start only if free+inactive memory >= this many GB (0 = off, the default here)
MIN_FREE_KB = int(float(os.environ.get("HEAVY_MIN_FREE_GB", "0")) * 1024 * 1024)
# optional back-off: no new start while the system-wide free memory percentage (kern.memorystatus_level,
# the value `memory_pressure` prints) is below this (0 = off, the default here)
MIN_FREE_PCT = int(os.environ.get("HEAVY_MIN_FREE_PCT", "0"))
# optional admission: start a job only while that free percentage is >= this (0 = off, the default);
# every evaluation is appended to HEAVY_ADMIT_LOG (default <lock dir>/../admission.log) with its value
ADMIT_PCT = int(os.environ.get("HEAVY_MIN_FREE_PCT_ADMIT", "0"))
ADMIT_LOG = os.environ.get("HEAVY_ADMIT_LOG", os.path.join(os.path.dirname(LOCK_DIR), "admission.log"))
# optional: while that free percentage is below this, the most recently started job of this process is
# killed (status LOW_MEMORY, not a verdict), one at a time (0 = off, the default)
KILL_NEWEST_PCT = int(os.environ.get("HEAVY_KILL_NEWEST_PCT", "0"))
# Isolated candidate, not deployed/owner-approved: thermal guard and 1..3 configured slots required.
# Inbox057 permits the MacBook owner up to three light jobs after fresh resource checks.
# Slot count alone does not authorize admission. Thermal pressure denies admission, then 30 min quiet.
# A separate thermal-state mutex protects updates outside the admission transaction.
# Running-job thermal/swap protection remains an owner gate; this code does not provide it.
# The power log is only
# scanned after a new system sleep (kern.sleeptime changed); HEAVY_THERMAL_KNOWN_EMERGENCY names an
# emergency already handled when the state file is first created.
RESOURCE_PROFILE = os.environ.get("HEAVY_RESOURCE_PROFILE", "")
THERMAL_GUARD_PATH = os.environ.get("HEAVY_THERMAL_GUARD", "")
THERMAL_GUARD = THERMAL_GUARD_PATH not in ("", "0")
_ADMISSION = threading.local()
# opt-out of the background QoS clamp (nice -n 19 stays): HEAVY_NO_TASKPOLICY=1
TASKPOLICY = [] if (os.environ.get("HEAVY_TASKPOLICY") == "0" or os.environ.get("HEAVY_NO_TASKPOLICY", "0") == "1") else ["taskpolicy", "-b"]
THERMAL_QUIET_S = 1800
PROBE_TIMEOUT = 15
HISTORY_TIMEOUT = 180
ADMISSION_MAX_AGE = 5  # Reject a slow/stale sample; do not probe while holding admission flock.
CLEANUP_SECONDS = 5
MAX_OUTPUT_BYTES = 256 * 1024 * 1024  # Exceeding this is a collector error, never a Java verdict.
THERMAL_STATE = os.path.join(os.path.dirname(LOCK_DIR), "thermal-state.json")
THERMAL_LOG = os.path.join(os.path.dirname(LOCK_DIR), "thermal.log")
_RUNNING = {}  # job id -> start time, jobs of this process
_RUNNING_LOCK = threading.Lock()


def _alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def _holders():
    os.makedirs(LOCK_DIR, exist_ok=True)
    held = []
    for f in os.listdir(LOCK_DIR):
        p = os.path.join(LOCK_DIR, f)
        try:
            pid = int(open(p).read().strip())
        except (OSError, ValueError) as error:
            raise OSError("cannot establish slot ownership: %s" % p) from error
        if pid <= 0:
            raise OSError("invalid slot owner: %s" % p)
        if _alive(pid):
            held.append(f)
        else:
            raise OSError("dead slot owner requires explicit group/output custody review: %s" % p)
    return held


def _probe_text(argv, timeout=None):
    try:
        result = subprocess.run(argv, capture_output=True, text=True,
                                timeout=PROBE_TIMEOUT if timeout is None else timeout)
    except subprocess.SubprocessError as error:
        raise OSError("probe did not complete: %r" % argv) from error
    if result.returncode != 0 or not result.stdout.strip():
        raise OSError("failed or empty probe: %r" % argv)
    return result.stdout


def _pressure_ok():
    lvl = int(_probe_text(["sysctl", "-n", "kern.memorystatus_vm_pressure_level"]).strip())
    if lvl not in (1, 2, 4):
        raise ValueError("unrecognized memory-pressure level")
    return lvl == 1


def _free_ok():
    if not MIN_FREE_KB:
        return True
    out = _probe_text(["vm_stat"])
    page = int(out.split("page size of ")[1].split()[0])
    counts = {l.split(":")[0]: int(l.split(":")[1].strip().rstrip("."))
              for l in out.splitlines() if l.startswith(("Pages free:", "Pages inactive:"))}
    if set(counts) != {"Pages free", "Pages inactive"} or page <= 0 or min(counts.values()) < 0:
        raise ValueError("incomplete vm_stat sample")
    return sum(counts.values()) * page // 1024 >= MIN_FREE_KB


def _free_pct_ok():
    return not MIN_FREE_PCT or _free_level() >= MIN_FREE_PCT


def _free_level():
    """System-wide free memory percentage (kern.memorystatus_level, what memory_pressure prints),
    read with sysctlbyname so no process is started; -1 if unavailable."""
    try:
        import ctypes
        v = ctypes.c_uint32(0)
        n = ctypes.c_size_t(4)
        if ctypes.CDLL(None).sysctlbyname(b"kern.memorystatus_level", ctypes.byref(v), ctypes.byref(n), None, 0) == 0:
            if n.value != 4 or not 0 <= v.value <= 100:
                raise ValueError("invalid free-memory sample")
            return int(v.value)
    except (OSError, AttributeError):
        pass
    level = int(_probe_text(["sysctl", "-n", "kern.memorystatus_level"]).strip())
    if not 0 <= level <= 100:
        raise ValueError("invalid free-memory percentage")
    return level


def _admit_ok(tool):
    if not ADMIT_PCT:
        return True
    lvl = _free_level()
    ok = lvl >= ADMIT_PCT
    try:
        with open(ADMIT_LOG, "a") as f:
            f.write("%s pid=%d tool=%s free_pct=%d threshold=%d decision=%s\n"
                    % (time.strftime("%Y-%m-%dT%H:%M:%S"), os.getpid(), tool, lvl, ADMIT_PCT, "admit" if ok else "wait"))
    except OSError:
        pass
    return ok


def _last_sleep():
    """Time of the last system sleep (sysctl kern.sleeptime), read without scanning the power log."""
    import re
    out = _probe_text(["sysctl", "-n", "kern.sleeptime"])
    match = re.search(r"\bsec\s*=\s*(\d+)", out)
    if not match:
        raise ValueError("unrecognized sleep-time sample")
    return match[1]


def _last_thermal_emergency():
    """Timestamp of the last 'Thermal Emergency' sleep in pmset's log (slow: the log is large, so this
    runs only after a new system sleep)."""
    # Checked producer, no shell pipeline that can hide pmset failure. Preserve non-UTF8 events.
    with tempfile.TemporaryFile(mode="w+b") as log:
        subprocess.run(["pmset", "-g", "log"], stdout=log, stderr=subprocess.PIPE,
                       check=True, timeout=HISTORY_TIMEOUT)
        log.seek(0)
        last, nonempty = "", False
        for line in log:
            nonempty = nonempty or bool(line.strip())
            if b"thermal" in line.lower() and b"emergency" in line.lower():
                last = line.strip().decode("utf-8", errors="backslashreplace")
        if not nonempty:
            raise OSError("empty thermal history")
        return last


def _thermal_now(therm):
    """Parse current status without running the potentially long historical power-log scan."""
    import re
    speeds = re.findall(r"CPU[_\s]+Speed[_\s]+Limit\s*[:=]\s*(-?\d+)", therm, re.I)
    levels = re.findall(r"warning\s*level\s*[:=]\s*(-?\d+)", therm, re.I)
    if not speeds and not levels and "no thermal warning level has been recorded" not in therm.lower():
        raise ValueError("unrecognized thermal status")
    if any(not 0 <= int(speed) <= 100 for speed in speeds) or any(int(level) < 0 for level in levels):
        raise ValueError("invalid thermal/performance level")
    return any(int(speed) < 100 for speed in speeds) or any(int(level) > 0 for level in levels)


def _thermal_pressure(st):
    """(pressure?, reason), including history after a sleep; admission only."""
    if _thermal_now(_probe_text(["pmset", "-g", "therm"])):
        return True, "thermal/performance pressure"
    sl = _last_sleep()
    if sl and sl != st.get("last_sleep"):
        st["last_sleep"] = sl
        last = _last_thermal_emergency()
        if last and last != st.get("last_emergency"):
            st["last_emergency"] = last
            return True, "thermal emergency sleep at %s" % last
    return False, ""


def _thermal_cap():
    import json
    if RESOURCE_PROFILE == "void-rsk":
        # Reuse the local owner's existing state, cap1 and 30-minute recovery steps.
        # The caller supplies the same bounded guard.py path to both producers.
        if not os.path.isabs(THERMAL_GUARD_PATH) or not os.path.isfile(THERMAL_GUARD_PATH):
            raise OSError("local thermal guard path missing; no policy substitution")
        state = json.loads(_probe_text([sys.executable, THERMAL_GUARD_PATH, "--thermal-only"], timeout=210))
        if state.get("ok") is not True or type(state.get("jbmc_slots")) is not int or not 1 <= state["jbmc_slots"] <= 3:
            raise OSError("invalid local thermal state")
        return min(JBMC_SLOTS, state["jbmc_slots"])
    # A separate nonblocking state mutex, never the admission directory flock.
    with open(THERMAL_STATE + ".lock", "a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0
        try:
            st = json.load(open(THERMAL_STATE))
        except FileNotFoundError:
            st = {"cap": 0, "last_event": 0, "last_sleep": "",
                  "last_emergency": os.environ.get("HEAVY_THERMAL_KNOWN_EMERGENCY", "")}
        hot, why = _thermal_pressure(st)
        now, old = time.time(), st["cap"]
        if hot:
            st["last_event"] = now
        st["last_check"] = now
        st["cap"] = 0 if hot or now - st["last_event"] < THERMAL_QUIET_S else JBMC_SLOTS
        tmp = THERMAL_STATE + ".%d" % os.getpid()
        json.dump(st, open(tmp, "w"))
        os.replace(tmp, THERMAL_STATE)
        if st["cap"] != old or hot:
            with open(THERMAL_LOG, "a") as f:
                f.write("%s pid=%d cap %d -> %d reason=%s\n" %
                        (time.strftime("%Y-%m-%dT%H:%M:%S"), os.getpid(), old, st["cap"], why))
        return st["cap"]


def _gradle_running():
    # Brackets prevent concurrent pgrep probes from matching each other's argv.
    r = subprocess.run(["pgrep", "-f", "[G]radleDaemon|[G]radleWrapperMain|[g]radle-launcher"],
                       capture_output=True, timeout=PROBE_TIMEOUT)
    if r.returncode not in (0, 1):
        raise OSError("Gradle probe failed")
    return r.returncode == 0


def acquire(tool, poll=10):
    """Blocks until a slot for `tool` ("jbmc" or "lean") is free and the machine is not loaded."""
    while True:
        slot = _try_acquire(tool)
        if slot:
            return slot
        time.sleep(poll)


def _resource_sample():
    """Two bounded local probes, never under the admission flock. No heavy/version command."""
    import math
    import re
    start = time.monotonic()
    raw = _probe_text(["/usr/sbin/sysctl", "-n", "kern.memorystatus_vm_pressure_level",
                       "kern.memorystatus_level", "vm.swapusage", "kern.sleeptime"], timeout=1)
    lines = raw.strip().splitlines()
    if len(lines) != 4:
        raise ValueError("incomplete local resource sample")
    pressure, free = int(lines[0]), int(lines[1])
    if pressure not in (1, 2, 4) or not 0 <= free <= 100:
        raise ValueError("invalid pressure/free-memory sample")
    swap = re.fullmatch(r"total\s*=\s*(\d+(?:\.\d+)?)([KMGT])\s+used\s*=\s*(\d+(?:\.\d+)?)([KMGT])\s+free\s*=\s*(\d+(?:\.\d+)?)([KMGT])(?:\s+\(encrypted\))?", lines[2].strip())
    sleep = re.fullmatch(r"\{\s*sec\s*=\s*(\d+),\s*usec\s*=\s*(\d+)\s*\}(?:\s+(.+))?", lines[3].strip())
    if swap is None or sleep is None or int(sleep[2]) >= 1000000:
        raise ValueError("invalid swap/sleep sample")
    if sleep[3]:
        time.strptime(sleep[3], "%a %b %d %H:%M:%S %Y")  # Optional BSD ctime presentation.
    values = [float(swap[i]) * 1024 ** ("KMGT".index(swap[i+1])+1) for i in (1,3,5)]
    if not all(math.isfinite(v) for v in values) or abs(values[0]-values[1]-values[2]) > 0.02 * max(1024 ** ("KMGT".index(swap[i])+1) for i in (2,4,6)):
        raise ValueError("inconsistent swap sample")
    thermal = _probe_text(["/usr/bin/pmset", "-g", "therm"], timeout=1)
    load = os.getloadavg()[0]
    if not math.isfinite(load) or load < 0 or time.monotonic() - start > ADMISSION_MAX_AGE:
        raise ValueError("invalid/stale CPU/resource sample")
    return dict(at=time.monotonic(), pressure=pressure, free_pct=free, swap_used=values[1],
                sleep=sleep[1], hot=_thermal_now(thermal), load=load,
                raw_sysctl=raw, raw_thermal=thermal)


def _resources_safe(sample, floor, initial=None):
    # Local thermal pressure reduces new admission to cap1; it does not kill admitted jobs.
    # It is still parsed/recorded on every running sample. Other profiles retain their gate.
    return (sample["pressure"] == 1 and sample["free_pct"] >= floor
            and (RESOURCE_PROFILE == "void-rsk" or not sample["hot"])
            and sample["load"] <= MAX_LOAD and 0 <= time.monotonic()-sample["at"] <= ADMISSION_MAX_AGE
            and (initial is None or (sample["swap_used"] <= initial["swap_used"]
                                     and sample["sleep"] == initial["sleep"])))


def _owner_resources_ready():
    """Explicit void-rsk profile proposal; deployment/caller custody remains with the owner."""
    if RESOURCE_PROFILE != "void-rsk":
        raise OSError("on-host resource/watchdog adapter not approved; isolated candidate cannot launch")
    first = _resource_sample()
    if not _resources_safe(first, ADMIT_PCT):
        return False
    time.sleep(0.1)
    second = _resource_sample()
    if not _resources_safe(second, ADMIT_PCT, first):
        return False
    _ADMISSION.sample = second
    return True


def _try_acquire(tool):
    """One check-and-acquire transaction under an exclusive flock on LOCK_DIR (the same directory every
    caller of this queue locks, whichever program it belongs to): the holder checks, the admission check
    and the slot creation cannot interleave with another caller's. Returns the slot path or None."""
    if tool not in ("lean", "jbmc") or not 1 <= JBMC_SLOTS <= 3 or not THERMAL_GUARD:
        raise OSError("isolated candidate requires owner-configured 1..3 slots and thermal monitoring")
    if RESOURCE_PROFILE == "void-rsk":
        if not (40 <= ADMIT_PCT <= 100 and 0 < RSS_LIMIT_KB <= 12 * 1024**2
                and TIMEOUT == 600 and 0 < MAX_LOAD <= 32 and 15 <= MIN_FREE_PCT <= ADMIT_PCT):
            raise OSError("void-rsk requires >=40% admission, at most12GiB/job,600s,load<=32 and>=15% running floor")
    elif ADMIT_PCT != 41 or RSS_LIMIT_KB != 8 * 1024 * 1024 or TIMEOUT != 600:
        raise OSError("MacBook candidate requires unchanged 41% admission, 8GiB/job and 600s watchdog")
    os.makedirs(LOCK_DIR, exist_ok=True)
    # Slow history precedes fresh resource sampling, outside the admission flock.
    cap = _thermal_cap()
    if not cap:
        return None
    sampled_at = time.monotonic()
    if not _owner_resources_ready():
        return None
    if not (os.getloadavg()[0] <= MAX_LOAD and _pressure_ok() and _free_ok()
            and _free_pct_ok() and not _gradle_running() and _admit_ok(tool)):
        return None
    dfd = os.open(LOCK_DIR, os.O_RDONLY)
    try:
        fcntl.flock(dfd, fcntl.LOCK_EX)
        if time.monotonic() - sampled_at > ADMISSION_MAX_AGE:
            return None
        held = _holders()
        lean = [h for h in held if h.startswith("lean")]
        jbmc = [h for h in held if h.startswith("jbmc")]
        if any(h not in ["jbmc.%d" % i for i in range(cap)] for h in jbmc):
            return None  # Drain higher-numbered holders without killing admitted jobs.
        if tool == "lean" and not held:
            names = ["lean"]
        elif tool == "jbmc" and not lean and len(jbmc) < cap:
            names = ["jbmc.%d" % i for i in range(JBMC_SLOTS)]
        else:
            return None
        for n in names:
            p = os.path.join(LOCK_DIR, n)
            try:
                fd = os.open(p, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            except FileExistsError:
                continue
            os.write(fd, str(os.getpid()).encode())
            os.close(fd)
            return p
        return None
    finally:
        os.close(dfd)  # releases the flock


_libproc = None


def _pids(kind, ident):
    """libproc PROC_PGRP_ONLY=2 / PROC_PPID_ONLY=6. Counts are bytes, not PIDs."""
    import ctypes
    global _libproc
    if _libproc is None:
        _libproc = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    width = ctypes.sizeof(ctypes.c_int)
    size = _libproc.proc_listpids(kind, ident, None, 0)
    if size < 0 or size % width or size > 4 * 65536:
        raise OSError("invalid PID enumeration size")
    pids = (ctypes.c_int * (size // width + 64))()
    count = _libproc.proc_listpids(kind, ident, pids, ctypes.sizeof(pids))
    if count < 0 or count >= ctypes.sizeof(pids) or count % width:
        raise OSError("failed or truncated PID enumeration")
    members = set(pids[:count // width]) - {0}
    if any(pid < 0 for pid in members):
        raise OSError("invalid PID enumeration member")
    return members


def _exited(pid, diagnostic=None):
    """An unreadable process is not free memory unless its exit is confirmed."""
    try:
        os.kill(pid, 0)
    except ProcessLookupError as error:
        if diagnostic is not None:
            diagnostic["signal0"] = {"result": "ESRCH", "errno": error.errno}
        return True
    except OSError as error:
        if diagnostic is not None:
            diagnostic["signal0"] = {"result": "error", "errno": error.errno}
        raise
    if diagnostic is not None:
        diagnostic["signal0"] = {"result": "success"}
    try:
        result = os.waitid(os.P_PID, pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
    except (AttributeError, OSError) as error:
        if diagnostic is not None:
            diagnostic["waitid"] = {"result": "unavailable" if isinstance(error, AttributeError)
                                    else "error", "errno": getattr(error, "errno", None)}
        return False
    if diagnostic is not None:
        diagnostic["waitid"] = {"result": "none"} if result is None else {
            "result": "returned", "si_pid": result.si_pid, "si_code": result.si_code}
    return (result is not None and result.si_pid == pid
            and result.si_code in (os.CLD_EXITED, os.CLD_KILLED, os.CLD_DUMPED))


def _rss_kb(pgid, observed=None, reap=None, diagnostics=None, phase="unspecified"):
    """Sum the job group and walk descendant relationships without spawning ps.
    Reject observed descendants outside the group: group kill cannot contain them.
    Sampling cannot recover already-detached/reparented children; commands must not daemonize.
    Based on the existing owner's retained group-RSS implementation (owner-reference/)."""
    import ctypes
    members = _pids(2, pgid)
    if observed is not None:
        observed.update(members)
    if not members:
        if not _group_exists(pgid, reap):
            return 0
        raise OSError("empty RSS enumeration for a live process group")
    pending = list(members)
    deadline = time.monotonic() + 5
    while pending:
        if len(members) > 65536 or time.monotonic() > deadline:
            raise OSError("descendant enumeration exceeded its bound")
        children = _pids(6, pending.pop()) - members
        members.update(children)
        if observed is not None:
            observed.update(children)
        pending.extend(children)
    group = _pids(2, pgid)
    if observed is not None:
        observed.update(group)
    if group - members:
        raise OSError("process group grew during RSS sample; incomplete membership")
    for pid in members - group:
        if not _exited(pid):
            raise OSError("live descendant escaped the protected process group: %d" % pid)
    total = 0
    for pid in sorted(members):
        if time.monotonic() > deadline:
            raise OSError("RSS sample exceeded its bound")
        buf = ctypes.create_string_buffer(96)  # PROC_PIDTASKINFO; resident bytes at offset 8.
        read_at = time.monotonic()
        ctypes.set_errno(0)
        returned = _libproc.proc_pidinfo(pid, 4, ctypes.c_uint64(0), buf, 96)
        read_errno = ctypes.get_errno()  # Before any further native call or exit check.
        exit_check = {} if returned != 96 else None
        if diagnostics is not None:
            diagnostics.append(dict(pid=pid, root_pid=pgid, group_id=pgid,
                                    in_group=pid in group, flavor=4, size=96, at=read_at,
                                    phase=phase[:32], returned=returned, errno=read_errno,
                                    exit_check=exit_check))
            del diagnostics[:-16]  # Fixed-size scalar records; retain the failing read.
        if returned == 96:
            total += int.from_bytes(buf.raw[8:16], "little")
        elif not _exited(pid, exit_check):
            if diagnostics is not None:
                # Observe one same-PID transition, never repair the rejected sample.
                followup = dict(pid=pid, flavor=4, size=96, deadline=deadline,
                                attempted=False)
                diagnostics[-1]["recheck"] = followup
                retry_buf = ctypes.create_string_buffer(96)
                followup["at"] = time.monotonic()
                if followup["at"] < deadline:
                    followup["attempted"] = True
                    try:
                        ctypes.set_errno(0)
                        retry_return = _libproc.proc_pidinfo(pid, 4, ctypes.c_uint64(0), retry_buf, 96)
                        retry_errno = ctypes.get_errno()
                        retry_exit = {} if retry_return != 96 else None
                        followup.update(returned=retry_return, errno=retry_errno,
                                        exit_check=retry_exit)
                        if retry_return != 96:
                            followup["exit_confirmed"] = _exited(pid, retry_exit)
                    except (OSError, AttributeError) as error:
                        followup["error"] = dict(type=type(error).__name__[:64],
                                                errno=getattr(error, "errno", None))
            raise OSError("RSS unreadable; exit unconfirmed for group member %d" % pid)
    return total // 1024


def _group_exists(pgid, reap=None):
    """Darwin may briefly return EPERM during exit. Only success/ESRCH resolves it."""
    deadline = time.monotonic() + min(0.05, CLEANUP_SECONDS)
    while True:
        try:
            os.killpg(pgid, 0)
            return True
        except ProcessLookupError:
            return False
        except PermissionError:
            # Reap only the caller's own root, nonblocking; never infer group death from EPERM.
            if reap is not None:
                reap()
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.005)


def _group_state(pgid, observed, reap=None):
    """Track known survivors without signalling individual PIDs (which may have been reused)."""
    group = set()
    if _group_exists(pgid, reap):
        group = _pids(2, pgid)
        if not group:
            raise OSError("live group has empty enumeration")
    observed.update(group)
    if len(observed) > 65536:
        raise OSError("observed descendant bound exceeded")
    deadline = time.monotonic() + CLEANUP_SECONDS
    live = set()
    for pid in observed:
        if time.monotonic() > deadline:
            raise OSError("group exit check exceeded its bound")
        if not _exited(pid):
            live.add(pid)
    return live & group, live - group


def _drain_output(pipe, out):
    """Bound each nonblocking drain so output cannot starve monitoring; return actual pipe EOF."""
    for _ in range(64):
        try:
            data = os.read(pipe.fileno(), 65536)
        except BlockingIOError:
            return False
        except InterruptedError:
            continue
        if not data:
            return True
        out.write(data)  # Preserve bytes already read, including the final over-limit chunk.
        if out.tell() > MAX_OUTPUT_BYTES:
            raise OSError("collector output limit exceeded")
    return False


def run(cmd, tool="jbmc", timeout=None, capture_receipt=None, raw_output_path=None):
    """Five-field legacy return; optional receipt records custody, not reviewer approval.

    OK requires reaped root, no known live descendants and pipe EOF. Unknown cleanup retains a
    non-PID quarantine marker, which _holders rejects even after this wrapper exits. Polling cannot
    detect a never-observed detached descendant that closed stdout; command containment stays an
    explicit owner gate. Group-only signals are NOT claimed to terminate observed escaped children.
    """
    import hashlib
    import math
    import select
    receipt = capture_receipt if capture_receipt is not None else {}
    receipt.clear()
    receipt.update(schema="trie-process-custody.v1", state="NOT_STARTED", argv=list(cmd),
                   runtime_acceptance="OPEN", rss_diagnostics=[])
    try:
        timeout = min(float(TIMEOUT), float(TIMEOUT if timeout is None else timeout))
        if not math.isfinite(timeout) or timeout <= 0:
            raise ValueError("invalid watchdog timeout")
        slot = acquire(tool)
    except (OSError, ValueError, IndexError, KeyError, TypeError, subprocess.SubprocessError) as error:
        return "MONITOR_ERROR", 125, "heavy_run: unsafe admission: %s\n" % error, 0, 0
    p, timer, out = None, None, None
    start = time.monotonic()
    peak, text, raw = 0, "", b""
    killed, observed, errors = {}, set(), []
    eof, custody, output_error, finished = False, False, False, False
    root_done_at = None
    kill_lock = threading.Lock()

    def record_error(message):
        message = message[:2048]
        if message not in errors and len(errors) < 16:
            errors.append(message)

    def kill(why):
        # A root may have exited while its process group still runs. Never gate this on poll().
        with kill_lock:
            if finished or p is None:
                return
            if not killed:
                killed.update(status=why, at=time.monotonic())
            try:
                os.killpg(p.pid, 9)
            except ProcessLookupError:
                pass
            except Exception as error:
                record_error("group kill failed: %s" % error)

    try:
        # Fresh durable spool survives cancellation/read errors; caller retains it with the receipt.
        stream = (tempfile.NamedTemporaryFile(mode="w+b", prefix="trie-heavy-", suffix=".raw", delete=False)
                  if raw_output_path is None else
                  os.fdopen(os.open(raw_output_path, os.O_RDWR | os.O_CREAT | os.O_EXCL, 0o600), "w+b"))
        with stream as out:
            receipt["raw_output_path"] = out.name if raw_output_path is None else os.path.abspath(os.fspath(raw_output_path))
            if RESOURCE_PROFILE == "void-rsk":
                initial = dict(_ADMISSION.sample)
                if not _resources_safe(initial, ADMIT_PCT):
                    raise OSError("local admission sample expired before launch")
                receipt.update(resource_profile=RESOURCE_PROFILE, resource_admission=initial,
                               resource_samples=[], policy=dict(slots=JBMC_SLOTS, admit_pct=ADMIT_PCT,
                               running_free_pct=MIN_FREE_PCT, rss_limit_kb=RSS_LIMIT_KB,
                               max_load=MAX_LOAD, watchdog_seconds=TIMEOUT))
            p = subprocess.Popen(["nice", "-n", "19"] + TASKPOLICY + cmd,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 bufsize=0, start_new_session=True)
            observed.add(p.pid)
            os.set_blocking(p.stdout.fileno(), False)
            timer = threading.Timer(timeout, kill, ("TIMEOUT",))
            timer.daemon = True
            timer.start()
            with _RUNNING_LOCK:
                _RUNNING[p.pid] = start
            next_sample = start
            while True:
                now = time.monotonic()
                root_done = p.poll() is not None
                if root_done and root_done_at is None:
                    root_done_at = now
                if now - start >= timeout and not killed:
                    kill("TIMEOUT")
                try:
                    if not eof:
                        eof = _drain_output(p.stdout, out)
                except Exception as error:
                    output_error = True
                    record_error("output: %s" % error)
                    kill("MONITOR_ERROR")
                try:
                    live, escaped = _group_state(p.pid, observed, p.poll)
                    if escaped:
                        raise OSError("known descendants outside group remain live: %s" % sorted(escaped))
                    if root_done and live:
                        raise OSError("root exited with live group members: %s" % sorted(live))
                    if not killed and now >= next_sample:
                        rss = _rss_kb(p.pid, observed, p.poll,
                                      receipt["rss_diagnostics"], "pre-resource")
                        peak = max(peak, rss)
                        if rss > RSS_LIMIT_KB:
                            kill("EXCEEDED_MEMORY")
                        if not killed and RESOURCE_PROFILE == "void-rsk":
                            sample = _resource_sample()
                            receipt["resource_samples"].append(sample)
                            if not _resources_safe(sample, MIN_FREE_PCT, initial):
                                raise OSError("running CPU/thermal/pressure/free-memory/swap/sleep gate failed")
                            peak = max(peak, _rss_kb(p.pid, observed, p.poll,
                                                     receipt["rss_diagnostics"], "post-resource"))
                        if peak > RSS_LIMIT_KB:
                            kill("EXCEEDED_MEMORY")
                        if KILL_NEWEST_PCT and _free_level() < KILL_NEWEST_PCT:
                            with _RUNNING_LOCK:
                                if max(_RUNNING, key=_RUNNING.get) == p.pid:
                                    kill("LOW_MEMORY")
                        next_sample = time.monotonic() + 1
                    if root_done and not live and eof:
                        custody = True
                        break
                except Exception as error:
                    record_error("monitor: %s: %s" % (type(error).__name__, error))
                    kill("MONITOR_ERROR")
                if ((killed and time.monotonic() - killed["at"] >= CLEANUP_SECONDS)
                        or (root_done_at is not None and time.monotonic() - root_done_at >= CLEANUP_SECONDS)):
                    record_error("bounded group/output cleanup not established")
                    kill("MONITOR_ERROR")
                    break
                if eof:
                    time.sleep(0.01)
                else:
                    select.select([p.stdout], [], [], 0.01)
            out.seek(0)
            raw = out.read()
            try:
                text = raw.decode("utf-8", errors="strict")
            except UnicodeError as error:
                output_error = True
                record_error("non-UTF8 output: %s" % error)
                text = raw.decode("utf-8", errors="backslashreplace")
    except BaseException as error:
        output_error = True
        record_error("collector setup/read: %s: %s" % (type(error).__name__, error))
        kill("MONITOR_ERROR")
    finally:
        # The context manager closes/flushed the spool even on cancellation. Recover raw bytes
        # before returning; no decoding or diagnostic framing can replace the original file.
        if out is not None:
            try:
                with open(receipt["raw_output_path"], "rb") as retained:
                    raw = retained.read()
                try:
                    text = raw.decode("utf-8", errors="strict")
                except UnicodeError as error:
                    output_error = True
                    record_error("non-UTF8 output: %s" % error)
                    text = raw.decode("utf-8", errors="backslashreplace")
            except BaseException as error:
                output_error = True
                record_error("retained output read failed: %s" % error)
        # Serialize with an already-started watchdog callback before closing/releasing anything.
        with kill_lock:
            finished = True
        if timer is not None:
            timer.cancel()
        if p is not None:
            with _RUNNING_LOCK:
                _RUNNING.pop(p.pid, None)
            if p.stdout is not None:
                p.stdout.close()
        if custody or p is None:
            os.unlink(slot)
        else:
            # Never allow dead-owner reclamation to turn uncertain cleanup into a free slot.
            with open(slot, "w") as hold:
                hold.write("QUARANTINED: group/output custody unresolved; owner intervention required\n")
                hold.flush()
                os.fsync(hold.fileno())
        receipt.update(state="COMPLETE" if custody and not output_error else "INCOMPLETE",
                       root_exit_code=None if p is None else p.returncode,
                       output_eof=eof, known_descendants_closed=custody,
                       slot_released=custody or p is None, observed_pids=sorted(observed),
                       output_bytes=len(raw), output_sha256=hashlib.sha256(raw).hexdigest(),
                       watchdog_seconds=timeout, errors=list(dict.fromkeys(errors)))
    elapsed = round(time.monotonic() - start, 3)
    status = "MONITOR_ERROR" if errors or not custody else killed.get("status", "OK")
    receipt.update(guard_status=status, elapsed_seconds=elapsed)
    if killed:
        text += "\nheavy_run: %s kill requested\n" % killed["status"]
    if errors:
        text += "\nheavy_run: MONITOR_ERROR: %s\n" % "; ".join(dict.fromkeys(errors))
    code = p.returncode if p is not None and p.returncode is not None else 125
    return status, code, text, peak, elapsed


def checked_output(argv):
    """Version/preparation query through the exclusive shared slot; no nested lease."""
    status, code, text, peak, elapsed = run(argv, tool="lean")
    if status != "OK" or code != 0 or not text.strip():
        raise OSError("guarded query failed: %r / %s / %s" % (argv, status, code))
    return text.strip()


if __name__ == "__main__":
    args = sys.argv[1:]
    tool, timeout = "jbmc", None
    while args and args[0] != "--":
        if args[0] == "--tool":
            tool, args = args[1], args[2:]
        elif args[0] == "--timeout":
            timeout, args = int(args[1]), args[2:]
        else:
            sys.exit("usage: heavy_run.py [--tool jbmc|lean] [--timeout S] -- command...")
    receipt = {}
    status, code, output, peak, dt = run(args[1:], tool, timeout, capture_receipt=receipt)
    if receipt.get("raw_output_path"):
        receipt_path = receipt["raw_output_path"] + ".custody.json"
        try:
            with open(receipt_path, "x") as capture:
                json.dump(receipt, capture, indent=2)
                capture.write("\n")
                capture.flush()
                os.fsync(capture.fileno())
            sys.stderr.write("heavy_run: custody_receipt=%s\n" % receipt_path)
        except OSError as error:
            status = "MONITOR_ERROR"
            sys.stderr.write("heavy_run: custody receipt failed: %s\n" % error)
    sys.stdout.write(output)
    sys.stderr.write("heavy_run: status=%s exit=%s peak_rss_kb=%d time_s=%s\n" % (status, code, peak, dt))
    sys.exit(124 if status == "TIMEOUT" else 137 if status in ("EXCEEDED_MEMORY", "LOW_MEMORY") else 125 if status == "MONITOR_ERROR" else code)
