# Batch 5 provenance

`trie-b5-20260927-0414` completed on `voids-macbook-pro-2.local` with 112 expected verdicts.
Three validation IDs matched the originating host; 109 work results were merged. All work
results are bounded `SUCCESS`, not unbounded proofs. Re-auditing the merged stubs against
the current conditional whitelist introduced no changes or new review flags.

The executor manifest exactly matches the batch's original reference for every validation
and work ID. All archived harness/model source digests match repository commit
`6642bf537a3c841912a73f36cf5915697f2c1e1a`. The manifest's older `source_commit` label records
an uncommitted snapshot; content hashes, not that label, establish the committed identity.

This is historical-snapshot evidence, not a claim that the current aggregate harness classpath
is identical. The 109 selected wrapper bodies and `TrieOpsHarness.java` are unchanged.
`Nondet.java` adds only `in2`, unused by these wrappers and their operations. Production and
model classpath digests and selected normalized arguments are unchanged. The machine-readable
[source reconciliation](source-reconciliation.json) records these checks and old source lines.
Merged results link to the verified historical commit rather than the current branch.

To repeat the exact executor/reference comparison from the repository root:

```bash
python3 verification/trie/jbmc/invocation.py compare \
  verification/trie/jbmc/evidence-b5/reference-manifest.json \
  verification/trie/jbmc/evidence-b5/executor-manifest.json \
  $(< verification/trie/jbmc/evidence-b5/validation.txt) \
  $(< verification/trie/jbmc/evidence-b5/work.txt)
```

The original result logs remain under `results/hosts/voids-macbook-pro-2.local/` in this
worktree. Their SHA-256 hashes are retained in `log-digests.json`. The per-result commands,
bounds, stubs, failed properties, host and source identity remain in `results/summary.json`.
No remote process or batch snapshot was modified during validation or integration.
