# Lean model of the rskj Unitrie: abstractions and their justification

Pinned code: rskj `ecef55ddf2b79fe5cd84c824118117dd825744b2`. Java paths below are relative to
`rskj-core/src/main/java/`. The model is executable (`lake exe trie-diff`), and every `def`
carries a docstring naming the Java method and line range it mirrors.

## Layout

| Lean module | Java |
| --- | --- |
| `RskjTrie/Basic.lean` | `byte[]`, array reads, `java.nio.ByteBuffer` reads, exceptions |
| `RskjTrie/Uint.lean` | `co/rsk/core/types/ints/Uint8`, `Uint16`, `Uint24` |
| `RskjTrie/VarInt.lean` | `co.rsk.bitcoinj.core.VarInt` (bitcoinj-thin 0.14.4-rsk-18, read with `javap -c -p`) |
| `RskjTrie/PathEncoder.lean` | `co/rsk/trie/PathEncoder.java` |
| `RskjTrie/TrieKeySlice.lean` | `co/rsk/trie/TrieKeySlice.java` |
| `RskjTrie/SharedPathSerializer.lean` | `co/rsk/trie/SharedPathSerializer.java` |
| `RskjTrie/Trie.lean` | `Trie` / `NodeReference` data, constructors, store-free predicates |
| `RskjTrie/Serialization.lean` | `Trie.fromMessage*`, `toMessage`/`internalToMessage`, `toMessageOrchid`, `getHash*`, `getChildrenSize`, `getValue`, `getValueHash`; `NodeReference.getNode`/`serializeInto`/`isEmbeddable`/`referenceSize`/`getHash*`; `TrieStoreImpl.retrieve`/`retrieveValue` |
| `RskjTrie/Ops.lean` | `Trie.find`/`get`/`put`/`internalPut`/`split`/`delete`/`deleteRecursive`, delete-coalescing in `put(TrieKeySlice,…)` |
| `RskjTrie/TrieStore.lean` | `TrieStoreImpl.save` over a `HashMapDB` |
| `RskjTrie/TrieKeyMapper.lean` | `org/ethereum/db/TrieKeyMapper.java` (+ `ByteUtil.stripLeadingZeroes`, `DataWord.valueOf`, `RskAddress`) |
| `RskjTrie/Keccak.lean` | `Keccak256Helper.keccak256` (executable only; tested, not proved) |
| `RskjTrie/Proofs/*.lean` | theorems (see the report / `Audit.lean`) |
| `TrieDiff.lean` | differential runner, `differential/FORMAT.md` |

`Trie` and `NodeReference` are mutually dependent in Java; their store- and serialization-dependent
methods live together in `Serialization.lean`.

## Java construct → Lean construct → why it is sound → what JBMC should confirm

