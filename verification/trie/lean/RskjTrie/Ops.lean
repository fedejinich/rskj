import RskjTrie.Serialization
/-!
# Trie operations: `find`, `get`, `put`, `internalPut`, `split`, `delete`, `deleteRecursive`

Java's `put` family returns a `Trie` that may be `null` or the receiver itself (`this`), and
`internalPut` tests the child's result with *reference* equality (`newNode == node`,
Trie.java:887). `PutRes` records exactly these three outcomes, so the model takes the same branches.
-/
namespace RskjTrie

/-- Result of `Trie.put(TrieKeySlice, byte[], boolean)` / `internalPut`: `same` = the receiver
object (`this`), `null` = Java `null`, `new t` = a freshly constructed node `t`. -/
inductive PutRes where
  | same
  | null
  | new (t : Trie)
  deriving Repr, Inhabited

namespace Trie
open TrieKeySlice

/-- `Trie.retrieveNode(byte implicitByte)` — Trie.java:741-747:
`getNodeReference(b).getNode().orElse(null)`. -/
def retrieveNode (env : Env) (t : Trie) (implicitByte : Bool) : Except Err (Option Trie) :=
  (t.getNodeReference implicitByte).getNode env

theorem slice_length_lt (key : TrieKeySlice) (c : Nat) (h : c < key.length) :
    (key.slice (c + 1) key.length).length < key.length := by
  simp [slice] at *; omega

/-- `Trie.find(TrieKeySlice)` — Trie.java:654-675. -/
def findSlice (env : Env) (t : Trie) (key : TrieKeySlice) : Except Err (Option Trie) :=
  if t.sharedPath.length > key.length then .ok none
  else
    let commonPathLength := (key.commonPath t.sharedPath).length
    if commonPathLength < t.sharedPath.length then .ok none
    else if _h : commonPathLength = key.length then .ok (some t)
    else do
      match ← t.retrieveNode env (key.get commonPathLength) with
      | none => pure none
      | some node => node.findSlice env (key.slice (commonPathLength + 1) key.length)
termination_by key.length
decreasing_by
  apply slice_length_lt
  have := lcp_length_le_left key t.sharedPath
  rw [← commonPath_eq_lcp] at this
  omega

/-- `Trie.find(byte[] key)` — Trie.java:650-652. -/
def find (env : Env) (t : Trie) (key : Bytes) : Except Err (Option Trie) :=
  t.findSlice env (TrieKeySlice.fromKey key)

/-- `Trie.get(byte[] key)` — Trie.java:405-416: `find(key)` then `node.getValue()`. -/
def get (env : Env) (t : Trie) (key : Bytes) : Except Err (Option Bytes) := do
  match ← t.find env key with
  | none => pure none
  | some node => node.getValue env

