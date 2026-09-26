# rskj trie verification (Stage 1)

Formal verification of the **Java** Unitrie implementation in `rskj-core/src/main/java/co/rsk/trie`
(plus the key mapper `org/ethereum/db/TrieKeyMapper.java`) against the RSKIPs that specify it.

- **Pinned code:** rskj `ecef55ddf2b79fe5cd84c824118117dd825744b2` (fedejinich/rskj master, 2026-09-26).
  Production code is not modified by this work.
- **Specification:** the RSKIPs (rsksmart/RSKIPs, read-only clone at commit `c578f4e`). RSKIPs are the spec;
  where Java disagrees with an RSKIP that is recorded as a finding, not "fixed".
- **JBMC** checks the real, compiled rskj classes with bounded model checking.
- **Lean 4** gives unbounded proofs over a model that mirrors the Java classes one-to-one.
- **Differential tests** run the same case vectors on the real Java classes and on the executable
  Lean model and require byte-identical output (root hashes, serialized nodes, lookups).

## Layout

| Path | Contents |
| --- | --- |
| `spec/obligations.md`, `spec/obligations.json` | Obligations extracted from the RSKIPs, each with file/section/line citation |
| `lean/` | Lake project: executable model of the Java classes + one theorem per obligation |
| `jbmc/` | Harnesses on the real classes, environment models, `run-jbmc.sh`, pinned JBMC build |
| `differential/` | Shared case vectors, Java runner, Lean runner, `run.sh` |
| `matrix.md`, `matrix.json` | Traceability matrix: obligation -> Lean theorem -> JBMC harness -> status |
| `review/` | Source of the interactive review page |

## Toolchains (task-local, nothing global)

```sh
. verification/trie/env.sh          # ELAN_HOME, PATH, rskj_classpath()
verification/trie/jbmc/setup-jbmc.sh  # builds pinned JBMC 6.11.0 into verification/trie/.tools
```

Lean: `leanprover/lean4:v4.34.1` (core only, no Mathlib). JBMC: CBMC 6.11.0
(`820ff0f555b43fb78e0cd9332e498461bd14244b`) with java-models-library `c7835345`.

## Conventions

- **Obligation IDs:** `TRIE-<AREA>-<NN>`, areas: `KEY` (key mapping), `PATH` (bit-path encoding),
  `LSH` (shared-prefix length compression), `VARINT`, `NODE` (node format/flags/field order),
  `EMB` (embedded nodes), `VAL` (long values), `OPS` (put/get/delete), `CMP` (compression / canonical
  shape), `HASH` (node and root hash), `SER` (serialization round trip / parser), `STORE` (TrieStore),
  `SIZE` (treeSize / childrenSize). Stage 2 (inclusion proofs) uses `PROOF` and is out of scope here.
- **Lean theorem for obligation `TRIE-X-NN`:** `RskjTrie.Obligations.trie_x_nn` in
  `lean/RskjTrie/Obligations.lean`.
- **JBMC harness for obligation `TRIE-X-NN`:** a static method in `jbmc/harness/`, listed in
  `jbmc/harnesses.json` with its bounds.
- **Keccak-256** is an ideal, opaque function in both tools: Lean theorems take it as a parameter with
  explicit hypotheses (e.g. injectivity) instead of axioms; JBMC replaces it with a consistent
  nondeterministic oracle. Differential tests use the real Keccak on both sides.

## Status definitions (matrix)

| Status | Meaning |
| --- | --- |
| `proved` | Lean proves it for all inputs over the model **and** JBMC passes on the real classes within the stated bounds |
| `bounded` | Holds within the JBMC bounds on the real classes; no complete Lean proof |
| `fails` | Java does not satisfy the obligation as the RSKIP states it; reproducer attached |
| `finding` | RSKIP text is ambiguous/inconsistent or silent and the behaviour Java actually has is recorded (and verified); reproducer attached |
