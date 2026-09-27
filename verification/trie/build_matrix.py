#!/usr/bin/env python3
"""Joins the spec, Lean, JBMC and differential results into matrix.json, matrix.md and the review page.

Inputs:  spec/obligations.json, lean/obligations-map.json, jbmc/results/summary.json,
         differential/results/summary.json
Outputs: matrix.json, matrix.md, review/index.html (review/template.html with the matrix inlined)

Status per Stage-1 obligation (see README "Status definitions"):
  fails    Java is shown not to satisfy a requirement/derived obligation (Lean counterexample, a
           JBMC rskip-reading harness failing as expected)
  finding  ambiguity: the RSKIP is unclear/inconsistent/silent and Java's actual behaviour is verified
  proved   Lean proves the model statement under its hypotheses; all declared JBMC checks pass
  bounded  JBMC property harnesses pass; no complete Lean proof
  open     anything else (missing or failing evidence): the goal is not met while any row is open
"""
import json
import re
from functools import cache
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RSKJ_COMMIT = "ecef55ddf2b79fe5cd84c824118117dd825744b2"
RSKIPS_REPO = "https://github.com/fedejinich/RSKIPs/blob"
RSKJ_REPO = "https://github.com/fedejinich/rskj/blob"
BRANCH = "fm/trie-verify"
PR_URL = "https://github.com/fedejinich/rskj/pull/2"
TREE = f"https://github.com/fedejinich/rskj/blob/{BRANCH}/verification/trie"


def load(path, default):
    p = ROOT / path
    return json.loads(p.read_text()) if p.exists() else default


def rskip_links(o, commit):
    """'61; 32' or '68-69; RSKIP242.md:27' -> [(label, url)]."""
    links = []
    for part in str(o["lines"]).split(";"):
        part = part.strip()
        if not part:
            continue
        m = re.match(r"(?:(RSKIP\d+)\.md:)?([\d,\- ]+)$", part)
        if not m:
            continue
        f = f"IPs/{m.group(1)}.md" if m.group(1) else o["file"]
        for rng in m.group(2).split(","):
            a, _, b = rng.strip().partition("-")
            anchor = f"#L{a}" + (f"-L{b}" if b else "")
            links.append((f"{Path(f).stem}:{rng.strip()}", f"{RSKIPS_REPO}/{commit}/{f}{anchor}"))
    return links


def java_link(ref):
    path, _, lines = ref.partition(":")
    a, _, b = lines.partition("-")
    anchor = (f"#L{a}" + (f"-L{b}" if b else "")) if a.isdigit() else ""
    return (ref.replace("rskj-core/src/main/java/", ""), f"{RSKJ_REPO}/{RSKJ_COMMIT}/{path}{anchor}")


@cache
def harness_methods(path):
    methods = {}
    for i, line in enumerate(path.read_text().splitlines(), 1):
        match = re.search(r"\bstatic\s+.*?\b(\w+)\s*\(", line)
        if match:
            methods.setdefault(match[1], i)
    return methods


def harness_url(run):
    f = ROOT / "jbmc/harness" / f"{run.get('class', '')}.java"
    if not f.exists():
        return f"{TREE}/jbmc/harness"
    line = harness_methods(f).get(run.get("method", ""))
    return f"{TREE}/jbmc/harness/{f.name}" + (f"#L{line}" if line else "")


def decorate(lean, runs):
    for t in (lean or {}).get("theorems", []):
        t["url"] = f"{TREE}/{t.get('file', '')}" + (f"#L{t['line']}" if t.get("line") else "")
    for r in runs:
        r["url"] = r.get("harness_source_url") or harness_url(r)
        if r.get("evidence_manifest"):
            r["evidence_manifest_url"] = f"{TREE}/{r['evidence_manifest']}"
        if r.get("reproducer"):
            paths = r["reproducer"] if isinstance(r["reproducer"], list) else [r["reproducer"]]
            r["reproducer_links"] = []
            for path in paths:
                rel = path.split("verification/trie/")[-1]
                r["reproducer_links"].append((Path(path).stem, f"{TREE}/{rel if rel.startswith('jbmc/') else 'jbmc/' + rel}"))


def summary(o, lean):
    note = (lean or {}).get("note") or o["java"]["note"]
    return note.replace("Code reading only, not a verification verdict. ", "")


def classify(o, lean, runs):
    props = [r for r in runs if r.get("role") == "property"]
    readings = [r for r in runs if r.get("role") == "rskip-reading"]
    negs = [r for r in runs if r.get("role") == "negative-control"]
    def checked(r):
        return r.get("pass") is True and r.get("stub_audit") == "none on property path"

    j_prop_ok = bool(props) and bool(negs) and all(checked(r) for r in runs)
    j_refutes = any(checked(r) and r.get("verdict") == "FAILURE" for r in readings)
    lean_status = (lean or {}).get("lean_status", "none")
    # An arbitrary property FAILURE can be an unwind/oracle/harness failure, not a Java finding.
    # Counterexamples require a reviewed RSKIP-reading harness or a Lean counterexample theorem.
    diverges = lean_status == "refuted" or j_refutes
    verified = lean_status in ("proved", "refuted") or j_prop_ok or j_refutes
    if not verified:
        return "open"
    if o["kind"] == "ambiguity":
        return "finding"
    if diverges:
        return "fails"
    if lean_status == "proved" and j_prop_ok:
        return "proved"
    if j_prop_ok:
        return "bounded"
    return "open"


