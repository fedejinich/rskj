# Historical b3 stub review

This directory retains the original reference and executor manifests and source files for the ten unresolved b3 results. `reconciliation.json` records matching invocation commands, expected failed assertions, original log/stub digests and the non-harness classpath match against the original b6 reference. The aggregate b3 harness bytecode differs from b6; this is not a current-source replay. The existing invocation comparator passes for all ten IDs. Reference and executor JSON are not byte-identical: their host paths and source-commit descriptions differ. Their ordered classpath digests, source hashes, tool versions and selected normalized arguments match. All twenty retained log/stub hashes were rechecked against the aggregate's original host files.

Five original failing results now have justified per-result stub exceptions in `reviewed-results.json`, enforced by `reaudit.py`. They are the three logging-only entries below, `store-collect-rskip` and `dto-embedded-long-value-rskip`. The other five remain `REVIEW`. No Java verdict, executable model, harness or global benign-stub list changed. `reconciliation.json` retains the original pre-review audit labels. These notes support the complete-trie task, not an approved MVP or a component acceptance.

## Logging-only entries

The only unresolved methods in these three entries are `ThreadLocal.remove` and `DataSourceWithCache.emitLogs`:

- `store-save-retrieve-neg`
- `store-content-addressed-rskip`
- `store-saved-entries-neg`

At the pinned `TrieStoreImpl.save`, `traceInfo` starts null. It can become non-null only inside `logger.isTraceEnabled()`. Both unresolved calls require `traceInfo != null`. The actual model's factory returns the real NOP logger, whose final trace-enabled method returns false. The existing bytecode evidence is in `../audits/logging-stub-bytecode.txt`.

The historical input reconciliation now establishes the missing connection to b3. Its model, production and SLF4J classpath digests equal those used for that logger inspection. Thus the source argument applies to these particular retained executions. It does not establish behavior with another logger, with trace logging enabled, or for another caller of either missing method.

The exceptions bind the complete original result record except its audit label, both historical manifests, and the original log/stub bytes by SHA256. Changed IDs, commands, bounds, outcomes, tool versions, manifests or evidence bytes cannot inherit the exception. These methods were not added to the global benign-stub list.

## JDK bytecode provenance

`jdk-bytecode.txt` records explicit-class-file `javap -c -p` excerpts from the original b6 reference. The whole models directory, JDK directory, production directory and core-models jar were rehashed and matched against b3's executor manifest before extracting them. This does not use whichever JDK happens to run `javap` as the inspected implementation.

The original b3 harness directory was also retrieved read-only and rehashed to the b3 manifest digest. `jdk-callers.json` inventories direct calls across 6,531 classes resolved in original classpath order. It finds 51 call sites for Preconditions/reflective allocation and 13 for Objects range checks. This static inventory includes unreachable methods; it is not a reachability proof.

The core-models jar has no ArrayList, Collections, Objects or ByteBuffer class. The classpath also supplies the explicit heap ByteBuffer model; the extracted JDK directory does not contain ByteBuffer or HeapByteBuffer. That model performs its own bounds checks and does not call the missing Preconditions methods.

## Four epoch/collection entries

The original `StoreHarness.multi` always constructs `MultiTrieStore(0, 3, ...)`. The pinned constructor creates an `ArrayList` with capacity three and adds exactly three entries. Later operations read or replace entries without changing its size.

The inspected ArrayList bytecode allocates `Object[capacity]` directly. Its append helper calls `grow` only when the old size equals the array length. The constructor's three additions have old sizes 0, 1 and 2, so this list never grows. A reflective allocator is not needed for that construction. This narrows the allocation review; it is not yet a complete exclusion of every other possible caller of `Array.newInstance` in the loaded program.

For `store-epochs` and `store-epochs-neg`, `getCurrentStore` accesses index zero of the three-entry list. For collection, the pinned code reads indexes one and two and replaces index zero. `ArrayList.get` and `set` call `Objects.checkIndex`, but discard its returned integer and use the original index. These arguments satisfy the real JDK check. A synthesized result is therefore not being used as an array index at these sites. This argument is specific to the three-epoch harness; it says nothing about zero- or one-epoch stores.

