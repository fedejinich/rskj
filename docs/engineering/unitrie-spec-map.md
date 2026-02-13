# Unitrie Spec Map (Java Source of Truth)

## Purpose
This map is the canonical traceability index for consensus-critical Java `unitrie` behavior and its Rust implementation targets.

Every entry binds:
1. Stable `SPEC_ID`.
2. Java source anchor.
3. Rust target implementation scope (`legacy-v1`, `next`).
4. Required executable evidence (tests/corpus).
5. Current status for parity closure tracking.

The machine-readable source of truth is:
- `/Users/void_rsk/.codex/worktrees/35ae/rskj/docs/engineering/unitrie-spec-map.json`

## Status Legend
- `missing`: no implementation/evidence mapped yet.
- `partial`: implementation and/or evidence still incomplete.
- `implemented`: behavior implemented, evidence still maturing.
- `verified`: implementation plus evidence accepted for the current gate scope.

## Consensus-Critical Coverage
| SPEC_ID | Class | Java Anchor | Rust Target | Status |
|---|---|---|---|---|
| `SPEC-TRIE-PUT-SPLIT-COALESCE-001` | trie | `co/rsk/trie/Trie.java:438,827,915` | legacy-v1,next | partial |
| `SPEC-TRIE-DELETE-RECURSIVE-PREFIX-001` | trie | `co/rsk/trie/Trie.java:475` | legacy-v1,next | verified |
| `SPEC-TRIE-GET-FIND-001` | trie | `co/rsk/trie/Trie.java:407,650` | legacy-v1,next | verified |
| `SPEC-TRIE-COLLECT-KEYS-ITERATION-001` | trie | `co/rsk/trie/Trie.java:594,618` | legacy-v1,next | implemented |
| `SPEC-TRIE-CHILDREN-SIZE-VARINT-001` | trie | `co/rsk/trie/Trie.java:682,997` | legacy-v1,next | partial |
| `SPEC-TRIE-EMBEDDABLE-THRESHOLD-44-001` | trie | `co/rsk/trie/Trie.java:68,588` | legacy-v1,next | partial |
| `SPEC-TRIE-VALUE-LENGTH-HASH-001` | trie | `co/rsk/db/MutableTrieImpl.java:67,78` | legacy-v1,next | verified |
| `SPEC-CODEC-RSKIP107-SERIALIZE-001` | codec-rskip107 | `co/rsk/trie/Trie.java:677` | legacy-v1,next | verified |
| `SPEC-CODEC-RSKIP107-DESERIALIZE-001` | codec-rskip107 | `co/rsk/trie/Trie.java:259` | legacy-v1,next | verified |
| `SPEC-CODEC-ORCHID-SERIALIZE-001` | codec-orchid | `co/rsk/trie/Trie.java:525` | legacy-v1,next | verified |
| `SPEC-CODEC-ORCHID-DESERIALIZE-001` | codec-orchid | `co/rsk/trie/Trie.java:177` | legacy-v1,next | verified |
| `SPEC-STORAGE-KEYS-RSKIP108-MAPPING-001` | storage-keys | `org/ethereum/db/TrieKeyMapper.java:68,74` | legacy-v1,next | implemented |
| `SPEC-STORAGE-KEYS-ITERATION-ORDER-001` | storage-keys | `co/rsk/db/MutableTrieImpl.java:93` | legacy-v1,next | implemented |
| `SPEC-PERSISTENCE-SAVE-RAW-NODES-001` | persistence | `co/rsk/trie/TrieStoreImpl.java:56,89` | legacy-v1,next | implemented |
| `SPEC-PERSISTENCE-LONG-VALUE-BLOBS-001` | persistence | `co/rsk/trie/TrieStoreImpl.java:132` | legacy-v1,next | partial |
| `SPEC-PERSISTENCE-RETRIEVE-ROOT-001` | persistence | `co/rsk/trie/TrieStoreImpl.java:162` | legacy-v1,next | partial |
| `SPEC-HASH-EMPTY-ROOT-001` | hash | `co/rsk/trie/Trie.java:371,407` | legacy-v1,next | verified |
| `SPEC-HASH-LONG-VALUE-THRESHOLD-001` | hash | `co/rsk/trie/Trie.java:732,963` | legacy-v1,next | partial |
| `SPEC-HASH-ROOT-PARITY-001` | hash | `co/rsk/cli/tools/UnitrieValidationRunOnDemand.java:328` | legacy-v1,next | partial |

## Diagnostic / Non-Critical Coverage
| SPEC_ID | Class | Java Anchor | Rust Target | Status |
|---|---|---|---|---|
| `SPEC-JNI-EXECUTION-STABILITY-001` | jni | `co/rsk/trie/engine/rust/RustUnitrieBridge.java:45` | legacy-v1,next | implemented |
| `SPEC-TRIE-UNCLASSIFIED-001` | diagnostics | `co/rsk/trie/engine/rust/diagnostics/TrieDifferentialSpecResolver.java:26` | legacy-v1,next | implemented |

## Required Prefix Domains
The mandatory consensus-critical domains validated by tooling are:
- `SPEC-TRIE-`
- `SPEC-CODEC-RSKIP107-`
- `SPEC-CODEC-ORCHID-`
- `SPEC-STORAGE-KEYS-`
- `SPEC-PERSISTENCE-`
- `SPEC-HASH-`

## Gate Policy
PR gate `unitrie-spec-parity-gate` fails if any of the following is true:
1. Spec map JSON is invalid against policy checks/schema rules.
2. A consensus-critical entry has status `missing`.
3. A consensus-critical entry has no evidence references (`requiredTests` and `requiredCorpus` both empty).
4. Any required prefix domain is absent from the consensus-critical map.
