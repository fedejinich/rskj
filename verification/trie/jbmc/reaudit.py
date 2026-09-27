#!/usr/bin/env python3
"""Recomputes stub_audit for every entry of results/summary.json against the current
models/benign-stubs.json and the exact historical decisions in evidence-b3-stub-review/.
Those decisions never apply to another result record, invocation manifest or log/stub bytes.

A benign stub listed in CONDITIONAL is accepted for an entry only if that entry's JBMC log reports
the named property SUCCESS (the evidence the justification in benign-stubs.json relies on);
otherwise the entry gets "REVIEW: ...". Logs are results/<id>.log, or results/hosts/<host>/<id>.log
for merged results from another executor.

    verification/trie/jbmc/reaudit.py
Run while no run-jbmc.sh is active (it rewrites summary.json)."""
import hashlib, json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
BENIGN = json.load(open(os.path.join(HERE, "models", "benign-stubs.json")))
CONDITIONAL = {
    "java::java.lang.Class.getEnumConstants:()[Ljava/lang/Object;":
        r"\[java::org\.ethereum\.util\.FastByteComparisons\$LexicographicalComparerHolder\.getBestComparer:"
        r"\(\)Lorg/ethereum/util/FastByteComparisons\$Comparer;\.array-index-out-of-bounds-high\.1\].*: SUCCESS",
}


def log_of(r):
    for p in (os.path.join(HERE, "results", "hosts", r.get("host", ""), r["id"] + ".log"),
              os.path.join(HERE, "results", r["id"] + ".log")):
        if r.get("batch") and "hosts" not in p:
            continue
        if os.path.exists(p):
            return open(p, errors="replace").read()
    return ""


def reviewed_stubs(r):
    """Exact historical exceptions; changed evidence fails closed to ordinary review."""
    evidence = os.path.join(HERE, "evidence-b3-stub-review")
    try:
        decisions = json.load(open(os.path.join(evidence, "reviewed-results.json")))
        decision = decisions["results"].get(r["id"])
        if not decision:
            return []
        identity = json.dumps({k: v for k, v in r.items() if k != "stub_audit"},
                              sort_keys=True, separators=(",", ":")).encode()
        if hashlib.sha256(identity).hexdigest() != decision["result_sha256"]:
            return []
        files = {os.path.join(evidence, name): digest
                 for name, digest in decisions["manifests"].items()}
        for suffix, key in ((".log", "log_sha256"), (".stubs.txt", "stubs_sha256")):
            files[os.path.join(HERE, "results", "hosts", r["host"], r["id"] + suffix)] = decision[key]
        for path, digest in files.items():
            with open(path, "rb") as f:
                if hashlib.sha256(f.read()).hexdigest() != digest:
                    return []
        return decision["approved_stubs"]
    except (OSError, ValueError, KeyError):
        return []


def audit(r):
    reviewed = reviewed_stubs(r)
    unknown = [f for f in r.get("stubs", []) if f not in BENIGN and f not in reviewed]
    log = None
    for f in r.get("stubs", []):
        if f in CONDITIONAL and f not in unknown:
            log = log_of(r) if log is None else log
            if not re.search(CONDITIONAL[f], log):
                unknown.append(f + " (condition not shown in log)")
    return "none on property path" if not unknown else "REVIEW: " + ", ".join(unknown)


def main():
    p = os.path.join(HERE, "results", "summary.json")
    s = json.load(open(p))
    changed = 0
    for r in s["results"]:
        a = audit(r)
        if a != r.get("stub_audit"):
            r["stub_audit"], changed = a, changed + 1
    tmp = p + ".tmp"
    json.dump(s, open(tmp, "w"), indent=2)
    os.replace(tmp, p)
    review = [r["id"] for r in s["results"] if r["stub_audit"].startswith("REVIEW")]
    print("reaudit: %d entries changed, %d still REVIEW%s" % (changed, len(review), (": " + ", ".join(review)) if review else ""))


if __name__ == "__main__":
    main()
