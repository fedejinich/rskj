#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPORT_DIR="${REPO_ROOT}/rskj-core/build/reports/jmh"
RUN_GROUP_ID="$(date -u +%Y%m%d-%H%M%S)"
RUNS_DIR="${REPORT_DIR}/deep-runs/${RUN_GROUP_ID}"
MEDIAN_OUTPUT="${REPORT_DIR}/result_trie_engine_median_summary.json"

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

ensure_rust_library_path

export UNITRIE_JMH_WARMUP_ITERATIONS="${UNITRIE_JMH_WARMUP_ITERATIONS:-5}"
export UNITRIE_JMH_MEASUREMENT_ITERATIONS="${UNITRIE_JMH_MEASUREMENT_ITERATIONS:-15}"
export UNITRIE_JMH_WARMUP_SECONDS="${UNITRIE_JMH_WARMUP_SECONDS:-10}"
export UNITRIE_JMH_MEASUREMENT_SECONDS="${UNITRIE_JMH_MEASUREMENT_SECONDS:-10}"
export UNITRIE_JMH_FORKS="${UNITRIE_JMH_FORKS:-1}"
export UNITRIE_JMH_ENGINES="${UNITRIE_JMH_ENGINES:-java,rust}"
export UNITRIE_JMH_RUST_IMPLEMENTATIONS="${UNITRIE_JMH_RUST_IMPLEMENTATIONS:-next}"

for attempt in 1 2 3; do
  echo "[unitrie] deep benchmark run ${attempt}/3"
  (
    cd "${REPO_ROOT}"
    ./gradlew --no-daemon --stacktrace :rskj-core:jmh -Pbenchmark=BenchmarkTrieEngineRunner
  )

  cp "${REPORT_DIR}/result_trie_engine.csv" "${RUNS_DIR}/result_trie_engine_run${attempt}.csv"
  cp "${REPORT_DIR}/result_trie_engine_summary.json" "${RUNS_DIR}/result_trie_engine_summary_run${attempt}.json"
  cp "${REPORT_DIR}/result_trie_engine_comparison.md" "${RUNS_DIR}/result_trie_engine_comparison_run${attempt}.md"
done

python3 "${REPO_ROOT}/scripts/unitrie/benchmark_median_report.py" \
  --runs-dir "${RUNS_DIR}" \
  --output "${MEDIAN_OUTPUT}" \
  --candidate "rust(next)"

echo "Deep benchmark 3x complete."
echo "Run snapshots: ${RUNS_DIR}"
echo "Median summary: ${MEDIAN_OUTPUT}"
