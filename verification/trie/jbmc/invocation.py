#!/usr/bin/env python3
"""Invocation manifests: what exactly a JBMC run executed, independent of where it ran.

run-jbmc.sh writes results/invocation-manifest.json at every run:
  jbmc_version, jdk_version, source_commit (git HEAD and dirty flag, or the SOURCE file a batch
  carries), classpath [{entry, sha256}] in JBMC_CP order (a directory's digest is the sha256 of its
  sorted "relative-path sha256" lines), sources {relative path: sha256} for the harness, models,
  harness list and runner, and argv {id: normalized argv} for every entry of harnesses.json.
Normalized argv: the classpath value is replaced by "$JBMC_CP" and the jbmc/ directory by "$HERE",
so two runs are the same invocation iff their normalized argv, classpath digests (in order),
sources, JBMC and JDK versions are equal.

    invocation.py compare A.json B.json [ID ...]   # exit 0 iff identical (for the given ids)
"""
import hashlib, json, os, subprocess, sys


def _file_sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def digest(p):
    if os.path.isfile(p):
        return _file_sha(p)
    lines = []
    for root, dirs, files in os.walk(p):
        dirs.sort()
        for n in sorted(files):
            if n.startswith("."):
                continue  # e.g. jdk17/.done marker
            f = os.path.join(root, n)
            lines.append("%s %s" % (os.path.relpath(f, p), _file_sha(f)))
    return hashlib.sha256("\n".join(lines).encode()).hexdigest()


def normalize(argv, cp, here):
    return [a.replace(cp, "$JBMC_CP").replace(here + "/", "$HERE/") for a in argv]


def sources(here):
    out = {}
    for sub in ("harness", "models"):
        for root, dirs, files in os.walk(os.path.join(here, sub)):
            dirs.sort()
            for n in sorted(files):
                f = os.path.join(root, n)
                out[os.path.relpath(f, here)] = _file_sha(f)
    for n in ("harnesses.json", "run-jbmc.sh", "heavy_run.py", "invocation.py"):
        if os.path.exists(os.path.join(here, n)):
            out[n] = _file_sha(os.path.join(here, n))
    return out


def source_commit(here):
    s = os.path.join(here, "..", "SOURCE")
    if os.path.exists(s):
        return open(s).read().strip()
    try:
        head = subprocess.run(["git", "-C", here, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
        dirty = subprocess.run(["git", "-C", here, "status", "--porcelain", "--", "."], capture_output=True, text=True).stdout
        return head + (" (uncommitted changes under verification/trie/jbmc)" if dirty.strip() else "")
    except OSError:
        return "unknown"


def manifest(cp, here, argv_by_id, jbmc_version):
    jdk = os.environ.get("JDK17", "")
    jv = subprocess.run([os.path.join(jdk, "bin", "java"), "-version"], capture_output=True, text=True).stderr.strip() if jdk else ""
    return {"jbmc_version": jbmc_version, "jdk_version": jv, "source_commit": source_commit(here),
            "classpath": [{"entry": e.replace(here + "/", "$HERE/"), "sha256": digest(e)} for e in cp.split(":")],
            "sources": sources(here),
            "argv": {i: normalize(a, cp, here) for i, a in argv_by_id.items()}}


def compare(a, b, ids=None):
    diffs = []
    for k in ("jbmc_version", "jdk_version"):
        if a[k] != b[k]:
            diffs.append("%s: %r != %r" % (k, a[k], b[k]))
    ca, cb = [x["sha256"] for x in a["classpath"]], [x["sha256"] for x in b["classpath"]]
    if ca != cb:
        for i in range(max(len(ca), len(cb))):
            ea = a["classpath"][i] if i < len(ca) else None
            eb = b["classpath"][i] if i < len(cb) else None
            if not ea or not eb or ea["sha256"] != eb["sha256"]:
                diffs.append("classpath[%d]: %s != %s" % (i, ea and ea["entry"], eb and eb["entry"]))
    for f in sorted(set(a["sources"]) | set(b["sources"])):
        if a["sources"].get(f) != b["sources"].get(f):
            diffs.append("source %s differs" % f)
    for i in (ids or sorted(set(a["argv"]) | set(b["argv"]))):
        if a["argv"].get(i) != b["argv"].get(i):
            diffs.append("argv %s differs" % i)
    return diffs


if __name__ == "__main__":
    if len(sys.argv) < 4 or sys.argv[1] != "compare":
        sys.exit(__doc__)
    d = compare(json.load(open(sys.argv[2])), json.load(open(sys.argv[3])), sys.argv[4:] or None)
    print("\n".join(d) if d else "identical")
    sys.exit(1 if d else 0)
