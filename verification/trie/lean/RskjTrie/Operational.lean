import RskjTrie.TrieStore
/-!
# Operational (cache-faithful) layer

The pure model (`Trie`, `Serialization`, `Ops`, `TrieStore`) treats Java's caches as pure. They are
not always pure: `NodeReference.lazyNode` (a hashed child becomes loaded after
`getNode()`), `Trie.hash` and `Trie.encoded` (computed once, never invalidated) and `Trie.saved`
(`TrieStoreImpl.save` skips saved nodes) change observable behaviour on crafted stores
(TRIE-HASH-04, TRIE-STORE-06).

This layer keeps those caches per Java object. Every method returns its result together with the
updated receiver (the object it mutated), and callers thread the updated objects in the order Java
evaluates them. It is what `trie-diff` runs. `Proofs/Bridge.lean` relates it to the pure layer.

Recursion is bounded by a fuel argument decremented on every call (`OFUEL` per operation, far
above the call depth of any trie: an exhausted budget is reported as an error, never silently).

Aliasing: Java objects are shared between the old and the new trie after `put`; this layer models
each object once, as a value inside the trie the runner holds. A cache written *through the old
trie* into an object that the new trie shares is not seen by the new trie. MODEL.md lists where
Java does this (`referenceSize` of the replaced child in `internalPut`, Trie.java:901/908) and why
it only matters when a later load changes an embedding decision (crafted stores).
-/
namespace RskjTrie.Op

/-- `NodeReference{lazyNode, lazyHash}` with identity-free value semantics. -/
inductive ORef (α : Type) where
  /-- both null -/
  | empty
  /-- `lazyNode = t`, `lazyHash` (cached or read from the parent message) -/
  | node (t : α) (lazyHash : Option Bytes)
  /-- `lazyNode = null`, `lazyHash = h` -/
  | hash (h : Bytes)
  deriving Repr, Inhabited

/-- `co.rsk.trie.Trie` with its caches (Trie.java:77-120). -/
structure OTrie where
  sharedPath : TrieKeySlice
  value : Option Bytes
  left : ORef OTrie
  right : ORef OTrie
  valueLength : Nat
  valueHash : Option Bytes
  childrenSize : Option Nat
  /-- `Trie.hash` cache -/
  hash : Option Bytes
  /-- `Trie.encoded` cache -/
  encoded : Option Bytes
  /-- `Trie.saved` -/
  saved : Bool
  deriving Repr, Inhabited

/-- Per-operation call budget. -/
def OFUEL : Nat := 1000000

def ORef.isEmpty {α} : ORef α → Bool
  | .empty => true
  | _ => false

def ORef.wasLoaded {α} : ORef α → Bool
  | .node _ _ => true
  | _ => false

namespace OTrie

/-- A freshly constructed Java object (no caches, not saved). -/
def mk' (p : TrieKeySlice) (v : Option Bytes) (l r : ORef OTrie) (vl : Nat) (vh : Option Bytes)
    (cs : Option Nat) : OTrie := ⟨p, v, l, r, vl, vh, cs, none, none, false⟩

/-- `new Trie(store)`. -/
def empty : OTrie := mk' [] none .empty .empty 0 none (some 0)

def isTerminal (t : OTrie) : Bool := t.left.isEmpty && t.right.isEmpty
def isEmptyTrieOf (vl : Nat) (l r : ORef OTrie) : Bool := if vl > 0 then false else l.isEmpty && r.isEmpty
def isEmptyTrie (t : OTrie) : Bool := isEmptyTrieOf t.valueLength t.left t.right
def hasLongValue (t : OTrie) : Bool := t.valueLength > 32

end OTrie

/-- `new NodeReference(store, node, null)`: empty for a null or empty node. -/
def ORef.ofNode (t : Option OTrie) : ORef OTrie :=
  match t with
  | none => .empty
  | some t => if t.isEmptyTrie then .empty else .node t none

mutual
/-- Objects created by `Trie.fromMessage` (no caches). -/
def ofPure : Trie → OTrie
  | ⟨p, v, l, r, vl, vh, cs⟩ => ⟨p, v, ofPureRef l, ofPureRef r, vl, vh, cs, none, none, false⟩
def ofPureRef : NodeRef Trie → ORef OTrie
  | .empty => .empty
  | .node t => .node (ofPure t) none
  | .hash h => .hash h
end

