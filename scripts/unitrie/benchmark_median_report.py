#!/usr/bin/env python3
"""Compute median Java vs Rust benchmark decision from 3 deep JMH runs."""

from __future__ import annotations

import argparse
import json
import pathlib
import statistics
import sys
from datetime import datetime, timezone
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build median benchmark summary for trie engines")
    parser.add_argument("--runs-dir", required=True, help="Directory containing result_trie_engine_summary_run*.json")
    parser.add_argument(
        "--output",
        required=True,
        help="Output file path for median summary JSON",
    )
    parser.add_argument(
        "--candidate",
        default="rust(next)",
        help="Candidate rust engine label from summary.json (default: rust(next))",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    runs_dir = pathlib.Path(args.runs_dir)
    output_path = pathlib.Path(args.output)
    candidate_engine = args.candidate

    run_files = sorted(runs_dir.glob("result_trie_engine_summary_run*.json"))
    if not run_files:
        print(f"No run summaries found under {runs_dir}", file=sys.stderr)
        return 1

    runs: list[dict[str, Any]] = []
    for run_file in run_files:
        with run_file.open("r", encoding="utf-8") as handle:
            runs.append(json.load(handle))

    workloads = collect_workloads(runs)
    workload_summaries = []

    for workload in workloads:
        java_avg = collect_metric(runs, workload, "java", "avgMicros")
        rust_avg = collect_metric(runs, workload, candidate_engine, "avgMicros")
        java_p95 = collect_metric(runs, workload, "java", "p95Micros")
        rust_p95 = collect_metric(runs, workload, candidate_engine, "p95Micros")
        java_throughput = collect_metric(runs, workload, "java", "throughputOpsPerSec")
        rust_throughput = collect_metric(runs, workload, candidate_engine, "throughputOpsPerSec")

        java_avg_median = safe_median(java_avg)
        rust_avg_median = safe_median(rust_avg)
        java_p95_median = safe_median(java_p95)
        rust_p95_median = safe_median(rust_p95)
        java_throughput_median = safe_median(java_throughput)
        rust_throughput_median = safe_median(rust_throughput)

        avg_win = is_less(rust_avg_median, java_avg_median)
        p95_win = is_less_or_equal_multiplier(rust_p95_median, java_p95_median, 1.02)
        throughput_win = is_greater(rust_throughput_median, java_throughput_median)
        workload_win = avg_win and p95_win and throughput_win

        workload_summaries.append(
            {
                "benchmark": workload,
                "java": {
                    "avgMicrosMedian": java_avg_median,
                    "p95MicrosMedian": java_p95_median,
                    "throughputOpsPerSecMedian": java_throughput_median,
                },
                "candidate": {
                    "engine": candidate_engine,
                    "avgMicrosMedian": rust_avg_median,
                    "p95MicrosMedian": rust_p95_median,
                    "throughputOpsPerSecMedian": rust_throughput_median,
                },
                "decision": {
                    "avgWin": avg_win,
                    "p95Win": p95_win,
                    "throughputWin": throughput_win,
                    "workloadWin": workload_win,
                    "criteria": {
                        "avg": "rust avg_time < java avg_time",
                        "p95": "rust p95 <= java p95 * 1.02",
                        "throughput": "rust throughput > java throughput",
                    },
                },
            }
        )

    wins = sum(1 for workload in workload_summaries if workload["decision"]["workloadWin"])
    total = len(workload_summaries)

    payload = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "runsDir": str(runs_dir.resolve()),
        "runCount": len(run_files),
        "candidateEngine": candidate_engine,
        "runFiles": [str(path.resolve()) for path in run_files],
        "workloads": workload_summaries,
        "summary": {
            "totalWorkloads": total,
            "workloadsWon": wins,
            "workloadsLost": total - wins,
        },
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)

    print(
        "Median benchmark summary generated: "
        f"wins={wins}/{total} output={output_path.resolve()}"
    )
    return 0


def collect_workloads(runs: list[dict[str, Any]]) -> list[str]:
    workloads: set[str] = set()
    for run in runs:
        for result in run.get("results", []):
            benchmark = result.get("benchmark")
            if isinstance(benchmark, str):
                workloads.add(benchmark)
    return sorted(workloads)


def collect_metric(runs: list[dict[str, Any]], workload: str, engine: str, metric: str) -> list[float]:
    values: list[float] = []
    for run in runs:
        entry = find_result_entry(run, workload, engine)
        if entry is None:
            continue
        metrics = entry.get("metrics")
        if not isinstance(metrics, dict):
            continue
        value = metrics.get(metric)
        if isinstance(value, (int, float)):
            values.append(float(value))
    return values


def find_result_entry(run: dict[str, Any], workload: str, engine: str) -> dict[str, Any] | None:
    for result in run.get("results", []):
        if not isinstance(result, dict):
            continue
        if result.get("benchmark") == workload and result.get("engine") == engine:
            return result
    return None


def safe_median(values: list[float]) -> float | None:
    if not values:
        return None
    return float(statistics.median(values))


def is_less(candidate: float | None, baseline: float | None) -> bool:
    if candidate is None or baseline is None:
        return False
    return candidate < baseline


def is_greater(candidate: float | None, baseline: float | None) -> bool:
    if candidate is None or baseline is None:
        return False
    return candidate > baseline


def is_less_or_equal_multiplier(candidate: float | None, baseline: float | None, multiplier: float) -> bool:
    if candidate is None or baseline is None:
        return False
    return candidate <= baseline * multiplier


if __name__ == "__main__":
    sys.exit(main())
