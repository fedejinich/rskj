# parser-lshared-non-canonical-rskip: 1/1879 (reference) vs 1/2117 (void, batch 2)

**Cause.** The 1/1879 reference in results/summary.json on void-rsk was stale: it was produced on
2026-09-26 at 19:29, before `bclcrypto-jdk15on-1.59.jar` was added to the JBMC classpath in
run-jbmc.sh (it is needed for `DataWord.getData`). Loading its classes adds 238 properties
(null-pointer, array-bounds and cast checks in the Bouncy Castle code JBMC now converts). The verdict
is unchanged: the only failing property is the harness assertion `ParserHarness.java:71`.

**Evidence** (all runs on void-rsk, same JBMC 6.11.0 and JDK 17.0.17):
- current tree: `** 1 of 2117 failed` (reference/…log);
- batch trie-b2-20260926-2217 unpacked and replayed here with its own run-jbmc.sh: `** 1 of 2117 failed`
  (b2-replay/…log) — the same count void got;
- current tree with only the bclcrypto jar removed from JBMC_CP: `** 1 of 1879 failed` (stale-1879/…log),
  which reproduces the stale reference exactly;
- compare.txt: the normalized argv of batch 2 equals the current one; every classpath entry except
  the harness classes is byte-identical (sha256); the harness classes differ only because
  KeyHarness/TrieKeySliceHarness/Nondet/SplitHarness changed after batch 2 was packed (not used by
  this harness).

run-batch.sh already derived its argv from the same per-harness spec (it runs the packed
run-jbmc.sh on the packed harnesses.json); batch 2 was consistent, the reference was not.

**Fix.** run-jbmc.sh now writes results/invocation-manifest.json at every run (invocation.py: JBMC
and JDK versions, source commit, sha256 of every classpath entry in order, sha256 of every source
file, normalized argv of every harness). This batch carries the reference manifest
(reference-manifest.json, produced from the same tree the batch was packed from), and run-batch.sh
compares the executor's manifest with it after the validation ids and stops before work.txt if any
flag, classpath digest, source or version differs.