/-- `TrieStoreImpl.retrieve(hash)` — TrieStoreImpl.java:152-168: parse, then `markAsSaved()`. -/
def retrieve (env : Env) (hash : Bytes) : Except Err (Option OTrie) :=
  match env.db hash with
  | none => .ok none
  | some m => do
    let t ← Trie.fromMessage env m
    pure (some { ofPure t with saved := true })

/-- `Trie.getValue()` — Trie.java:985-992 (caches the retrieved long value). -/
def OTrie.getValue (env : Env) (t : OTrie) : Except Err (Option Bytes × OTrie) :=
  match t.value with
  | some v => .ok (some v, t)
  | none =>
    if t.valueLength > 0 then
      match t.valueHash with
      | none => .error "unreachable: excluded by checkValueLength"
      | some h =>
        match env.db h with
        | none => .error "IllegalArgumentException: Invalid value length"
        | some v =>
          if v.length ≠ t.valueLength then .error "IllegalArgumentException: Invalid value length"
          else .ok (some v, { t with value := some v })
    else .ok (none, t)

/-- `Trie.getValueHash()` — Trie.java:975-983 (caches). -/
def OTrie.getValueHash (env : Env) (t : OTrie) : Except Err (Option Bytes × OTrie) :=
  match t.valueHash with
  | some h => .ok (some h, t)
  | none =>
    if t.valueLength > 0 then do
      let (v, t) ← t.getValue env
      let h := env.H (v.getD [])
      pure (some h, { t with valueHash := some h })
    else .ok (none, t)

mutual

/-- `NodeReference.getNode()` — NodeReference.java:87-126 with `shouldCache = true`. -/
def ORef.getNode (env : Env) : Nat → ORef OTrie → Except Err (Option OTrie × ORef OTrie)
  | 0, _ => .error "fuel"
  | _ + 1, r =>
    match r with
    | .empty => .ok (none, r)
    | .node t lh => .ok (some t, .node t lh)
    | .hash h => do
      match ← retrieve env h with
      | some t => pure (some t, .node t (some h))
      | none => throw "System.exit(1): Broken database, execution can't continue"

/-- `NodeReference.getHash()` — NodeReference.java:69-80 (caches `lazyHash`). -/
def ORef.getHash (env : Env) : Nat → ORef OTrie → Except Err (Option Bytes × ORef OTrie)
  | 0, _ => .error "fuel"
  | f + 1, r =>
    match r with
    | .empty => .ok (none, r)
    | .hash h => .ok (some h, r)
    | .node t (some h) => .ok (some h, .node t (some h))
    | .node t none => do
      let (h, t) ← OTrie.getHash env f t
      pure (some h, .node t (some h))

/-- `NodeReference.isEmbeddable()` — NodeReference.java:141-148. -/
def ORef.isEmbeddable (env : Env) : Nat → ORef OTrie → Except Err (Bool × ORef OTrie)
  | 0, _ => .error "fuel"
  | f + 1, r =>
    match r with
    | .node t lh => do
      let (e, t) ← OTrie.isEmbeddable env f t
      pure (e, .node t lh)
    | _ => .ok (false, r)

/-- `NodeReference.serializedLength()` — NodeReference.java:156-166. -/
def ORef.serializedLength (env : Env) : Nat → ORef OTrie → Except Err (Nat × ORef OTrie)
  | 0, _ => .error "fuel"
  | f + 1, r =>
    if r.isEmpty then .ok (0, r)
    else do
      let (e, r) ← ORef.isEmbeddable env f r
      if e then
        match r with
        | .node t lh => do
          let (n, t) ← OTrie.getMessageLength env f t
          pure (n + 1, .node t lh)
        | _ => .error "unreachable"
      else pure (32, r)

/-- `NodeReference.serializeInto(ByteBuffer)` — NodeReference.java:168-180. -/
def ORef.serializeInto (env : Env) : Nat → ORef OTrie → Except Err (Bytes × ORef OTrie)
  | 0, _ => .error "fuel"
  | f + 1, r =>
    if r.isEmpty then .ok ([], r)
    else do
      let (e, r) ← ORef.isEmbeddable env f r
      if e then
        match r with
        | .node t lh => do
          let (m, t) ← OTrie.toMessage env f t
          let len ← Uint8.mk m.length
          pure (Uint8.encode len ++ m, .node t lh)
        | _ => .error "unreachable"
      else do
        let (h, r) ← ORef.getHash env f r
        match h with
        | some h => pure (h, r)
        | none => throw "IllegalStateException: The hash should always exists at this point"

