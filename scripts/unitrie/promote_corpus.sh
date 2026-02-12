#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEFAULT_CORPUS_DIR="${REPO_ROOT}/rskj-core/build/reports/unitrie-validation/corpus"
TARGET_DIR="${REPO_ROOT}/rskj-core/src/test/resources/trie/differential"

resolve_source() {
  if [[ $# -ge 1 ]]; then
    echo "$1"
    return 0
  fi

  if [[ ! -d "${DEFAULT_CORPUS_DIR}" ]]; then
    echo "" 
    return 0
  fi

  ls -1t "${DEFAULT_CORPUS_DIR}"/corpus-block-*.jsonl 2>/dev/null | head -n 1
}

SOURCE_PATH="$(resolve_source "$@")"
if [[ -z "${SOURCE_PATH}" ]]; then
  echo "No corpus file provided and no auto-generated corpus found in ${DEFAULT_CORPUS_DIR}" >&2
  exit 1
fi

if [[ ! -f "${SOURCE_PATH}" ]]; then
  echo "Corpus file not found: ${SOURCE_PATH}" >&2
  exit 1
fi

mkdir -p "${TARGET_DIR}"
TARGET_PATH="${TARGET_DIR}/$(basename "${SOURCE_PATH}")"

SOURCE_REAL="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${SOURCE_PATH}")"
TARGET_REAL="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${TARGET_PATH}")"

if [[ "${SOURCE_REAL}" == "${TARGET_REAL}" ]]; then
  echo "Corpus already promoted: ${TARGET_PATH}"
  exit 0
fi

cp "${SOURCE_PATH}" "${TARGET_PATH}"

echo "Promoted corpus: ${SOURCE_PATH}"
echo "Target resource: ${TARGET_PATH}"
