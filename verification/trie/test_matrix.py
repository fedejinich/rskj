#!/usr/bin/env python3
"""Regression checks for evidence completeness and links. Run: python3 verification/trie/test_matrix.py"""
import json
import tempfile
import sys
from pathlib import Path
from unittest.mock import patch

import build_matrix as m
sys.path.insert(0, str(Path(__file__).parent / "jbmc"))
import coverage as jbmc_coverage
import reproducers

obligation = {"id": "TRIE-TEST-01", "stage": 1, "area": "TEST", "kind": "requirement",
              "title": "Test", "statement": "Test", "quote": "Test", "rskip": "RSKIP107",
              "section": "Test", "file": "IPs/RSKIP107.md", "lines": "1",
              "java": {"refs": [], "reading": "conforms", "note": "Test"}}
lean = {"id": obligation["id"], "lean_status": "proved", "theorems": [
    {"name": "test", "file": "lean/RskjTrie/Obligations/Hash.lean", "line": 1}]}
prop = {"id": "p1", "role": "property", "obligations": [obligation["id"]],
        "pass": True, "verdict": "SUCCESS", "stub_audit": "none on property path",
        "time_s": 0, "host": "fixture", "bounds": {}}
neg = {**prop, "id": "neg", "role": "negative-control", "verdict": "FAILURE"}
assert m.classify(obligation, lean, [prop, neg]) == "proved"
assert m.classify(obligation, lean, [prop, neg, {**prop, "id": "p2", "pass": False, "verdict": "PENDING"}]) == "open"
assert m.classify(obligation, lean, [{**prop, "stub_audit": "REVIEW: missing model"}, neg]) == "open"
assert m.classify(obligation, lean, [{**prop, "pass": False, "verdict": "FAILURE", "failed_properties": ["unwind.1"]}, neg]) == "open"
assert m.classify(obligation, lean, [prop]) == "open"  # absent negative control

with tempfile.TemporaryDirectory() as tmp, patch.object(m, "ROOT", Path(tmp)):
    cases = Path(tmp) / "differential/cases/reproducers.cases"
    cases.parent.mkdir(parents=True)
    cases.write_text("# TRIE-HASH-04\n# continuation comment\ncase hash\nhash\nend\n"
                     "# TRIE-HASH-02\ncase empty\nend\n")
    with patch.object(reproducers, "TRIE", tmp):
        assert reproducers._cases("TRIE-HASH-04") == ["case hash", "hash", "end"]
        assert reproducers._cases("TRIE-HASH-02") == ["case empty", "end"]
    inputs = {
        "spec/obligations.json": {"rskips_commit": "test", "obligations": [obligation]},
        "lean/obligations-map.json": [lean],
        "jbmc/harnesses.json": {"harnesses": [
            {k: v for k, v in r.items() if k not in ("pass", "verdict", "stub_audit")}
            for r in [prop, {**prop, "id": "p2"}, neg]]},
        "jbmc/results/summary.json": {"results": [prop, neg]},
    }
    for name, data in inputs.items():
        path = Path(tmp) / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data))
    m.main()
    matrix = json.loads((Path(tmp) / "matrix.json").read_text())
    assert matrix["counts"]["proved"] == 0
    assert matrix["counts"]["open"] == 1
    assert matrix["jbmc_pending"] == 1
    assert matrix["jbmc_complete_obligations"] == 0
    assert len(matrix["rows"][0]["jbmc"]) == 3
    harness = Path(tmp) / "jbmc/harness/Example.java"
    harness.parent.mkdir(parents=True)
    harness.write_text("class Example {\n  public static void example() {}\n}\n")
    assert m.harness_url({"class": "Example", "method": "example"}).endswith("/Example.java#L2")
    assert "/lean/lean/" not in matrix["rows"][0]["lean"]["theorems"][0]["url"]
    run = {"reproducer": ["jbmc/reproducers/TRIE-HASH-04.md", "jbmc/reproducers/TRIE-HASH-05.md"]}
    m.decorate(None, [run])
    assert len(run["reproducer_links"]) == 2
    assert run["reproducer_links"][0][1].endswith("/jbmc/reproducers/TRIE-HASH-04.md")
    inputs["jbmc/harnesses.json"]["harnesses"] = [
        {**prop, "split_of": "node-format-3"}, neg]
    (Path(tmp) / "jbmc/harnesses.json").write_text(json.dumps(inputs["jbmc/harnesses.json"]))
    m.main()
    row = json.loads((Path(tmp) / "matrix.json").read_text())["rows"][0]
    assert row["jbmc_complete"]  # all declared entries, but the advertised domain still has a gap
    assert row["coverage_notes"] and row["status"] == "open"
    assert jbmc_coverage.write(str(Path(tmp) / "jbmc")) == {"check": 1}
    (Path(tmp) / "jbmc/harnesses.json").write_text(json.dumps({"harnesses": [prop, neg]}))
    assert jbmc_coverage.write(str(Path(tmp) / "jbmc")) == {"holds": 1}
    (Path(tmp) / "jbmc/results/summary.json").write_text(json.dumps({"results": [
        {**prop, "stub_audit": "REVIEW: missing model"}, neg]}))
    assert jbmc_coverage.write(str(Path(tmp) / "jbmc")) == {"check": 1}
print("matrix evidence and links: OK")