/-- `NodeReference.referenceSize()` — NodeReference.java:188-195. -/
def ORef.referenceSize (env : Env) : Nat → ORef OTrie → Except Err (Nat × ORef OTrie)
  | 0, _ => .error "fuel"
  | f + 1, r => do
    let (n, r) ← ORef.getNode env f r
    match n, r with
    | none, r => pure (0, r)
    | some _, .node t lh => do
      let (s, t) ← OTrie.nodeSize env f t
      pure (s, .node t lh)
    | some _, r => pure (0, r)

/-- `nodeSize(Trie)` — NodeReference.java:192-195. -/
def OTrie.nodeSize (env : Env) : Nat → OTrie → Except Err (Nat × OTrie)
  | 0, _ => .error "fuel"
  | f + 1, t => do
    let ext : Nat := if t.hasLongValue then t.valueLength else 0
    let (cs, t) ← OTrie.getChildrenSize env f t
    let (m, t) ← OTrie.getMessageLength env f t
    pure (wrap64 ((cs : Int) + ext + m), t)

/-- `Trie.getChildrenSize()` — Trie.java:1001-1011 (caches). -/
def OTrie.getChildrenSize (env : Env) : Nat → OTrie → Except Err (Nat × OTrie)
  | 0, _ => .error "fuel"
  | f + 1, t =>
    match t.childrenSize with
    | some c => .ok (c, t)
    | none =>
      if t.isTerminal then .ok (0, { t with childrenSize := some 0 })
      else do
        let (a, l) ← ORef.referenceSize env f t.left
        let t := { t with left := l }
        let (b, r) ← ORef.referenceSize env f t.right
        let t := { t with right := r }
        let c := wrap64 ((a : Int) + b)
        pure (c, { t with childrenSize := some c })

/-- `Trie.internalToMessage()` — Trie.java:677-739, in Java's evaluation order: `getChildrenSize`,
the `serializedLength`s sizing the buffer, the `isEmbeddable`s of the flags, the `serializeInto`s,
then the value. Sets `encoded`. -/
def OTrie.internalToMessage (env : Env) : Nat → OTrie → Except Err (Bytes × OTrie)
  | 0, _ => .error "fuel"
  | f + 1, t => do
    let lvalue := t.valueLength
    let hasLongVal := t.hasLongValue
    let (childrenSize, t) ← OTrie.getChildrenSize env f t
    let (_, l) ← ORef.serializedLength env f t.left
    let t := { t with left := l }
    let (_, r) ← ORef.serializedLength env f t.right
    let t := { t with right := r }
    let (leftEmb, l) ← ORef.isEmbeddable env f t.left
    let t := { t with left := l }
    let (rightEmb, r) ← ORef.isEmbeddable env f t.right
    let t := { t with right := r }
    let flags := Trie.mkFlags hasLongVal (SharedPathSerializer.isPresent t.sharedPath)
      (!t.left.isEmpty) (!t.right.isEmpty) leftEmb rightEmb
    let (leftBytes, l) ← ORef.serializeInto env f t.left
    let t := { t with left := l }
    let (rightBytes, r) ← ORef.serializeInto env f t.right
    let t := { t with right := r }
    let csBytes := if !t.isTerminal then VarInt.encode childrenSize else []
    let (valueBytes, t) ← if hasLongVal then do
        let (vh, t) ← t.getValueHash env
        match vh with
        | some vh => pure (vh ++ Uint24.encode lvalue, t)
        | none => throw "NullPointerException"
      else if lvalue > 0 then do
        let (v, t) ← t.getValue env
        match v with
        | some v => pure (v, t)
        | none => throw "NullPointerException"
      else pure ([], t)
    let m := flags :: SharedPathSerializer.serializeInto t.sharedPath ++ leftBytes ++ rightBytes ++
      csBytes ++ valueBytes
    pure (m, { t with encoded := some m })

/-- `Trie.toMessage()` — Trie.java:506-512. -/
def OTrie.toMessage (env : Env) : Nat → OTrie → Except Err (Bytes × OTrie)
  | 0, _ => .error "fuel"
  | f + 1, t =>
    match t.encoded with
    | some m => .ok (m, t)
    | none => OTrie.internalToMessage env f t

/-- `Trie.getMessageLength()` — Trie.java:514-520. -/
def OTrie.getMessageLength (env : Env) : Nat → OTrie → Except Err (Nat × OTrie)
  | 0, _ => .error "fuel"
  | f + 1, t => do
    let (m, t) ← OTrie.toMessage env f t
    pure (m.length, t)

