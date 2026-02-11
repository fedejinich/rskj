# Unitrie-rs Design and Rollout (V1)

## 1. Problem Statement
`unitrie` is consensus-critical in RSKj. Today it is tightly coupled to Java-only internals, which limits modular evolution and blocks reuse by Rust-based clients.

This design introduces an in-repo Rust crate (`unitrie-rs`) and a runtime-switchable trie engine in RSKj:
- `java` (default, current behavior)
- `rust` (opt-in, JNI-backed adapter)
- `rust-shadow` (Java source of truth + deterministic Rust mirror checks)

The default path remains Java to protect consensus safety during V1.

## 2. Goals and Non-Goals
### Goals
- Introduce a modular engine abstraction so RSKj can select trie implementation at runtime.
- Add JNI bridge scaffolding for a Rust trie engine without changing default behavior.
- Add shadow-mode differential checks for deterministic mismatch detection.
- Add raw persistence extension points in `TrieStore` for Rust-native persistence paths.
- Add benchmark harnesses for Java vs Rust-engine modes under equal workloads.
- Provide a rollout and rollback strategy suitable for consensus-sensitive software.

### Non-Goals (V1)
- Switching production default to Rust.
- Replacing Java DTO/snapshot pipeline.
- Enabling fuzzing in CI (deferred roadmap included below).
- Claiming parity gates are met before differential suite and benchmark thresholds pass.

## 3. Consensus-Critical Invariants and Hardfork Risk Model
### Invariants that must match Java behavior
- `get`, `put`, `deleteRecursive` externally observable behavior.
- Root hash determinism for identical operation sequence.
- Empty trie hash semantics.
- Long-value handling and value-hash behavior.
- Node embedding thresholds and child encoding behavior.
- Compatibility across legacy/orchid behavior and RSKIP107-activated behavior.
- Persistence/readback equivalence (Java->Rust, Rust->Java).

### Risk model
- Any trie divergence can alter state roots and trigger consensus split (hardfork risk).
- Therefore V1 keeps Java default and adds `rust-shadow` to detect divergences before enabling Rust in production.
- `failOnMismatch=true` provides fail-close behavior for safety-sensitive environments.
- Rollback is configuration-only (`engine=java`) and does not require schema migration in V1.

## 4. Current Java `unitrie` Behavior Map
### Core components
- `co.rsk.trie.Trie`: immutable trie node graph and hash/serialization behavior.
- `co.rsk.db.MutableTrieImpl`: mutable facade over immutable trie transitions.
- `co.rsk.trie.TrieStore` + `TrieStoreImpl` + `MultiTrieStore`: persistence, retrieval, epoch rotation.
- `co.rsk.db.RepositoryLocator`: repository creation from state root snapshots.

### Persistence model (Java path)
- Nodes serialized as trie messages and stored by hash.
- Long values stored out-of-line under value hash.
- Multi-epoch store keeps `unitrie_*` directories and GC epoch behavior unchanged.

## 5. Rust Crate Architecture
Crate path: `/Users/void_rsk/.codex/worktrees/35ae/rskj/unitrie-rs`

### Modules
- `trie.rs`: mutable trie core abstraction used by JNI.
- `hash.rs`: Keccak helper and empty-trie hash semantics.
- `path.rs`: path bit-packing helpers.
- `codec_orchid.rs`: codec placeholder module for orchid-compatible encoding stage.
- `codec_rskip107.rs`: codec placeholder module for RSKIP107-compatible encoding stage.
- `store.rs`: trait for raw-node/raw-value store adapter.
- `ffi.rs`: JNI exports, handle table, JNI error translation.

### Current V1 implementation notes
- JNI entrypoints are fully wired and tested at crate level.
- Handle lifecycle uses an in-process map keyed by opaque `jlong`.
- Error conditions translate to Java exceptions (`IllegalArgumentException` / `IllegalStateException`).
- Rust internals are intentionally isolated from Java persistence pipeline in V1.

## 6. JNI Boundary Contract
Java side: `co.rsk.trie.engine.rust.RustUnitrieBridge`

### Native operations
- `nativeCreateTrie() -> long`
- `nativeDestroyTrie(long handle)`
- `nativeGet(long handle, byte[] key) -> byte[]|null`
- `nativePut(long handle, byte[] key, byte[] valueOrNull)`
- `nativeDelete(long handle, byte[] key)`
- `nativeDeleteRecursive(long handle, byte[] key)`
- `nativeRootHash(long handle) -> byte[]`

### Memory and ownership rules
- Java owns byte-array lifetimes on the caller side.
- Rust copies incoming byte arrays into owned buffers.
- Returned arrays are newly allocated JNI byte arrays.
- Handles are opaque; Java must eventually call destroy.
- Invalid handles and null-required arguments raise Java exceptions.
- No global mutable state is exposed across engines except internal synchronized handle table.

