#!/usr/bin/env bash
# Packs a self-contained JBMC batch for a second executor (same arch: macOS arm64).
#
#   verification/trie/jbmc/make-batch.sh BATCH_ID VALIDATION_IDS_FILE WORK_IDS_FILE
#
# Writes ~/trie-batches/BATCH_ID/ (override TRIE_BATCHES):
#   trie.tar.gz   verification/trie without .tools, logs, jbmc/build, jbmc/results, lean/.lake
#   deps.tar.gz   what .tools provides here, in the same relative layout: the JBMC binary (links only
#                 system libraries) and its models library, the rskj-core classes and runtime jars of
#                 the pinned commit, and this JDK 17 (so the extracted JDK bytecode is identical)
#   classpath.rel rskj classpath, entries relative to verification/trie, in the original order
#   validation.txt, work.txt   harness ids; validation ids run first, the work list after
#   memory-hints.tsv  id<TAB>peak RSS MB measured here (results/summary.json peak_rss_mb) or "unknown"
#   run-batch.sh  executor entry point (copied from jbmc/run-batch.sh)
#   evidence/     optional (EVIDENCE_DIR): reference invocation manifest, logs and diffs
#   trie.tar.gz also carries trie/SOURCE: the source commit this batch was packed from
#   SHA256SUMS    sha256 of every file above
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../env.sh"
ID="$1"; VAL="$2"; WORK="$3"
JDK17="${JDK17:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
OUT="${TRIE_BATCHES:-$HOME/trie-batches}/$ID"
[ -e "$OUT" ] && { echo "exists: $OUT" >&2; exit 2; }
mkdir -p "$OUT"
known="$(python3 -c "import json;print('\n'.join(e['id'] for e in json.load(open('$HERE/harnesses.json'))['harnesses']))")"
for i in $(cat "$VAL" "$WORK"); do grep -qx "$i" <<<"$known" || { echo "unknown id: $i" >&2; exit 2; }; done

S="$(mktemp -d)"; trap 'rm -rf "$S"' EXIT
# packed from a staging copy so the batch can carry SOURCE (the source commit, read by invocation.py)
mkdir -p "$S/stage"
rsync -a --exclude '/trie/.tools' --exclude '/trie/logs' --exclude '/trie/jbmc/build' --exclude '/trie/jbmc/results' \
  --exclude '/trie/lean/.lake' "$TRIE_VERIFY" "$S/stage/"
python3 -c "import sys; sys.path.insert(0, '$HERE'); import invocation; print(invocation.source_commit('$HERE'), '| batch $ID')" > "$S/stage/trie/SOURCE"
tar -czf "$OUT/trie.tar.gz" -C "$S/stage" trie
D="$S/.tools"; mkdir -p "$D/cbmc/jbmc/src/jbmc" "$D/cbmc/jbmc/lib/java-models-library/target" "$D/deps/jars"
cp "$TRIE_VERIFY/.tools/cbmc/jbmc/src/jbmc/jbmc" "$D/cbmc/jbmc/src/jbmc/"
cp "$TRIE_VERIFY/.tools/cbmc/jbmc/lib/java-models-library/target/"{core-models,cprover-api}.jar "$D/cbmc/jbmc/lib/java-models-library/target/"
cp -R "$JDK17" "$D/deps/jdk17"
: > "$OUT/classpath.rel"
n=0
for e in $(rskj_classpath | tr ':' '\n'); do
  case "$e" in
    *.jar) cp "$e" "$D/deps/jars/"; echo ".tools/deps/jars/$(basename "$e")" >> "$OUT/classpath.rel" ;;
    *) n=$((n+1)); cp -R "$e" "$D/deps/rskj$n"; echo ".tools/deps/rskj$n" >> "$OUT/classpath.rel" ;;
  esac
done
tar -czf "$OUT/deps.tar.gz" -C "$S" .tools
cp "$VAL" "$OUT/validation.txt"; cp "$WORK" "$OUT/work.txt"
python3 - "$HERE/results/summary.json" $(cat "$VAL" "$WORK") > "$OUT/memory-hints.tsv" <<'PY'
import json, os, sys
p = sys.argv[1]
R = {r["id"]: r for r in json.load(open(p))["results"]} if os.path.exists(p) else {}
print("id\tpeak_rss_mb")
for i in sys.argv[2:]:
    mb = R.get(i, {}).get("peak_rss_mb")
    print("%s\t%s" % (i, mb if mb else "unknown"))
PY
cp "$HERE/run-batch.sh" "$OUT/run-batch.sh"; chmod +x "$OUT/run-batch.sh"
if [ -n "${EVIDENCE_DIR:-}" ]; then cp -R "$EVIDENCE_DIR" "$OUT/evidence"; fi
(cd "$OUT" && find . -type f ! -name SHA256SUMS | sed 's|^\./||' | sort | xargs shasum -a 256 > SHA256SUMS)
echo "$OUT"; cat "$OUT/SHA256SUMS"