/-- `Trie.isEmbeddable()` — Trie.java:587-589. -/
def OTrie.isEmbeddable (env : Env) : Nat → OTrie → Except Err (Bool × OTrie)
  | 0, _ => .error "fuel"
  | f + 1, t =>
    if t.isTerminal then do
      let (n, t) ← OTrie.getMessageLength env f t
      pure (decide (n ≤ Trie.MAX_EMBEDDED_NODE_SIZE_IN_BYTES), t)
    else .ok (false, t)

/-- `Trie.getHash()` — Trie.java:362-376: the cached hash, `EMPTY_HASH` (not cached) for the
empty trie, else `keccak256(toMessage())` (cached). -/
def OTrie.getHash (env : Env) : Nat → OTrie → Except Err (Bytes × OTrie)
  | 0, _ => .error "fuel"
  | f + 1, t =>
    match t.hash with
    | some h => .ok (h, t)
    | none =>
      if t.isEmptyTrie then .ok (Trie.emptyHash env, t)
      else do
        let (m, t) ← OTrie.toMessage env f t
        let h := env.H m
        pure (h, { t with hash := some h })

end

/-! ## Lookups -/

/-- `Trie.find(TrieKeySlice)` followed by `node.getValue()` (Trie.java:405-416, 654-675), with
`retrieveNode` caching the child in the reference and the value cached in the found node. -/
def OTrie.getRec (env : Env) : Nat → OTrie → TrieKeySlice → Except Err (Option Bytes × OTrie)
  | 0, _, _ => .error "fuel"
  | f + 1, t, key =>
    if t.sharedPath.length > key.length then .ok (none, t)
    else
      let commonPathLength := (key.commonPath t.sharedPath).length
      if commonPathLength < t.sharedPath.length then .ok (none, t)
      else if commonPathLength = key.length then t.getValue env
      else do
        let pos := key.get commonPathLength
        let sub := key.slice (commonPathLength + 1) key.length
        if pos = false then
          let (n, l) ← ORef.getNode env f t.left
          match n, l with
          | some _, .node c lh => do
            let (v, c) ← OTrie.getRec env f c sub
            pure (v, { t with left := .node c lh })
          | _, l => pure (none, { t with left := l })
        else
          let (n, r) ← ORef.getNode env f t.right
          match n, r with
          | some _, .node c lh => do
            let (v, c) ← OTrie.getRec env f c sub
            pure (v, { t with right := .node c lh })
          | _, r => pure (none, { t with right := r })

/-- `Trie.get(byte[] key)`. -/
def OTrie.get (env : Env) (t : OTrie) (key : Bytes) : Except Err (Option Bytes × OTrie) :=
  t.getRec env OFUEL (TrieKeySlice.fromKey key)

/-! ## put / delete -/

/-- Outcome of `put`/`internalPut`: `same` = the (possibly mutated) receiver. -/
inductive OPutRes where
  | same
  | null
  | new (t : OTrie)

def OPutRes.isSame : OPutRes → Bool
  | .same => true
  | _ => false

def OPutRes.toOpt : OPutRes → Option OTrie
  | .new n => some n
  | _ => none

/-- `retrieveNode(pos)`, or `new Trie(store)`; returns the node and the receiver with the cached
reference. `fresh = true` when the node is the new empty trie (not referenced by the receiver). -/
def OTrie.retrieveNodeOrEmpty (env : Env) (f : Nat) (t : OTrie) (pos : Bool) :
    Except Err (OTrie × Bool × OTrie) := do
  if pos = false then
    let (n, l) ← ORef.getNode env f t.left
    match n with
    | some n => pure (n, false, { t with left := l })
    | none => pure (OTrie.empty, true, { t with left := l })
  else
    let (n, r) ← ORef.getNode env f t.right
    match n with
    | some n => pure (n, false, { t with right := r })
    | none => pure (OTrie.empty, true, { t with right := r })

/-- Write a mutated child object back into the reference at `pos` (Java: it *is* the object the
reference holds). -/
def OTrie.writeBack (t : OTrie) (pos : Bool) (c : OTrie) : OTrie :=
  if pos = false then
    match t.left with
    | .node _ lh => { t with left := .node c lh }
    | _ => t
  else
    match t.right with
    | .node _ lh => { t with right := .node c lh }
    | _ => t

