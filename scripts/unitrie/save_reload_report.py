#!/usr/bin/env python3
"""Extract saveReloadCycle-focused KPI report from JMH artifacts."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Dict, Optional


def load_json(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def find_result(summary: Dict[str, Any], benchmark: str, engine: str) -> Optional[Dict[str, Any]]:
    for row in summary.get("results", []):
        if row.get("benchmark") == benchmark and row.get("engine") == engine:
            return row
    return None


def find_jni_row(jni_breakdown: Dict[str, Any], benchmark: str, candidate: str) -> Optional[Dict[str, Any]]:
    for row in jni_breakdown.get("rows", []):
        if row.get("benchmark") == benchmark and row.get("candidate") == candidate:
            return row
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate saveReloadCycle KPI report.")
    parser.add_argument(
        "--summary",
        default="rskj-core/build/reports/jmh/result_trie_engine_summary.json",
        help="Path to result_trie_engine_summary.json",
    )
    parser.add_argument(
        "--jni-breakdown",
        default="rskj-core/build/reports/jmh/result_trie_engine_jni_breakdown.json",
        help="Path to result_trie_engine_jni_breakdown.json",
    )
    parser.add_argument(
        "--benchmark",
        default="saveReloadCycle",
        help="Workload name to report (default: saveReloadCycle)",
    )
    parser.add_argument(
        "--java-engine",
        default="java",
        help="Java engine label in summary.json (default: java)",
    )
    parser.add_argument(
        "--rust-engine",
        default="rust(next)",
        help="Rust engine label in summary.json (default: rust(next))",
    )
    parser.add_argument(
        "--rust-candidate",
        default="rust(next)",
        help="Rust candidate label in jni breakdown (default: rust(next))",
    )
    parser.add_argument(
        "--out",
        default="rskj-core/build/reports/jmh/result_trie_save_reload_focus.json",
        help="Output JSON path",
    )
    args = parser.parse_args()

    summary_path = Path(args.summary)
    jni_path = Path(args.jni_breakdown)
    output_path = Path(args.out)

    summary = load_json(summary_path)
    jni_breakdown = load_json(jni_path)

    java_row = find_result(summary, args.benchmark, args.java_engine)
    rust_row = find_result(summary, args.benchmark, args.rust_engine)
    jni_row = find_jni_row(jni_breakdown, args.benchmark, args.rust_candidate)

    if java_row is None:
        raise SystemExit(f"Missing Java row for benchmark={args.benchmark} engine={args.java_engine}")
    if rust_row is None:
        raise SystemExit(f"Missing Rust row for benchmark={args.benchmark} engine={args.rust_engine}")

    java_metrics = java_row.get("metrics", {})
    rust_metrics = rust_row.get("metrics", {})

    rust_nodes_saved = rust_metrics.get("rustNodesSavedPerOp")
    rust_dirty_nodes_saved = rust_metrics.get("rustDirtyNodesSavedPerOp")
    dirty_ratio = None
    if isinstance(rust_nodes_saved, (int, float)) and rust_nodes_saved > 0 and isinstance(
        rust_dirty_nodes_saved, (int, float)
    ):
        dirty_ratio = rust_dirty_nodes_saved / rust_nodes_saved

    payload: Dict[str, Any] = {
        "generatedAt": summary.get("generatedAt"),
        "gitCommit": summary.get("gitCommit"),
        "benchmark": args.benchmark,
        "java": {
            "engine": args.java_engine,
            "avgMicros": java_metrics.get("avgMicros"),
            "p95Micros": java_metrics.get("p95Micros"),
            "throughputOpsPerSec": java_metrics.get("throughputOpsPerSec"),
        },
        "rust": {
            "engine": args.rust_engine,
            "avgMicros": rust_metrics.get("avgMicros"),
            "p95Micros": rust_metrics.get("p95Micros"),
            "throughputOpsPerSec": rust_metrics.get("throughputOpsPerSec"),
            "storeCallbackCallsPerOp": rust_metrics.get("rustStoreCallbackCallsPerOp"),
            "storeCallbackNsPerOp": rust_metrics.get("rustStoreCallbackNsPerOp"),
            "nodesLoadedFromStorePerOp": rust_metrics.get("rustNodesLoadedFromStorePerOp"),
            "nodesDecodedPerOp": rust_metrics.get("rustNodesDecodedPerOp"),
            "nodesSavedPerOp": rust_nodes_saved,
            "dirtyNodesSavedPerOp": rust_dirty_nodes_saved,
            "dirtyNodesSavedRatio": dirty_ratio,
            "rehydrateRootOnlyCountPerOp": rust_metrics.get("rustRehydrateRootOnlyCountPerOp"),
            "rehydrateFullScanFallbackCountPerOp": rust_metrics.get(
                "rustRehydrateFullScanFallbackCountPerOp"
            ),
        },
        "jniBreakdown": jni_row if jni_row is not None else {},
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=False)
        handle.write("\n")

    print(f"saveReloadCycle focus report: {output_path}")
    print(json.dumps(payload, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
