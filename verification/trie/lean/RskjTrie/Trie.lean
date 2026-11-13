import RskjTrie.SharedPathSerializer
import RskjTrie.Uint
/-!
# `co.rsk.trie.Trie` and `co.rsk.trie.NodeReference`: data and store-free methods

Java fields → model (see MODEL.md for the soundness argument of each abstraction):

* `Trie.value` (nullable `byte[]`)            → `value : Option Bytes`
* `Trie.left/right` (`NodeReference`)         → `left/right : NodeRef Trie`
* `Trie.valueLength` (`Uint24`)               → `valueLength : Nat`
* `Trie.valueHash` (nullable `Keccak256`)     → `valueHash : Option Bytes`
* `Trie.childrenSize` (nullable `VarInt`)     → `childrenSize : Option Nat` (64-bit pattern)
* `Trie.sharedPath` (`TrieKeySlice`)          → `sharedPath : TrieKeySlice` (= `List Bool`)
* `Trie.store`                                → not a field: every trie of a run shares one store,
  passed as `Env` to the operations that read it.
* caches `hash`, `hashOrchid`, `encoded` and the `saved` flag → not modelled (pure caches / an
  optimisation of `TrieStoreImpl.save`, see MODEL.md).
* `NodeReference{lazyNode, lazyHash}`         → `NodeRef.empty` (both null), `NodeRef.node t`
  (`lazyNode = t`, `lazyHash` is then only a cache of `t.getHash()`), `NodeRef.hash h`
  (`lazyNode = null`, `lazyHash = h`).
-/
namespace RskjTrie

/-- `co.rsk.trie.NodeReference` state (NodeReference.java:33-55). -/
inductive NodeRef (α : Type) where
  /-- `NodeReference.empty()` / `lazyNode == null && lazyHash == null`. -/
  | empty
  /-- `lazyNode != null` (node resident in memory). -/
  | node (t : α)
  /-- `lazyNode == null && lazyHash != null` (node only known by hash, to be read from store). -/
  | hash (h : Bytes)
  deriving Repr, DecidableEq, Inhabited

/-- `co.rsk.trie.Trie` (Trie.java:61-156), without the store and the pure caches. -/
structure Trie where
  sharedPath : TrieKeySlice
  value : Option Bytes
  left : NodeRef Trie
  right : NodeRef Trie
  valueLength : Nat
  valueHash : Option Bytes
  childrenSize : Option Nat
  deriving Repr, Inhabited

/-- The environment a Java `Trie` sees through its `TrieStore`: the hash function
(`Keccak256Helper.keccak256`, a parameter of every theorem) and the contents of the
`KeyValueDataSource` behind `TrieStoreImpl` (a finite map from byte arrays to byte arrays). -/
structure Env where
  H : Bytes → Bytes
  db : Bytes → Option Bytes

/-- Bound on the nesting of *store reads inside size/hash computations*
(`getChildrenSize` of a node whose `childrenSize` is null, reached only from legacy/orchid
nodes). Java recurses without bound (a cyclic store would overflow the stack); the model returns
an error after `FUEL` nested reads. Never reached by nodes produced by `put`/`fromMessageRskip107`,
whose `childrenSize` is never null. -/
def FUEL : Nat := 4096

/-- Java `long` arithmetic result as a 64-bit pattern. -/
def wrap64 (x : Int) : Nat := (x % (2 ^ 64 : Int)).toNat

/-- Java `(byte) b` and `0bxxxxxxxx` flag constants as `UInt8`. -/
abbrev Flags := UInt8

namespace NodeRef

/-- `NodeReference.isEmpty()` — NodeReference.java:61-63. -/
def isEmpty {α} : NodeRef α → Bool
  | .empty => true
  | _ => false

/-- `NodeReference.wasLoaded()` — NodeReference.java:151-153. -/
def wasLoaded {α} : NodeRef α → Bool
  | .node _ => true
  | _ => false

end NodeRef

namespace Trie

/-- `Trie.ARITY` — Trie.java:67. -/
def ARITY : Nat := 2
/-- `Trie.MAX_EMBEDDED_NODE_SIZE_IN_BYTES` — Trie.java:68. -/
def MAX_EMBEDDED_NODE_SIZE_IN_BYTES : Nat := 44
/-- `Trie.MESSAGE_HEADER_LENGTH` (orchid) — Trie.java:71. -/
def MESSAGE_HEADER_LENGTH : Nat := 6

/-- `new Trie(store)` — Trie.java:128-130 → 132-134: empty path, null value, empty refs,
`valueLength = 0`, `childrenSize = new VarInt(0)`. -/
def empty : Trie := ⟨[], none, .empty, .empty, 0, none, some 0⟩

/-- `Trie.getDataLength(byte[])` — Trie.java:823-829 (`new Uint24(value.length)` may throw). -/
def getDataLength (v : Option Bytes) : Except Err Nat :=
  match v with
  | none => .ok 0
  | some v => Uint24.mk v.length

/-- `private Trie(TrieStore, TrieKeySlice, byte[] value)` — Trie.java:132-134. -/
def leaf (p : TrieKeySlice) (v : Option Bytes) : Except Err Trie := do
  let n ← getDataLength v
  pure ⟨p, v, .empty, .empty, n, none, some 0⟩

/-- `Trie.isTerminal()` — Trie.java:942-944. -/
def isTerminal (t : Trie) : Bool := t.left.isEmpty && t.right.isEmpty

/-- `Trie.isEmptyTrie(Uint24, NodeReference, NodeReference)` — Trie.java:959-965. -/
def isEmptyTrieOf (valueLength : Nat) (l r : NodeRef Trie) : Bool :=
  if valueLength > 0 then false else l.isEmpty && r.isEmpty

/-- `Trie.isEmptyTrie()` — Trie.java:946-948. -/
def isEmptyTrie (t : Trie) : Bool := isEmptyTrieOf t.valueLength t.left t.right

/-- `Trie.hasLongValue()` — Trie.java:967-969: `valueLength > 32`. -/
def hasLongValue (t : Trie) : Bool := t.valueLength > 32

/-- `Trie.checkValueLength()` — Trie.java:1027-1037 (run by the full constructor, Trie.java:155). -/
def checkValueLength (t : Trie) : Except Err Unit :=
  match t.value with
  | some v => if v.length ≠ t.valueLength then .error "IllegalArgumentException: Invalid value length" else .ok ()
  | none => if t.valueLength > 0 ∧ t.valueHash = none then .error "IllegalArgumentException: Invalid value length" else .ok ()

/-- `Trie.getNodeReference(byte implicitByte)` — Trie.java:749-751 (`false` = 0 = left). -/
def getNodeReference (t : Trie) (implicitByte : Bool) : NodeRef Trie :=
  if implicitByte = false then t.left else t.right

end Trie

/-- `new NodeReference(store, node, null)` — NodeReference.java:44-55: a null node or an empty
trie gives the empty reference. -/
def NodeRef.ofNode (t : Option Trie) : NodeRef Trie :=
  match t with
  | none => .empty
  | some t => if t.isEmptyTrie then .empty else .node t

end RskjTrie
