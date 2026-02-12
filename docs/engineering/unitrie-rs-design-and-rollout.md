# Unitrie-rs Design and Rollout (V4 Optimization Program)

## 1. Problem Statement
`unitrie` is consensus-critical in RSKj. Any semantic divergence between implementations can change state roots and cause chain split.

RSKj currently has Java as the canonical implementation. This project introduces `unitrie-rs` as a Rust crate plus JNI integration, with runtime engine selection:
- `java` (default, production-safe baseline)
- `rust` (Rust-backed execution path)
- `rust-shadow` (Java source of truth + deterministic Rust comparison)

## 2. Goals and Non-Goals
### Goals
- Provide an in-repo Rust crate with modular architecture suitable for future extraction.
- Expose a JNI bridge with explicit ABI for trie lifecycle, persistence, and observability.
- Support runtime engine selection and strict mismatch policy.
- Add an on-demand, deterministic engine-validation flow with fail-fast artifacts.
- Keep Java as default engine until parity and performance gates are satisfied.

### Non-Goals in this phase
- Switching production default to Rust.
- Claiming full consensus parity is complete.
- Enabling fuzzing jobs in this phase.

## 3. Consensus-Critical Invariants and Risk Model
### Critical invariants
- Deterministic root hash for identical operation sequence.
- Exact behavior for `get`, `put`, `deleteRecursive`.
- Value length/hash semantics used by `EXTCODESIZE`/`EXTCODEHASH`.
- Encoding and persistence compatibility (RSKIP107 and Orchid compatibility path).
- Cross-read/write interoperability between engines.

### Hardfork risk model
- Divergent trie behavior can alter state root and trigger consensus split.
- `engine=java` remains default.
- `rust-shadow` supports deterministic mismatch detection with configurable fail behavior.
- Rollback remains configuration-only (`engine=java`) in this phase.

### Current status statement
This phase closes the MVP scope for deterministic parity validation in a bounded range, but complete Java↔Rust bit-for-bit parity still requires additional expanded-range validation before considering `engine=rust` for production default.

## 4. Java Behavior Map (Current Source of Truth)
- `co.rsk.trie.Trie`: immutable node model, hashing/serialization, traversal.
- `co.rsk.db.MutableTrieImpl`: mutable facade over immutable trie transitions.
- `co.rsk.trie.TrieStore` + `TrieStoreImpl` + `MultiTrieStore`: persistence and GC epoch handling.
- `co.rsk.db.RepositoryLocator`: snapshot/repository creation from state roots.

## 5. Rust Crate Architecture (`unitrie-rs`)
Crate path: `/Users/void_rsk/.codex/worktrees/35ae/rskj/unitrie-rs`

### Modules
- `core_trie`: trie core behavior, path-compressed structure materialization, persisted-root loading, and save compatibility.
- `next/core_trie`: next-generation mutable trie facade with incremental dirty tracking.
- `next/node_arena`: stable node ids and dirty-node set for incremental persistence strategy.
- `next/hash_cache`: root-hash cache invalidation/update support.
- `next/persistence`: incremental save orchestration.
- `node_ref`: Java-compatible node and reference types (`TrieNode`, `NodeReference`, `SharedPath`, `ValueRef`, `CodecMode`).
- `codec_rskip107`: RSKIP107 exact encode/decode boundary.
- `codec_orchid`: Orchid compatibility encode/decode boundary.
- `path/shared_path_serializer`: shared-path serialization compatible with Java length prefix rules.
- `store_adapter`: raw node/value persistence adapter trait.
- `ffi`: JNI ABI and handle management.
- `hash`: Keccak and empty-trie hash helpers.
- `varint`: Bitcoin-style varint encoding/decoding used by RSKIP107 fields.

## 6. JNI Boundary Contract (V2 ABI)
Java class: `co.rsk.trie.engine.rust.RustUnitrieBridge`

