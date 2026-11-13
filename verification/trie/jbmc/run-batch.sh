#!/usr/bin/env bash
# Executor side of a batch made by make-batch.sh. Run from the batch directory on the executor:
#
#   ./run-batch.sh
#
# Checks SHA256SUMS, unpacks into ./work, runs validation.txt then work.txt through run-jbmc.sh
# under this executor's limits and copies summary.json, logs and stub lists to ./results/ with
# results/HOST. Defaults are the MacBook's (set by its own Firstmate): at most 3 concurrent, 8 GB RSS
# watchdog, start a job only while memory_pressure's free percentage is >= 41, no start below 15, the
# newest job killed below 10 (LOW_MEMORY, not a verdict), load gate 10, memory-pressure gate, 600 s
# per harness, caffeinate; any can be overridden by env.
# memory-hints.tsv gives each id's peak RSS measured on the originating host ("unknown" if never
# measured). The work-list verdicts count only if the validation ids reproduce the originating host's.
# If evidence/reference-manifest.json is present, the run stops before work.txt unless this host's
# invocation manifest (invocation.py) is identical to it for every listed id.
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
cd "$D"
shasum -a 256 -c SHA256SUMS
W="$D/work"; T="$W/verification/trie"
rm -rf "$W" && mkdir -p "$W/verification"
tar -xzf trie.tar.gz -C "$W/verification"
tar -xzf deps.tar.gz -C "$T"
sed "s|^|$T/|" classpath.rel | paste -sd: - > "$T/.tools/rskj-classpath.txt"
export HEAVY_JBMC_SLOTS="${HEAVY_JBMC_SLOTS:-3}" HEAVY_RSS_GB="${HEAVY_RSS_GB:-8}" HEAVY_MIN_FREE_GB="${HEAVY_MIN_FREE_GB:-0}" \
  HEAVY_MIN_FREE_PCT_ADMIT="${HEAVY_MIN_FREE_PCT_ADMIT:-41}" HEAVY_MIN_FREE_PCT="${HEAVY_MIN_FREE_PCT:-15}" \
  HEAVY_KILL_NEWEST_PCT="${HEAVY_KILL_NEWEST_PCT:-10}" \
  HEAVY_MAX_LOAD="${HEAVY_MAX_LOAD:-10}" HEAVY_TIMEOUT="${HEAVY_TIMEOUT:-600}" JBMC_JOBS="${JBMC_JOBS:-3}" \
  JDK17="$T/.tools/deps/jdk17"
mkdir -p "$D/results"
hostname > "$D/results/HOST"
collect() { cp "$T/jbmc/results/"*.json "$T/jbmc/results/"*.log "$T/jbmc/results/"*.stubs.txt "$D/results/" 2>/dev/null || true; }
trap collect EXIT
caffeinate -i "$T/jbmc/run-jbmc.sh" $(cat validation.txt) 2>&1 | tee "$D/results/run-validation.out"
# same invocation as the originating host (flags, classpath content, sources, versions), or stop here
cp "$T/jbmc/results/invocation-manifest.json" "$D/results/"
if [ -f evidence/reference-manifest.json ]; then
  python3 "$T/jbmc/invocation.py" compare evidence/reference-manifest.json "$T/jbmc/results/invocation-manifest.json" \
    $(cat validation.txt work.txt) | tee "$D/results/invocation-compare.txt"
  [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "invocation differs from the reference: stopping before work.txt" >&2; exit 3; }
fi
caffeinate -i "$T/jbmc/run-jbmc.sh" $(cat work.txt) 2>&1 | tee "$D/results/run-work.out"
