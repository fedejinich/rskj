#!/usr/bin/env bash
# Builds the JBMC environment models and harnesses, then runs every entry of harnesses.json on
# the real compiled rskj classes. Writes results/<id>.log, results/<id>.stubs.txt,
# results/summary.json and results/invocation-manifest.json (invocation.py).
#
#   verification/trie/jbmc/run-jbmc.sh              # all entries
#   verification/trie/jbmc/run-jbmc.sh ID [ID...]   # selected entries, in this order (summary is merged)
#
# Fixed JBMC options for every entry: --unwinding-assertions (loop/recursion bounds are checked,
# never assumed). JBMC's default exception handling is kept: implicit runtime exceptions (null
# dereference, array index, negative array size, division by zero, bad cast) are checked as
# assertions, and explicitly thrown exceptions propagate; the uncaught-exception check stays enabled,
# so an exception escaping the harness method is a FAILURE either way. (An entry may add
# --throw-runtime-exceptions to make implicit exceptions catchable; it is several times slower.)
# --static-values models/static-values.json replaces the static initialiser of the classes listed
# there (see models/README.md).
# Env: JDK17 (javac for the models, source of the extracted JDK classes), JBMC_JOBS (parallel
# entries, default 2, capped by HEAVY_JBMC_SLOTS). Every JBMC process goes through jbmc/heavy_run.py
# (HEAVY_JBMC_SLOTS=2, HEAVY_RSS_GB=6, HEAVY_MAX_LOAD=8, HEAVY_TIMEOUT=300 by default; a second
# executor sets its own). A fresh run: rm -rf build results && run-jbmc.sh.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../env.sh"
JDK17="${JDK17:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
B="$HERE/build"
LIB="$TRIE_VERIFY/.tools/cbmc/jbmc/lib/java-models-library/target"
CPROVER="$LIB/cprover-api.jar"
RSKJ_CP="$(rskj_classpath)"
RSKJ_CLASSES="$(echo "$RSKJ_CP" | cut -d: -f1)"
jar_of() { echo "$RSKJ_CP" | tr ':' '\n' | grep "/$1" | head -1; }
SLF4J="$(jar_of slf4j-api-)"; BITCOINJ="$(jar_of bitcoinj-thin-)"; GUAVA="$(jar_of guava-)"; LANG3="$(jar_of commons-lang3-)"; BC="$(jar_of bclcrypto-jdk15on-)"
for j in "$SLF4J" "$BITCOINJ" "$GUAVA" "$LANG3" "$BC"; do [ -f "$j" ] || { echo "missing jar: $j" >&2; exit 2; }; done

# 1. Real JDK 17 bytecode for the JDK classes JBMC's models library lacks and JBMC can execute.
JDK_CLASSES='java/util/[A-Za-z0-9$]+|java/util/function/[A-Za-z0-9$]+|java/lang/Iterable|java/nio/Buffer(Over|Under)flowException|java/io/(ByteArrayOutputStream|OutputStream|IOException|Closeable|Flushable)'
if [ ! -f "$B/jdk17/.done" ]; then
  rm -rf "$B/jdk17" && mkdir -p "$B/jdk17"
  "$JDK17/bin/jimage" extract --dir "$B/jdk17" --include "regex:/java.base/($JDK_CLASSES)\.class" "$JDK17/lib/modules"
  "$JDK17/bin/java" -version 2>&1 | head -1 > "$B/jdk17/.done"
fi

# 2. Environment models (see header comment of each file).
rm -rf "$B/models" && mkdir -p "$B/models"
"$JDK17/bin/javac" -nowarn -g --release 17 -d "$B/models" "$HERE/models/src/jbmcenv/Observe.java"
"$JDK17/bin/javac" -nowarn -g --patch-module java.base="$HERE/models/src:$LIB/core-models.jar" --add-reads java.base=ALL-UNNAMED \
  -cp "$B/models:$CPROVER:$LIB/core-models.jar:$RSKJ_CLASSES" -d "$B/models" \
  "$HERE/models/src/java/lang/Object.java" "$HERE/models/src/java/lang/JbmcCanonicalClasses.java" "$HERE/models/src/java/lang/Math.java" "$HERE/models/src/java/lang/Integer.java" \
  "$HERE/models/src/java/lang/System.java" "$HERE/models/src/java/nio/ByteBuffer.java" \
  "$HERE/models/src/jdk/internal/util/ArraysSupport.java"