def main():
    spec = load("spec/obligations.json", None)
    lean_map = {e["id"]: e for e in load("lean/obligations-map.json", [])}
    jbmc = load("jbmc/results/summary.json", {"results": []})
    entries = load("jbmc/harnesses.json", {"harnesses": []})["harnesses"]
    results = {r["id"]: r for r in jbmc["results"]}
    # Missing split parts must remain visible and must never count as passing evidence.
    all_runs = [{**e, **results.get(e["id"], {"verdict": "PENDING", "pass": False})} for e in entries]
    diff = load("differential/results/summary.json", {})
    rows = []
    for o in spec["obligations"]:
        runs = [dict(r) for r in all_runs if o["id"] in r.get("obligations", [])]
        lean = lean_map.get(o["id"])
        decorate(lean, runs)
        status = classify(o, lean, runs) if o["stage"] == 1 else "stage-2"
        rows.append({
            "id": o["id"], "stage": o["stage"], "area": o["area"], "kind": o["kind"], "title": o["title"],
            "statement": o["statement"], "quote": o["quote"], "rskip": o["rskip"], "section": o["section"],
            "rskip_links": rskip_links(o, spec["rskips_commit"]),
            "java_links": [java_link(r) for r in o["java"]["refs"]],
            "java_reading": o["java"]["reading"], "java_note": o["java"]["note"],
            "reproducer_hint": o.get("reproducer_hint", ""), "applicability": o.get("applicability", ""),
            "lean": lean, "jbmc": runs, "status": status, "summary": summary(o, lean),
            "coverage_notes": (["format3 checks deletion of the first and second keys, not the third; the missing deletion check is queued after live batches settle."]
                if any(r.get("split_of") == "node-format-3" for r in runs) else []) +
                (["Three savedEntries index choices overwrite the first key instead of creating three distinct keys; distinct-key corrections are queued after live batches settle."]
                if any(r.get("split_of") == "store-saved-entries" for r in runs) else []),
            "jbmc_complete": bool(runs) and all(r.get("pass") is True and r.get("stub_audit") == "none on property path" for r in runs),
            "coverage": ("lean+jbmc" if lean and runs else "lean-only" if lean else "jbmc-only" if runs else "none")
            if o["stage"] == 1 else "stage-2",
        })
    for row in rows:
        if row["coverage_notes"] and row["status"] in ("proved", "bounded"):
            row["status"] = "open"
    counts = {s: sum(r["status"] == s for r in rows) for s in ["proved", "bounded", "fails", "finding", "open", "stage-2"]}
    coverage = {c: sum(r["coverage"] == c for r in rows) for c in ["lean+jbmc", "lean-only", "jbmc-only", "none"]}
    matrix = {
        "rskj_commit": RSKJ_COMMIT, "rskips_commit": spec["rskips_commit"], "branch": BRANCH, "pr_url": PR_URL,
        "jbmc_version": jbmc.get("jbmc_version"), "lean_toolchain": (ROOT / "lean/lean-toolchain").read_text().strip()
        if (ROOT / "lean/lean-toolchain").exists() else None,
        "differential": diff, "counts": counts, "coverage": coverage, "rows": rows,
        "jbmc_entries": len(entries), "jbmc_pending": sum(r["verdict"] == "PENDING" for r in all_runs),
        "jbmc_complete_obligations": sum(r["stage"] == 1 and r["jbmc_complete"] for r in rows),
    }
    (ROOT / "matrix.json").write_text(json.dumps(matrix, indent=1) + "\n")

    md = ["# Trie verification matrix", "",
          f"rskj `{RSKJ_COMMIT}` · RSKIPs `{spec['rskips_commit']}` · JBMC {matrix['jbmc_version']} · "
          f"{matrix['lean_toolchain']}", "",
          "Status: " + ", ".join(f"**{k}** {v}" for k, v in counts.items()), "",
          "Coverage (Stage 1): " + ", ".join(f"{k} {v}" for k, v in coverage.items()), "",
          "Lean proves statements under the listed model hypotheses; JBMC checks the real classes within each harness bound.", "",
          f"JBMC declared-entry completion for {matrix['jbmc_complete_obligations']}/{sum(r['stage'] == 1 for r in rows)} Stage-1 obligations; "
          f"{matrix['jbmc_pending']}/{matrix['jbmc_entries']} harness entries pending. Findings do not imply complete coverage.", "",
          "Declared-entry completion is not exhaustive input coverage: six split entries are empty-domain sentinels; "
          "format3 omits third-key deletion and three savedEntries cases overwrite the first key. "
          "See [scope reconciliation and queued corrections](jbmc/audits/coverage-reconciliation.md).", "",
          "| Obligation | Kind | Status | Lean | JBMC (bounds) | RSKIP |", "| --- | --- | --- | --- | --- | --- |"]
    for r in rows:
        lean = r["lean"] or {}
        thms = ", ".join(f"`{t['name'].split('.')[-1]}`" for t in lean.get("theorems", [])) or "—"
        jb = "<br>".join(f"`{x['id']}` {x.get('role', '')} {x.get('verdict', '')} ({bounds_str(x.get('bounds'))})"
                         for x in r["jbmc"]) or "—"
        rk = ", ".join(f"[{a}]({b})" for a, b in r["rskip_links"][:3])
        md.append(f"| {r['id']} {r['title']} | {r['kind']} | **{r['status']}** | {lean.get('lean_status', 'none')}: "
                  f"{thms} | {jb} | {rk} |")
    (ROOT / "matrix.md").write_text("\n".join(md) + "\n")

    tpl = ROOT / "review/template.html"
    if tpl.exists():
        data = json.dumps(matrix).replace("</", "<\\/")
        (ROOT / "review/index.html").write_text(tpl.read_text().replace("/*MATRIX_DATA*/null", data))
    print(json.dumps(counts), json.dumps(coverage))


def bounds_str(b):
    if not b:
        return ""
    return ", ".join(f"{k}={v}" for k, v in b.items() if k != "flags")


if __name__ == "__main__":
    main()
