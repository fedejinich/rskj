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
- every process runs under `nice -n 19` and `taskpolicy -b`;
- a watchdog kills it above HEAVY_RSS_GB of resident memory (result "EXCEEDED_MEMORY", not a verdict)
  or after the timeout (result "TIMEOUT").

Defaults are this machine's limits (2 JBMC slots, 6 GB, load 8, 300 s); a second executor passes its
own through the environment. CLI, for other runners (e.g. the Lean build):
    heavy_run.py --tool lean [--timeout S] -- lake build
exit code: the tool's, or 124 on timeout, 137 on memory kill.
"""
import fcntl, os, subprocess, sys, tempfile, threading, time

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
# optional thermal guard (HEAVY_THERMAL_GUARD=1): the JBMC cap drops to 1 on thermal pressure (a
# thermal/performance warning in `pmset -g therm`, CPU_Speed_Limit < 100, or a new "Thermal Emergency"
# sleep in `pmset -g log`) and steps back up by one after every 30 minutes without an event, never above
# HEAVY_JBMC_SLOTS. The state is shared by every caller of this lock (thermal-state.json next to it) and
# each change is appended to thermal.log. Running jobs are never killed by it. The power log is only
# scanned after a new system sleep (kern.sleeptime changed); HEAVY_THERMAL_KNOWN_EMERGENCY names an
# emergency already handled when the state file is first created.
THERMAL_GUARD = os.environ.get("HEAVY_THERMAL_GUARD", "0") == "1"
THERMAL_QUIET_S = 1800
THERMAL_STATE = os.path.join(os.path.dirname(LOCK_DIR), "thermal-state.json")
THERMAL_LOG = os.path.join(os.path.dirname(LOCK_DIR), "thermal.log")
_RUNNING = {}  # job id -> start time, jobs of this process
_RUNNING_LOCK = threading.Lock()


def _alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def _holders():
    os.makedirs(LOCK_DIR, exist_ok=True)
    held = []
    for f in os.listdir(LOCK_DIR):
        p = os.path.join(LOCK_DIR, f)
        try:
            pid = int(open(p).read().strip() or 0)
        except (OSError, ValueError):
            pid = 0
        if pid and _alive(pid):
            held.append(f)
        else:
            try:
                os.unlink(p)  # stale slot of a dead owner
            except OSError:
                pass
    return held


def _pressure_ok():
    try:
        lvl = int(subprocess.run(["sysctl", "-n", "kern.memorystatus_vm_pressure_level"],
                                 capture_output=True, text=True).stdout.strip() or 1)
    except (OSError, ValueError):
        lvl = 1
    return lvl < 2


def _free_ok():
    if not MIN_FREE_KB:
        return True
    out = subprocess.run(["vm_stat"], capture_output=True, text=True).stdout
    page = int(out.split("page size of ")[1].split()[0])
    pages = sum(int(l.split(":")[1].strip().rstrip(".")) for l in out.splitlines()
                if l.startswith(("Pages free:", "Pages inactive:")))
    return pages * page // 1024 >= MIN_FREE_KB


def _free_pct_ok():
    if not MIN_FREE_PCT:
        return True
    try:
        lvl = int(subprocess.run(["sysctl", "-n", "kern.memorystatus_level"],
                                 capture_output=True, text=True).stdout.strip())
    except (OSError, ValueError):
        return False  # cannot read it: do not start
    return lvl >= MIN_FREE_PCT


def _free_level():
    """System-wide free memory percentage (kern.memorystatus_level, what memory_pressure prints),
    read with sysctlbyname so no process is started; -1 if unavailable."""
    try:
        import ctypes
        v = ctypes.c_uint32(0)
        n = ctypes.c_size_t(4)
        if ctypes.CDLL(None).sysctlbyname(b"kern.memorystatus_level", ctypes.byref(v), ctypes.byref(n), None, 0) == 0:
            return int(v.value)
    except (OSError, AttributeError):
        pass
    try:
        return int(subprocess.run(["sysctl", "-n", "kern.memorystatus_level"],
                                  capture_output=True, text=True).stdout.strip())
    except (OSError, ValueError):
        return -1


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
    out = subprocess.run(["sysctl", "-n", "kern.sleeptime"], capture_output=True, text=True).stdout
    return out.split("sec = ")[1].split(",")[0] if "sec = " in out else ""


def _last_thermal_emergency():
    """Timestamp of the last 'Thermal Emergency' sleep in pmset's log (slow: the log is large, so this
    runs only after a new system sleep)."""
    out = subprocess.run(["sh", "-c", "pmset -g log | grep -i 'thermal emergency' | tail -1"],
                         capture_output=True, text=True).stdout.strip()
    return out[:25].strip()


def _thermal_pressure(st):
    """(pressure?, reason) from pmset; updates st["last_sleep"] / st["last_emergency"]."""
    import re
    therm = subprocess.run(["pmset", "-g", "therm"], capture_output=True, text=True).stdout
    m = re.search(r"CPU_Speed_Limit\s*=\s*(\d+)", therm)
    if m and int(m.group(1)) < 100:
        return True, "CPU_Speed_Limit=%s" % m.group(1)
    for l in therm.splitlines():
        if "warning level" in l.lower() and not l.strip().lower().startswith("note: no "):
            return True, l.strip()
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
    now = time.time()
    try:
        st = json.load(open(THERMAL_STATE))
    except (OSError, ValueError):
        st = {"cap": JBMC_SLOTS, "last_event": 0, "last_step": 0, "last_check": 0, "last_sleep": "",
              "last_emergency": os.environ.get("HEAVY_THERMAL_KNOWN_EMERGENCY", "")}
    if now - st.get("last_check", 0) < 60:
        return min(st["cap"], JBMC_SLOTS)
    st["last_check"] = now
    hot, why = _thermal_pressure(st)
    old = st["cap"]
    if hot:
        st["cap"], st["last_event"] = 1, now
    elif st["cap"] < JBMC_SLOTS and now - max(st["last_event"], st["last_step"]) >= THERMAL_QUIET_S:
        st["cap"], st["last_step"] = st["cap"] + 1, now
    st["cap"] = min(st["cap"], JBMC_SLOTS)
    tmp = THERMAL_STATE + ".%d" % os.getpid()
    json.dump(st, open(tmp, "w"))
    os.replace(tmp, THERMAL_STATE)
    if st["cap"] != old or hot:
        with open(THERMAL_LOG, "a") as f:
            f.write("%s pid=%d cap %d -> %d%s\n" % (time.strftime("%Y-%m-%dT%H:%M:%S"), os.getpid(), old, st["cap"],
                                                     " (%s)" % why if hot else " (30 min without thermal events)"))
    return st["cap"]


def _gradle_running():
    r = subprocess.run(["pgrep", "-f", "GradleDaemon|GradleWrapperMain|gradle-launcher"], capture_output=True)
    return r.returncode == 0


def acquire(tool, poll=10):
    """Blocks until a slot for `tool` ("jbmc" or "lean") is free and the machine is not loaded."""
    while True:
        if os.getloadavg()[0] <= MAX_LOAD and _pressure_ok() and _free_ok() and _free_pct_ok() and not _gradle_running():
            slot = _try_acquire(tool)
            if slot:
                return slot
        time.sleep(poll)


def _try_acquire(tool):
    """One check-and-acquire transaction under an exclusive flock on LOCK_DIR (the same directory every
    caller of this queue locks, whichever program it belongs to): the holder checks, the admission check
    and the slot creation cannot interleave with another caller's. Returns the slot path or None."""
    os.makedirs(LOCK_DIR, exist_ok=True)
    dfd = os.open(LOCK_DIR, os.O_RDONLY)
    try:
        fcntl.flock(dfd, fcntl.LOCK_EX)
        held = _holders()
        lean = [h for h in held if h.startswith("lean")]
        jbmc = [h for h in held if h.startswith("jbmc")]
        cap = _thermal_cap() if THERMAL_GUARD and tool == "jbmc" else JBMC_SLOTS
        if tool == "lean" and not held:
            names = ["lean"]
        elif tool == "jbmc" and not lean and len(jbmc) < cap:
            names = ["jbmc.%d" % i for i in range(JBMC_SLOTS)]
        else:
            return None
        if not _admit_ok(tool):  # evaluated right before a start that would otherwise happen
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


