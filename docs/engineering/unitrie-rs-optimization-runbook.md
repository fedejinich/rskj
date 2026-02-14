# Unitrie-rs Optimization Runbook (V5)

## 1. Scope
This runbook defines the iterative optimization flow for `unitrie-rs` while preserving consensus safety.

Default production runtime remains:
- `blockchain.unitrie.engine = "java"`

Rust variants:
- `legacy-v1` (frozen baseline)
- `next` (active optimization target)

## 1.1 Spec-first contract (V4.2)
Before optimization decisions, parity evidence must be traceable through:
1. `/Users/void_rsk/.codex/worktrees/35ae/rskj/docs/engineering/unitrie-spec-map.json`
2. `/Users/void_rsk/.codex/worktrees/35ae/rskj/docs/engineering/unitrie-spec-map.md`
3. `/Users/void_rsk/.codex/worktrees/35ae/rskj/docs/engineering/unitrie-spec-map.schema.json`

Hard local check:
```bash
scripts/unitrie/check_spec_map.sh
```

PR policy:
1. spec/parity gaps are blocking
2. benchmark performance warnings remain non-blocking

## 1.2 V5 replacement target
Current objective for `rust(next)`:
1. Reach `5/5` benchmark wins against Java on deep median E2E.
2. Respect balanced memory policy:
   - `gc.alloc.rate.norm` for Rust must remain `<= Java * 1.15` per workload.
3. Keep parity and consensus safety unchanged.

Workload win definition:
1. `avg_time` (Rust) < `avg_time` (Java)
2. `p95` (Rust) <= `p95` (Java) * `1.02`
3. `throughput` (Rust) > `throughput` (Java)
4. `alloc_norm` (Rust) <= `alloc_norm` (Java) * `1.15`

## 2. Baseline and immutability
1. Legacy snapshot path:
   - `/Users/void_rsk/.codex/worktrees/35ae/rskj/unitrie-rs-legacy-v1`
2. CI policy:
   - PRs must not modify `unitrie-rs-legacy-v1`.
3. Active code path:
   - Core implementation: `/Users/void_rsk/.codex/worktrees/35ae/rskj/unitrie-rs-core`
   - JNI adapter/runtime glue: `/Users/void_rsk/.codex/worktrees/35ae/rskj/unitrie-rs`

## 3. Optimization loop
Use this sequence on every optimization cycle:
1. Implement small change in `unitrie-rs-core` (`next` path only when possible); touch `unitrie-rs` only for JNI adapter needs.
2. Validate spec map:
   - `scripts/unitrie/check_spec_map.sh`
3. Run Rust tests:
   - `cargo test --manifest-path unitrie-rs-core/Cargo.toml`
   - `cargo test --manifest-path unitrie-rs/Cargo.toml`
4. Run focused Java/unitrie tests:
   - `./gradlew :rskj-core:test --tests "co.rsk.config.UnitrieConfigTest" --tests "co.rsk.trie.engine.rust.*"`
5. Run benchmark comparison (`java` vs `rust legacy-v1,next`).
6. Inspect benchmark artifacts and warnings.
7. If performance improves and parity remains clean, keep change.
8. If divergence/regression appears, triage and revert/fix before next cycle.

Reusable-core validation command:
```bash
scripts/unitrie/validate_reusable_core.sh
```
This command enforces:
1. `unitrie-rs-core` parity checks (`legacy-v1` vs `next`) in Rust.
2. Java differential corpus replay against Rust for both implementations.

## 4. Benchmark commands
## Fast local sample
```bash
UNITRIE_JMH_WARMUP_ITERATIONS=1 \
UNITRIE_JMH_MEASUREMENT_ITERATIONS=2 \
UNITRIE_JMH_WARMUP_SECONDS=1 \
UNITRIE_JMH_MEASUREMENT_SECONDS=1 \
UNITRIE_JMH_FORKS=1 \
UNITRIE_JMH_ENGINES=java,rust \
UNITRIE_JMH_RUST_IMPLEMENTATIONS=next \
./gradlew :rskj-core:jmh -Pbenchmark=BenchmarkTrieEngineRunner
```

## Deep profile sample
```bash
UNITRIE_JMH_WARMUP_ITERATIONS=5 \
UNITRIE_JMH_MEASUREMENT_ITERATIONS=15 \
UNITRIE_JMH_WARMUP_SECONDS=10 \
UNITRIE_JMH_MEASUREMENT_SECONDS=10 \
UNITRIE_JMH_FORKS=1 \
UNITRIE_JMH_ENGINES=java,rust \
UNITRIE_JMH_RUST_IMPLEMENTATIONS=next \
./gradlew :rskj-core:jmh -Pbenchmark=BenchmarkTrieEngineRunner
```

## Deep decision run (3 attempts, median)
```bash
scripts/unitrie/benchmark_deep_3x.sh
```

Manual median report generation for an existing deep-runs folder:
```bash
scripts/unitrie/benchmark_median_report.py \
  --runs-dir rskj-core/build/reports/jmh/deep-runs/<run-group-id> \
  --output rskj-core/build/reports/jmh/result_trie_engine_median_summary.json \
  --candidate "rust(next)" \
  --memory-multiplier 1.15
```

Save/reload focused KPI extraction:
```bash
scripts/unitrie/save_reload_report.py \
  --summary rskj-core/build/reports/jmh/result_trie_engine_summary.json \
  --jni-breakdown rskj-core/build/reports/jmh/result_trie_engine_jni_breakdown.json \
  --out rskj-core/build/reports/jmh/result_trie_save_reload_focus.json
```