### Exposed native operations
- `createTrie`
- `createTrieFromRoot`
- `destroyTrie`
- `get`
- `put`
- `delete`
- `deleteRecursive`
- `save`
- `getValueLength`
- `getValueHash`
- `collectKeys`
- `getStorageKeys`
- `rootHash`
- `currentRootHash`
- `getPerfCounters`
- `resetPerfCounters`

### Memory and ownership
- Java owns input/output JNI arrays.
- Rust copies inbound arrays into owned memory.
- Returned arrays are fresh JNI allocations.
- Opaque handles are mandatory for lifecycle control.
- Invalid arguments/handles map to Java exceptions.

## 7. Store Adapter and Persistence
Java adapter: `co.rsk.trie.engine.rust.RustTrieStoreAdapter`

Responsibilities:
- Load raw node bytes by hash.
- Save raw node bytes.
- Save raw value bytes.

This preserves existing `TrieStore` ownership while enabling Rust persistence writes in `engine=rust`.

## 8. Engine Selection and Runtime Behavior
Config:
- `blockchain.unitrie.engine = java | rust | rust-shadow`
- `blockchain.unitrie.rust.failOnMismatch = true | false`
- `blockchain.unitrie.rust.libraryPath = "<optional absolute path>"`
- `blockchain.unitrie.rust.impl = legacy-v1 | next`

### Validation run tuning
- `blockchain.unitrie.validationRun.defaultBlockCount = 50` (fast local default)
- `blockchain.unitrie.validationRun.deepBlockCount = 500` (MVP bounded validation run)

### Mode behavior
- `java`: legacy `MutableTrieImpl`.
- `rust`: Rust-backed mutable trie path via JNI.
- `rust-shadow`: Java source of truth, deterministic Rust checks, configurable fail-fast.

### Mainnet startup in controlled environments
Dedicated node CLI options are available for explicit engine selection:
- `--unitrie-engine=<java|rust|rust-shadow>`
- `--unitrie-rust-library-path=<absolute path>`

Mainnet examples:
```bash
java -cp rskj-core-<VERSION>.jar co.rsk.Start --main --unitrie-engine=java
java -cp rskj-core-<VERSION>.jar co.rsk.Start --main --unitrie-engine=rust
java -cp rskj-core-<VERSION>.jar co.rsk.Start --main --unitrie-engine=rust-shadow
```

With explicit JNI library path:
```bash
java -cp rskj-core-<VERSION>.jar co.rsk.Start --main --unitrie-engine=rust --unitrie-rust-library-path=/abs/path/libunitrie_rs_jni.so
```

Operational notes:
1. `engine=java` remains the production default.
2. Starting mainnet with `rust` or `rust-shadow` logs an explicit warning that the mode is experimental.
3. `-Xblockchain.unitrie.*` and `-Dblockchain.unitrie.*` remain supported for backward compatibility.
4. If both dedicated CLI options and `-X` set the same unitrie key, `-X` takes precedence.

## 9. Validation Run (On-Demand)
Official gate name: **Validation Run (On-Demand)**.

CLI tool:
- `co.rsk.cli.tools.UnitrieValidationRunOnDemand`
- Command name: `unitrie-validation-run`

Behavior:
1. Execute identical block range with Java and Rust engines.
2. Compare per-block final state root.
3. Fail-fast on first divergence (configurable) and write mismatch artifact.
4. Report A/B metrics:
- blocks/sec
- ms/block
- total time

### MVP Gate Procedure (500 blocks, 2 clean runs)
Gate status for this phase is considered **MVP reliable** only when:
1. The exact same 500-block range is executed with `--repeatRuns 2`.
2. Both attempts finish with zero divergences and zero JNI exceptions.
3. If divergence appears, triage artifacts and corpus are generated and replayed before retrying.

Runbook commands:
1. Fast local check (uses `defaultBlockCount`):
   `./gradlew :rskj-core:run --args='unitrie-validation-run --fromBlock <N>'`
2. Deep 500-block check:
   `./gradlew :rskj-core:run --args='unitrie-validation-run --fromBlock <N> --deep --failFast true'`
3. Sustained gate (official):
   `./gradlew :rskj-core:run --args='unitrie-validation-run --fromBlock <N> --deep --repeatRuns 2 --failFast true --artifactLevel extended --captureCorpusOnMismatch true'`