For `store-collect` and `store-collect-rskip`, `Collections.rotate` selects `rotate1` for an ArrayList because it implements RandomAccess. Size three also selects that path independently of the type test. The `rotate2` path containing `subList` calls is not taken. With distance one and size three, `rotate1` reads index zero and replaces indexes one, two and zero; every index is in range. The original collection log records `rotate1` unwinding for each collection.

The four missing sublist range-check helpers are consequently not needed by this rotation path. Keep the remaining whole-call-path allocation review separate; a dead sublist path alone does not accept the collection result.

## Three DTO entries

The missing `Preconditions.checkFromIndexSize` is reached through `Objects.checkFromIndexSize` in `ByteArrayOutputStream.write(byte[], int, int)`, not through the custom ByteBuffer implementation.

Pinned TrieDTO and SharedPathSerializer pass entire arrays to `encoder.write(byte[])`. The inspected inherited `OutputStream.write(byte[])` forwards offset zero and the array's exact length. The real check therefore receives `(0, length, length)`. `ByteArrayOutputStream.write` discards the returned integer before copying with the original offset and length. The check's return value cannot change that copy.

This gives a concrete bounds justification for the inspected write sites in `dto-roundtrip-inline-neg`, `dto-embedded-long-value` and `dto-embedded-long-value-rskip`. Final acceptance still requires confirming there is no other relevant call site in each retained execution. A substring search for successful bounds properties is not enough to establish that. The inline negative control also needs the logging justification above.

## Retained failing traces

Only three of the seven failing logs retain a trace. Do not infer a missing trace from an expected FAILURE. `negative-trace-review.json` records the three available traces and names the four missing ones.

- `store-content-addressed-rskip`: 6,647 state blocks, no call to either unresolved logging method.
- `store-collect-rskip`: 24,887 state blocks, 22 calls to `checkIndex`, all with `0 <= index < length` and a null exception callback. No call to reflective allocation, logging or sublist range-check stubs.
- `dto-embedded-long-value-rskip`: 8,616 state blocks, nine calls to `checkFromIndexSize`, all satisfying the real range check, with null callbacks.

`preconditions-reference.txt` supplies the missing methods' reference semantics from local OpenJDK Homebrew 17.0.17+0. ArrayList, Objects, Collections, OutputStream and ByteArrayOutputStream from that same JDK archive are byte-identical to the historical inputs. The two int checks return the original index without calls or side effects when their bounds hold. This is reference evidence, not a claim that JBMC executed the missing class.

The JDK caller bytecode above discards the range-check return values. Replacing those particular stub calls by the real checks preserves the inspected failing paths: the checks do not throw, their return values are unused, and the other unresolved methods are not called. This justifies the two trace-specific exceptions. It does not approve their positive companion results or prove whole-program unreachability.

`python3 verification/trie/jbmc/test_reaudit.py` recomputes the trace argument checks from the original logs and tests the exact-evidence exceptions. It rejects invalid/missing traces, invalid range arguments, reachable unresolved allocation, changed result metadata, extra stubs, missing files, changed log/stub bytes and mismatched manifests. It also confirms that all five unaccepted entries still require review.

## Remaining work

Finish the whole-path analysis for `store-epochs`, `store-epochs-neg`, `store-collect`, `dto-roundtrip-inline-neg` and `dto-embedded-long-value`. The static inventory narrows the relevant code but does not settle its reachable paths. In particular, only Arrays' generic `copyOf` reflective-allocation caller appears in the store logs; lack of other property listings is not an unreachability proof.

Reaudit only without a competing summary writer. Audit-policy changes do not alter the immutable remote compiled inputs. Executable model/harness repairs remain gated on the old snapshots settling, and require fresh affected properties and negative controls.