mutual

/-- `put(TrieKeySlice, byte[], boolean)` — Trie.java:770-821. Returns the result and the mutated
receiver. -/
def OTrie.putSlice (env : Env) : Nat → OTrie → TrieKeySlice → Option Bytes → Bool →
    Except Err (OPutRes × OTrie)
  | 0, _, _, _, _ => .error "fuel"
  | f + 1, t, key, value, isRecursiveDelete => do
    let value := Trie.normValue value
    let (r, t) ← OTrie.internalPut env f t key value isRecursiveDelete
    let trie ← match r with
      | .null => return (.null, t)
      | .same => pure t
      | .new n => pure n
    if value.isSome then return (r, t)
    if trie.isEmptyTrie then return (.null, t)
    if trie.valueLength > 0 then return (r, t)
    if trie.left.isEmpty == trie.right.isEmpty then return (r, t)
    let (child, childImplicitByte) ← if !trie.left.isEmpty then do
        let (c, _) ← ORef.getNode env f trie.left
        pure (c, false)
      else do
        let (c, _) ← ORef.getNode env f trie.right
        pure (c, true)
    match child with
    | none => throw "System.exit(1): Broken database, execution can't continue"
    | some child =>
      let newSharedPath := trie.sharedPath.rebuildSharedPath childImplicitByte child.sharedPath
      pure (.new (OTrie.mk' newSharedPath child.value child.left child.right child.valueLength
        child.valueHash child.childrenSize), t)

