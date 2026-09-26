#!/usr/bin/env bash
# Runs every case file on the real Java classes and on the executable Lean model and requires
# byte-identical output. Usage: differential/run.sh [cases/foo.cases ...]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../env.sh"
CP="$(rskj_classpath)"
OUT="$HERE/results"
CLASSES="$TRIE_VERIFY/.tools/differential-classes"
mkdir -p "$OUT" "$CLASSES"

javac --release 17 -cp "$CP" -d "$CLASSES" "$HERE/java/DiffRunner.java"
(cd "$TRIE_VERIFY/lean" && lake build trie-diff >/dev/null)
LEAN_EXE="$TRIE_VERIFY/lean/.lake/build/bin/trie-diff"

[ $# -gt 0 ] || set -- "$HERE"/cases/*.cases
fail=0
entries=()
for f in "$@"; do
  name="$(basename "$f" .cases)"
  java -cp "$CLASSES:$CP" DiffRunner < "$f" > "$OUT/$name.java.out" 2> "$OUT/$name.java.err"
  "$LEAN_EXE" < "$f" > "$OUT/$name.lean.out"
  n="$(grep -c '^case ' "$OUT/$name.java.out")"
  lines="$(wc -l < "$OUT/$name.java.out" | tr -d ' ')"
  if cmp -s "$OUT/$name.java.out" "$OUT/$name.lean.out"; then
    echo "PASS $name: $n cases, $lines identical output lines"
    entries+=("{\"name\": \"$name\", \"cases\": $n, \"lines\": $lines, \"pass\": true}")
  else
    entries+=("{\"name\": \"$name\", \"cases\": $n, \"lines\": $lines, \"pass\": false}")
    echo "FAIL $name: first difference:"
    diff "$OUT/$name.java.out" "$OUT/$name.lean.out" | head -20
    fail=1
  fi
done
(IFS=,; echo "{\"files\": [${entries[*]}]}") > "$OUT/summary.json"
exit $fail
