#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "[unitrie] validating reusable core crate parity (legacy-v1 vs next)"
cargo test --manifest-path "${REPO_ROOT}/unitrie-rs-core/Cargo.toml"

echo "[unitrie] validating java differential replay against rust legacy+next"
(
  cd "${REPO_ROOT}"
  ./gradlew --no-daemon :rskj-core:test \
    --tests co.rsk.trie.engine.rust.UnitrieDifferentialCorpusReplayTest
)

echo "[unitrie] reusable-core validation completed"
