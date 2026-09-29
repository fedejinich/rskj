#!/usr/bin/env bash
# Builds the pinned JBMC used by every harness in this directory into
# verification/trie/.tools (gitignored). Nothing is installed globally.
#
# Pins (sha256 of the downloaded archives):
#   CBMC/JBMC 6.11.0  commit 820ff0f555b43fb78e0cd9332e498461bd14244b
#   java-models-library commit c7835345cf635279cf59f4a286c05538f8026bd8
#   minisat 2.2.1 (Debian orig tarball, what CBMC's Makefile downloads)
#   Zulu JDK 8.0.504 + Maven 3.9.9, only to build JBMC's core-models.jar
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOOLS="$HERE/../.tools"
DL="$TOOLS/downloads"
mkdir -p "$DL"

fetch() { # url file sha256
  local url="$1" file="$DL/$2" sha="$3"
  [ -f "$file" ] || curl -sSfL -o "$file" "$url"
  echo "$sha  $file" | shasum -a 256 -c -
}

CBMC_SHA=820ff0f555b43fb78e0cd9332e498461bd14244b
MODELS_SHA=c7835345cf635279cf59f4a286c05538f8026bd8
fetch "https://github.com/diffblue/cbmc/archive/$CBMC_SHA.tar.gz" cbmc-6.11.0.tar.gz \
  0660e6c8a7526db68113ffe39d3900fc279eb6890aa846b04e1a772888e6c925
fetch "https://github.com/diffblue/java-models-library/archive/$MODELS_SHA.tar.gz" java-models-library-c783534.tar.gz \
  01712141cbb101f244f2cceeffd0af7398836b92c1db3690dae09114e0a00c2c
fetch http://ftp.debian.org/debian/pool/main/m/minisat2/minisat2_2.2.1.orig.tar.gz minisat2_2.2.1.orig.tar.gz \
  e54afa3c192c1753bc8075c0c7e126d5c495d9066e3f90a2588091149ac9ca40
fetch https://cdn.azul.com/zulu/bin/zulu8.96.0.205-ca-jdk8.0.504-macosx_aarch64.tar.gz zulu8-jdk.tar.gz \
  58bb3c08f2aa63d9743cf31899fa4b8c6c9effefce9479e7288c26621c3bb21b
fetch https://archive.apache.org/dist/maven/maven-3/3.9.9/binaries/apache-maven-3.9.9-bin.tar.gz apache-maven-3.9.9-bin.tar.gz \
  7a9cdf674fc1703d6382f5f330b3d110ea1b512b51f1652846d9e4e8a588d766

SRC="$TOOLS/cbmc"
if [ ! -d "$SRC" ]; then
  mkdir -p "$SRC"
  tar xzf "$DL/cbmc-6.11.0.tar.gz" -C "$SRC" --strip-components=1
  mkdir -p "$SRC/jbmc/lib/java-models-library"
  tar xzf "$DL/java-models-library-c783534.tar.gz" -C "$SRC/jbmc/lib/java-models-library" --strip-components=1
  # Same steps as CBMC's `make minisat2-download`, but from the verified tarball.
  tar xzf "$DL/minisat2_2.2.1.orig.tar.gz" -C "$SRC"
  mv "$SRC/minisat2-2.2.1" "$SRC/minisat-2.2.1"
  (cd "$SRC/minisat-2.2.1" && patch -p1 < ../scripts/minisat-2.2.1-patch)
fi
mkdir -p "$TOOLS/deps"
[ -d "$TOOLS/deps/jdk8" ] || { mkdir -p "$TOOLS/deps/jdk8"; tar xzf "$DL/zulu8-jdk.tar.gz" -C "$TOOLS/deps/jdk8" --strip-components=1; }
[ -d "$TOOLS/deps/maven" ] || { mkdir -p "$TOOLS/deps/maven"; tar xzf "$DL/apache-maven-3.9.9-bin.tar.gz" -C "$TOOLS/deps/maven" --strip-components=1; }

export JAVA_HOME="$TOOLS/deps/jdk8/Contents/Home"
export PATH="$JAVA_HOME/bin:$TOOLS/deps/maven/bin:$PATH"
export MAVEN_ARGS="-Dmaven.repo.local=$TOOLS/maven-repository"
GIT_INFO="cbmc-6.11.0-$CBMC_SHA"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || nproc)"

# The tarball has no .git: GIT_INFO stops `git describe` from reading the rskj checkout.
make -C "$SRC/src" -j"$JOBS" CXX=clang++ CC=clang GIT_INFO="$GIT_INFO" cbmc.dir
make -C "$SRC/jbmc/src" -j"$JOBS" CXX=clang++ CC=clang GIT_INFO="$GIT_INFO" java_bytecode.dir
make -C "$SRC/jbmc/src/jbmc" -j"$JOBS" CXX=clang++ CC=clang GIT_INFO="$GIT_INFO"
"$SRC/jbmc/src/jbmc/jbmc" --version
ls -l "$SRC/jbmc/lib/java-models-library/target/core-models.jar"
