#!/usr/bin/env bash
# Builds the Lean model and proofs from scratch with warnings as errors, checks that no delivered
# theorem depends on `sorryAx`, that the sources contain no `sorry`/`admit`/`axiom`, runs the
# Keccak test vectors and the smoke differential cases.
#   verification/trie/lean/scripts/check.sh
set -euo pipefail
LEAN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$LEAN_DIR/../env.sh"
cd "$LEAN_DIR"

echo "== clean build (warnings are errors)"
rm -rf .lake/build
lake build --wfail

echo "== no sorry / admit / axiom in sources"
if grep -rnwE 'sorry|admit' --include='*.lean' RskjTrie RskjTrie.lean TrieDiff.lean Audit.lean test; then
  echo "FAIL: sorry/admit found"; exit 1
fi
if grep -rnE '^[[:space:]]*(@\[[^]]*\][[:space:]]*)?((private|protected|noncomputable|unsafe)[[:space:]]+)*axiom[[:space:]]' \
    --include='*.lean' RskjTrie RskjTrie.lean TrieDiff.lean Audit.lean test; then
  echo "FAIL: axiom declaration found"; exit 1
fi

echo "== axiom audit"
audit="$(lake env lean Audit.lean 2>&1)"
echo "$audit"
if grep -q 'sorryAx' <<<"$audit"; then echo "FAIL: a theorem depends on sorryAx"; exit 1; fi
if grep -qiE '^.*error' <<<"$audit"; then echo "FAIL: Audit.lean did not compile"; exit 1; fi
bad="$(grep -oE '\[[^]]*\]' <<<"$audit" | tr -d '[] ' | tr ',' '\n' | sort -u | grep -vxE 'propext|Quot.sound|Classical.choice' || true)"
if [ -n "$bad" ]; then echo "FAIL: unexpected axioms: $bad"; exit 1; fi

echo "== Keccak-256 test vectors"
lake env lean test/KeccakTest.lean

echo "== smoke differential cases (expected output = real Java DiffRunner output)"
"$LEAN_DIR/.lake/build/bin/trie-diff" < test/smoke.cases | diff -u test/smoke.expected -

echo "OK"