/-- `internalPut` — Trie.java:831-917. -/
def OTrie.internalPut (env : Env) : Nat → OTrie → TrieKeySlice → Option Bytes → Bool →
    Except Err (OPutRes × OTrie)
  | 0, _, _, _, _ => .error "fuel"
  | f + 1, t, key, value, isRecursiveDelete => do
    let commonPath := key.commonPath t.sharedPath
    if commonPath.length < t.sharedPath.length then
      if value.isNone then return (.same, t)
      let s ← OTrie.split env f t commonPath
      let (r, s) ← OTrie.putSlice env f s key value isRecursiveDelete
      match r with
      | .same => pure (.new s, t)
      | r => pure (r, t)
    else if t.sharedPath.length ≥ key.length then
      let dl ← Trie.getDataLength value
      let (unchanged, t) ← if t.valueLength = dl then do
          let (x, t) ← t.getValue env
          pure (decide (x = value), t)
        else pure (false, t)
      if unchanged then return (.same, t)
      if isRecursiveDelete then
        return (.new (OTrie.mk' t.sharedPath none .empty .empty 0 none (some 0)), t)
      if OTrie.isEmptyTrieOf dl t.left t.right then return (.null, t)
      pure (.new (OTrie.mk' t.sharedPath value t.left t.right dl none t.childrenSize), t)
    else if t.isEmptyTrie then do
      let dl ← Trie.getDataLength value
      pure (.new (OTrie.mk' key value .empty .empty dl none (some 0)), t)
    else
      let pos := key.get t.sharedPath.length
      let (node, fresh, t) ← t.retrieveNodeOrEmpty env f pos
      let subKey := key.slice (t.sharedPath.length + 1) key.length
      let (newNode, node) ← OTrie.putSlice env f node subKey value isRecursiveDelete
      let t := if fresh then t else t.writeBack pos node
      if newNode.isSame then return (.same, t)
      let newRef := ORef.ofNode newNode.toOpt
      let (newLeft, newRight, childrenSize, t) ← if pos = false then do
          match t.childrenSize with
          | some c => do
            let (a, l) ← ORef.referenceSize env f t.left
            let t := { t with left := l }
            let (b, newRef) ← ORef.referenceSize env f newRef
            pure (newRef, t.right, some (wrap64 ((c : Int) - a + b)), t)
          | none => pure (newRef, t.right, none, t)
        else do
          match t.childrenSize with
          | some c => do
            let (a, r) ← ORef.referenceSize env f t.right
            let t := { t with right := r }
            let (b, newRef) ← ORef.referenceSize env f newRef
            pure (t.left, newRef, some (wrap64 ((c : Int) - a + b)), t)
          | none => pure (t.left, newRef, none, t)
      if OTrie.isEmptyTrieOf t.valueLength newLeft newRight then return (.null, t)
      pure (.new (OTrie.mk' t.sharedPath t.value newLeft newRight t.valueLength t.valueHash
        childrenSize), t)

/-- `split(TrieKeySlice)` — Trie.java:919-940. -/
def OTrie.split (env : Env) : Nat → OTrie → TrieKeySlice → Except Err OTrie
  | 0, _, _ => .error "fuel"
  | f + 1, t, commonPath => do
    let commonPathLength := commonPath.length
    let newChildSharedPath := t.sharedPath.slice (commonPathLength + 1) t.sharedPath.length
    let newChildTrie := OTrie.mk' newChildSharedPath t.value t.left t.right t.valueLength
      t.valueHash t.childrenSize
    let newChildReference := ORef.ofNode (some newChildTrie)
    let pos := t.sharedPath.get commonPathLength
    let (cs, newChildReference) ← ORef.referenceSize env f newChildReference
    let (newLeft, newRight) :=
      if pos = false then (newChildReference, ORef.empty) else (ORef.empty, newChildReference)
    pure (OTrie.mk' commonPath none newLeft newRight 0 none (some cs))

end

/-- `Trie.put(byte[] key, byte[] value)` — Trie.java:438-443. -/
def OTrie.put (env : Env) (t : OTrie) (key : Bytes) (value : Option Bytes) : Except Err OTrie := do
  let (r, t) ← t.putSlice env OFUEL (TrieKeySlice.fromKey key) value false
  match r with
  | .same => pure t
  | .null => pure OTrie.empty
  | .new n => pure n

/-- `Trie.delete(byte[] key)`. -/
def OTrie.delete (env : Env) (t : OTrie) (key : Bytes) : Except Err OTrie := t.put env key none

/-- `Trie.deleteRecursive(byte[] key)`. -/
def OTrie.deleteRecursive (env : Env) (t : OTrie) (key : Bytes) : Except Err OTrie := do
  let (r, t) ← t.putSlice env OFUEL (TrieKeySlice.fromKey key) none true
  match r with
  | .same => pure t
  | .null => pure OTrie.empty
  | .new n => pure n

/-! ## Save -/

mutual
/-- `TrieStoreImpl.save(Trie, boolean isRootNode, …)` — TrieStoreImpl.java:92-145 with the `saved`
flag: a saved node is skipped (:93-95); an embedded non-root node is not marked saved. Reads
during the save go through `view db` (the trie's own store). -/
def saveRec (view : DB → Env) : Nat → DB → OTrie → Bool → Except Err (DB × OTrie)
  | 0, _, _, _ => .error "fuel"
  | f + 1, db, t, isRootNode => do
    if t.saved then return (db, t)
    let (trieKeyBytes, t) ← OTrie.getHash (view db) f t
    let (db, l) ← saveRef view f db t.left
    let t := { t with left := l }
    let (db, r) ← saveRef view f db t.right
    let t := { t with right := r }
    let (db, t) ← if t.hasLongValue then do
        let (vh, t) ← t.getValueHash (view db)
        let (v, t) ← t.getValue (view db)
        match vh, v with
        | some vh, some v => pure (db.put vh v, t)
        | _, _ => throw "NullPointerException"
      else pure (db, t)
    let (e, t) ← OTrie.isEmbeddable (view db) f t
    if e && !isRootNode then return (db, t)
    let (m, t) ← OTrie.toMessage (view db) f t
    pure (db.put trieKeyBytes m, { t with saved := true })
/-- TrieStoreImpl.java:106-118: only loaded references are followed. -/
def saveRef (view : DB → Env) : Nat → DB → ORef OTrie → Except Err (DB × ORef OTrie)
  | 0, _, _ => .error "fuel"
  | f + 1, db, r =>
    match r with
    | .node c lh => do
      let (db, c) ← saveRec view f db c false
      pure (db, .node c lh)
    | r => pure (db, r)
end

/-- `TrieStoreImpl.save(Trie)` over a single `HashMapDB`. -/
def save (H : Bytes → Bytes) (db : DB) (t : OTrie) : Except Err (DB × OTrie) :=
  saveRec (fun d => ⟨H, d⟩) OFUEL db t true

/-- `getHash()` with the per-operation budget. -/
def OTrie.hashOf (env : Env) (t : OTrie) : Except Err (Bytes × OTrie) := OTrie.getHash env OFUEL t

/-- `toMessage()` with the per-operation budget. -/
def OTrie.messageOf (env : Env) (t : OTrie) : Except Err (Bytes × OTrie) := OTrie.toMessage env OFUEL t

end RskjTrie.Op
