# Historical b3 stub review

This directory retains the original reference and executor manifests and source files for the ten unresolved b3 results. `reconciliation.json` records matching invocation commands, expected failed assertions, original log/stub digests and the non-harness classpath match against the original b6 reference. The aggregate b3 harness bytecode differs from b6; this is not a current-source replay. The existing invocation comparator passes for all ten IDs. Reference and executor JSON are not byte-identical: their host paths and source-commit descriptions differ. Their ordered classpath digests, source hashes, tool versions and selected normalized arguments match. All twenty retained log/stub hashes were rechecked against the aggregate's original host files.

No verdict, executable model, harness or audit whitelist changed. All ten results remain `REVIEW` pending a narrowly scoped acceptance rule and its checks. These notes support the existing complete-trie task, not an approved MVP or a partial component acceptance.

## Logging-only entries

The only unresolved methods in these three entries are `ThreadLocal.remove` and `DataSourceWithCache.emitLogs`:

- `store-save-retrieve-neg`
- `store-content-addressed-rskip`
- `store-saved-entries-neg`

At the pinned `TrieStoreImpl.save`, `traceInfo` starts null. It can become non-null only inside `logger.isTraceEnabled()`. Both unresolved calls require `traceInfo != null`. The actual model's factory returns the real NOP logger, whose final trace-enabled method returns false. The existing bytecode evidence is in `../audits/logging-stub-bytecode.txt`.

The historical input reconciliation now establishes the missing connection to b3. Its model, production and SLF4J classpath digests equal those used for that logger inspection. Thus the source argument applies to these particular retained executions. It does not establish behavior with another logger, with trace logging enabled, or for another caller of either missing method.

Any future acceptance must bind the original per-result log/stub hashes, invocation and compiled-input identity. Do not add these methods to a global benign-stub list on the strength of these three results.

## JDK bytecode provenance

`jdk-bytecode.txt` records explicit-class-file `javap -c -p` excerpts from the original b6 reference. The whole models directory, JDK directory, production directory and core-models jar were rehashed and matched against b3's executor manifest before extracting them. This does not use whichever JDK happens to run `javap` as the inspected implementation.

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

## Next acceptance steps

1. Complete the call-site inventory for reflective allocation and both index-check signatures in the selected original inputs. Record any reachable caller not covered above.
2. After the old snapshots settle, encode only justified per-result audit exceptions, bound to historical evidence identities. Tests must reject changed log/stub bytes, mismatched manifests and unreviewed result IDs.
3. Reaudit without a competing summary writer and regenerate the matrix. Preserve every remaining REVIEW entry. No executable model change can inherit old verdicts; such a change needs fresh affected properties and negative controls.
