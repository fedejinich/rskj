# Source this file: sets up the task-local toolchains (nothing global).
#   . verification/trie/env.sh
TRIE_VERIFY="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
RSKJ_ROOT="$(cd "$TRIE_VERIFY/../.." && pwd)"
export TRIE_VERIFY RSKJ_ROOT
export ELAN_HOME="$TRIE_VERIFY/.tools/elan"
export PATH="$ELAN_HOME/bin:$TRIE_VERIFY/.tools/cbmc/jbmc/src/jbmc:$PATH"

# Real rskj-core classes + runtime jars at the pinned commit (see classpath.gradle).
rskj_classpath() {
  local f="$TRIE_VERIFY/.tools/rskj-classpath.txt"
  if [ ! -s "$f" ]; then
    (cd "$RSKJ_ROOT" && ./gradlew -q --init-script verification/trie/classpath.gradle \
      :rskj-core:printTrieVerifyClasspath | tail -1 > "$f")
  fi
  tail -1 "$f"
}
