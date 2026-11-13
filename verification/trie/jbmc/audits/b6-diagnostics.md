# Original b6 diagnostics

This is an evidence review, not a batch import or acceptance. The original batch remains immutable. No executable source, bound or model was changed for this review.

At 2026-09-27 15:14:08 UTC, a read-only executor summary query found 157 recorded b6 results, 155 with the expected verdict. No final b6 summary was present. No b7/b8 summary was present. These are observations, not completion claims or instructions to defer the authorized sequence.

The two diagnostic logs were retained earlier under the task-local `live-041` capture. Their identities are:

- `hash-orchid.log`: SHA256 `ce00e0ee66a7680058008c0f49bde43cddc0a43938e34fa661de7eadb99aa7eb`
- `parser-huge-lshared-rskip.log`: SHA256 `d7c9895235af22dfeda1e8c8eb91aedd4657f4c01c23eae050ef8e11d1efb64a`
- Executor invocation manifest: SHA256 `2d9a315aa4acb9cbdc76e5ad8d76e2a5f0a3f238b419606cb13ecb4c660359c5`

## Orchid check exhausts the oracle table

`hash-orchid` returned FAILURE, exit 10, in 34.65 seconds. Its only failed property is `java::org.ethereum.crypto.Keccak256Helper.keccak256:([B)[B.assertion.1`, at model line 78. That assertion is explicitly `size < MAX_ENTRIES`, the “oracle table full” assertion, with capacity 16.

The exact executed `HashHarness.java` and `Keccak256Helper.java` source hashes match the inspected sources:

- HashHarness: `80053e1999b8ed097f59e595731b443fc6d881d89e5f5c4189de4557d737d7ad`
- Keccak model: `759567ba3cf1d3faf36e2d038d061ac2a3a3881c7bc3520821a1ca19d394afbd`

The invocation calls `HashHarness.orchidHash` directly, not a per-pair SplitHarness wrapper. It accumulates hashes across the key-pair loop and both flags in a single oracle table. Creating a fresh Trie per flag fixes the earlier cache-confounding harness pattern but does not reset this static table. Therefore this observed failure is oracle-capacity exhaustion, not a refutation of the fresh-per-flag Java hash equation.

After the immutable snapshots settle, split the existing pair domain into separate executions, preserving both flag cases and the empty-root assertions. Keep the separate cache-transition counterexample and negative control. Do not remove the capacity assertion, reset the table while live objects can retain its old hashes, or accept this FAILURE as a Java counterexample. New wrappers need new manifests and fresh property/control verdicts.

## Large shared path stops in the solver

`parser-huge-lshared-rskip` returned ERROR, exit 6, in 11.61 seconds, with no failed properties. The retained log ends with `array too large for flattening`. The executed invocation already includes `--arrays-uf-always`. That option did not resolve this case.

`ParserHarness.SER05` is the seven-byte message `50 ff fe ff ff ff 7f`. The harness observes the requested ByteBuffer read after allocation and asks whether it is at most `64 * SER05.length`, or 448 bytes. Its companion check names the 268,435,456-byte request. The solver error is neither an accepted assertion failure nor a Java runtime allocation result.

This property is a concrete 64-times-input budget, not a standalone proof or refutation of an arbitrary asymptotic O(input length) claim. A fixed ratio violation must not be promoted into a stronger complexity theorem. Lean does not model memory allocation here, and SER-05 remains partial.

The original error remains recorded. Any later allocation abstraction would require a separate soundness argument and fresh evidence; observing a model hook alone cannot establish real allocation behavior. Do not run the large allocation on the host merely to obtain a desired failure. Reassess the precise resource obligation and the solver's supported array representation before scheduling follow-up.
