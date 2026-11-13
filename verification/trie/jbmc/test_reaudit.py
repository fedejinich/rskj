#!/usr/bin/env python3
"""Historical stub exception and retained-trace checks. No JBMC execution."""
import copy
import gzip
import hashlib
import json
from pathlib import Path
import re
import runpy
import shutil
import tempfile
from unittest.mock import patch

import reaudit

HERE = Path(__file__).resolve().parent
EVIDENCE = HERE / "evidence-b3-stub-review"
results = {r["id"]: r for r in json.loads((HERE / "results/summary.json").read_text())["results"]}
decisions = json.loads((EVIDENCE / "reviewed-results.json").read_text())
review = json.loads((EVIDENCE / "reconciliation.json").read_text())
assert set(decisions["results"]) == {
    "store-save-retrieve-neg", "store-content-addressed-rskip", "store-saved-entries-neg",
    "store-collect-rskip", "dto-embedded-long-value-rskip",
    "store-epochs-neg", "dto-roundtrip-inline-neg", "dto-embedded-long-value",
    "store-epochs", "store-collect",
}
for row in review["results"]:
    r = results[row["id"]]
    accepted = r["id"] in decisions["results"]
    assert (reaudit.audit(r) == "none on property path") == accepted, r["id"]
    if not accepted:
        continue
    for key, value in (("id", "unreviewed-result"), ("batch", "other-batch"),
                       ("command", r["command"] + " --unwind 1"),
                       ("bounds", {"unwind": 1}), ("failed_properties", ["unreviewed.assertion.1"]),
                       ("jbmc_version", "other-version"), ("pass", False)):
        changed = {**r, key: value}
        assert not reaudit.reviewed_stubs(changed), (r["id"], key)
        assert reaudit.audit(changed).startswith("REVIEW"), (r["id"], key)
    changed = copy.deepcopy(r)
    changed["stubs"].append("java::unreviewed.method:()V")
    assert reaudit.audit(changed).startswith("REVIEW")

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    shutil.copytree(EVIDENCE, root / EVIDENCE.name)
    r = results["store-collect-rskip"]
    host = root / "results/hosts" / r["host"]
    host.mkdir(parents=True)
    paths = []
    for suffix in (".log", ".stubs.txt"):
        target = host / (r["id"] + suffix)
        shutil.copyfile(HERE / "results/hosts" / r["host"] / target.name, target)
        paths.append(target)
    paths += [root / EVIDENCE.name / name for name in decisions["manifests"]]
    with patch.object(reaudit, "HERE", str(root)):
        assert reaudit.audit(r) == "none on property path"
        for path in paths:
            original = path.read_bytes()
            path.write_bytes(original + b"\n")
            assert reaudit.audit(r).startswith("REVIEW"), path
            path.unlink()
            assert reaudit.audit(r).startswith("REVIEW"), path
            path.write_bytes(original)
        assert reaudit.audit(r) == "none on property path"


def trace_checks(text):
    """Check concrete arguments, not merely the presence of successful properties."""
    blocks = re.split(r"(?=^State \d+ )", text, flags=re.M)[1:]
    assert blocks, "No trace retained"
    pending, calls = {}, []
    for block in blocks:
        header = block.splitlines()[0]
        func = header.split(" function ", 1)[1].rsplit(" thread ", 1)[0]
        assert not any(name in func for name in (
            "java.lang.reflect.Array.newInstance", "java.lang.ThreadLocal.remove",
            "DataSourceWithCache.emitLogs", ".subListRangeCheck")), header
        if func.startswith(("java.util.Objects.checkIndex(", "java.util.Objects.checkFromIndexSize(")):
            for match in re.finditer(r"^  stub_ignored_arg(\d+)=(null|-?\d+) ", block, re.M):
                index = int(match[1])
                if index == 0:
                    pending = {}
                pending[index] = None if match[2] == "null" else int(match[2])
        for name, count in (("checkIndex", 2), ("checkFromIndexSize", 3)):
            if not func.startswith("jdk.internal.util.Preconditions." + name + "("):
                continue
            assert set(pending) == set(range(count + 1)) and pending[count] is None
            args = [pending[i] for i in range(count + 1)]
            assert (0 <= args[0] < args[1]) if count == 2 else (
                0 <= args[0] and 0 <= args[1] and args[0] <= args[2] - args[1])
            calls.append({"state": int(header.split()[1]), "method": name,
                          "arguments": args, "valid": True})
            pending = {}
    return len(blocks), calls


traces = json.loads((EVIDENCE / "negative-trace-review.json").read_text())
assert len(traces["results"]) == 3
for row in traces["results"]:
    r = results[row["id"]]
    raw = (HERE / "results/hosts" / r["host"] / (r["id"] + ".log")).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == row["log_sha256"]
    count, calls = trace_checks(raw.decode())
    assert count == row["trace_state_blocks"] and calls == row["range_check_calls"]
for invalid in (
    "No trace retained",
    "State 1 function java.util.Objects.checkIndex(int, int) thread 0\n"
    "  stub_ignored_arg0=-1 (bits)\n  stub_ignored_arg1=3 (bits)\n"
    "  stub_ignored_arg2=null (bits)\n"
    "State 2 function jdk.internal.util.Preconditions.checkIndex() thread 0\n",
    "State 1 function java.lang.reflect.Array.newInstance() thread 0\n",
):
    try:
        trace_checks(invalid)
    except AssertionError:
        pass
    else:
        raise AssertionError("Invalid trace accepted")