4. Optional deterministic run id:
   append `--runId unitrie-v3-<tag>`.

Artifact interpretation:
1. `run-<runId>-attempt-<i>/run-manifest.json`: attempt metadata and environment.
2. `mismatch-block-<n>.txt`: human triage summary.
3. `mismatch-block-<n>.json`: machine-readable divergence artifact.
4. `corpus-block-<n>-<shortHash>.jsonl`: auto-generated differential corpus when mismatch is detected.

Corpus promotion workflow:
1. Move generated JSONL corpus into `rskj-core/src/test/resources/trie/differential/`.
2. Add/adjust replay assertions in `UnitrieDifferentialCorpusReplayTest`.
3. Re-run replay test locally.
4. Retry the 500-block sustained gate only after replay is deterministic.

### Fast vs deep profile
- Fast local default is intentionally small (`defaultBlockCount`, default 50).
- Deep parity run remains available on demand (`deepBlockCount`, default 500).
- No nightly scheduling is assumed by this design.

## 10. Test Strategy and Acceptance Criteria
### Required test layers
- Engine/config parsing tests.
- Factory and adapter wiring tests.
- JNI load/fallback behavior tests.
- Rust crate unit tests.
- Differential parity tests (operation replay).
- Cross read/write compatibility tests (Java↔Rust).
- Validation run mismatch-path and artifact generation checks.

### Acceptance criteria for promotion
- No deterministic divergence in agreed differential corpus.
- Validation Run (On-Demand) passes for the 500-block MVP range on an existing local DB.
- Performance meets agreed envelope relative to Java baseline.
- Java remains rollback-safe default until all gates pass.

## 11. Benchmark Methodology
JMH package:
`/Users/void_rsk/.codex/worktrees/35ae/rskj/rskj-core/src/jmh/java/co/rsk/jmh/trie`

Workloads:
- put/get/delete mix
- long-value heavy paths
- save/reload cycle
- storage key iteration
- dataset replay (`massive-upload.dmp`)

### Benchmark Metrics Baseline for Rust Optimization
This benchmark suite is the performance observability baseline for `unitrie-rs` optimization.
It is intentionally separate from consensus parity gating.

#### Collected metrics
- Latency:
  - `AverageTime` (mean) in microseconds per operation.
  - `SampleTime` percentiles (`p50`, `p95`, `p99`) in microseconds per operation.
- Throughput:
  - `Throughput` converted to operations per second.
- Memory/GC:
  - `gc.alloc.rate.norm` (bytes allocated per operation).
  - `gc.alloc.rate`, `gc.count`, `gc.time` from JMH GC profiler.
- Trie store I/O counters (per operation):
  - `store_get_ops`
  - `store_put_ops`
  - `store_delete_ops`
  - `store_bytes_read`
  - `store_bytes_written_key`
  - `store_bytes_written_value`

#### Artifacts
The runner produces:
- `build/reports/jmh/result_trie_engine.csv` (raw JMH output)
- `build/reports/jmh/result_trie_engine_summary.json` (machine-readable summary)
- `build/reports/jmh/result_trie_engine_comparison.md` (human-readable Java vs Rust delta report)

#### Non-blocking warning policy (conservative)
Warnings are emitted (exit code remains success) when Rust regresses vs Java beyond:
- avg latency: `> 5%`
- p95 latency: `> 10%`
- alloc/op: `> 15%`
- value-bytes-written/op: `> 15%`
- throughput drop: `> 5%`

This stage is intentionally alert-only for performance. It does not block parity validation flows.

#### Runbook commands
Fast local sample:
```bash
UNITRIE_JMH_WARMUP_ITERATIONS=1 \
UNITRIE_JMH_MEASUREMENT_ITERATIONS=2 \
UNITRIE_JMH_WARMUP_SECONDS=1 \
UNITRIE_JMH_MEASUREMENT_SECONDS=1 \
UNITRIE_JMH_FORKS=1 \
./gradlew :rskj-core:jmh -Pbenchmark=BenchmarkTrieEngineRunner
```

