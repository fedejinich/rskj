# Reference for the b6, b7 and b8 snapshots

This directory records four local validation controls, not completed remote work.
The original b6 archive was unpacked into an isolated task-local directory. No active
batch or aggregate summary was changed. Only `validation.txt` ran, with one worker
through the shared queue. All four controls matched their expected verdicts and the
existing local controls. All four stub audits report `none on property path`.

The b6, b7 and b8 archives have identical proof-source digests. The harnesses, models,
entry declarations, invocation code and runner script match signed source commit
`4a694a0db820f9b43b3c3c3e99a7c611f82e01ce`. There is one runtime difference. The archived
`heavy_run.py` predates `HEAVY_NO_TASKPOLICY` and always uses `taskpolicy -b` with nice 19.
The reference controls therefore used that original background QoS even though the
opt-out environment variable was set. The archived runner is retained here verbatim.
It is not claimed to match the later runtime revision.

`reference-manifest.json` records the actual compiled classpath, source digests,
versions and normalized per-ID arguments. `validation-results.json` and the four
logs retain the outcomes and resource limits. AppleDouble `._` archive entries are
filesystem metadata, not source files.

Before accepting any batch's work, compare its executor manifest for **every**
validation and work ID, then compare the validation outcomes and audit the work
results. Matching archived source alone does not establish compiled-input identity
or verify any pending work.

```bash
python3 verification/trie/jbmc/invocation.py compare \
  verification/trie/jbmc/evidence-b6-reference/reference-manifest.json \
  "$BATCH/results/invocation-manifest.json" \
  $(< "$BATCH/validation.txt") $(< "$BATCH/work.txt")
```
