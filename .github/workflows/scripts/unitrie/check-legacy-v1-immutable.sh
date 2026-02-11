#!/usr/bin/env bash
set -euo pipefail

if [[ "${GITHUB_EVENT_NAME:-}" != "pull_request" ]]; then
  echo "Skipping immutable legacy check outside pull_request event."
  exit 0
fi

BASE_SHA="${GITHUB_BASE_SHA:-}"
HEAD_SHA="${GITHUB_SHA:-}"

if [[ -z "$BASE_SHA" || -z "$HEAD_SHA" ]]; then
  echo "Missing GITHUB_BASE_SHA or GITHUB_SHA for immutable legacy check."
  exit 1
fi

CHANGED_FILES=$(git diff --name-only "$BASE_SHA" "$HEAD_SHA" -- unitrie-rs-legacy-v1 || true)
if [[ -n "$CHANGED_FILES" ]]; then
  echo "Detected forbidden changes under unitrie-rs-legacy-v1:"
  echo "$CHANGED_FILES"
  echo "unitrie-rs-legacy-v1 is immutable. Apply changes in unitrie-rs instead."
  exit 1
fi

echo "Immutable legacy check passed: no changes in unitrie-rs-legacy-v1."
