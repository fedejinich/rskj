#!/usr/bin/env python3
"""Merge Java core JMH and Rust core benchmark summaries into one comparison artifact."""

from __future__ import annotations

import argparse
import json
import pathlib
from datetime import datetime, timezone
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Merge Java core and Rust core trie benchmark summaries")
    parser.add_argument(
        "--java-summary",
        default="rskj-core/build/reports/jmh/result_trie_engine_summary.json",
        help="Path to JMH summary produced by TrieJavaCoreBenchmark",
    )
    parser.add_argument(
        "--rust-summary",
        default="rskj-core/build/reports/jmh/result_trie_rust_core_summary.json",
        help="Path to rust core summary produced by core_trie_bench.rs",
    )
    parser.add_argument(
        "--output",
        default="rskj-core/build/reports/jmh/result_trie_core_comparison.json",
        help="Output JSON path",
    )
    return parser.parse_args()


def load_json(path: pathlib.Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def main() -> int:
    args = parse_args()
    java_path = pathlib.Path(args.java_summary)
    rust_path = pathlib.Path(args.rust_summary)
    output_path = pathlib.Path(args.output)

    if not java_path.exists():
        raise SystemExit(f"Java summary not found: {java_path}")
    if not rust_path.exists():
        raise SystemExit(f"Rust summary not found: {rust_path}")

    java_summary = load_json(java_path)
    rust_summary = load_json(rust_path)

    java_by_workload = index_java_results(java_summary)
    rust_by_workload = index_rust_results(rust_summary)

    workloads = sorted(set(java_by_workload) | set(rust_by_workload))
    rows: list[dict[str, Any]] = []
    for workload in workloads:
        java_metrics = java_by_workload.get(workload)
        rust_metrics = rust_by_workload.get(workload)
        rows.append(
            {
                "benchmark": workload,
                "java": java_metrics,
                "rust": rust_metrics,
                "deltaPct": {
                    "avgMicros": pct_change_lower_is_better(java_metrics, rust_metrics, "avgMicros"),
                    "p95Micros": pct_change_lower_is_better(java_metrics, rust_metrics, "p95Micros"),
                    "throughputOpsPerSec": pct_change_higher_is_better(
                        java_metrics,
                        rust_metrics,
                        "throughputOpsPerSec",
                    ),
                },
            }
        )

    payload = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "javaSummary": str(java_path.resolve()),
        "rustSummary": str(rust_path.resolve()),
        "rows": rows,
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)

    print(f"Core benchmark comparison written to {output_path.resolve()}")
    return 0


def index_java_results(summary: dict[str, Any]) -> dict[str, dict[str, float]]:
    indexed: dict[str, dict[str, float]] = {}
    for row in summary.get("results", []):
        if not isinstance(row, dict):
            continue
        if row.get("engine") != "java":
            continue
        benchmark = row.get("benchmark")
        metrics = row.get("metrics")
        if not isinstance(benchmark, str) or not isinstance(metrics, dict):
            continue
        indexed[benchmark] = {
            "avgMicros": as_float(metrics.get("avgMicros")),
            "p95Micros": as_float(metrics.get("p95Micros")),
            "throughputOpsPerSec": as_float(metrics.get("throughputOpsPerSec")),
        }
    return indexed


def index_rust_results(summary: dict[str, Any]) -> dict[str, dict[str, float]]:
    indexed: dict[str, dict[str, float]] = {}
    for row in summary.get("workloads", []):
        if not isinstance(row, dict):
            continue
        benchmark = row.get("benchmark")
        metrics = row.get("metrics")
        if not isinstance(benchmark, str) or not isinstance(metrics, dict):
            continue
        indexed[benchmark] = {
            "avgMicros": as_float(metrics.get("avgMicros")),
            "p95Micros": as_float(metrics.get("p95Micros")),
            "throughputOpsPerSec": as_float(metrics.get("throughputOpsPerSec")),
        }
    return indexed


def as_float(value: Any) -> float | None:
    if isinstance(value, (int, float)):
        return float(value)
    return None


def pct_change_lower_is_better(
    java_metrics: dict[str, float] | None,
    rust_metrics: dict[str, float] | None,
    metric: str,
) -> float | None:
    baseline = value_or_none(java_metrics, metric)
    candidate = value_or_none(rust_metrics, metric)
    if baseline is None or candidate is None or baseline == 0.0:
        return None
    return ((candidate - baseline) / baseline) * 100.0


def pct_change_higher_is_better(
    java_metrics: dict[str, float] | None,
    rust_metrics: dict[str, float] | None,
    metric: str,
) -> float | None:
    baseline = value_or_none(java_metrics, metric)
    candidate = value_or_none(rust_metrics, metric)
    if baseline is None or candidate is None or baseline == 0.0:
        return None
    return ((candidate - baseline) / baseline) * 100.0


def value_or_none(metrics: dict[str, float] | None, key: str) -> float | None:
    if metrics is None:
        return None
    value = metrics.get(key)
    if not isinstance(value, (int, float)):
        return None
    return float(value)


if __name__ == "__main__":
    raise SystemExit(main())
