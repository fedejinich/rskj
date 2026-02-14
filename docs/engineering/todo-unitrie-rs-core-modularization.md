# Unitrie-rs Core Modularization TODO

Status date: 2026-02-14

## Dependency graph

```mermaid
graph TD
  T1["T1 (RSKJ-2481) Create reusable crate scaffold"]
  T2["T2 (RSKJ-2482) Implement stable reusable API wrappers"]
  T3["T3 (RSKJ-2483) Add Rust parity tests (legacy-v1 vs next)"]
  T4["T4 (RSKJ-2484) Extend Java differential replay for both impls"]
  T5["T5 (RSKJ-2485) Add unified validation script"]
  T6["T6 (RSKJ-2486) Update engineering docs and runbook"]

  T1 --> T2
  T2 --> T3
  T2 --> T5
  T4 --> T5
  T3 --> T5
  T5 --> T6
```

## Execution TODO list

- [x] `T1` `status: done` `depends_on: []` `jira: RSKJ-2481`
  - Create new reusable crate `unitrie-rs-core` with no JNI dependency by default.
- [x] `T2` `status: done` `depends_on: [T1]` `jira: RSKJ-2482`
  - Expose a stable modular API (`UnitrieCore`, implementation selector, store adapter bridge).
- [x] `T3` `status: done` `depends_on: [T2]` `jira: RSKJ-2483`
  - Add deterministic Rust tests validating `next` against `legacy-v1`.
- [x] `T4` `status: done` `depends_on: []` `jira: RSKJ-2484`
  - Update Java corpus replay test to run against both Rust implementations.
- [x] `T5` `status: done` `depends_on: [T2, T3, T4]` `jira: RSKJ-2485`
  - Add one command/script to validate reusable crate + Java differential replay path.
- [x] `T6` `status: done` `depends_on: [T5]` `jira: RSKJ-2486`
  - Document reusable-crate usage and validation flow (including future Reth integration note).
