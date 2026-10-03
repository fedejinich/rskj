import RskjTrie.Obligations.Hash
import RskjTrie.Obligations.Emb
import RskjTrie.MultiTrieStore
/-! # Obligations TRIE-STORE-* (TrieStoreImpl, MultiTrieStore) -/
namespace RskjTrie.Obligations
open RskjTrie Trie TrieKeySlice

set_option linter.unusedSimpArgs false

/-- TRIE-STORE-01: for a non-empty reachable trie (keys shorter than `2^28` bytes) and `H`
yielding 32 bytes, injective on the trie's messages and values: after `save`, `retrieve(getHash())`
yields a node with the same hash and the same `get` results (reading through the new store). -/
theorem trie_store_01 (H : Bytes → Bytes) (hH : ∀ x, (H x).length = 32) (db : DB) (t : Trie)
    (ht : Reachable ⟨H, db⟩ t) (hk : ∀ k, t.get ⟨H, db⟩ k ≠ .ok none → k.length < 2 ^ 28)
    (hne : t.isEmptyTrie = false) (hinj : InjOn H (t.vals H)) :
    ∃ db' t', TrieStoreImpl.save H db t = .ok db' ∧ t.getHash ⟨H, db⟩ = .ok (t.hashS H) ∧
      TrieStoreImpl.retrieve ⟨H, db'⟩ (t.hashS H) = .ok (some t') ∧
      (∀ key, t'.get ⟨H, db'⟩ key = t.get ⟨H, db⟩ key) ∧ t'.getHash ⟨H, db'⟩ = t.getHash ⟨H, db⟩ := by
  obtain ⟨db', h1, h2, h3, h4, h5⟩ := Trie.save_retrieve H hH db t ht.WF
    (pathsOK_of_reachable ⟨H, db⟩ t ht hk) hne hinj
  exact ⟨db', _, h1, h2, h3, h4, h5⟩

/-- TRIE-STORE-01 for the empty trie: `save` writes `H(80) ↦ 40`, and `retrieve(H(80))` yields an
empty node (every `get` is `null`, hash `H(80)`). -/
theorem trie_store_01_empty (H : Bytes → Bytes) (db : DB) :
    ∃ db' t', TrieStoreImpl.save H db Trie.empty = .ok db' ∧ db' (H [0x80]) = some [0x40] ∧
      TrieStoreImpl.retrieve ⟨H, db'⟩ (H [0x80]) = .ok (some t') ∧
      (∀ key, t'.get ⟨H, db'⟩ key = .ok none) ∧ t'.getHash ⟨H, db'⟩ = .ok (H [0x80]) := by
  have hw := Trie.save_writes H db Trie.empty (Trie.WF_empty H).1 (Trie.WF_empty H).2.1
  have hdb : applyWrites db (Trie.empty.saveWrites H true) = db.put (H [0x80]) [0x40] := by
    simp [Trie.saveWrites, NodeRef.saveWrites, Trie.empty, applyWrites, Trie.hashS, isEmptyTrie, isEmptyTrieOf,
      NodeRef.isEmpty, Trie.encS, Trie.mkFlags, SharedPathSerializer.isPresent, SharedPathSerializer.serializeInto]
    rfl
  rw [hdb] at hw
  have hput : (db.put (H [0x80]) [0x40]) (H [0x80]) = some [0x40] := by simp [DB.put]
  let e : Trie := ⟨[], none, .empty, .empty, 0, none, some 0⟩
  have hr : TrieStoreImpl.retrieve ⟨H, db.put (H [0x80]) [0x40]⟩ (H [0x80]) = .ok (some e) := by
    simp only [TrieStoreImpl.retrieve, hput]; rfl
  refine ⟨_, e, hw, hput, hr, fun key => ?_, Trie.getHash_empty _ e rfl⟩
  rw [Trie.get_eq_contents _ e (by simp [e, Trie.Resident, NodeRef.Resident, ValueOK])]
  simp [e, Trie.contents_leaf]

