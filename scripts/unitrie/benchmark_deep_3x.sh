#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPORT_DIR="${REPO_ROOT}/rskj-core/build/reports/jmh"
RUN_GROUP_ID="$(date -u +%Y%m%d-%H%M%S)"
RUNS_DIR="${REPORT_DIR}/deep-runs/${RUN_GROUP_ID}"
MEDIAN_OUTPUT="${REPORT_DIR}/result_trie_engine_median_summary.json"
JNI_MICRO_OUTPUT="${REPORT_DIR}/result_trie_jni_microbench.json"
JAVA_CORE_OUTPUT="${REPORT_DIR}/result_trie_java_core_summary.json"
RUST_CORE_OUTPUT="${REPORT_DIR}/result_trie_rust_core_summary.json"
CORE_COMPARISON_OUTPUT="${REPORT_DIR}/result_trie_core_comparison.json"
SAVE_RELOAD_FOCUS_OUTPUT="${REPORT_DIR}/result_trie_save_reload_focus.json"

MODE="e2e"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--mode e2e|jni-micro|full]

Modes:
  e2e       Run deep 3x end-to-end trie engine benchmark (default)
  jni-micro Run JNI-only micro-overhead benchmark
  full      Run e2e + jni-micro + java-core + rust-core + merge report
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "${MODE}" != "e2e" && "${MODE}" != "jni-micro" && "${MODE}" != "full" ]]; then
  echo "Unsupported mode: ${MODE}" >&2
  usage >&2
  exit 1
fi

mkdir -p "${RUNS_DIR}"

ensure_rust_library_path() {
  if [[ -n "${UNITRIE_JMH_RUST_LIBRARY_PATH:-}" && -f "${UNITRIE_JMH_RUST_LIBRARY_PATH}" ]]; then
    return 0
  fi

  local release_dir="${REPO_ROOT}/unitrie-rs/target/release"
  local candidates=(
    "${release_dir}/libunitrie_rs_jni.so"
    "${release_dir}/libunitrie_rs_jni.dylib"
    "${release_dir}/unitrie_rs_jni.dll"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -f "${candidate}" ]]; then
      export UNITRIE_JMH_RUST_LIBRARY_PATH="${candidate}"
      return 0
    fi
  done

  echo "Rust JNI library not found in target/release. Building release library..."
  cargo build --manifest-path "${REPO_ROOT}/unitrie-rs/Cargo.toml" --release

  for candidate in "${candidates[@]}"; do
    if [[ -f "${candidate}" ]]; then
      export UNITRIE_JMH_RUST_LIBRARY_PATH="${candidate}"
      return 0
    fi
  done

  echo "Could not locate built JNI library for unitrie-rs." >&2
  exit 1
}

run_gradle_benchmark() {
  (
    cd "${REPO_ROOT}"
    ./gradlew --no-daemon --stacktrace :rskj-core:jmh -Pbenchmark=BenchmarkTrieEngineRunner
  )
}

