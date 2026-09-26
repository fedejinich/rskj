import RskjTrie.TrieStore
import RskjTrie.Proofs.RoundTrip
import RskjTrie.Proofs.Hash
/-!
# Proofs: `TrieStoreImpl.save` / `retrieve` — a saved trie reloads with the same contents and hash
-/
namespace RskjTrie
open Trie TrieKeySlice

/-! ## A re-parsed trie re-encodes to the original message, without reading the store -/

section
variable (env : Env)

def Trie.ReEnc (t : Trie) : Prop :=
  ∀ fuel,
    (t.reparse env.H).getChildrenSize env fuel = .ok (t.encS env.H).2 ∧
    (t.reparse env.H).internalToMessage env fuel = .ok (t.encS env.H).1 ∧
    (t.reparse env.H).isEmbeddable env fuel = .ok (t.isTerminal && decide ((t.encS env.H).1.length ≤ 44))

def NodeRef.ReEnc (r : NodeRef Trie) : Prop :=
  ∀ fuel,
    (r.reparse env.H).serializeInto env fuel = .ok (r.encS env.H).1 ∧
    (r.reparse env.H).isEmbeddable env fuel = .ok (r.encS env.H).2.2
end

theorem Trie.isTerminal_reparse (H : Bytes → Bytes) (t : Trie) : (t.reparse H).isTerminal = t.isTerminal := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
  simp only [Trie.reparse, isTerminal, NodeRef.isEmpty_reparse]

mutual
theorem Trie.reEnc (env : Env) : ∀ t : Trie, t.Resident → t.ReEnc env
  | ⟨p, v, l, r, vl, vh, cs⟩, ⟨hv, hrl, hrr⟩ => by
    intro fuel
    obtain ⟨il1, il2⟩ := NodeRef.reEnc env l hrl fuel
    obtain ⟨ir1, ir2⟩ := NodeRef.reEnc env r hrr fuel
    have hcsz : (Trie.reparse env.H ⟨p, v, l, r, vl, vh, cs⟩).getChildrenSize env fuel =
        .ok (Trie.encS env.H ⟨p, v, l, r, vl, vh, cs⟩).2 := by
      rw [Trie.getChildrenSize]; simp only [Trie.reparse]; rw [Trie.encS_eq env.H p v l r vl vh cs]
    have hmsg : (Trie.reparse env.H ⟨p, v, l, r, vl, vh, cs⟩).internalToMessage env fuel =
        .ok (Trie.encS env.H ⟨p, v, l, r, vl, vh, cs⟩).1 := by
      rw [Trie.internalToMessage, hcsz]
      simp only [Trie.reparse, il1, il2, ir1, ir2, except_bind_ok, NodeRef.isEmpty_reparse]
      rcases hv with ⟨rfl, rfl⟩ | ⟨x, rfl, hx, hpos, _⟩
      · simp [hasLongValue, Trie.encS, isTerminal, NodeRef.isEmpty_reparse]
      · by_cases hlong : vl > 32
        · simp [hasLongValue, hlong, getValueHash, hpos, Trie.encS, isTerminal, NodeRef.isEmpty_reparse]
        · simp [hasLongValue, hlong, hpos, getValue, Trie.encS, isTerminal, NodeRef.isEmpty_reparse]
    refine ⟨hcsz, hmsg, ?_⟩
    rw [Trie.isEmbeddable, Trie.isTerminal_reparse]
    split
    · next h => simp only [hmsg, h, MAX_EMBEDDED_NODE_SIZE_IN_BYTES, except_bind_ok, Bool.true_and]; rfl
    · next h => simp [h]
