# Unitrie-rs Optimization Runbook (V4)

## 1. Scope
This runbook defines the iterative optimization flow for `unitrie-rs` while preserving consensus safety.

Default production runtime remains:
- `blockchain.unitrie.engine = "java"`

Rust variants:
- `legacy-v1` (frozen baseline)
- `next` (active optimization target)

## 2. Baseline and immutability
1. Legacy snapshot path:
   - `/Users/void_rsk/.codex/worktrees/35ae/rskj/unitrie-rs-legacy-v1`
2. CI policy:
   - PRs must not modify `unitrie-rs-legacy-v1`.
3. Active code path:
   - `/Users/void_rsk/.codex/worktrees/35ae/rskj/unitrie-rs`

## 3. Optimization loop
Use this sequence on every optimization cycle:
1. Implement small change in `unitrie-rs` (`next` path only when possible).
2. Run Rust tests:
   - `cargo test --manifest-path unitrie-rs/Cargo.toml`
3. Run focused Java/unitrie tests:
   - `./gradlew :rskj-core:test --tests "co.rsk.config.UnitrieConfigTest" --tests "co.rsk.trie.engine.rust.*"`
4. Run benchmark comparison (`java` vs `rust legacy-v1,next`).
5. Inspect benchmark artifacts and warnings.
6. If performance improves and parity remains clean, keep change.
7. If divergence/regression appears, triage and revert/fix before next cycle.

## 4. Benchmark commands
## Fast local sample
```bash
UNITRIE_JMH_WARMUP_ITERATIONS=1 \
UNITRIE_JMH_MEASUREMENT_ITERATIONS=2 \
UNITRIE_JMH_WARMUP_SECONDS=1 \
UNITRIE_JMH_MEASUREMENT_SECONDS=1 \
UNITRIE_JMH_FORKS=1 \
UNITRIE_JMH_ENGINES=java,rust \
UNITRIE_JMH_RUST_IMPLEMENTATIONS=legacy-v1,next \
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
UNITRIE_JMH_RUST_IMPLEMENTATIONS=legacy-v1,next \
./gradlew :rskj-core:jmh -Pbenchmark=BenchmarkTrieEngineRunner
```

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

Interpretation rules:
1. `summary.json` is machine-readable source of truth.
2. `comparison.md` highlights Java deltas per Rust candidate (`legacy-v1`, `next`).
3. Warnings are non-blocking signals for triage, not consensus verdicts.

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
3. Promote corpus to deterministic replay test.
4. Fix root cause.
5. Re-run replay test.
6. Re-run 500-block validation gate.

## 8. Promotion checklist (`rust(next)` candidate)
1. Functional parity sustained in bounded validation runs.
2. No JNI stability issues.
3. Rust `next` outperforms Java under agreed V4 policy.
4. Rollback remains immediate via `blockchain.unitrie.engine=java`.