/-- `Trie.split(TrieKeySlice commonPath)` — Trie.java:919-940. Returns the new node together with
the (trivial) fact that its shared path is `commonPath`, used for termination of `put`. -/
def split (env : Env) (t : Trie) (commonPath : TrieKeySlice) :
    Except Err {s : Trie // s.sharedPath = commonPath} := do
  let commonPathLength := commonPath.length
  let newChildSharedPath := t.sharedPath.slice (commonPathLength + 1) t.sharedPath.length
  let newChildTrie : Trie := ⟨newChildSharedPath, t.value, t.left, t.right, t.valueLength,
    t.valueHash, t.childrenSize⟩
  let newChildReference := NodeRef.ofNode (some newChildTrie)
  -- this bit will be implicit and not present in a shared path
  let pos := t.sharedPath.get commonPathLength
  let childrenSize ← newChildReference.referenceSize env FUEL
  let (newLeft, newRight) :=
    if pos = false then (newChildReference, NodeRef.empty) else (NodeRef.empty, newChildReference)
  pure ⟨⟨commonPath, none, newLeft, newRight, 0, none, some childrenSize⟩, rfl⟩

/-- `put(TrieKeySlice, byte[], boolean)`'s normalisation — Trie.java:774-776: an empty array
becomes `null`. -/
def normValue (value : Option Bytes) : Option Bytes :=
  match value with
  | some v => if v.length = 0 then none else some v
  | none => none

/-- Trie.java:878-881: `retrieveNode(pos)`, or `new Trie(store)` if there is no child. -/
def retrieveNodeOrEmpty (env : Env) (t : Trie) (pos : Bool) : Except Err Trie := do
  match ← t.retrieveNode env pos with
  | some n => pure n
  | none => pure Trie.empty

/-- Trie.java:891-910: replace the child at `pos` by `newNodeReference` and update a non-null
`childrenSize` incrementally (`childrenSize - old.referenceSize() + new.referenceSize()`, long
arithmetic). Returns `(newLeft, newRight, childrenSize)`. -/
def replaceChild (env : Env) (t : Trie) (pos : Bool) (newNodeReference : NodeRef Trie) :
    Except Err (NodeRef Trie × NodeRef Trie × Option Nat) := do
  let childrenSize := t.childrenSize
  if pos = false then
    let cs ← match childrenSize with
      | some c => do
        let a ← t.left.referenceSize env FUEL
        let b ← newNodeReference.referenceSize env FUEL
        pure (some (wrap64 ((c : Int) - a + b)))
      | none => pure none
    pure (newNodeReference, t.right, cs)
  else
    let cs ← match childrenSize with
      | some c => do
        let a ← t.right.referenceSize env FUEL
        let b ← newNodeReference.referenceSize env FUEL
        pure (some (wrap64 ((c : Int) - a + b)))
      | none => pure none
    pure (t.left, newNodeReference, cs)

/-- `newNode == node` in Trie.java:887: the recursive `put` returned its receiver. -/
def _root_.RskjTrie.PutRes.isSame : PutRes → Bool
  | .same => true
  | _ => false

/-- The node a non-`same` result denotes (`null` → `none`). -/
def _root_.RskjTrie.PutRes.toOpt : PutRes → Option Trie
  | .new n => some n
  | _ => none

/-- Termination measure helper: `1` iff `internalPut` takes the `split` branch. -/
def splitRank (t : Trie) (key : TrieKeySlice) : Nat :=
  if (key.commonPath t.sharedPath).length < t.sharedPath.length then 1 else 0

theorem splitRank_split (key cp : TrieKeySlice) (s : Trie) (h : s.sharedPath = key.commonPath cp) :
    splitRank s key = 0 := by
  simp [splitRank, h, commonPath_idem]

mutual

/-- `Trie.put(TrieKeySlice key, byte[] value, boolean isRecursiveDelete)` — Trie.java:770-821:
normalise the value, `internalPut`, then (for deletes only) coalesce a value-less node with a
single child into that child. -/
def putSlice (env : Env) (t : Trie) (key : TrieKeySlice) (value : Option Bytes)
    (isRecursiveDelete : Bool) : Except Err PutRes := do
  let value := normValue value
  let r ← t.internalPut env key value isRecursiveDelete
  -- it's null or it is not a delete operation
  let trie ← match r with
    | .null => return .null
    | .same => pure t
    | .new n => pure n
  if value.isSome then return r
  if trie.isEmptyTrie then return .null
  -- only coalesce if node has only one child and no value
  if trie.valueLength > 0 then return r
  -- both left and right exist (or not) at the same time
  if trie.left.isEmpty == trie.right.isEmpty then return r
  let (child, childImplicitByte) ← if !trie.left.isEmpty then do
      pure ((← trie.left.getNode env), false)
    else do
      pure ((← trie.right.getNode env), true)
  match child with
  | none => throw "System.exit(1): Broken database, execution can't continue"
  | some child =>
    let newSharedPath := trie.sharedPath.rebuildSharedPath childImplicitByte child.sharedPath
    pure (.new ⟨newSharedPath, child.value, child.left, child.right, child.valueLength,
      child.valueHash, child.childrenSize⟩)
termination_by (key.length, splitRank t key, 1)
decreasing_by apply Prod.Lex.right; apply Prod.Lex.right; omega

/-- `Trie.internalPut(TrieKeySlice, byte[], boolean)` — Trie.java:831-917. -/
def internalPut (env : Env) (t : Trie) (key : TrieKeySlice) (value : Option Bytes)
    (isRecursiveDelete : Bool) : Except Err PutRes := do
  let commonPath := key.commonPath t.sharedPath
  if _hsplit : commonPath.length < t.sharedPath.length then
    -- when we are removing a key we know splitting is not necessary
    if value.isNone then return .same
    let ⟨s, _hs⟩ ← t.split env commonPath
    -- `this.split(commonPath).put(...)`: a `this` result of that call is the split node
    match ← s.putSlice env key value isRecursiveDelete with
    | .same => pure (.new s)
    | r => pure r
  else if t.sharedPath.length ≥ key.length then
    let dl ← getDataLength value
    -- `this.valueLength.equals(getDataLength(value)) && Arrays.equals(this.getValue(), value)`
    let unchanged ← if t.valueLength = dl then (fun x => decide (x = value)) <$> t.getValue env
      else pure false
    if unchanged then return .same
    if isRecursiveDelete then
      return .new ⟨t.sharedPath, none, .empty, .empty, 0, none, some 0⟩
    if isEmptyTrieOf dl t.left t.right then return .null
    pure (.new ⟨t.sharedPath, value, t.left, t.right, dl, none, t.childrenSize⟩)
  else if t.isEmptyTrie then
    .new <$> leaf key value
  else
    -- this bit will be implicit and not present in a shared path
    let pos := key.get t.sharedPath.length
    let node ← t.retrieveNodeOrEmpty env pos
    let subKey := key.slice (t.sharedPath.length + 1) key.length
    let newNode ← node.putSlice env subKey value isRecursiveDelete
    -- reference equality
    if newNode.isSame then return .same
    let newNodeReference := NodeRef.ofNode newNode.toOpt
    let (newLeft, newRight, childrenSize) ← t.replaceChild env pos newNodeReference
    if isEmptyTrieOf t.valueLength newLeft newRight then return .null
    pure (.new ⟨t.sharedPath, t.value, newLeft, newRight, t.valueLength, t.valueHash, childrenSize⟩)
termination_by (key.length, splitRank t key, 0)
decreasing_by
  · apply Prod.Lex.right; apply Prod.Lex.left
    rw [splitRank_split key t.sharedPath s _hs]
    have : splitRank t key = 1 := by unfold splitRank; split <;> simp_all
    omega
  · apply Prod.Lex.left
    apply slice_length_lt
    omega

end

/-- `Trie.put(byte[] key, byte[] value)` — Trie.java:438-443 (`null` becomes `new Trie(store)`). -/
def put (env : Env) (t : Trie) (key : Bytes) (value : Option Bytes) : Except Err Trie := do
  match ← t.putSlice env (TrieKeySlice.fromKey key) value false with
  | .same => pure t
  | .null => pure Trie.empty
  | .new n => pure n

/-- `Trie.delete(byte[] key)` — Trie.java:470-472: `put(key, null)`. -/
def delete (env : Env) (t : Trie) (key : Bytes) : Except Err Trie := t.put env key none

/-- `Trie.deleteRecursive(byte[] key)` — Trie.java:475-480. -/
def deleteRecursive (env : Env) (t : Trie) (key : Bytes) : Except Err Trie := do
  match ← t.putSlice env (TrieKeySlice.fromKey key) none true with
  | .same => pure t
  | .null => pure Trie.empty
  | .new n => pure n

end Trie
end RskjTrie
