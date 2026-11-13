#!/usr/bin/env python3
"""jbmc/reproducers/<OBLIGATION>.md: one self-contained reproducer per RSKIP reading refuted by JBMC.

Each file gives the RSKIP text and location, the Java locations, the reading asserted and the Java
behaviour (with the paired property harness), the JBMC verdict and violated property, the last
program-level assignments of the counterexample trace (setup states of __CPROVER_initialize and class
initialisers left out), and the same inputs in the Lean obligations map and the differential cases.
The per-run logs are not committed, so the trace excerpt is copied here.

run-jbmc.sh rebuilds all of them at the end of every run; `reproducers.py` alone does the same (after a
batch merge) from results/summary.json and the logs (results/<id>.log or results/hosts/<host>/<id>.log).
"""
import json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
TRIE = os.path.dirname(HERE)


def _trace_excerpt(out, n=25):
    """Last assignments to program variables before the violated assertion: setup states
    (__CPROVER_initialize, class initialisers), JBMC temporaries, object internals and the construction
    of the AssertionError are left out, and values are shown without their bit patterns."""
    i = out.find("Trace for ")
    if i < 0:
        return ""
    keep, fn = [], ""
    for l in out[i:].splitlines():
        if l.startswith("State "):
            fn = l
            continue
        if l.startswith("Violated property:"):
            break
        m = re.match(r"\s+([A-Za-z_][\w.\[\]]*)=(.*)$", l)
        if not m or "__CPROVER_initialize" in fn or "clinit" in fn:
            continue
        name, val = m.group(1), re.sub(r"\s*\([01 ]+\)\s*$", "", m.group(2)).strip()
        if any(t in name for t in ("$", "@", "tmp", "dynamic_object", "cproverMonitorCount")) or val.startswith(("{", "&", "null")):
            continue
        if re.search(r"file \S*(AssertionError|Error|Throwable|Object)\.java", fn):
            continue
        loc = re.search(r"file (\S+) function (\S+) line (\d+)", fn)
        keep.append("%-42s %s = %s" % ("%s:%s" % (loc.group(1).split("/")[-1], loc.group(3)) if loc else "", name, val[:100]))
    return "\n".join(keep[-n:])


def _violated(out):
    i = out.find("Violated property:")
    return "\n".join(l.strip() for l in out[i:].splitlines()[1:4] if l.strip()) if i >= 0 else ""


def _cases(obl):
    p = os.path.join(TRIE, "differential", "cases", "reproducers.cases")
    if not os.path.exists(p):
        return []
    out, grab = [], False
    for l in open(p):
        if l.startswith("#"):
            ids = re.findall(r"TRIE-[A-Z]+-\d+", l)
            if ids:
                grab = obl in ids
            continue
        if grab and l.strip():
            out.append(l.strip())
    return out


def _lean(obl):
    p = os.path.join(TRIE, "lean", "obligations-map.json")
    if not os.path.exists(p):
        return []
    return ["%s (%s:%s, %s)" % (t["name"], t["file"], t["line"], t["status"])
            for m in json.load(open(p)) if m["id"] == obl for t in m.get("theorems", [])]


def _section(e, r, out):
    rp = e["repro"]
    body = ["### `%s` (`%s.%s`)" % (e["id"], e["class"], e["method"]), "",
            "- RSKIP reading asserted: %s" % rp["rskip"],
            "- Input: %s" % rp["input"],
            "- Java output: %s (property harness `%s`)" % (rp["java"], rp.get("property", "?")),
            "- RSKIP-expected output: %s" % rp["rskip_expected"],
            "- JBMC verdict of the reading: %s (expected %s), host %s" % (r["verdict"], e["expect"], r.get("host") or "?"),
            "- Stub audit: %s. Expected verdicts with unresolved stubs are not accepted proof." % r.get("stub_audit", "not recorded"),
            "- Failed properties: %s" % (", ".join("`%s`" % p for p in r.get("failed_properties", [])) or "none"), ""]
    v = _violated(out)
    if v:
        body += ["Violated property:", "", "```", v, "```", ""]
    t = _trace_excerpt(out)
    body += ["Last assignments to program variables in the counterexample:", "", "```", t or "(none recorded)", "```", ""]
    return body


def path_of(obl):
    return os.path.relpath(os.path.join(HERE, "reproducers", obl + ".md"), TRIE)


def write_all():
    entries = {e["id"]: e for e in json.load(open(os.path.join(HERE, "harnesses.json")))["harnesses"]}
    spec = {o["id"]: o for o in json.load(open(os.path.join(TRIE, "spec", "obligations.json")))["obligations"]}
    by = {}
    for r in json.load(open(os.path.join(HERE, "results", "summary.json")))["results"]:
        e = entries.get(r["id"])
        if e and e.get("role") == "rskip-reading" and e.get("repro"):
            for obl in e["obligations"]:
                by.setdefault(obl, []).append((e, r))
    d = os.path.join(HERE, "reproducers")
    os.makedirs(d, exist_ok=True)
    for obl, ers in sorted(by.items()):
        o = spec.get(obl, {})
        quote = (o.get("quote") or "").strip().replace("\n", "\n> ")
        body = ["# %s: %s" % (obl, o.get("title", "")), "",
                "Generated by jbmc/reproducers.py. JBMC checks the RSKIP reading of this obligation on the real rskj "
                "classes; the paired property harness is listed separately. Pending results and unresolved stub audits "
                "remain open evidence.", "",
                "## RSKIP", "",
                "%s (`%s:%s`, %s)" % (o.get("rskip", "?"), o.get("file", "?"), o.get("lines", "?"), o.get("section", "")), "",
                "> %s" % quote, "",
                "## Java", ""] + ["- `%s`" % x for x in o.get("java", {}).get("refs", [])] + ["", "## JBMC", ""]
        for e, r in ers:
            logs = [os.path.join(HERE, "results", "hosts", r.get("host") or "", r["id"] + ".log"),
                    os.path.join(HERE, "results", r["id"] + ".log")]
            out = next((open(p, errors="replace").read() for p in logs if os.path.exists(p)), "")
            body += _section(e, r, out)
        cases, lean = _cases(obl), _lean(obl)
        body += ["## Same inputs elsewhere", "",
                 "- Differential cases (`differential/cases/reproducers.cases`): %s" % (", ".join("`%s`" % c for c in cases) or "none"),
                 "- Lean: %s" % ("; ".join(lean) or "none"),
                 "- Hint in the spec: %s" % (o.get("reproducer_hint") or "none"), ""]
        open(os.path.join(d, obl + ".md"), "w").write("\n".join(body))
    return sorted(by)


if __name__ == "__main__":
    print("\n".join(write_all()))
