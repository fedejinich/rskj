#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

ensure_rust_jni_library_path() {
  if [[ -n "${UNITRIE_RUST_JNI_LIBRARY_PATH:-}" && -f "${UNITRIE_RUST_JNI_LIBRARY_PATH}" ]]; then
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
      export UNITRIE_RUST_JNI_LIBRARY_PATH="${candidate}"
      return 0
    fi
  done

  echo "[unitrie] JNI library not found in release target, building it first"
  cargo build --manifest-path "${REPO_ROOT}/unitrie-rs/Cargo.toml" --release

  for candidate in "${candidates[@]}"; do
    if [[ -f "${candidate}" ]]; then
      export UNITRIE_RUST_JNI_LIBRARY_PATH="${candidate}"
      return 0
    fi
  done

  echo "Could not find unitrie JNI library after build" >&2
  exit 1
}

ensure_rust_jni_library_path
JNI_LIBRARY_DIR="$(dirname "${UNITRIE_RUST_JNI_LIBRARY_PATH}")"
export JAVA_TOOL_OPTIONS="-Djava.library.path=${JNI_LIBRARY_DIR}${JAVA_TOOL_OPTIONS:+ ${JAVA_TOOL_OPTIONS}}"

echo "[unitrie] validating reusable core crate parity (legacy-v1 vs next)"
cargo test --manifest-path "${REPO_ROOT}/unitrie-rs-core/Cargo.toml"

echo "[unitrie] validating java differential replay against rust legacy+next"
(
  cd "${REPO_ROOT}"
  ./gradlew --no-daemon :rskj-core:test \
    --tests co.rsk.trie.engine.rust.UnitrieDifferentialCorpusReplayTest
)

echo "[unitrie] reusable-core validation completed"