theorem NodeRef.reEnc (env : Env) : ∀ r : NodeRef Trie, r.Resident → r.ReEnc env
  | .empty, _ => by
    intro fuel; simp [NodeRef.reparse, NodeRef.serializeInto, NodeRef.isEmbeddable, NodeRef.encS]
  | .hash _, h => absurd h (by simp [NodeRef.Resident])
  | .node c, ⟨hres, hne⟩ => by
    intro fuel
    obtain ⟨i1, i2, i3⟩ := Trie.reEnc env c hres fuel
    simp only [NodeRef.reparse]
    split
    · next hemb =>
      refine ⟨?_, ?_⟩
      · rw [NodeRef.serializeInto]
        have hle : (Trie.encS env.H c).1.length ≤ 44 := by simp at hemb; exact hemb.2
        simp only [i3, hemb, except_bind_ok, ↓reduceIte, i2, NodeRef.encS]
        simp [Uint8.mk, show ¬ ((Trie.encS env.H c).1.length > 255) by omega]
      · rw [NodeRef.isEmbeddable]; simp only [i3, NodeRef.encS]
    · next hemb =>
      refine ⟨?_, ?_⟩
      · simp only [NodeRef.serializeInto, NodeRef.encS, hemb, Bool.false_eq_true, ↓reduceIte,
          Trie.hashS]
        try rfl
      · simp only [NodeRef.isEmbeddable, NodeRef.encS]; simpa using hemb
end

/-- The re-parsed trie has the original hash. -/
theorem Trie.getHash_reparse (env : Env) (t : Trie) (hres : t.Resident) :
    (t.reparse env.H).getHash env = .ok (t.hashS env.H) := by
  unfold Trie.getHash; rw [Trie.getHashF, Trie.isEmptyTrie_reparse]
  unfold Trie.hashS
  split
  · rfl
  · rw [((Trie.reEnc env t hres) FUEL).2.1]; rfl

/-! ## What `save` writes -/

mutual
/-- Every node message and every long value of `t` (the byte strings a save may write). -/
def Trie.vals (H : Bytes → Bytes) : Trie → List Bytes
  | ⟨p, v, l, r, vl, vh, cs⟩ =>
    (Trie.encS H ⟨p, v, l, r, vl, vh, cs⟩).1 :: ((if vl > 32 then [v.getD []] else []) ++
      (NodeRef.vals H l ++ NodeRef.vals H r))
def NodeRef.vals (H : Bytes → Bytes) : NodeRef Trie → List Bytes
  | .node c => Trie.vals H c
  | _ => []
end

/-- `H` is injective on `S` (the ideal-hash assumption, restricted to what is written). -/
def InjOn (H : Bytes → Bytes) (S : List Bytes) : Prop := ∀ a ∈ S, ∀ b ∈ S, H a = H b → a = b