## 7. Engine Selection and Fallback
Config keys:
- `blockchain.unitrie.engine = "java" | "rust" | "rust-shadow"` (default: `java`)
- `blockchain.unitrie.rust.failOnMismatch = true|false`
- `blockchain.unitrie.rust.libraryPath = "" | "<absolute native library path>"`

### Behavior
- `java`: uses current `MutableTrieImpl`.
- `rust-shadow`: Java source of truth; Rust mirror runs when JNI is available; mismatches follow policy.
- `rust`: JNI required; if bridge cannot load, startup fails fast.

### Fallback semantics
- In `rust-shadow`, JNI load failure falls back to Java-only execution (with warning logs).
- In `rust`, JNI load failure throws immediately to avoid silent engine drift.

## 8. Test Strategy and Acceptance Criteria
### Required test layers
- Config tests: parsing/default/fallback behavior.
- Engine selection tests: enum parsing and factory behavior.
- Repository wiring tests: `RepositoryLocator` uses injected factory.
- JNI fallback tests: rust vs rust-shadow behavior with missing native library.
- Rust crate unit tests: hash/path/trie semantics and JNI-safe behavior at crate boundary.
- Differential replay tests (planned expansion): same op sequence, compare root/value/reload.
- Cross-read/write compatibility tests (planned expansion): Java->Rust and Rust->Java persistence.

### Acceptance criteria (V1 gate)
- Java default behavior unchanged.
- `rust-shadow` mismatch path validated and policy-controlled.
- JNI bridge load path deterministic and well-logged.
- Differential smoke tests pass in CI before rollout progression.

## 9. Benchmark Methodology and Regression Gates
JMH package: `/Users/void_rsk/.codex/worktrees/35ae/rskj/rskj-core/src/jmh/java/co/rsk/jmh/trie`

### Workloads covered
- Put/get/delete mix.
- Long-value heavy paths.
- Save/reload cycle.
- Account storage key iteration.
- Dataset-driven replay using:
  `/Users/void_rsk/.codex/worktrees/35ae/rskj/rskj-core/src/test/resources/trie/massive-upload.dmp`

### Methodology
- Same benchmark code path with `@Param(engine={java,rust-shadow})`.
- Deterministic key/value corpus and deterministic dataset replay.
- CSV output for historical trend analysis.

### Regression gate
- Target threshold: no regression beyond ~5% on agreed corpus before Rust production enablement.
- If threshold is exceeded, keep Java default and block rollout stage advancement.

## 10. Rollout Stages and Rollback Playbook
### Stage 0: Scaffolding (this V1)
- Add config keys, factory abstraction, JNI adapter, Rust crate foundation, benchmark harness, and docs.

### Stage 1: CI shadow validation
- Run differential smoke checks on PR.
- Run extended deterministic corpus and benchmark trend reports nightly.

### Stage 2: Controlled environments
- Enable `rust-shadow` in canary/staging with `failOnMismatch=true`.
- Investigate and eliminate mismatches; collect benchmark evidence.

### Stage 3: Optional Rust enablement
- Consider `engine=rust` only after parity and performance gates are met.
- Keep rollback as config change to `engine=java`.

### Rollback playbook
1. Set `blockchain.unitrie.engine=java`.
2. Restart node process.
3. Preserve mismatch logs and benchmark artifacts for triage.
4. Keep differential tests active until root cause is resolved.

## 11. CI Strategy (V1, No Fuzzing Yet)
### PR checks
- Java trie and engine-selection tests.
- Rust unit tests (`cargo test` in `unitrie-rs`).
- JNI load smoke path.
- Differential parity smoke subset.
- JMH smoke invocation for trie benchmark class.

### Nightly checks
- Extended deterministic differential replay corpus.
- Extended benchmark suites and trend publication.

### Deferred
- Fuzzing jobs are intentionally excluded from V1 implementation.

## 12. Future Fuzzing Roadmap (Not Implemented in V1)
- Add cross-engine differential fuzzing harness (Java vs Rust) for op-sequence generation.
- Seed with deterministic corpus and historical mismatch reproductions.
- Include targeted mutators for:
  - long/short value boundary transitions,
  - deletion recursion edge cases,
  - persistence/reload orderings,
  - codec mode transitions (legacy/orchid/RSKIP107).
- Promote findings into deterministic regression vectors in both Java and Rust test suites.

## 13. Open V1 Follow-Ups
- Expand Rust trie internals to full Java parity semantics under consensus gates.
- Add exhaustive cross-read/write compatibility suite.
- Add production-grade JNI lifecycle cleanup hooks integrated with repository lifecycle.
- Define and automate benchmark baseline management with threshold alarms.
