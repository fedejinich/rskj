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

## Unresolved stub checks after b5 integration

Ten recorded results still have `REVIEW` stub audits. Expected verdicts alone do not
close them. The following source review does not change the whitelist or those verdicts.

`TrieStoreImpl.save`, at pinned Java lines 58–85, initializes `traceInfo` to null and
only assigns it inside `logger.isTraceEnabled()`. Both `ThreadLocal.remove` and
`DataSourceWithCache.emitLogs` occur inside the later `traceInfo != null` block.
The archived `models/src/org/slf4j/LoggerFactory.java` returns the real SLF4J
`NOPLogger` for both overloads. These two logging stubs are candidates for an
unreachable-path justification under that model. They are the only unresolved stubs
in `store-save-retrieve-neg`, `store-content-addressed-rskip` and
`store-saved-entries-neg`. The [recorded b6 bytecode](logging-stub-bytecode.txt)
confirms both factory overloads return `NOPLogger.NOP_LOGGER` and its final
`isTraceEnabled` method returns false. Before accepting historical results, verify
that evidence against each result's actual classpath. This does not establish
behavior with trace logging enabled.

The remaining seven results need separate JDK-path review:

- `store-epochs` and `store-epochs-neg` include reflective array allocation and
  `Preconditions.checkIndex`. `MultiTrieStore` constructs and accesses an `ArrayList`
  at Java lines 47–49 and 153. The harness uses three live epochs. Index checks cannot
  be dismissed as logging, and a synthesized allocator is not an implementation of
  array allocation.
- `store-collect` and `store-collect-rskip` also include four sublist range-check
  stubs. `MultiTrieStore.collect`, lines 144–148, indexes and rotates the epoch list.
  Establish which `Collections.rotate` and list paths the compiled harness can reach
  before treating the sublist calls as dead code.
- `dto-roundtrip-inline-neg`, `dto-embedded-long-value` and
  `dto-embedded-long-value-rskip` include `Preconditions.checkFromIndexSize`.
  The byte-buffer and array-copy path needs its own bounds justification or an
  executable implementation. A desired failing DTO assertion does not establish
  that the missing range check is harmless.

After snapshots settle, apply only justified stub-audit changes and re-audit the
retained logs. Any change to executable models requires fresh affected properties
and negative controls with new invocation manifests. No blanket approval of
`Preconditions`, reflective allocation or sublist helpers is justified by this review.