mv "$B/models/java.base/"* "$B/models/" 2>/dev/null && rmdir "$B/models/java.base" 2>/dev/null || true
"$JDK17/bin/javac" -nowarn -g --release 17 -cp "$CPROVER:$SLF4J:$RSKJ_CLASSES" -d "$B/models" \
  "$HERE/models/src/org/slf4j/LoggerFactory.java" "$HERE/models/src/org/ethereum/crypto/Keccak256Helper.java" \
  "$HERE/models/src/jbmcenv/MemoryKeyValueDataSource.java"

# 3. Harnesses, compiled against the real rskj classes.
rm -rf "$B/harness" && mkdir -p "$B/harness"
"$JDK17/bin/javac" -nowarn -g --release 17 -cp "$B/models:$CPROVER:$RSKJ_CP" -d "$B/harness" "$HERE"/harness/*.java

# Order matters: harness, models (shadow the real classes they replace), JBMC models library,
# extracted JDK classes, then the real rskj classes and the few jars the trie code needs.
JBMC_CP="$B/harness:$B/models:$LIB/core-models.jar:$CPROVER:$B/jdk17/java.base:$RSKJ_CLASSES:$SLF4J:$BITCOINJ:$GUAVA:$LANG3:$BC"
mkdir -p "$HERE/results"
export JBMC_CP HERE JDK17
python3 - "$@" <<'PY'
import json, os, re, socket, subprocess, sys, threading, time, concurrent.futures as cf
sys.path.insert(0, os.environ["HERE"])
import heavy_run
HOST = socket.gethostname()
LIMITS = {"jbmc_slots": heavy_run.JBMC_SLOTS, "rss_gb": heavy_run.RSS_LIMIT_KB / 1048576,
          "max_load": heavy_run.MAX_LOAD, "timeout_s": heavy_run.TIMEOUT}
HERE = os.environ["HERE"]; CP = os.environ["JBMC_CP"]
entries = json.load(open(os.path.join(HERE, "harnesses.json")))["harnesses"]
sel = sys.argv[1:]
if sel:
    by_id = {e["id"]: e for e in entries}
    missing = [i for i in sel if i not in by_id]
    if missing: sys.exit("unknown harness ids: %s" % sorted(missing))
    entries = [by_id[i] for i in dict.fromkeys(sel)]  # run in the order given
version = subprocess.run(["jbmc", "--version"], capture_output=True, text=True).stdout.strip()

# Functions JBMC synthesises by design (no bytecode expected).
SYNTHETIC = re.compile(r"^java::(array\[|.*<clinit_wrapper>|.*<user_specified_clinit>|.*\$\$Lambda|org\.cprover\.)|^__CPROVER|^_start")

# Bounds for loops inside the environment models (entries may override: later entries win).
# Keccak oracle table scans run over at most MAX_ENTRIES = 16 entries; sameBytes/clone copy
# messages and values, at most 64 bytes by default (entries hashing longer messages raise it); Nondet.bytes fills at most 74 bytes. Unwinding assertions check them.
K = "java::org.ethereum.crypto.Keccak256Helper"
MODEL_UNWINDSET = [K + ".keccak256:([B)[B.0:17", K + ".keccak256:([B)[B.1:17", K + ".sameBytes:([B[B)Z.0:65",
                   K + ".fresh:()[B.0:33", "java::array[byte].clone:()Ljava/lang/Object;.0:65",
                   "java::Nondet.bytes:(I)[B.0:75",
                   # harness byte-array helpers (loops over concrete lengths, at most 128 bytes here)
                   "java::Nondet.cat:([[B)[B.0:9", "java::Nondet.cat:([[B)[B.1:130", "java::Nondet.same:([B[B)Z.0:130",
                   "java::Nondet.at:([BI[B)Z.0:130", "java::Nondet.slice:([BII)[B.0:130", "java::Nondet.rep:(II)[B.0:130",
                   "java::Nondet.b:([I)[B.0:130",
                   # environment copy loops (System.arraycopy model, ByteBuffer model)
                   "java::java.lang.System.arraycopy:(Ljava/lang/Object;ILjava/lang/Object;II)V.0:130",
                   "java::java.lang.System.arraycopy:(Ljava/lang/Object;ILjava/lang/Object;II)V.1:130",
                   "java::java.nio.ByteBuffer.get:([B)Ljava/nio/ByteBuffer;.0:130",
                   "java::java.nio.ByteBuffer.put:([B)Ljava/nio/ByteBuffer;.0:130"]

# Stubs (methods without bytecode, see stubs()) reviewed and found off every property path, with the
# reason. Anything else is reported as "REVIEW: ..." in stub_audit.
BENIGN_STUBS = json.load(open(os.path.join(HERE, "models", "benign-stubs.json")))

DATASOURCE_FILTER = r"^(?!.*org/ethereum/datasource/(?!(KeyValueDataSource|DataSource|DataSourceKeyIterator)\.class)).*$"

def args_for(e):
    a = ["jbmc", e["class"], "-cp", CP, "--function", e["class"] + "." + e["method"],
         "--unwinding-assertions",
         "--static-values", os.path.join(HERE, "models", "static-values.json")]
    if "unwind" in e: a += ["--unwind", str(e["unwind"])]
    # an entry's unwindset comes last: JBMC keeps the last bound given for a loop id, so an entry may
    # lower a model default (e.g. arraycopy 130 -> exact copy length); --unwinding-assertions still
    # proves every bound sufficient
    a += ["--unwindset", ",".join(MODEL_UNWINDSET + ([e["unwindset"]] if e.get("unwindset") else []))]
    if e.get("max_nondet_array_length", 64) < 32:
        sys.exit("%s: max_nondet_array_length must be >= 32 (Keccak model outputs are nondet 32-byte arrays)" % e["id"])
    a += ["--max-nondet-array-length", str(e.get("max_nondet_array_length", 64))]
    # Load only the interfaces of org.ethereum.datasource: store harnesses use the in-memory model,
    # and the other implementations (HashMapDB, caches, LevelDB/RocksDB) would only add
    # interface-dispatch targets on infeasible paths.
    a += ["--java-cp-include-files", DATASOURCE_FILTER]
    if e.get("role") == "rskip-reading":
        a += ["--trace"]
    for k, flag in [("max_nondet_string_length", "--max-nondet-string-length"),
                    ("max_nondet_tree_depth", "--max-nondet-tree-depth"),
                    ("java_max_vla_length", "--java-max-vla-length")]:
        if k in e: a += [flag, str(e[k])]
    return a + e.get("flags", [])

def stubs(e):
    """Functions whose body JBMC generated because it had no bytecode for them
    (jbmc/src/java_bytecode/simple_method_stubbing.cpp): no source-line location at all and either
    an empty body or the stub's `to_construct`/`to_return` nondet local."""
    _, _, out, _, _ = heavy_run.run(args_for(e) + ["--show-goto-functions"], "jbmc")
    found, name, body = [], None, []
    def close():
        text = "\n".join(body)
        if name and not SYNTHETIC.search(name) and not re.search(r"// \d+ file \S+ line \d+", text):
            instrs = [l for l in body if not l.strip().startswith("//") and l.strip()]
            empty = all(re.search(r"END_FUNCTION|SKIP", l) for l in instrs)
            if empty or "::to_construct" in text or "::to_return" in text:
                found.append(name)
    for line in out.splitlines():
        m = re.match(r"^\S.* /\* (java::\S+|\S+) \*/$", line)
        if m or line.startswith("^^^^"):
            close()
            name, body = (m.group(1) if m else None), []
        elif name:
            body.append(line)
    close()
    return sorted(set(found))