## JNI-only decontaminated benchmark modes (V4.3)
Use the dedicated script modes:

1. End-to-end only:
```bash
scripts/unitrie/benchmark_deep_3x.sh --mode e2e
```
2. JNI micro-overhead only:
```bash
scripts/unitrie/benchmark_deep_3x.sh --mode jni-micro
```
3. Full decontaminated run (`e2e + jni-micro + core-to-core`):
```bash
scripts/unitrie/benchmark_deep_3x.sh --mode full
```

`--mode full` additionally runs:
1. Java core-only benchmark (`TrieJavaCoreBenchmark`) over shared corpus.
2. Rust core-only benchmark (`unitrie-rs-core/benches/core_trie_bench.rs`) over the same corpus.
3. Merge step via:
```bash
scripts/unitrie/merge_core_benchmarks.py
```

Shared corpus:
- `/Users/void_rsk/.codex/worktrees/35ae/rskj/benchmarks/unitrie-corpus/workloads-v1.json`

If JNI library is not discoverable:
```bash
UNITRIE_JMH_RUST_LIBRARY_PATH=/absolute/path/to/libunitrie_rs_jni.dylib \
./gradlew :rskj-core:jmh -Pbenchmark=BenchmarkTrieEngineRunner
```

## 5. Artifact interpretation
Generated files:
- `/Users/void_rsk/.codex/worktrees/35ae/rskj/rskj-core/build/reports/jmh/result_trie_engine.csv`
- `/Users/void_rsk/.codex/worktrees/35ae/rskj/rskj-core/build/reports/jmh/result_trie_engine_summary.json`
- `/Users/void_rsk/.codex/worktrees/35ae/rskj/rskj-core/build/reports/jmh/result_trie_engine_comparison.md`
- `/Users/void_rsk/.codex/worktrees/35ae/rskj/rskj-core/build/reports/jmh/result_trie_engine_jni_breakdown.json`
- `/Users/void_rsk/.codex/worktrees/35ae/rskj/rskj-core/build/reports/jmh/result_trie_jni_microbench.json`
- `/Users/void_rsk/.codex/worktrees/35ae/rskj/rskj-core/build/reports/jmh/result_trie_java_core_summary.json`
- `/Users/void_rsk/.codex/worktrees/35ae/rskj/rskj-core/build/reports/jmh/result_trie_rust_core_summary.json`
- `/Users/void_rsk/.codex/worktrees/35ae/rskj/rskj-core/build/reports/jmh/result_trie_core_comparison.json`
- `/Users/void_rsk/.codex/worktrees/35ae/rskj/rskj-core/build/reports/jmh/result_trie_save_reload_focus.json`

Interpretation rules:
1. `summary.json` is machine-readable source of truth.
2. `comparison.md` highlights Java deltas per Rust candidate (`legacy-v1`, `next`).
3. Warnings are non-blocking signals for triage, not consensus verdicts.
4. For V4.2 decisions, use median across 3 deep runs stored under `deep-runs/`.
5. Median verdict artifact:
   - `/Users/void_rsk/.codex/worktrees/35ae/rskj/rskj-core/build/reports/jmh/result_trie_engine_median_summary.json`
6. `result_trie_engine_jni_breakdown.json` provides JNI contamination ratio per workload:
   - `jniBoundaryNsPerOp = ffi_decode + ffi_encode`
   - `coreRuntimeNsPerOp`
   - `storeCallbackNsPerOp`
   - `jniOverheadRatioPct`
7. Core comparison (`result_trie_core_comparison.json`) is the JNI-free signal for Java core vs Rust core.
8. Save/reload focus (`result_trie_save_reload_focus.json`) is the dedicated KPI source for:
   - `storeCallbackCallsPerOp`
   - `storeCallbackNsPerOp`
   - `nodesSavedPerOp`
   - `dirtyNodesSavedPerOp`
   - `dirtyNodesSavedRatio`
   - `rehydrateRootOnlyCountPerOp`
   - `rehydrateFullScanFallbackCountPerOp`

## 6. Parity gate (separate from benchmark)
Performance is not enough. Before considering promotion:
1. Run Validation Run (On-Demand):
   - `--deep --repeatRuns 2 --failFast true`
2. Use the same block range and same local DB.
3. Require zero divergences and zero JNI errors.

## 7. Divergence triage flow
When mismatch occurs:
1. Stop at first divergence (`fail-fast`).
2. Collect generated artifacts + corpus.
3. Promote corpus:
   - `scripts/unitrie/promote_corpus.sh <path-to-corpus.jsonl>`
4. Add/adjust deterministic replay assertions.
5. Run replay test until deterministic green.
6. Re-run 500-block validation gate.

## 8. Evidence ladder (must be sequential)
1. Spec map passes (`check_spec_map.sh`).
2. Unit tests pass.
3. Differential corpus replay passes.
4. Validation Run (On-Demand) `500` blocks x `2` clean runs.
5. Deep benchmark median report produced and reviewed.

## 9. Promotion checklist (`rust(next)` candidate)
1. Functional parity sustained in bounded validation runs.
2. No JNI stability issues.
3. Rust `next` wins `5/5` on deep median with memory criterion (`<=1.15x`).
4. Rollback remains immediate via `blockchain.unitrie.engine=java`.

## 10. Clarification
Benchmark superiority is necessary but never sufficient. Promotion requires both:
1. parity evidence ladder completion
2. benchmark median decision evidence

Important:
1. Decontaminated benchmark evidence is not a consensus gate.
2. Consensus parity gate remains Validation Run (On-Demand) `500x2`.