Deep local sample:
```bash
UNITRIE_JMH_WARMUP_ITERATIONS=5 \
UNITRIE_JMH_MEASUREMENT_ITERATIONS=15 \
UNITRIE_JMH_WARMUP_SECONDS=10 \
UNITRIE_JMH_MEASUREMENT_SECONDS=10 \
UNITRIE_JMH_FORKS=1 \
./gradlew :rskj-core:jmh -Pbenchmark=BenchmarkTrieEngineRunner
```

Default engines for comparison are `java,rust` and default Rust implementations are `legacy-v1,next`. Override if needed:
```bash
UNITRIE_JMH_ENGINES=java,rust \
UNITRIE_JMH_RUST_IMPLEMENTATIONS=legacy-v1,next \
./gradlew :rskj-core:jmh -Pbenchmark=BenchmarkTrieEngineRunner
```

If Rust JNI is not in the default loader path, provide it explicitly:
```bash
UNITRIE_JMH_RUST_LIBRARY_PATH=/absolute/path/to/libunitrie_rs_jni.dylib \
./gradlew :rskj-core:jmh -Pbenchmark=BenchmarkTrieEngineRunner
```

#### Interpretation
- `OK` means no warning threshold was crossed in the Java vs Rust comparison table.
- `WARNING` means at least one conservative threshold was crossed; triage before optimization continues.
- A benchmark warning is a performance signal, not a consensus verdict.

#### Consensus clarification
Benchmark parity and state-root parity are different gates:
- Performance benchmark gate: this JMH suite (alert-only in this phase).
- Consensus/parity gate: Validation Run (On-Demand) block replay with fail-fast divergence artifacts.

## 12. Rollout and Rollback
### Rollout stages
1. Keep Java default with Rust optional.
2. Expand deterministic differential coverage.
3. Run Validation Run (On-Demand) for the bounded MVP range (500 blocks) and benchmark gates.
4. Consider controlled `engine=rust` environments only after sustained parity.

### Rollback
1. Set `blockchain.unitrie.engine=java`.
2. Restart node.
3. Preserve mismatch artifacts for triage.

## 13. Future Fuzzing Roadmap (Deferred)
Fuzzing is intentionally deferred from this phase, but design leaves hooks for:
- cross-engine operation-sequence fuzzing
- value-length boundary mutators (0/32/33)
- codec transition mutators
- persistence/reload ordering mutators

Findings should be promoted into deterministic regression vectors.

## 14. V4 Optimization Program (Legacy Frozen + Next Core)
### Immutable legacy baseline
The V1 Rust implementation is preserved in:
`/Users/void_rsk/.codex/worktrees/35ae/rskj/unitrie-rs-legacy-v1`

Policy:
1. `unitrie-rs-legacy-v1` is immutable and CI-enforced on pull requests.
2. Active optimization work continues in `unitrie-rs`.
3. Legacy remains the baseline for A/B and regression comparison.

### Implementation selector
Rust runtime variant is selected with:
- `blockchain.unitrie.rust.impl = "legacy-v1" | "next"`

Default remains `legacy-v1` for safety.

### Optimization gate policy
`engine=java` remains production default until both gates are satisfied:
1. Functional gate:
   - Validation Run (On-Demand), 500 blocks, `repeatRuns=2`, zero divergence, zero JNI errors.
2. Performance gate:
   - `rust(next)` must outperform Java on median deep benchmark runs according to V4 target policy.

### Replacement decision policy
Replacement candidacy requires:
1. consensus parity sustained in bounded differential runs,
2. performance superiority over Java in agreed benchmark workloads,
3. rollback-safe operation by configuration (`engine=java`).

## 15. V4.1 Optimization Sprint (2-3/5 wins target)
### Goal
Raise `rust(next)` from one benchmark win to at least two wins (stretch: three) while preserving consensus behavior.

Primary target workloads:
1. `putGetDeleteMix`
2. `accountStorageKeyIteration`