def write_coverage(allres):
    """results/coverage.md and coverage.json: Stage-1 obligation -> entries -> verdicts -> bounds."""
    obs = [o for o in json.load(open(os.path.join(HERE, "..", "spec", "obligations.json")))["obligations"] if o["stage"] == 1]
    by = {}
    for r in allres:
        for o in r["obligations"]:
            by.setdefault(o, []).append(r)
    rows, cov = [], []
    for o in obs:
        rs = by.get(o["id"], [])
        roles = {x["role"] for x in rs}
        ok = bool(rs) and all(x["pass"] for x in rs) and "property" in roles
        cell = "; ".join("%s (%s, %s%s)" % (x["id"], x["role"], x["verdict"], "" if x["pass"] else " UNEXPECTED")
                         for x in rs)
        bounds = "; ".join(sorted({json.dumps(x["bounds"].get("keys") or x["bounds"].get("note") or
                                              {k: v for k, v in x["bounds"].items() if k not in ("unwind", "flags", "unwindset")},
                                              separators=(",", ":")) for x in rs if x["role"] == "property"}))
        status = ("refuted-as-expected" if "rskip-reading" in roles else "holds") if ok else ("missing" if not rs else "check")
        cov.append({"obligation": o["id"], "reading": o["java"]["reading"], "status": status,
                    "entries": [{"id": x["id"], "role": x["role"], "verdict": x["verdict"], "pass": x["pass"],
                                 "time_s": x["time_s"], "bounds": x["bounds"]} for x in rs]})
        rows.append("| %s | %s | %s | %s | %s |" % (o["id"], o["java"]["reading"], status, cell, bounds))
    json.dump(cov, open(os.path.join(HERE, "results", "coverage.json"), "w"), indent=1)
    open(os.path.join(HERE, "results", "coverage.md"), "w").write(
        "# JBMC coverage of the Stage-1 obligations (generated by run-jbmc.sh)\n\n"
        "status: holds = every entry passed and a property harness exists; refuted-as-expected = the "
        "RSKIP reading FAILS as expected while Java's behaviour holds; check = some entry did not give "
        "its expected verdict; missing = no entry.\n\n"
        "| obligation | java reading (spec) | status | entries (role, verdict) | property bounds |\n|---|---|---|---|---|\n"
        + "\n".join(rows) + "\n")