replay_dir = EVIDENCE / "trace-replay"
replay = json.loads((replay_dir / "manifest.json").read_text())
executor = json.loads((EVIDENCE / "executor-manifest.json").read_text())
comparison = json.loads((replay_dir / "goto-comparison.json").read_text())
replayed = json.loads((replay_dir / "review.json").read_text())["results"]
assert {r["id"] for r in replayed} == {"store-epochs-neg", "dto-roundtrip-inline-neg"}
assert replay["historical_manifest_sha256"] == hashlib.sha256(
    (EVIDENCE / "executor-manifest.json").read_bytes()).hexdigest()
assert replay["jbmc_version"] == executor["jbmc_version"]
assert [r["sha256"] for r in replay["classpath"]] == [
    r["sha256"] for r in executor["classpath"]]
assert replay["static_values_sha256"] == executor["sources"]["models/static-values.json"]
for row in replayed:
    ident = row["id"]
    assert replay["argv"][ident]["normalized"] == executor["argv"][ident] + ["--trace"]
    raw = (replay_dir / (ident + ".log")).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == row["log_sha256"]
    count, calls = trace_checks(raw.decode())
    assert count == row["trace_state_blocks"] and calls == row["range_check_calls"]
    captured = next(r for r in replay["results"] if r["id"] == ident)
    assert captured["exit_code"] == 10 and captured["log_sha256"] == row["log_sha256"]
    failed = re.findall(r"^\[([^\]]+)\].*:\s*FAILURE\s*$", raw.decode(), re.M)
    assert failed == captured["failed_properties"] == results[ident]["failed_properties"]
    assert len(failed) == 1 and "VERIFICATION FAILED" in raw.decode()
    program = gzip.decompress((replay_dir / (ident + ".goto.txt.gz")).read_bytes())
    assert hashlib.sha256(program).hexdigest() == comparison[ident]["goto_sha256"]
    assert comparison[ident]["goto_bytes_identical_with_trace"] is True
    assert comparison[ident]["stubs"] == sorted(results[ident]["stubs"])
def dto_call_checks(text):
    """Inspect every loaded call site, including both virtual-dispatch alternatives."""
    pre = "java::jdk.internal.util.Preconditions.checkFromIndexSize:(IIILjava/util/function/BiFunction;)I"
    objects = "java::java.util.Objects.checkFromIndexSize:(III)I"
    writes = ["java::java.io.ByteArrayOutputStream.write:([BII)V",
              "java::java.io.OutputStream.write:([BII)V"]
    whole = "java::java.io.OutputStream.write:([B)V"
    logging = ["java::java.lang.ThreadLocal.remove:()V",
               "java::org.ethereum.datasource.DataSourceWithCache.emitLogs:()V"]
    calls = {target: [] for target in [pre, objects] + writes + logging}
    function = None
    for line in text.splitlines():
        header = re.match(r"^\S.* /\* (java::\S+|\S+) \*/$", line)
        if header:
            function = header.group(1)
        for target in calls:
            if "CALL" in line and target + "(" in line:
                assert re.search(r"\bCALL " + re.escape(target) + r"\(", line), line
                calls[target].append({"caller": function, "instruction": line.strip()})
    assert len(calls[pre]) == 1 and calls[pre][0]["caller"] == objects
    assert "cast(NULL, struct java::java.util.function.BiFunction*)" in calls[pre][0]["instruction"]
    assert {r["caller"] for r in calls[objects]} == set(writes)
    for target in writes:
        assert len(calls[target]) == 1 and calls[target][0]["caller"] == whole
        assert (", 0, *(cast(" + whole + "::b, struct java::array[reference]*)).length)") in calls[target][0]["instruction"]
    for target in logging:
        assert all(r["caller"] == "java::co.rsk.trie.TrieStoreImpl.save:(Lco/rsk/trie/Trie;)V"
                   for r in calls[target])
    return calls


inspection_dir = EVIDENCE / "callsite-review"
inspection = json.loads((inspection_dir / "inspection.json").read_text())
assert inspection["tool_version"] == executor["jbmc_version"]
assert inspection["classpath_sha256"]["3"] == [r["sha256"] for r in executor["classpath"]]
assert inspection["static_values_sha256"] == executor["sources"]["models/static-values.json"]
assert len(inspection["results"]) == 1
row = inspection["results"][0]
assert row["id"] == "dto-embedded-long-value" and row["exit_code"] == 0
assert row["normalized_argv"] == executor["argv"][row["id"]] + ["--show-goto-functions"]
compressed = (inspection_dir / (row["id"] + ".goto.txt.gz")).read_bytes()
assert hashlib.sha256(compressed).hexdigest() == row["gzip_sha256"]
program = gzip.decompress(compressed)
assert hashlib.sha256(program).hexdigest() == row["goto_sha256"]
text = program.decode()
calls = dto_call_checks(text)
assert all(calls[target] == row["calls"][target] for target in calls)
for changed in ("", text.replace(", 0, *(cast(java::java.io.OutputStream.write:([B)V::b,", ", 1, *(cast(java::java.io.OutputStream.write:([B)V::b,"),
                text.replace("cast(NULL, struct java::java.util.function.BiFunction*)", "nonnull_callback"),
                text.replace("java::java.io.OutputStream.write:([B)V */", "java::Unexpected.caller:()V */")):
    assert changed != text
    try:
        dto_call_checks(changed)
    except AssertionError:
        pass
    else:
        raise AssertionError("Invalid DTO call chain accepted")
runpy.run_path(str(EVIDENCE / "store-review/check.py"), run_name="__main__")
print("Historical audit checks passed: ten exact exceptions, no original reviews outstanding; "
      "three original traces, two trace replays and three positive loaded-program reviews.")