/-- `db'` is `db` plus writes of the form `H x ↦ x` with `x ∈ S`. -/
def Extends (H : Bytes → Bytes) (S : List Bytes) (db db' : DB) : Prop :=
  ∀ k, db' k = db k ∨ ∃ x ∈ S, k = H x ∧ db' k = some x

theorem Extends.refl (H S db) : Extends H S db db := fun _ => Or.inl rfl
theorem Extends.trans {H S db1 db2 db3} (a : Extends H S db1 db2) (b : Extends H S db2 db3) :
    Extends H S db1 db3 := by
  intro k
  rcases b k with h | h
  · rw [h]; exact a k
  · exact Or.inr h
theorem Extends.put {H S} (db : DB) (x : Bytes) (hx : x ∈ S) : Extends H S db (db.put (H x) x) := by
  intro k; unfold DB.put
  by_cases hk : k = H x
  · exact Or.inr ⟨x, hx, hk, by simp [hk]⟩
  · exact Or.inl (by simp [hk])
theorem Extends.persist {H S db db'} (hinj : InjOn H S) (e : Extends H S db db') {y : Bytes}
    (hy : y ∈ S) (h : db (H y) = some y) : db' (H y) = some y := by
  rcases e (H y) with h' | ⟨x, hx, hk, h'⟩
  · rw [h', h]
  · rw [h', hinj x hx y hy hk.symm]

mutual
/-- Every long value of `t` and every non-embedded child message of `t` is in the store under
its hash. -/
def Trie.Saved (H : Bytes → Bytes) (db : DB) : Trie → Prop
  | ⟨_, v, l, r, vl, _, _⟩ =>
    (vl > 32 → db (H (v.getD [])) = some (v.getD [])) ∧ NodeRef.Saved H db l ∧ NodeRef.Saved H db r
def NodeRef.Saved (H : Bytes → Bytes) (db : DB) : NodeRef Trie → Prop
  | .node c => ((NodeRef.encS H (.node c)).2.2 = false →
      db (H (Trie.encS H c).1) = some (Trie.encS H c).1) ∧ Trie.Saved H db c
  | _ => True
end

theorem Trie.vals_head (H : Bytes → Bytes) (t : Trie) : (t.encS H).1 ∈ t.vals H := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t; simp [Trie.vals]

mutual
theorem Trie.Saved_persist (H : Bytes → Bytes) (S : List Bytes) (hinj : InjOn H S) :
    ∀ (t : Trie) (db db' : DB), (∀ x ∈ t.vals H, x ∈ S) → Extends H S db db' →
      t.Saved H db → t.Saved H db'
  | ⟨p, v, l, r, vl, vh, cs⟩, db, db', hS, e, ⟨h1, h2, h3⟩ => by
    refine ⟨fun h => e.persist hinj (hS _ ?_) (h1 h), ?_, ?_⟩
    · simp [Trie.vals, h]
    · exact NodeRef.Saved_persist H S hinj l db db' (fun x hx => hS x (by simp [Trie.vals, hx])) e h2
    · exact NodeRef.Saved_persist H S hinj r db db' (fun x hx => hS x (by simp [Trie.vals, hx])) e h3
theorem NodeRef.Saved_persist (H : Bytes → Bytes) (S : List Bytes) (hinj : InjOn H S) :
    ∀ (r : NodeRef Trie) (db db' : DB), (∀ x ∈ NodeRef.vals H r, x ∈ S) → Extends H S db db' →
      NodeRef.Saved H db r → NodeRef.Saved H db' r
  | .empty, _, _, _, _, _ => trivial
  | .hash _, _, _, _, _, _ => trivial
  | .node c, db, db', hS, e, ⟨h1, h2⟩ =>
    ⟨fun h => e.persist hinj (hS _ (Trie.vals_head H c)) (h1 h),
      Trie.Saved_persist H S hinj c db db' hS e h2⟩
end

theorem Trie.hashS_nonempty (H : Bytes → Bytes) (t : Trie) (h : t.isEmptyTrie = false) :
    t.hashS H = H (t.encS H).1 := by simp [Trie.hashS, h]

theorem saveTail_spec (H : Bytes → Bytes) (S : List Bytes) (hinj : InjOn H S) (t : Trie) (db : DB)
    (isRoot : Bool) (hres : t.Resident) (hc : t.CacheOK H) (hS : ∀ x ∈ t.vals H, x ∈ S) :
    ∃ db', TrieStoreImpl.saveTail H db t isRoot (H (t.encS H).1) = .ok db' ∧ Extends H S db db' ∧
      (t.valueLength > 32 → db' (H (t.value.getD [])) = some (t.value.getD [])) ∧
      ((isRoot = true ∨ (t.isTerminal && decide ((t.encS H).1.length ≤ 44)) = false) →
        db' (H (t.encS H).1) = some (t.encS H).1) := by
  have hm := Trie.vals_head H t
  -- the node write
  have tailOK : ∀ db1 : DB, Extends H S db db1 → (t.valueLength > 32 → db1 (H (t.value.getD [])) = some (t.value.getD [])) →
      ∃ db', (do
          if (← t.isEmbeddable ⟨H, db1⟩ FUEL) && !isRoot then return db1
          let m ← t.toMessage ⟨H, db1⟩
          pure (db1.put (H (t.encS H).1) m) : Except Err DB) = .ok db' ∧ Extends H S db db' ∧
        (t.valueLength > 32 → db' (H (t.value.getD [])) = some (t.value.getD [])) ∧
        ((isRoot = true ∨ (t.isTerminal && decide ((t.encS H).1.length ≤ 44)) = false) →
          db' (H (t.encS H).1) = some (t.encS H).1) := by
    intro db1 e1 l1
    have eo := (Trie.encOK ⟨H, db1⟩ t hres hc FUEL)
    simp only [eo.2.2.1, except_bind_ok]
    by_cases hskip : ((t.isTerminal && decide ((t.encS H).1.length ≤ 44)) && !isRoot) = true
    · simp only [hskip, ↓reduceIte]
      refine ⟨db1, rfl, e1, l1, fun h => ?_⟩
      exfalso; rcases h with h | h <;> simp_all
    · simp only [hskip, Bool.false_eq_true, ↓reduceIte, Trie.toMessage, eo.2.1, except_bind_ok]
      have e2 := Extends.put (H := H) (S := S) db1 _ (hS _ hm)
      refine ⟨_, rfl, e1.trans e2, fun h => ?_, fun _ => by simp [DB.put]⟩
      have hv : t.value.getD [] ∈ S := hS _ (by
        obtain ⟨p, v, l, r, vl, vh, cs⟩ := t; simp only at h; simp [Trie.vals, h])
      exact e2.persist hinj hv (l1 h)
  unfold TrieStoreImpl.saveTail
  by_cases hlong : t.hasLongValue = true
  · simp only [hlong, ↓reduceIte]
    have hl : t.valueLength > 32 := by simpa [hasLongValue] using hlong
    obtain ⟨x, hxv, hxl⟩ : ∃ x, t.value = some x ∧ x.length = t.valueLength := by
      obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
      rcases hres.1 with ⟨_, h0⟩ | ⟨x, h1, h2, _, _⟩
      · simp only at hl h0; omega
      · exact ⟨x, h1, h2⟩
    have hgv : t.getValue ⟨H, db⟩ = .ok (some x) := by
      obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
      rw [Trie.getValue_resident _ _ hres.1]; simp only at hxv ⊢; rw [hxv]
    have hgvh : t.getValueHash ⟨H, db⟩ = .ok (some (H x)) := by
      obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
      simp only at hxv; subst hxv
      unfold getValueHash
      rcases hc.2.1 x rfl with h | h
      · subst h; simp only at hl; simp [getValue]; omega
      · subst h; rfl
    simp only [hgvh, hgv, except_bind_ok, except_pure]
    have hx : x ∈ S := hS x (by
      obtain ⟨p, v, l, r, vl, vh, cs⟩ := t; simp only at hl hxv; subst hxv; simp [Trie.vals, hl])
    have e1 := Extends.put (H := H) (S := S) db x hx
    obtain ⟨db', h1, h2, h3, h4⟩ := tailOK (db.put (H x) x) e1 (fun _ => by rw [hxv]; simp [DB.put])
    exact ⟨db', h1, h2, h3, h4⟩
  · simp only [hlong, Bool.false_eq_true, ↓reduceIte, except_pure, except_bind_ok]
    have hl : ¬ t.valueLength > 32 := by simpa [hasLongValue] using hlong
    exact tailOK db (Extends.refl _ _ _) (fun h => absurd h hl)

mutual
theorem Trie.saveRec_spec (H : Bytes → Bytes) (S : List Bytes) (hinj : InjOn H S) :
    ∀ (t : Trie) (db : DB) (isRoot : Bool), t.Resident → t.CacheOK H → t.isEmptyTrie = false →
      (∀ x ∈ t.vals H, x ∈ S) →
      ∃ db', TrieStoreImpl.saveRec H db t isRoot = .ok db' ∧ Extends H S db db' ∧ t.Saved H db' ∧
        ((isRoot = true ∨ (t.isTerminal && decide ((t.encS H).1.length ≤ 44)) = false) →
          db' (H (t.encS H).1) = some (t.encS H).1)
  | ⟨p, v, l, r, vl, vh, cs⟩, db, isRoot, hres, hc, hne, hS => by
    have hSl : ∀ x ∈ NodeRef.vals H l, x ∈ S := fun x hx => hS x (by simp [Trie.vals, hx])
    have hSr : ∀ x ∈ NodeRef.vals H r, x ∈ S := fun x hx => hS x (by simp [Trie.vals, hx])
    rw [TrieStoreImpl.saveRec]
    simp only [Trie.getHash, ((Trie.encOK ⟨H, db⟩ _ hres hc) FUEL).2.2.2.1, except_bind_ok,
      Trie.hashS_nonempty H _ hne]
    obtain ⟨db1, h1, e1, s1⟩ := NodeRef.saveRef_spec H S hinj l db hres.2.1 hc.2.2.1 hSl
    rw [h1, except_bind_ok]
    obtain ⟨db2, h2, e2, s2⟩ := NodeRef.saveRef_spec H S hinj r db1 hres.2.2 hc.2.2.2 hSr
    rw [h2, except_bind_ok]
    obtain ⟨db3, h3, e3, l3, w3⟩ := saveTail_spec H S hinj _ db2 isRoot hres hc hS
    refine ⟨db3, h3, e1.trans (e2.trans e3), ⟨l3, ?_, ?_⟩, w3⟩
    · exact NodeRef.Saved_persist H S hinj l db1 db3 hSl (e2.trans e3) s1
    · exact NodeRef.Saved_persist H S hinj r db2 db3 hSr e3 s2
theorem NodeRef.saveRef_spec (H : Bytes → Bytes) (S : List Bytes) (hinj : InjOn H S) :
    ∀ (R : NodeRef Trie) (db : DB), R.Resident → R.CacheOK H → (∀ x ∈ NodeRef.vals H R, x ∈ S) →
      ∃ db', TrieStoreImpl.saveRef H db R = .ok db' ∧ Extends H S db db' ∧ NodeRef.Saved H db' R
  | .empty, db, _, _, _ => ⟨db, rfl, Extends.refl _ _ _, trivial⟩
  | .hash _, _, h, _, _ => absurd h (by simp [NodeRef.Resident])
  | .node c, db, ⟨hres, hne⟩, hc, hS => by
    obtain ⟨db', h1, e1, s1, w1⟩ := Trie.saveRec_spec H S hinj c db false hres hc hne hS
    exact ⟨db', h1, e1, fun hemb => w1 (Or.inr (by simpa [NodeRef.encS] using hemb)), s1⟩
end

/-! ## Reading a saved trie back -/

theorem Trie.get_reparse (env : Env) (hH : ∀ x, (env.H x).length = 32) :
    ∀ (t : Trie), t.Resident → t.CacheOK env.H → t.PathsOK → t.Saved env.H env.db → ∀ (key : TrieKeySlice),
    (((t.reparse env.H).findSlice env key) >>= fun o => match o with
      | none => pure none
      | some n => n.getValue env) = .ok (t.contents key)
  | ⟨p, v, l, r, vl, vh, cs⟩, ⟨hv, hl, hr⟩, ⟨_, hvh, hcl, hcr⟩, ⟨_, hpl, hpr⟩, ⟨hsv, hsl, hsr⟩, key => by
    rw [findSlice]
    simp only [Trie.reparse, commonPath_eq_lcp]
    by_cases h1 : p.length > key.length
    · have : ¬ p <+: key := fun h => by have := h.length_le; omega
      simp [h1, Trie.contents, this]
    · simp only [h1, ↓reduceIte]
      by_cases h2 : (lcp key p).length < p.length
      · have : ¬ p <+: key := fun h => by rw [lcp_of_prefix h] at h2; omega
        simp [h2, Trie.contents, this]
      · have hlen := lcp_length_le_right key p
        have heq : (lcp key p).length = p.length := by omega
        have hpre : p <+: key := (lcp_eq_iff_prefix key p).mp heq
        simp only [heq]
        by_cases h3 : p.length = key.length
        · have hk : key.drop p.length = [] := by simp; omega
          simp only [h3, ↓reduceDIte, Nat.lt_irrefl, ↓reduceIte, except_bind_ok]
          rw [Trie.contents]; simp only [hpre, ↓reduceIte, hk]
          rcases hv with ⟨rfl, rfl⟩ | ⟨x, rfl, hx, hpos, _⟩
          · simp [getValue]
          · by_cases hlong : vl > 32
            · have hdb : env.db (env.H x) = some x := by simpa using hsv hlong
              simp [getValue, hlong, hpos, TrieStoreImpl.retrieveValue, hdb, hx]
            · simp [getValue, hlong]
        · simp only [h3, ↓reduceDIte]
          have hlt : p.length < key.length := by omega
          rw [Trie.contents]
          simp only [hpre, ↓reduceIte, drop_eq_cons_get hlt]
          simp only [retrieveNode, getNodeReference, slice_eq_drop, Nat.lt_irrefl, ↓reduceIte]
          cases hb : TrieKeySlice.get key p.length
          · simp only [↓reduceIte]
            cases l with
            | empty => rfl
            | hash => exact absurd hl (by simp [NodeRef.Resident])
            | node c =>
              simp only [NodeRef.reparse]
              split
              · simp only [NodeRef.getNode, except_bind_ok, NodeRef.contents]
                exact Trie.get_reparse env hH c hl.1 hcl hpl hsl.2 _
              · next hemb =>
                have hst := hsl.1 (by simpa [NodeRef.encS] using hemb)
                have hrt := (Trie.fromMessage_toMessage env hH c hl.1 hcl hpl).2
                simp only [NodeRef.getNode, TrieStoreImpl.retrieve, Trie.hashS_nonempty _ _ hl.2, hst,
                  hrt, except_map_ok, except_bind_ok, NodeRef.contents]
                exact Trie.get_reparse env hH c hl.1 hcl hpl hsl.2 _
          · simp only [Bool.true_eq_false, ↓reduceIte]
            cases r with
            | empty => rfl
            | hash => exact absurd hr (by simp [NodeRef.Resident])
            | node c =>
              simp only [NodeRef.reparse]
              split
              · simp only [NodeRef.getNode, except_bind_ok, NodeRef.contents]
                exact Trie.get_reparse env hH c hr.1 hcr hpr hsr.2 _
              · next hemb =>
                have hst := hsr.1 (by simpa [NodeRef.encS] using hemb)
                have hrt := (Trie.fromMessage_toMessage env hH c hr.1 hcr hpr).2
                simp only [NodeRef.getNode, TrieStoreImpl.retrieve, Trie.hashS_nonempty _ _ hr.2, hst,
                  hrt, except_map_ok, except_bind_ok, NodeRef.contents]
                exact Trie.get_reparse env hH c hr.1 hcr hpr hsr.2 _

/-- **Store round trip** (`TrieStoreImpl.save` then `retrieve(getHash())`): for a non-empty
well-formed trie whose shared paths fit an `int`, with a hash function that has 32-byte outputs and
is injective on the messages and long values of the trie (`t.vals H`), saving into *any* store
succeeds, and retrieving the root hash from the resulting store yields a trie (`t.reparse H`) with
the same `get` result for every key (long values are read back from the store) and the same hash. -/
theorem Trie.save_retrieve (H : Bytes → Bytes) (hH : ∀ x, (H x).length = 32) (db : DB) (t : Trie)
    (hwf : t.WF H) (hp : t.PathsOK) (hne : t.isEmptyTrie = false) (hinj : InjOn H (t.vals H)) :
    ∃ db', TrieStoreImpl.save H db t = .ok db' ∧
      t.getHash ⟨H, db⟩ = .ok (t.hashS H) ∧
      TrieStoreImpl.retrieve ⟨H, db'⟩ (t.hashS H) = .ok (some (t.reparse H)) ∧
      (∀ key, (t.reparse H).get ⟨H, db'⟩ key = t.get ⟨H, db⟩ key) ∧
      (t.reparse H).getHash ⟨H, db'⟩ = t.getHash ⟨H, db⟩ := by
  obtain ⟨hres, hc, _⟩ := hwf
  obtain ⟨db', h1, _, hs, hw⟩ := Trie.saveRec_spec H (t.vals H) hinj t db true hres hc hne (fun x hx => hx)
  have hroot := hw (Or.inl rfl)
  have hgh : t.getHash ⟨H, db⟩ = .ok (t.hashS H) := (Trie.encOK ⟨H, db⟩ t hres hc FUEL).2.2.2.1
  refine ⟨db', h1, hgh, ?_, fun key => ?_, ?_⟩
  · simp only [TrieStoreImpl.retrieve, Trie.hashS_nonempty H t hne, hroot]
    rw [(Trie.fromMessage_toMessage ⟨H, db'⟩ hH t hres hc hp).2]; rfl
  · rw [Trie.get_eq_contents ⟨H, db⟩ t hres]
    exact Trie.get_reparse ⟨H, db'⟩ hH t hres hc hp hs _
  · rw [hgh]; exact Trie.getHash_reparse ⟨H, db'⟩ t hres

/-- Shared paths are bounded by the keys: if every stored key has fewer than `2^31` bits (e.g.
byte keys shorter than `2^28` bytes), every shared path does, so `PathsOK` holds. -/
theorem Trie.PathsOK_of_keys : ∀ (t : Trie), t.CanonNE →
    (∀ q, t.contents q ≠ none → q.length < 2 ^ 31) → t.PathsOK
  | ⟨p, v, l, r, vl, vh, cs⟩, hc, hk => by
    obtain ⟨q, hq⟩ := Trie.support_nonempty _ hc
    have hpq := Trie.contents_prefix _ q hq
    refine ⟨Nat.lt_of_le_of_lt hpq.length_le (hk q hq), ?_, ?_⟩
    · cases l with
      | empty => trivial
      | hash => exact absurd hc.2.1 (by simp [NodeRef.Canon])
      | node c =>
        exact Trie.PathsOK_of_keys c hc.2.1 (fun q' hq' => by
          have := hk (p ++ false :: q') (by rw [Trie.contents_mk]; exact hq')
          simp at this; omega)
    · cases r with
      | empty => trivial
      | hash => exact absurd hc.2.2 (by simp [NodeRef.Canon])
      | node c =>
        exact Trie.PathsOK_of_keys c hc.2.2 (fun q' hq' => by
          have := hk (p ++ true :: q') (by rw [Trie.contents_mk]; exact hq')
          simp at this; omega)

theorem Trie.WF_PathsOK (H : Bytes → Bytes) (t : Trie) (h : t.WF H)
    (hk : ∀ q, t.contents q ≠ none → q.length < 2 ^ 31) : t.PathsOK := by
  rcases h.2.2 with h' | ⟨h1, _, _, h4, h5⟩
  · exact Trie.PathsOK_of_keys t h' hk
  · obtain ⟨p, v, l, r, vl, vh, cs⟩ := t; simp only at h1 h4 h5; subst h1 h4 h5
    exact ⟨by simp, trivial, trivial⟩

/-- Soundness condition of the "no `lazyNode` cache" abstraction (MODEL.md): in a message written
by `save`, a child referenced by hash is one whose re-parsed node is *not* embeddable, so loading it
(Java caches it in `lazyNode`) cannot change the parent's serialization. -/
theorem Trie.reparse_hashed_not_embeddable (env : Env) (c : Trie) (hres : c.Resident)
    (hemb : (NodeRef.encS env.H (.node c)).2.2 = false) (fuel : Nat) :
    NodeRef.reparse env.H (.node c) = .hash (c.hashS env.H) ∧
    (c.reparse env.H).isEmbeddable env fuel = .ok false := by
  have h3 := ((Trie.reEnc env c hres) fuel).2.2
  simp only [NodeRef.encS] at hemb
  refine ⟨by simp [NodeRef.reparse, hemb], by rw [h3, hemb]⟩

end RskjTrie
