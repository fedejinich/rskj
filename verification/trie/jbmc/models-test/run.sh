#!/usr/bin/env bash
# Differential test of the JBMC environment models against the real JDK 17 classes (on the JVM).
# The model sources are copied with their package renamed to jbmcmodel.<package> so they can be
# loaded next to the real classes. Usage: models-test/run.sh [iterations] [seed]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../../env.sh"
JDK17="${JDK17:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
OUT="$HERE/../build/models-test"
rm -rf "$OUT" && mkdir -p "$OUT/src" "$OUT/classes"
CPROVER="$TRIE_VERIFY/.tools/cbmc/jbmc/lib/java-models-library/target/cprover-api.jar"
for f in java/lang/System.java java/nio/ByteBuffer.java jdk/internal/util/ArraysSupport.java; do
  pkg="$(dirname "$f" | tr / .)"
  mkdir -p "$OUT/src/jbmcmodel/$(dirname "$f")"
  sed -e "s/^package $pkg;/package jbmcmodel.$pkg; import $pkg.*;/" "$HERE/../models/src/$f" \
    > "$OUT/src/jbmcmodel/$f"
done
X="--add-exports java.base/jdk.internal.util=ALL-UNNAMED"
RSKJ_CP="$(rskj_classpath)"
cp "$HERE/../models/src/jbmcenv/MemoryKeyValueDataSource.java" "$HERE/../models/src/jbmcenv/Observe.java" "$OUT/src/"
"$JDK17/bin/javac" $X -cp "$CPROVER:$RSKJ_CP" -d "$OUT/classes" $(find "$OUT/src" -name '*.java') "$HERE/ModelsDiffTest.java"
"$JDK17/bin/java" $X -cp "$OUT/classes:$CPROVER:$RSKJ_CP" ModelsDiffTest "$@"
