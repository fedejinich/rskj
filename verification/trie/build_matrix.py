#!/usr/bin/env python3
"""Joins the spec, Lean, JBMC and differential results into matrix.json, matrix.md and the review page.

Inputs:  spec/obligations.json, lean/obligations-map.json, jbmc/results/summary.json,
         differential/results/summary.json
Outputs: matrix.json, matrix.md, review/index.html (review/template.html with the matrix inlined)

Status per Stage-1 obligation (see README "Status definitions"):
  fails    Java is shown not to satisfy a requirement/derived obligation (Lean counterexample, a
           JBMC rskip-reading harness failing as expected, or a counterexample to a property harness)
  finding  ambiguity: the RSKIP is unclear/inconsistent/silent and Java's actual behaviour is verified
  proved   Lean proves it for all inputs and every JBMC property harness passes
  bounded  JBMC property harnesses pass; no complete Lean proof
  open     anything else (missing or failing evidence): the goal is not met while any row is open
"""
import json
import re
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


def harness_url(run):
    f = ROOT / "jbmc/harness" / f"{run.get('class', '')}.java"
    if not f.exists():
        return f"{TREE}/jbmc/harness"
    for i, line in enumerate(f.read_text().splitlines(), 1):
        if re.search(rf"\b{re.escape(run.get('method', ''))}\s*\(", line) and "static" in line:
            return f"{TREE}/jbmc/harness/{f.name}#L{i}"
    return f"{TREE}/jbmc/harness/{f.name}"


def decorate(lean, runs):
    for t in (lean or {}).get("theorems", []):
        t["url"] = f"{TREE}/lean/{t.get('file', '')}" + (f"#L{t['line']}" if t.get("line") else "")
    for r in runs:
        r["url"] = harness_url(r)
        if r.get("reproducer"):
            rel = str(r["reproducer"]).split("verification/trie/")[-1]
            r["reproducer_url"] = f"{TREE}/{rel if rel.startswith('jbmc/') else 'jbmc/' + rel}"


def summary(o, lean):
    note = (lean or {}).get("note") or o["java"]["note"]
    return note.replace("Code reading only, not a verification verdict. ", "")


def classify(o, lean, runs):
    props = [r for r in runs if r.get("role") == "property"]
    readings = [r for r in runs if r.get("role") == "rskip-reading"]
    negs = [r for r in runs if r.get("role") == "negative-control"]
    j_prop_ok = bool(props) and all(r.get("pass") for r in props) and all(r.get("pass") for r in negs)
    j_refutes = any(r.get("pass") for r in readings)
    j_prop_fail = any(r.get("verdict") == "FAILURE" for r in props)  # counterexample to a property
    lean_status = (lean or {}).get("lean_status", "none")
    diverges = lean_status == "refuted" or j_refutes or j_prop_fail
    verified = lean_status in ("proved", "refuted") or j_prop_ok or j_prop_fail
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
    diff = load("differential/results/summary.json", {})
    rows = []
    for o in spec["obligations"]:
        runs = [r for r in jbmc.get("results", []) if o["id"] in r.get("obligations", [])]
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
        })
    counts = {s: sum(r["status"] == s for r in rows) for s in ["proved", "bounded", "fails", "finding", "open", "stage-2"]}
    matrix = {
        "rskj_commit": RSKJ_COMMIT, "rskips_commit": spec["rskips_commit"], "branch": BRANCH, "pr_url": PR_URL,
        "jbmc_version": jbmc.get("jbmc_version"), "lean_toolchain": (ROOT / "lean/lean-toolchain").read_text().strip()
        if (ROOT / "lean/lean-toolchain").exists() else None,
        "differential": diff, "counts": counts, "rows": rows,
    }
    (ROOT / "matrix.json").write_text(json.dumps(matrix, indent=1) + "\n")

    md = ["# Trie verification matrix", "",
          f"rskj `{RSKJ_COMMIT}` · RSKIPs `{spec['rskips_commit']}` · JBMC {matrix['jbmc_version']} · "
          f"{matrix['lean_toolchain']}", "",
          "Status: " + ", ".join(f"**{k}** {v}" for k, v in counts.items()), "",
          "Lean = unbounded proof over the model; JBMC = bounded check on the real classes (bounds per harness).", "",
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
    print(json.dumps(counts))


def bounds_str(b):
    if not b:
        return ""
    return ", ".join(f"{k}={v}" for k, v in b.items() if k != "flags")


if __name__ == "__main__":
    main()
