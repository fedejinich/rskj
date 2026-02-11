# Unitrie-rs Design and Rollout (V3 MVP)

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

### Validation run tuning
- `blockchain.unitrie.validationRun.defaultBlockCount = 50` (fast local default)
- `blockchain.unitrie.validationRun.deepBlockCount = 500` (MVP bounded validation run)

### Mode behavior
- `java`: legacy `MutableTrieImpl`.
- `rust`: Rust-backed mutable trie path via JNI.
- `rust-shadow`: Java source of truth, deterministic Rust checks, configurable fail-fast.

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

Gate policy:
- No material regression beyond agreed threshold on the benchmark corpus.

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