Mandatory retained win:
1. `datasetDrivenMassiveUpload`

### Implemented optimization scope
1. `deleteRecursive` optimized to remove a lexicographic prefix range instead of scanning every key.
2. JNI `nativeGet` uses borrowed value access to avoid an intermediate Rust `Vec` clone.
3. `next` includes storage-iteration cache by `(accountAddress, mutationGeneration)`.
4. JNI packed storage key path added:
   - Rust encodes keys as `varint(count)` + `varint(len) + bytes`.
   - Java bridge decodes packed payload with strict validation.
   - RustMutableTrie uses packed path with automatic fallback to legacy array path.

### Evaluation protocol
1. Fast validation loop:
   - warmup `1`, measurement `2`, seconds `1`.
2. Deep decision loop:
   - warmup `5`, measurement `15`, seconds `10`.
   - execute three runs and use median for promotion decisions.
3. Functional guardrail remains mandatory:
   - Validation Run (On-Demand), `500` blocks, `repeatRuns=2`, fail-fast on divergence.

### Workload win criteria
A workload is considered a win for Rust when all are true:
1. `avg_time` Rust < Java
2. `p95` Rust <= Java * `1.02`
3. `throughput` Rust > Java

## 16. V4.2 Spec-First Evidence Program (Crimsonland-Inspired)
### Spec-first development contract
Consensus-critical work is now traceable through a stable spec map:
1. Machine-readable map:
   - `/Users/void_rsk/.codex/worktrees/35ae/rskj/docs/engineering/unitrie-spec-map.json`
2. Human-readable companion:
   - `/Users/void_rsk/.codex/worktrees/35ae/rskj/docs/engineering/unitrie-spec-map.md`
3. Validation schema:
   - `/Users/void_rsk/.codex/worktrees/35ae/rskj/docs/engineering/unitrie-spec-map.schema.json`

Every critical behavior is tracked with:
1. `SPEC_ID`
2. Java source anchor
3. Rust target (`legacy-v1` and/or `next`)
4. required tests/corpus evidence
5. status lifecycle (`missing|partial|implemented|verified`)

### Hard PR parity/spec gate
CI job: `unitrie-spec-parity-gate`

This job hard-fails on:
1. invalid spec map structure/completeness
2. missing evidence mapping for consensus-critical specs
3. parity replay failure (`UnitrieDifferentialCorpusReplayTest`)
4. rust-shadow smoke regression

Tooling:
1. `scripts/unitrie/check_spec_map.sh`
2. `scripts/unitrie/check_spec_map.py`

### Differential recorder enrichment
Differential JSONL events now include:
1. `specId`
2. `specClass`
3. `phase` (`mutation|read|save|reload`)
4. `engineImpl` (`legacy-v1|next`)

Divergence artifacts now include:
1. `suspectedSpecIds[]`
2. `evidenceBundleId`
3. `rustImpl`
4. `jniCounters` snapshot payload (available/unavailable marker)

### Benchmark policy in V4.2
Policy split:
1. PR smoke benchmark:
   - mandatory execution
   - non-blocking performance warnings
2. Deep decision benchmark:
   - manual/on-demand
   - three deep runs
   - median-based decision artifact

Deep helpers:
1. `scripts/unitrie/benchmark_deep_3x.sh`
2. `scripts/unitrie/benchmark_median_report.py`

Median output:
- `/Users/void_rsk/.codex/worktrees/35ae/rskj/rskj-core/build/reports/jmh/result_trie_engine_median_summary.json`

### Corpus promotion protocol
Mismatch handling before retrying validation:
1. capture corpus on fail-fast
2. promote corpus to test resources
3. replay deterministically in tests
4. retry validation run only after replay is green

Helper:
- `scripts/unitrie/promote_corpus.sh`

### Evidence ladder
Promotion claims must follow this order:
1. unit tests
2. differential corpus replay
3. validation run (500 blocks, repeatRuns=2, same DB/range)
4. deep benchmark median decision report

### Production default remains unchanged
`blockchain.unitrie.engine=java` stays the production default in this phase.