run_e2e_deep_3x() {
  export UNITRIE_JMH_WARMUP_ITERATIONS="${UNITRIE_JMH_WARMUP_ITERATIONS:-5}"
  export UNITRIE_JMH_MEASUREMENT_ITERATIONS="${UNITRIE_JMH_MEASUREMENT_ITERATIONS:-15}"
  export UNITRIE_JMH_WARMUP_SECONDS="${UNITRIE_JMH_WARMUP_SECONDS:-10}"
  export UNITRIE_JMH_MEASUREMENT_SECONDS="${UNITRIE_JMH_MEASUREMENT_SECONDS:-10}"
  export UNITRIE_JMH_FORKS="${UNITRIE_JMH_FORKS:-1}"
  export UNITRIE_JMH_ENGINES="${UNITRIE_JMH_ENGINES:-java,rust}"
  export UNITRIE_JMH_RUST_IMPLEMENTATIONS="${UNITRIE_JMH_RUST_IMPLEMENTATIONS:-next}"
  export UNITRIE_JMH_INCLUDE="${UNITRIE_JMH_INCLUDE:-TrieEngineBenchmark}"

  for attempt in 1 2 3; do
    echo "[unitrie] deep e2e benchmark run ${attempt}/3"
    run_gradle_benchmark

    cp "${REPORT_DIR}/result_trie_engine.csv" "${RUNS_DIR}/result_trie_engine_run${attempt}.csv"
    cp "${REPORT_DIR}/result_trie_engine_summary.json" "${RUNS_DIR}/result_trie_engine_summary_run${attempt}.json"
    cp "${REPORT_DIR}/result_trie_engine_comparison.md" "${RUNS_DIR}/result_trie_engine_comparison_run${attempt}.md"
    if [[ -f "${REPORT_DIR}/result_trie_engine_jni_breakdown.json" ]]; then
      cp "${REPORT_DIR}/result_trie_engine_jni_breakdown.json" "${RUNS_DIR}/result_trie_engine_jni_breakdown_run${attempt}.json"
    fi
    if [[ -f "${REPORT_DIR}/result_trie_engine_summary.json" && -f "${REPORT_DIR}/result_trie_engine_jni_breakdown.json" ]]; then
      python3 "${REPO_ROOT}/scripts/unitrie/save_reload_report.py" \
        --summary "${REPORT_DIR}/result_trie_engine_summary.json" \
        --jni-breakdown "${REPORT_DIR}/result_trie_engine_jni_breakdown.json" \
        --out "${RUNS_DIR}/result_trie_save_reload_focus_run${attempt}.json"
    fi
  done

  python3 "${REPO_ROOT}/scripts/unitrie/benchmark_median_report.py" \
    --runs-dir "${RUNS_DIR}" \
    --output "${MEDIAN_OUTPUT}" \
    --candidate "rust(next)"
  if [[ -f "${REPORT_DIR}/result_trie_engine_summary.json" && -f "${REPORT_DIR}/result_trie_engine_jni_breakdown.json" ]]; then
    python3 "${REPO_ROOT}/scripts/unitrie/save_reload_report.py" \
      --summary "${REPORT_DIR}/result_trie_engine_summary.json" \
      --jni-breakdown "${REPORT_DIR}/result_trie_engine_jni_breakdown.json" \
      --out "${SAVE_RELOAD_FOCUS_OUTPUT}"
  fi

  echo "[unitrie] deep e2e 3x complete"
}

run_jni_micro() {
  local backup_dir
  backup_dir="$(mktemp -d "${REPORT_DIR}/jni-micro-backup.XXXXXX")"
  for artifact in \
    result_trie_engine.csv \
    result_trie_engine_summary.json \
    result_trie_engine_comparison.md \
    result_trie_engine_jni_breakdown.json
  do
    if [[ -f "${REPORT_DIR}/${artifact}" ]]; then
      cp "${REPORT_DIR}/${artifact}" "${backup_dir}/${artifact}"
    fi
  done

  export UNITRIE_JMH_WARMUP_ITERATIONS="${UNITRIE_JMH_WARMUP_ITERATIONS:-5}"
  export UNITRIE_JMH_MEASUREMENT_ITERATIONS="${UNITRIE_JMH_MEASUREMENT_ITERATIONS:-15}"
  export UNITRIE_JMH_WARMUP_SECONDS="${UNITRIE_JMH_WARMUP_SECONDS:-10}"
  export UNITRIE_JMH_MEASUREMENT_SECONDS="${UNITRIE_JMH_MEASUREMENT_SECONDS:-10}"
  export UNITRIE_JMH_FORKS="${UNITRIE_JMH_FORKS:-1}"
  export UNITRIE_JMH_ENGINES="rust"
  export UNITRIE_JMH_RUST_IMPLEMENTATIONS="next"
  export UNITRIE_JMH_INCLUDE="TrieJniOverheadBenchmark"

  echo "[unitrie] running JNI micro-overhead benchmark"
  run_gradle_benchmark
  if [[ ! -f "${JNI_MICRO_OUTPUT}" ]]; then
    echo "Missing JNI microbench report: ${JNI_MICRO_OUTPUT}" >&2
    exit 1
  fi

  for artifact in \
    result_trie_engine.csv \
    result_trie_engine_summary.json \
    result_trie_engine_comparison.md \
    result_trie_engine_jni_breakdown.json
  do
    if [[ -f "${backup_dir}/${artifact}" ]]; then
      mv "${backup_dir}/${artifact}" "${REPORT_DIR}/${artifact}"
    fi
  done
  rm -rf "${backup_dir}"
}