/-- TRIE-STORE-02 (Java): `save` writes exactly `saveWrites` (TRIE-STORE-03); every entry is
content-addressed (`h = H(m)`) for a non-empty root; for the empty root the single entry is
`H(80) ↦ 40`. After `save`, every child referenced by hash in a saved node resolves to that child's
message and every long value to itself (`Trie.Saved`), for `H` injective on the trie's messages. -/
theorem trie_store_02 (H : Bytes → Bytes) :
    (∀ t : Trie, t.Resident → t.isEmptyTrie = false → ∀ kv ∈ t.saveWrites H true, kv.1 = H kv.2) ∧
    Trie.empty.saveWrites H true = [(H [0x80], [0x40])] ∧
    (∀ (db : DB) (t : Trie), t.Resident → t.CacheOK H → t.isEmptyTrie = false → InjOn H (t.vals H) →
      ∃ db', TrieStoreImpl.save H db t = .ok db' ∧ t.Saved H db' ∧ db' (t.hashS H) = some (t.encS H).1) := by
  refine ⟨fun t hr hne => Trie.saveWrites_content_addressed H t true hr hne, ?_, fun db t hr hc hne hinj => ?_⟩
  · simp [Trie.saveWrites, NodeRef.saveWrites, Trie.empty, Trie.hashS, isEmptyTrie, isEmptyTrieOf,
      NodeRef.isEmpty, Trie.encS, NodeRef.encS, Trie.mkFlags, SharedPathSerializer.isPresent,
      SharedPathSerializer.serializeInto]
  · obtain ⟨db', h1, _, hs, hw⟩ := Trie.saveRec_spec H (t.vals H) hinj t db true hr hc hne (fun x hx => hx)
    exact ⟨db', h1, hs, by rw [Trie.hashS_nonempty H t hne]; exact hw (Or.inl rfl)⟩

/-- TRIE-STORE-02 does not hold for the empty root: with Keccak-256, `save(new Trie())` stores
`40` under `keccak(80) = 56e81f…b421 ≠ keccak(40)`. -/
theorem trie_store_02_rskip_counterexample (db : DB) :
    ∃ db', TrieStoreImpl.save Keccak.keccak256 db Trie.empty = .ok db' ∧ db' keccak80 = some [0x40] ∧
      keccak80 ≠ Keccak.keccak256 [0x40] := by
  obtain ⟨db', _, h1, h2, _⟩ := trie_store_01_empty Keccak.keccak256 db
  refine ⟨db', h1, by rw [← keccak_80]; exact h2, by rw [keccak_40]; decide⟩

/-- TRIE-STORE-03: `save` writes, for the root (always, even if embeddable) and every node reachable
through loaded references that is not embeddable, `hash ↦ message`, plus `H(v) ↦ v` for every long
value; an embeddable non-root node gets no entry of its own. -/
theorem trie_store_03 (H : Bytes → Bytes) (db : DB) (t : Trie) (hres : t.Resident) (hc : t.CacheOK H) :
    TrieStoreImpl.save H db t = .ok (applyWrites db (t.saveWrites H true)) ∧
    (t.hashS H, (t.encS H).1) ∈ t.saveWrites H true ∧
    (∀ c : Trie, (c.isTerminal && decide ((c.encS H).1.length ≤ 44)) = true →
      c.saveWrites H false = NodeRef.saveWrites H c.left ++ NodeRef.saveWrites H c.right ++
        (if c.valueLength > 32 then [(H (c.value.getD []), c.value.getD [])] else [])) := by
  refine ⟨Trie.save_writes H db t hres hc, ?_, fun c hemb => ?_⟩
  · obtain ⟨p, v, l, r, vl, vh, cs⟩ := t; simp [Trie.saveWrites]
  · obtain ⟨p, v, l, r, vl, vh, cs⟩ := c
    simp only [Trie.saveWrites, hemb, Bool.not_false, Bool.and_true, ↓reduceIte, List.append_nil]