def write_reproducer(e, verdict, failed, out):
    """jbmc/reproducers/<OBLIGATION>.md from the entry's repro fields and the counterexample trace."""
    d = os.path.join(HERE, "reproducers")
    os.makedirs(d, exist_ok=True)
    rp = e["repro"]
    trace = out[out.find("Counterexample:"):] if "Counterexample:" in out else ""
    steps = [l for l in trace.splitlines() if re.match(r"\s+\S+=", l)]
    tail = "\n".join(steps[-40:])
    paths = []
    for obl in e["obligations"]:
        path = os.path.join(d, obl + ".md")
        body = ["# %s: RSKIP reading refuted on the real rskj classes (JBMC)" % obl, "",
                "Generated by run-jbmc.sh from harnesses.json entry `%s` (%s.%s)." % (e["id"], e["class"], e["method"]), "",
                "- RSKIP reading asserted: %s" % rp["rskip"],
                "- Input: %s" % rp["input"],
                "- Java output (checked by the paired property harness `%s`): %s" % (rp.get("property", "?"), rp["java"]),
                "- RSKIP-expected output: %s" % rp["rskip_expected"],
                "- JBMC verdict of the reading: %s; failed properties: %s" % (verdict, ", ".join(p for p, _ in failed) or "none"),
                "- Full log with trace: results/%s.log" % e["id"], "",
                "Last assignments of the counterexample trace:", "", "```", tail or "(no trace)", "```", ""]
        open(path, "w").write("\n".join(body))
        paths.append(os.path.relpath(path, os.path.dirname(HERE)))
    return paths

