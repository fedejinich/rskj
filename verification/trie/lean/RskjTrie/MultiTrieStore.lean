import RskjTrie.Operational
/-!
# `co.rsk.trie.MultiTrieStore` (epoch stores)

Modelled on the operational layer because `collect` depends on the `saved` flag: the root it
retrieves is marked saved (`retrieve`, MultiTrieStore.java:94) and `TrieStoreImpl.save` returns at
once for saved nodes (TrieStoreImpl.java:93-95).

Each epoch is a `TrieStoreImpl` over its own `HashMapDB`, i.e. a `DB`; `epochs` is newest first
(index 0 is the current store, MultiTrieStore.java:152-154). The `OnEpochDispose` callback and
`HashMapDB.close()` of the disposed epoch are not modelled (the epoch leaves the list).
-/
namespace RskjTrie.Op

structure MultiTrieStore where
  currentEpoch : Nat
  epochs : List DB

namespace MultiTrieStore

/-- `new MultiTrieStore(currentEpoch, liveEpochs, factory, disposer)` — MultiTrieStore.java:42-51
(the factory makes empty `TrieStoreImpl(HashMapDB)`s). -/
def new (currentEpoch liveEpochs : Nat) : MultiTrieStore :=
  ⟨max currentEpoch liveEpochs, List.replicate liveEpochs DB.empty⟩

/-- `retrieveValue(hash)` — MultiTrieStore.java:113-122: newest epoch first. -/
def retrieveValue (ms : MultiTrieStore) (h : Bytes) : Option Bytes := ms.epochs.findSome? (· h)

/-- The store a trie retrieved through `ms` reads from (`Trie.fromMessage(message, this)`). -/
def env (H : Bytes → Bytes) (ms : MultiTrieStore) : Env := ⟨H, ms.retrieveValue⟩

/-- `retrieve(rootHash)` — MultiTrieStore.java:87-98: the message from the newest epoch that has
it, parsed against the multi store, marked saved. -/
def retrieve (H : Bytes → Bytes) (ms : MultiTrieStore) (h : Bytes) : Except Err (Option OTrie) :=
  Op.retrieve (ms.env H) h

/-- `TrieStoreImpl.save` on epoch `i` of `ms`, reading through the multi store as it is updated. -/
def saveInto (H : Bytes → Bytes) (ms : MultiTrieStore) (i : Nat) (t : OTrie) :
    Except Err (MultiTrieStore × OTrie) := do
  let some db := ms.epochs[i]? | throw "IndexOutOfBoundsException"
  let view : DB → Env := fun d => env H { ms with epochs := ms.epochs.set i d }
  let (db', t) ← saveRec view OFUEL db t true
  pure ({ ms with epochs := ms.epochs.set i db' }, t)

/-- `save(trie)` — MultiTrieStore.java:59-62: `getCurrentStore().save(trie)`. -/
def save (H : Bytes → Bytes) (ms : MultiTrieStore) (t : OTrie) : Except Err (MultiTrieStore × OTrie) :=
  saveInto H ms 0 t

/-- `saveValue(value)` — MultiTrieStore.java:69-72 → `TrieStoreImpl.saveValue`
(TrieStoreImpl.java:221-225): `store.put(keccak256(value), value)` in the current epoch. -/
def saveValue (H : Bytes → Bytes) (ms : MultiTrieStore) (v : Bytes) : Except Err MultiTrieStore :=
  match ms.epochs with
  | db :: rest => .ok { ms with epochs := db.put (H v) v :: rest }
  | [] => .error "IndexOutOfBoundsException"

/-- `collect(oldestTrieHashToKeep)` — MultiTrieStore.java:137-150: retrieve the root (throws if
missing), `save` it into the second-oldest epoch, drop the oldest epoch, rotate, put a fresh store
in front, `currentEpoch++`. -/
def collect (H : Bytes → Bytes) (ms : MultiTrieStore) (h : Bytes) : Except Err MultiTrieStore := do
  let some oldest ← retrieve H ms h
    | throw "IllegalArgumentException: The trie with root is missing from every epoch"
  let n := ms.epochs.length
  if n < 2 then throw "IndexOutOfBoundsException"
  let (ms, _) ← saveInto H ms (n - 2) oldest
  pure ⟨ms.currentEpoch + 1, DB.empty :: ms.epochs.dropLast⟩

end MultiTrieStore
end RskjTrie.Op