run_core_to_core() {
  local backup_dir
  backup_dir="$(mktemp -d "${REPORT_DIR}/core-run-backup.XXXXXX")"
  for artifact in \
    result_trie_engine.csv \
    result_trie_engine_summary.json \
    result_trie_engine_comparison.md \
    result_trie_engine_jni_breakdown.json \
    result_trie_jni_microbench.json
  do
    if [[ -f "${REPORT_DIR}/${artifact}" ]]; then
      cp "${REPORT_DIR}/${artifact}" "${backup_dir}/${artifact}"
    fi
  done

  export UNITRIE_JMH_WARMUP_ITERATIONS="${UNITRIE_JMH_WARMUP_ITERATIONS:-5}"
  export UNITRIE_JMH_MEASUREMENT_ITERATIONS="${UNITRIE_JMH_MEASUREMENT_ITERATIONS:-15}"
  export UNITRIE_JMH_WARMUP_SECONDS="${UNITRIE_JMH_WARMUP_SECONDS:-10}"
  export UNITRIE_JMH_MEASUREMENT_SECONDS="${UNITRIE_JMH_MEASUREMENT_SECONDS:-10}"
  export UNITRIE_JMH_FORKS="${UNITRIE_JMH_FORKS:-1}"
  export UNITRIE_JMH_ENGINES="java"
  export UNITRIE_JMH_RUST_IMPLEMENTATIONS="next"
  export UNITRIE_JMH_INCLUDE="TrieJavaCoreBenchmark"

  echo "[unitrie] running Java core benchmark"
  run_gradle_benchmark
  cp "${REPORT_DIR}/result_trie_engine_summary.json" "${JAVA_CORE_OUTPUT}"

  echo "[unitrie] running Rust core benchmark"
  (
    cd "${REPO_ROOT}"
    UNITRIE_RUST_CORE_BENCH_OUTPUT="${RUST_CORE_OUTPUT}" \
      cargo bench --manifest-path "${REPO_ROOT}/unitrie-rs/Cargo.toml" --bench core_trie_bench
  )

  echo "[unitrie] merging core-to-core comparison"
  python3 "${REPO_ROOT}/scripts/unitrie/merge_core_benchmarks.py" \
    --java-summary "${JAVA_CORE_OUTPUT}" \
    --rust-summary "${RUST_CORE_OUTPUT}" \
    --output "${CORE_COMPARISON_OUTPUT}"

  for artifact in \
    result_trie_engine.csv \
    result_trie_engine_summary.json \
    result_trie_engine_comparison.md \
    result_trie_engine_jni_breakdown.json \
    result_trie_jni_microbench.json
  do
    if [[ -f "${backup_dir}/${artifact}" ]]; then
      mv "${backup_dir}/${artifact}" "${REPORT_DIR}/${artifact}"
    fi
  done
  rm -rf "${backup_dir}"
}

ensure_rust_library_path

case "${MODE}" in
  e2e)
    run_e2e_deep_3x
    ;;
  jni-micro)
    run_jni_micro
    ;;
  full)
    run_e2e_deep_3x
    run_jni_micro
    run_core_to_core
    ;;
esac

echo "[unitrie] mode=${MODE} finished"
echo "[unitrie] reports dir: ${REPORT_DIR}"
echo "[unitrie] run snapshots: ${RUNS_DIR}"