def run(e):
    log = os.path.join(HERE, "results", e["id"] + ".log")
    # Resource limits (jbmc/heavy_run.py): shared heavy-tool slot, load/memory-pressure wait,
    # nice + taskpolicy, RSS watchdog, per-harness timeout HEAVY_TIMEOUT (an entry may ask for less,
    # never more: a harness that does not fit is split, not given more time).
    timeout = min(e.get("timeout", heavy_run.TIMEOUT), heavy_run.TIMEOUT)
    status, code, out, peak_rss_kb, dt = heavy_run.run(args_for(e), "jbmc", timeout)
    open(log, "w").write(" ".join(args_for(e)) + "\n\n" + out)
    failed = re.findall(r"^\[(\S+)\] (.*): FAILURE$", out, re.M)
    if status == "TIMEOUT": verdict = "TIMEOUT"
    elif status == "EXCEEDED_MEMORY": verdict = "EXCEEDED_MEMORY"
    elif status == "LOW_MEMORY": verdict = "LOW_MEMORY"  # killed to protect the host (HEAVY_KILL_NEWEST_PCT); not a verdict
    elif code == 0 and "VERIFICATION SUCCESSFUL" in out: verdict = "SUCCESS"
    elif code == 10 and "VERIFICATION FAILED" in out: verdict = "FAILURE"
    else: verdict = "ERROR"
    ok = verdict == e["expect"]
    if ok and verdict == "FAILURE":
        # A negative control only counts if it fails for the deliberately false assertion.
        want = re.compile(e.get("expect_fail_regex", re.escape("java::%s.%s" % (e["class"], e["method"].split(":")[0])) + r".*\.assertion\.\d+"))
        ok = bool(failed) and all(want.search(pid) for pid, _ in failed)
    st = stubs(e)
    open(os.path.join(HERE, "results", e["id"] + ".stubs.txt"), "w").write("\n".join(st) + ("\n" if st else ""))
    unknown = [f for f in st if f not in BENIGN_STUBS]
    audit = "none on property path" if not unknown else "REVIEW: " + ", ".join(unknown)
    bounds = {k: e[k] for k in ("unwind", "unwindset", "max_nondet_array_length", "max_nondet_string_length",
                                "max_nondet_tree_depth", "java_max_vla_length", "flags") if k in e}
    bounds.update(e.get("bounds", {}))
    r = {"id": e["id"], "obligations": e.get("obligations", []), "role": e.get("role", "property"),
         "class": e["class"], "method": e["method"],
         "expect": e["expect"], "verdict": verdict, "pass": ok, "exit_code": code, "time_s": dt,
         "bounds": bounds, "note": e.get("note", ""), "status": e.get("status", "supported"),
         "reproducer": e.get("reproducer"), "stub_audit": audit,
         "host": HOST, "peak_rss_mb": round(peak_rss_kb / 1024), "limits": LIMITS,
         "failed_properties": [pid for pid, _ in failed], "stubs": st, "jbmc_version": version,
         "command": " ".join(args_for(e)).replace(CP, "$JBMC_CP").replace(HERE + "/", "")}
    if e.get("role") == "rskip-reading" and e.get("repro"):
        r["reproducer"] = write_reproducer(e, verdict, failed, out)
    print("%-44s %-8s expect %-8s %s %7.1fs  stubs=%d" % (e["id"], verdict, e["expect"], "PASS" if ok else "FAIL", dt, len(st)), flush=True)
    return r

path = os.path.join(HERE, "results", "summary.json")
order = [e["id"] for e in json.load(open(os.path.join(HERE, "harnesses.json")))["harnesses"]]
prev = {r["id"]: r for r in json.load(open(path))["results"]} if sel and os.path.exists(path) else {}
lock = threading.Lock()

def save_summary():
    # merge with the file on disk under a lock, so a concurrent run-jbmc.sh cannot overwrite results
    # recorded after this run started; this run's own results win for its entries
    import fcntl
    with open(path + ".lock", "w") as lf:
        fcntl.flock(lf, fcntl.LOCK_EX)
        disk = {r["id"]: r for r in json.load(open(path))["results"]} if os.path.exists(path) else {}
        disk.update({i: prev[i] for i in mine})
        prev.update({i: r for i, r in disk.items() if i not in mine})
        _write_summary()


def _write_summary():
    allres = [prev[i] for i in order if i in prev]
    tmp = path + ".tmp"
    json.dump({"jbmc_version": version, "classpath": CP.split(":"), "results": allres,
               "all_pass": all(r["pass"] for r in allres)}, open(tmp, "w"), indent=2)
    os.replace(tmp, path)

mine = set()


def run_and_record(e):
    r = run(e)
    with lock:
        prev[r["id"]] = r
        mine.add(r["id"])
        save_summary()   # progress survives an interruption
    return r

# what exactly this run executes (flags, classpath content, sources, versions): see invocation.py
import invocation
json.dump(invocation.manifest(CP, HERE, {e["id"]: args_for(e) for e in json.load(open(os.path.join(HERE, "harnesses.json")))["harnesses"]}, version),
          open(os.path.join(HERE, "results", "invocation-manifest.json"), "w"), indent=1)

# at most HEAVY_JBMC_SLOTS workers (the heavy-tool lock enforces it across runners anyway)
with cf.ThreadPoolExecutor(min(int(os.environ.get("JBMC_JOBS", "2")), heavy_run.JBMC_SLOTS)) as ex:
    res = list(ex.map(run_and_record, entries))
with lock:
    save_summary()
allres = [prev[i] for i in order if i in prev]
write_coverage(allres)
print("summary: %d/%d pass -> %s" % (sum(r["pass"] for r in allres), len(allres), path))
sys.exit(0 if all(r["pass"] for r in res) else 1)
PY