/-- TRIE-STORE-04: after `save` (non-empty `t`, `H` injective on its messages and values), every
node with a long value has its value stored under `H(value)` (`Trie.Saved`), and its
`getValueHash()` is `H(value)`. -/
theorem trie_store_04 (H : Bytes → Bytes) (db : DB) (t : Trie) (hres : t.Resident) (hc : t.CacheOK H)
    (hne : t.isEmptyTrie = false) (hinj : InjOn H (t.vals H)) :
    ∃ db', TrieStoreImpl.save H db t = .ok db' ∧ t.Saved H db' ∧
      (t.valueLength > 32 → db' (H (t.value.getD [])) = some (t.value.getD []) ∧
        t.getValueHash ⟨H, db'⟩ = .ok (some (H (t.value.getD [])))) := by
  obtain ⟨db', h1, _, hs, _⟩ := Trie.saveRec_spec H (t.vals H) hinj t db true hres hc hne (fun x hx => hx)
  refine ⟨db', h1, hs, fun hl => ⟨?_, ?_⟩⟩
  · obtain ⟨p, v, l, r, vl, vh, cs⟩ := t; exact hs.1 hl
  · obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
    obtain ⟨x, rfl, _, _, _⟩ : ∃ x, v = some x ∧ x.length = vl ∧ 0 < vl ∧ vl ≤ Uint24.MAX := by
      rcases hres.1 with ⟨_, h⟩ | h
      · simp only at hl; omega
      · exact h
    exact trie_val_03 ⟨H, db'⟩ _ hc hres x rfl

/-! ### MultiTrieStore -/

section MTS
open Op Op.MultiTrieStore

theorem set_self {α} (l : List α) (i : Nat) (a : α) (h : l[i]? = some a) : l.set i a = l := by
  obtain ⟨hi, rfl⟩ := List.getElem?_eq_some_iff.mp h
  exact List.set_getElem_self hi

/-- TRIE-STORE-05: `save` / `saveValue` change only the current epoch (index 0), and
`retrieveValue` (hence `retrieve`, which parses `retrieveValue`'s message) returns the entry of the
newest epoch that has it. -/
theorem trie_store_05 (H : Bytes → Bytes) :
    (∀ ms t ms' t', MultiTrieStore.save H ms t = .ok (ms', t') →
      ms'.currentEpoch = ms.currentEpoch ∧ ms'.epochs.length = ms.epochs.length ∧
      ∀ i, i ≠ 0 → ms'.epochs[i]? = ms.epochs[i]?) ∧
    (∀ ms v ms', MultiTrieStore.saveValue H ms v = .ok ms' →
      ms'.currentEpoch = ms.currentEpoch ∧ ms'.epochs.length = ms.epochs.length ∧
      ∀ i, i ≠ 0 → ms'.epochs[i]? = ms.epochs[i]?) ∧
    (∀ c (db : DB) rest h v, db h = some v → MultiTrieStore.retrieveValue ⟨c, db :: rest⟩ h = some v) ∧
    (∀ c (db : DB) rest h, db h = none →
      MultiTrieStore.retrieveValue ⟨c, db :: rest⟩ h = MultiTrieStore.retrieveValue ⟨c, rest⟩ h) ∧
    (∀ ms h, (MultiTrieStore.env H ms).db h = ms.retrieveValue h) := by
  refine ⟨fun ms t ms' t' e => ?_, fun ms v ms' e => ?_, fun c db rest h v hv => ?_,
    fun c db rest h hv => ?_, fun _ _ => rfl⟩
  · unfold MultiTrieStore.save saveInto at e
    cases h0 : ms.epochs[0]? with
    | none => simp [h0, bind, Except.bind, throw, throwThe, MonadExceptOf.throw] at e
    | some db =>
      simp only [h0, bind, Except.bind] at e
      split at e
      · cases e
      · simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at e
        obtain ⟨rfl, _⟩ := e
        exact ⟨rfl, List.length_set .., fun i hi => List.getElem?_set_ne (Ne.symm hi)⟩
  · unfold MultiTrieStore.saveValue at e
    obtain ⟨c, eps⟩ := ms
    cases eps with
    | nil => simp at e
    | cons db rest =>
      simp only [Except.ok.injEq] at e; subst e
      refine ⟨rfl, rfl, fun i hi => ?_⟩
      cases i with
      | zero => exact absurd rfl hi
      | succ i => rfl
  · simp [MultiTrieStore.retrieveValue, List.findSome?, hv]
  · simp [MultiTrieStore.retrieveValue, List.findSome?, hv]

/-- A node returned by `retrieve` is marked saved. -/
theorem retrieve_saved (env : Env) (h : Bytes) (t : OTrie) (e : Op.retrieve env h = .ok (some t)) :
    t.saved = true := by
  unfold Op.retrieve at e
  split at e
  · cases e
  · simp only [bind, Except.bind] at e
    split at e
    · cases e
    · simp only [pure, Except.pure, Except.ok.injEq, Option.some.injEq] at e; subst e; rfl

/-- `TrieStoreImpl.save` of a saved node writes nothing (TrieStoreImpl.java:93-95). -/
theorem saveInto_saved (H : Bytes → Bytes) (ms : MultiTrieStore) (i : Nat) (t : OTrie) (hs : t.saved = true)
    (hi : i < ms.epochs.length) : MultiTrieStore.saveInto H ms i t = .ok (ms, t) := by
  unfold saveInto
  rw [List.getElem?_eq_getElem hi]
  simp only [bind, Except.bind, show OFUEL = 999999 + 1 from rfl, saveRec, hs, ↓reduceIte, pure, Except.pure]
  rw [set_self _ _ _ (List.getElem?_eq_getElem hi)]

/-- TRIE-STORE-06 (Java): `collect` copies nothing — the retrieved root is marked saved, so
`save` into the second-oldest epoch returns at once; the result is the rotated epoch list with
the oldest epoch dropped and a fresh current epoch. -/
theorem trie_store_06 (H : Bytes → Bytes) (ms ms' : MultiTrieStore) (h : Bytes)
    (e : MultiTrieStore.collect H ms h = .ok ms') :
    ms' = ⟨ms.currentEpoch + 1, DB.empty :: ms.epochs.dropLast⟩ := by
  unfold MultiTrieStore.collect at e
  simp only [bind, Except.bind] at e
  split at e
  · cases e
  · rename_i o ho
    cases o with
    | none => simp [throw, throwThe, MonadExceptOf.throw] at e
    | some t =>
      simp only at e
      split at e
      · cases e
      · rename_i hn
        rw [saveInto_saved H ms _ t (retrieve_saved _ h t ho) (by omega)] at e
        simp only [pure, Except.pure, Except.ok.injEq] at e
        exact e.symm

/-- The reproducer: `MultiTrieStore(0, 3)`, save `{01: aa, 02: bb}`, then `collect(root)` three
times, checking `retrieve(root).isPresent()` after each (Java prints `true, true, false`). -/
def store06 : Except Err (Bytes × List Bool) := do
  let ms := MultiTrieStore.new 0 3
  let t ← OTrie.empty.put (ms.env Keccak.keccak256) [0x01] (some [0xaa])
  let t ← t.put (ms.env Keccak.keccak256) [0x02] (some [0xbb])
  let (ms, t) ← MultiTrieStore.save Keccak.keccak256 ms t
  let (root, _) ← t.hashOf (ms.env Keccak.keccak256)
  let ms1 ← MultiTrieStore.collect Keccak.keccak256 ms root
  let p1 ← MultiTrieStore.retrieve Keccak.keccak256 ms1 root
  let ms2 ← MultiTrieStore.collect Keccak.keccak256 ms1 root
  let p2 ← MultiTrieStore.retrieve Keccak.keccak256 ms2 root
  let ms3 ← MultiTrieStore.collect Keccak.keccak256 ms2 root
  let p3 ← MultiTrieStore.retrieve Keccak.keccak256 ms3 root
  pure (root, [p1.isSome, p2.isSome, p3.isSome])

def root06 : Bytes := [0xe5, 0x41, 0x38, 0x62, 0x0e, 0x01, 0xa7, 0x20, 0x01, 0xb5, 0x28, 0xb4, 0x99, 0x86, 0xdc,
  0x1d, 0x7a, 0xd0, 0xb6, 0xd3, 0xf2, 0x30, 0x26, 0x12, 0x4b, 0x36, 0xc0, 0xff, 0x75, 0x8f, 0x8c, 0x48]

/-- TRIE-STORE-06 does not hold: after the third `collect` the kept root (`e54138…8c48`, Java's
root hash) is no longer retrievable. -/
theorem trie_store_06_rskip_counterexample : store06 = .ok (root06, [true, true, false]) :=
  (okEq_iff _ _).1 (by decide +kernel)

end MTS

end RskjTrie.Obligations