def _rss_kb(pid):
    """Resident memory of pid in KB, read from the kernel (libproc proc_pidinfo PROC_PIDTASKINFO)
    without starting a process: spawning `ps` every second can stall for minutes when an endpoint
    security agent inspects each exec, which used to delay the timeout check too. Falls back to ps."""
    global _libproc
    try:
        import ctypes
        if _libproc is None:
            _libproc = ctypes.CDLL("/usr/lib/libproc.dylib")
        buf = ctypes.create_string_buffer(96)  # struct proc_taskinfo; pti_resident_size at offset 8
        if _libproc.proc_pidinfo(pid, 4, ctypes.c_uint64(0), buf, 96) == 96:
            return int.from_bytes(buf.raw[8:16], "little") // 1024
        return 0
    except (OSError, AttributeError):
        r = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True)
        try:
            return int(r.stdout.strip() or 0)
        except ValueError:
            return 0


def run(cmd, tool="jbmc", timeout=None):
    """Runs cmd under the limits. Returns (status, exit_code, output, peak_rss_kb, seconds) with status
    one of "OK" (finished, any exit code), "TIMEOUT", "EXCEEDED_MEMORY", "LOW_MEMORY" (see
    HEAVY_KILL_NEWEST_PCT). The deadline kill is a timer
    independent of the memory poll, and it kills the whole process group. For a killed run, seconds is
    the time the kill was sent; how long the process took to exit afterwards is appended to the output."""
    timeout = timeout or TIMEOUT
    slot = acquire(tool)
    try:
        with tempfile.TemporaryFile(mode="w+") as out:
            t0 = time.time()
            p = subprocess.Popen(["nice", "-n", "19", "taskpolicy", "-b"] + cmd,
                                 stdout=out, stderr=subprocess.STDOUT, text=True, start_new_session=True)
            killed = {}

            def kill(why):
                if p.poll() is None and not killed:
                    killed.update(status=why, at=round(time.time() - t0, 2))
                    try:
                        os.killpg(p.pid, 9)
                    except OSError:
                        pass

            timer = threading.Timer(timeout, kill, ("TIMEOUT",))
            timer.daemon = True
            timer.start()
            with _RUNNING_LOCK:
                _RUNNING[p.pid] = t0
            peak = 0
            while p.poll() is None:
                rss = _rss_kb(p.pid)
                peak = max(peak, rss)
                if rss > RSS_LIMIT_KB:
                    kill("EXCEEDED_MEMORY")
                    break
                if KILL_NEWEST_PCT and 0 <= _free_level() < KILL_NEWEST_PCT:
                    with _RUNNING_LOCK:
                        newest = max(_RUNNING, key=_RUNNING.get) == p.pid
                        if newest:
                            del _RUNNING[p.pid]
                    if newest:
                        kill("LOW_MEMORY")
                        break
                try:
                    p.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    pass
            p.wait()
            timer.cancel()
            with _RUNNING_LOCK:
                _RUNNING.pop(p.pid, None)
            end = round(time.time() - t0, 2)
            out.seek(0)
            text = out.read()
            if killed:
                text += "\nheavy_run: %s kill sent at %.2f s, process exited at %.2f s\n" % (killed["status"], killed["at"], end)
                return killed["status"], p.returncode, text, peak, killed["at"]
            return "OK", p.returncode, text, peak, end
    finally:
        try:
            os.unlink(slot)
        except OSError:
            pass


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
    status, code, output, peak, dt = run(args[1:], tool, timeout)
    sys.stdout.write(output)
    sys.stderr.write("heavy_run: status=%s exit=%s peak_rss_kb=%d time_s=%s\n" % (status, code, peak, dt))
    sys.exit(124 if status == "TIMEOUT" else 137 if status in ("EXCEEDED_MEMORY", "LOW_MEMORY") else code)