| Java | Lean | Soundness argument | JBMC should check on the real classes |
| --- | --- | --- | --- |
| `byte[]` | `Bytes = List UInt8` | The trie code copies arrays it receives/returns (`cloneArray`, `Arrays.copyOf*`) and never mutates a shared array after construction, so only contents matter. | – |
| exceptions (`IllegalArgumentException`, `BufferUnderflowException`, `ArrayIndexOutOfBounds`, `NegativeArraySize`, `NullPointerException`) | `Except String` | Every Java throw site in the mirrored code has an `.error` at the same point of the control flow; the runner prints only `error`. | – |
| `nodeStopper.stop(1)` (`System.exit(1)`, broken DB) | `.error` | Java does not return. | – |
| `ByteBuffer.wrap(m)` + relative `get`s + `get(position())` | `BB = StateT Bytes (Except String)`, state = remaining bytes | The parsers only read forwards from position 0 of a buffer whose limit is the array end; `get(byte[n])` throws without consuming when short (modelled). | – |
| `ByteBuffer.allocate(n)` + `put`s in `internalToMessage`/`toMessageOrchid` | list concatenation | The allocated size is the sum of the pieces' `serializedLength`s (`serializedLength_eq` proves the shared-path part). | the buffer is exactly full after the last `put` (no `BufferOverflowException`, no trailing zeros), for all nodes |
| `TrieKeySlice(expandedKey, offset, limit)` | `List Bool` (the viewed contents) | All methods observe only `expandedKey[offset..limit)`; `rebuildSharedPath`'s `copyOfRange` past the view is overwritten before use. | call sites of `slice(from,to)` satisfy `0 ≤ from ≤ to ≤ length()` and `get(i)` has `i < length()` (the model's `slice`/`get` do not throw) |
| expanded key bytes `0`/`1` | `Bool` | `PathEncoder.encode` tests `path[k] == 0`; `decode` only writes `0`/`1`. | – |
| `Uint24 valueLength`, `Uint8`, `Uint16` | `Nat` + range-checking constructors returning `Except` | Constructors throw outside the range; the model does too. | – |
| `VarInt.value` (`long`) | `Nat` in `[0,2^64)` = two's-complement bit pattern | `sizeOf`/`encode` look only at the bit pattern (negatives → 9 bytes), decode produces the pattern; `long` arithmetic in `internalPut`/`nodeSize` is `wrap64`. | – |
| `(int) varint.value` in `SharedPathSerializer.getPathBitsLength` | `toInt32` | exact. | – |
| `Trie.store` field | an `Env` (hash + store contents) passed to the operations that read the store | All nodes of one trie share one store. | – |
| `KeyValueDataSource` / `HashMapDB` | `DB = Bytes → Option Bytes` (finite map), `DB.put` | `HashMapDB.get/put` are map lookups/updates. | – |
| `Keccak256Helper.keccak256` | parameter `Env.H`; theorems assume only what they state (32-byte output, injectivity on the written values); `Keccak.lean` for execution | – | – |
| `NodeReference{lazyNode, lazyHash}` | `NodeRef.empty` / `.node t` / `.hash h` | `.node t` = `lazyNode ≠ null` (then `lazyHash` is only a cache of `t.getHash()`); `.hash h` = not loaded. **Limitation**: after `getNode()` loads a hashed reference, Java caches `lazyNode`, and `isEmbeddable()` (NodeReference.java:141-148) then depends on the loaded node, so the parent's message/hash can change (`TRIE-HASH-04`). The model does not cache and keeps `.hash h`. This is exact whenever no *loaded* hashed child is embeddable, which holds for every store written by `TrieStoreImpl.save` from well-formed tries (a stored message hashes exactly the non-embeddable children, `Trie.reparse`), and fails only for crafted stores (`differential/cases/reproducers.cases` case `repro-hash-04-loaded`). | for a node read from a store it wrote itself, loading a hashed child never makes `isEmbeddable()` true |
| `NodeReference(store, node, null)` with an empty node | `NodeRef.ofNode` → `.empty` | NodeReference.java:44-55. | – |
| caches `Trie.hash`, `hashOrchid`, `encoded`, `valueHash` (when the value is present), `NodeReference.lazyHash` of resident nodes, retrieved long `value` | not modelled (recomputed) | Each is a function of the node contents. **Same limitation as above**: `hash`/`encoded` computed *before* a lazy child is loaded are not invalidated afterwards. | same as above |
| `Trie.childrenSize` (nullable) | `Option Nat` | Not a pure cache: it is serialized. The model keeps it and mirrors the incremental update (Trie.java:891-910); `childrenSize_from_scratch` proves it equals the from-scratch value in well-formed tries. | – |
| `valueHash` when `value == null` (lazy long value) | `valueHash : Option Bytes` | the only link to the value in the store. | – |
| `Trie.saved` / `wasSaved()` / `markAsSaved()` | not modelled; `save` always walks resident nodes | A node marked saved was written under the same key with the same bytes, as were its long values and non-embedded descendants; rewriting is a no-op on the map. On crafted stores (non-canonical messages) the model may *add* an entry under the hash of the re-encoded message; it never changes an existing key's value. | – |
| `newNode == node` (Trie.java:887), returning `this` | `PutRes.same`/`.null`/`.new t`, `PutRes.isSame` | `same` exactly when Java returns the receiver; `split(...).put(...)` returning its receiver becomes `.new splitNode`. | – |
| `checkValueLength()` in constructors | checked in the parsers; not re-checked in `put` | The constructors used by `put`/`split`/coalescing copy fields of nodes that already passed the check, or build `value.length == valueLength`. | `checkValueLength` never throws from `internalPut`/`split`/coalescing |
| `getValueHash()` ↔ `getValue()` mutual call | `getValue` reads `valueHash` directly | `checkValueLength` excludes `value == null && valueLength > 0 && valueHash == null`, the only case where Java's pair would recurse. | – |
| recursion depth | `fromMessageRskip107` bounded by `message.length + 1` (never exhausted: each nesting level consumes ≥ 2 bytes); `FUEL = 4096` nested *store reads* inside size/hash computations (reachable only through legacy/orchid nodes with `childrenSize == null`) | Java recursion is unbounded (a cyclic store overflows the stack). | – |
| `TrieKeyMapper.accountKeys` cache | not modelled | memoises a pure function, returns copies. | – |
| `DataWord.valueOf(byte[])` | `dataWordValueOf` (left pad to 32, > 32 bytes throws) | DataWord.java:566-585. | – |

Two helper definitions factor code that Java writes inline, with the same control flow:
`readChild`/`readValue` (Trie.java:273-307 left/right child reads, 314-338 value), and
`retrieveNodeOrEmpty`/`replaceChild` (Trie.java:878-881, 891-910); `saveTail`/`saveRef`
(TrieStoreImpl.java:106-118, 120-143). The differential output was re-checked after each.

## Known divergence from Java (differential)

`reproducers.cases` / `repro-hash-04-loaded`: `load` of a crafted store in which a parent refers
*by hash* to a 4-byte terminal child, `getk 00`, then `hash`: Java returns
`d8921fa4…085de` (the loaded child is now embedded), the model returns `04f34ee9…b19b` (the stored
hash). All other cases in `differential/cases/*.cases` are byte-identical.
