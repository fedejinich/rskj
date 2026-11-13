import RskjTrie.Ops
/-!
# `co.rsk.trie.TrieStore` / `TrieStoreImpl` over a byte-keyed store (`HashMapDB`)

The key-value data source is a function `Bytes → Option Bytes` (a finite map: only finitely many
`put`s are ever applied to the empty map). `retrieve`/`retrieveValue` are in
`Serialization.lean` (they are needed by `NodeReference.getNode`).

`Trie.saved` / `wasSaved()` / `markAsSaved()` are not modelled: `save` skips a node already marked
saved; such a node (and the long values and non-embedded descendants it needs) is already in the
store under the same keys with the same contents, so re-writing it is a no-op on the map
(MODEL.md, "saved flag").
-/
namespace RskjTrie

/-- A byte-keyed key-value store (`KeyValueDataSource` contents). -/
abbrev DB := Bytes → Option Bytes

/-- The empty store (`new HashMapDB()`). -/
def DB.empty : DB := fun _ => none

/-- `HashMapDB.put(key, value)` (non-null value). -/
def DB.put (db : DB) (k v : Bytes) : DB := fun k' => if k' = k then some v else db k'

namespace TrieStoreImpl

/-- The end of `save(Trie, boolean isRootNode, …)` — TrieStoreImpl.java:120-143: store a long
value under its hash; then, unless the node is embeddable and not the root, store the node's
message under `trieKeyBytes` (its hash, computed at the start of `save`). Reads during the save
see the store as updated so far. -/
def saveTail (H : Bytes → Bytes) (db : DB) (t : Trie) (isRootNode : Bool) (trieKeyBytes : Bytes) :
    Except Err DB := do
  let db ← if t.hasLongValue then do
      let vh ← t.getValueHash ⟨H, db⟩
      let v ← t.getValue ⟨H, db⟩
      match vh, v with
      | some vh, some v => pure (db.put vh v)
      | _, _ => throw "NullPointerException"
    else pure db
  if (← t.isEmbeddable ⟨H, db⟩ FUEL) && !isRootNode then return db
  let m ← t.toMessage ⟨H, db⟩
  pure (db.put trieKeyBytes m)

mutual
/-- `TrieStoreImpl.save(Trie trie, boolean isRootNode, int level, TraceInfo)` —
TrieStoreImpl.java:92-145: hash, then the loaded children (left, right), then `saveTail`. -/
def saveRec (H : Bytes → Bytes) (db : DB) : Trie → Bool → Except Err DB
  | t@⟨_, _, l, r, _, _, _⟩, isRootNode => do
    let trieKeyBytes ← t.getHash ⟨H, db⟩
    let db ← saveRef H db l
    let db ← saveRef H db r
    saveTail H db t isRootNode trieKeyBytes

/-- TrieStoreImpl.java:106-118: `if (ref.wasLoaded()) ref.getNode().ifPresent(n -> save(n, false, …))`
(only resident references are saved). -/
def saveRef (H : Bytes → Bytes) (db : DB) : NodeRef Trie → Except Err DB
  | .node c => saveRec H db c false
  | _ => pure db
end

/-- `TrieStoreImpl.save(Trie)` — TrieStoreImpl.java:56-87 (tracing omitted). -/
def save (H : Bytes → Bytes) (db : DB) (t : Trie) : Except Err DB := saveRec H db t true

end TrieStoreImpl
end RskjTrie
