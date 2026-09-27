# b6–b8 audit reconciliation

Sol's [read-only audit](b6-b8-split-audit.md) checks assignment coverage, not property verdicts.
The 1,425 unique split IDs cover the generator's domains once. Six `part11-none` entries contain
no reachable pair assertion: they are sentinels for empty domains, not missing legal pairs and
not additional tested cases. `hash-node-hash-part11-none` separately checks a one-key trie.

## Scope limits and accepted obligations

- `NodeHarness.format3` deletes only `K[i]` and `K[j]`, never `K[l]`. Its mapped node-format,
  embedding, value, serialization and size obligations quantify over reachable nodes, including
  third-key deletion histories. In particular, TRIE-SIZE-02 concerns incremental size after
  deletion/coalescing. The current finite harness cannot support a claim that all three deletion
  choices were checked. No symmetry reduction has been established.
- Three `StoreHarness.savedEntries` choices (`i,j` = `0,9`, `1,10`, `2,11`) overwrite `K[i]`.
  These exercise two distinct keys, not three. TRIE-STORE-03 and TRIE-STORE-04 quantify over
  every saved reachable trie, including three-distinct-key tries. The RSKIPs do not demand these
  exact test indices, but the accepted three-key harness domain must not claim them as covered.

Both are finite-harness coverage limitations, not demonstrated Java violations or missing
assigned IDs. Lean theorems remain separate evidence under their own hypotheses. Completing
all existing batch IDs will not by itself close these two advertised-domain gaps.

## Correction queue within this task

Preserve the live b5–b8 source snapshots and executions. After those batches settle:

1. Add the missing third-key deletion check to the format3 harness and correct its bounds text.
2. Make the savedEntries third key distinct from both earlier keys; retain the existing overwrite
   cases as such rather than relabeling their old results.
3. Regenerate affected splits and invocation manifests, then rerun affected properties and their
   negative controls through the shared resource queue. Old-source verdicts do not verify new code.
4. Accept remote results only after per-ID invocation/source identity, expected controls, stub
   audit and unwinding checks pass. Pending batches and resource stops are not verified evidence.

No in-flight harness or generated source was changed for this reconciliation.
