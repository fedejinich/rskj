import RskjTrie.Proofs.PutLemmas
/-!
# Proofs: `put` / `delete` map semantics and invariants

For a resident trie with consistent caches in canonical shape, `putSlice` (Java
`put(TrieKeySlice, byte[], false)`) succeeds, returns a resident, cache-consistent, canonical trie,
and updates the contents at exactly one key.
-/
namespace RskjTrie
open Trie TrieKeySlice

/-- The node a `PutRes` denotes (`same` = the receiver). -/
def PutRes.node (t : Trie) : PutRes → Option Trie
  | .same => some t
  | .null => none
  | .new n => some n

def optContents : Option Trie → List Bool → Option Bytes
  | none, _ => none
  | some n, q => n.contents q

/-- Values fit Java's `Uint24` value length. -/
def VOK (v : Option Bytes) : Prop := ∀ x, v = some x → x.length ≤ Uint24.MAX

/-- The shape of a node just produced by `split` on the way to inserting `k`: no value, exactly
one child at side `b`, and `k` continues with `!b` (or ends here). -/
def SplitShape (t : Trie) (k : List Bool) : Prop :=
  t.value = none ∧ t.valueLength = 0 ∧ t.sharedPath <+: k ∧
  ∃ b, t.getNodeReference b ≠ .empty ∧ t.getNodeReference (!b) = .empty ∧
    (k.length = t.sharedPath.length ∨ TrieKeySlice.get k t.sharedPath.length = !b)

def Pre (H : Bytes → Bytes) (t : Trie) (k : List Bool) (v : Option Bytes) : Prop :=
  t.Resident ∧ t.CacheOK H ∧ t.CanonBelow ∧ (t.Canon ∨ (v.isSome ∧ SplitShape t k))

def PostPut (H : Bytes → Bytes) (t : Trie) (k : List Bool) (v : Option Bytes) (r : PutRes) : Prop :=
  (∀ n, r.node t = some n → n.Resident ∧ n.CacheOK H ∧ n.CanonNE) ∧
  (∀ q, optContents (r.node t) q = upd t.contents k v q)

def PostIP (H : Bytes → Bytes) (t : Trie) (k : List Bool) (v : Option Bytes) (r : PutRes) : Prop :=
  (∀ n, r.node t = some n →
    n.Resident ∧ n.CacheOK H ∧ n.CanonBelow ∧ (v.isSome → n.CanonNE) ∧ (n.CanonNE ∨ n.value = none)) ∧
  (∀ q, optContents (r.node t) q = upd t.contents k v q)

theorem normValue_idem (v : Option Bytes) : normValue (normValue v) = normValue v := by
  unfold normValue; cases v with
  | none => rfl
  | some x => by_cases h : x.length = 0 <;> simp [h]

theorem Trie.Resident_path (c : Trie) (p' : List Bool) :
    (⟨p', c.value, c.left, c.right, c.valueLength, c.valueHash, c.childrenSize⟩ : Trie).Resident ↔
      c.Resident := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := c; simp [Trie.Resident]

theorem Trie.CacheOK_path (H : Bytes → Bytes) (c : Trie) (p' : List Bool) :
    (⟨p', c.value, c.left, c.right, c.valueLength, c.valueHash, c.childrenSize⟩ : Trie).CacheOK H ↔
      c.CacheOK H := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := c; simp [Trie.CacheOK, encS_snd]

theorem Trie.CanonNE_path (c : Trie) (p' : List Bool) :
    (⟨p', c.value, c.left, c.right, c.valueLength, c.valueHash, c.childrenSize⟩ : Trie).CanonNE ↔
      c.CanonNE := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := c; simp [Trie.CanonNE]

theorem Trie.value_none_of_resident {t : Trie} (h : t.Resident) (h0 : ¬ t.valueLength > 0) :
    t.value = none := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
  rcases h.1 with ⟨h1, _⟩ | ⟨x, _, _, hpos, _⟩
  · exact h1
  · simp at h0; omega

theorem Trie.contents_isEmpty {t : Trie} (hr : t.Resident) (he : t.isEmptyTrie = true) (q : List Bool) :
    t.contents q = none := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
  simp only [isEmptyTrie, isEmptyTrieOf] at he
  split at he
  · simp at he
  · next h0 =>
    have hv := Trie.value_none_of_resident (t := ⟨p, v, l, r, vl, vh, cs⟩) hr h0
    simp only at hv; subst hv
    have hl : l = .empty := by cases l <;> simp_all [NodeRef.isEmpty]
    have hr' : r = .empty := by cases r <;> simp_all [NodeRef.isEmpty]
    subst hl hr'
    rw [Trie.contents_leaf]; simp

theorem NodeRef.eq_empty_of_isEmpty {r : NodeRef Trie} (h : r.isEmpty = true) : r = .empty := by
  cases r <;> simp_all [NodeRef.isEmpty]

theorem NodeRef.contents_ofNode (c : Trie) (hr : c.Resident) (q : List Bool) :
    NodeRef.contents (NodeRef.ofNode (some c)) q = c.contents q := by
  simp only [NodeRef.ofNode]
  split
  · next he => rw [Trie.contents_isEmpty hr he]; rfl
  · rfl

theorem NodeRef.refOK (env : Env) (R : NodeRef Trie) (hr : R.Resident) (hc : R.CacheOK env.H) (fuel : Nat) :
    R.referenceSize env fuel = .ok (NodeRef.encS env.H R).2.1 :=
  ((NodeRef.encOK env R hr hc) fuel).2.1

theorem NodeRef.ofNode_props (H : Bytes → Bytes) (o : Option Trie)
    (h : ∀ n, o = some n → n.Resident ∧ n.CacheOK H ∧ n.CanonNE) :
    (NodeRef.ofNode o).Resident ∧ (NodeRef.ofNode o).CacheOK H ∧ (NodeRef.ofNode o).Canon := by
  cases o with
  | none => simp [NodeRef.ofNode, NodeRef.Resident, NodeRef.CacheOK, NodeRef.Canon]
  | some n =>
    obtain ⟨h1, h2, h3⟩ := h n rfl
    simp only [NodeRef.ofNode]
    split
    · simp [NodeRef.Resident, NodeRef.CacheOK, NodeRef.Canon]
    · next he => exact ⟨⟨h1, by simpa using he⟩, h2, h3⟩

/-- Children of a resident node are what `retrieveNodeOrEmpty` returns. -/
theorem retrieveNodeOrEmpty_spec (env : Env) (t : Trie) (hres : t.Resident) (hc : t.CacheOK env.H)
    (hb : t.CanonBelow) (pos : Bool) :
    ∃ c, t.retrieveNodeOrEmpty env pos = .ok c ∧ NodeRef.ofNode (some c) = t.getNodeReference pos ∧
      c.Resident ∧ c.CacheOK env.H ∧ c.Canon := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
  obtain ⟨_, hrl, hrr⟩ := hres
  obtain ⟨_, _, hcl, hcr⟩ := hc
  obtain ⟨hbl, hbr⟩ := hb
  have gen : ∀ R : NodeRef Trie, R.Resident → R.CacheOK env.H → R.Canon →
      ∃ c, (do match ← R.getNode env with
                | some n => pure n
                | none => pure Trie.empty : Except Err Trie) = .ok c ∧
        NodeRef.ofNode (some c) = R ∧ c.Resident ∧ c.CacheOK env.H ∧ c.Canon := by
    intro R h1 h2 h3
    cases R with
    | empty =>
      refine ⟨Trie.empty, rfl, rfl, ?_, ?_, ?_⟩
      · simp [Trie.empty, Trie.Resident, ValueOK, NodeRef.Resident]
      · simp [Trie.empty, Trie.CacheOK, NodeRef.CacheOK, encS_snd, kidsSize, NodeRef.isEmpty]
      · right; simp [Trie.empty]
    | hash => simp [NodeRef.Resident] at h1
    | node c =>
      refine ⟨c, rfl, ?_, h1.1, h2, Or.inl h3⟩
      simp [NodeRef.ofNode, h1.2]
  cases pos
  · exact gen l hrl hcl hbl
  · exact gen r hrr hcr hbr

theorem replaceChild_spec (env : Env) (t : Trie) (hres : t.Resident) (hc : t.CacheOK env.H)
    (pos : Bool) (R : NodeRef Trie) (hR : R.Resident) (hcR : R.CacheOK env.H) :
    ∃ nl nr cs', t.replaceChild env pos R = .ok (nl, nr, cs') ∧
      (if pos = false then nl = R ∧ nr = t.right else nl = t.left ∧ nr = R) ∧
      (cs' = none ∨ cs' = some (kidsSize env.H nl nr)) := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
  obtain ⟨_, hrl, hrr⟩ := hres
  obtain ⟨hcs, _, hcl, hcr⟩ := hc
  rw [encS_snd] at hcs
  unfold replaceChild
  cases pos
  · simp only [↓reduceIte]
    rcases hcs with h | h
    · subst h; exact ⟨_, _, _, rfl, ⟨rfl, rfl⟩, Or.inl rfl⟩
    · subst h
      simp only [NodeRef.refOK env l hrl hcl, NodeRef.refOK env R hR hcR, except_bind_ok, except_pure]
      exact ⟨_, _, _, rfl, ⟨rfl, rfl⟩, Or.inr (by rw [kidsSize_update_left env.H l R r hrl hR hrr])⟩
  · simp only [Bool.true_eq_false, ↓reduceIte]
    rcases hcs with h | h
    · subst h; exact ⟨_, _, _, rfl, ⟨rfl, rfl⟩, Or.inl rfl⟩
    · subst h
      simp only [NodeRef.refOK env r hrr hcr, NodeRef.refOK env R hR hcR, except_bind_ok, except_pure]
      exact ⟨_, _, _, rfl, ⟨rfl, rfl⟩, Or.inr (by rw [kidsSize_update_right env.H l r R hrl hrr hR])⟩

def dataLen (value : Option Bytes) : Nat :=
  match value with
  | some x => x.length
  | none => 0

theorem getDataLength_spec (value : Option Bytes) (hv : VOK value) :
    getDataLength value = .ok (dataLen value) := by
  cases value with
  | none => rfl
  | some x => simp [getDataLength, Uint24.mk, dataLen, show ¬ (x.length > Uint24.MAX) from by
      have := hv x rfl; omega]

theorem normValue_eq (value : Option Bytes) (hn : normValue value = value) :
    ∀ x, value = some x → x ≠ [] := by
  intro x hx; subst hx; intro h; subst h; simp [normValue] at hn

/-- The child that `split` pushes down. -/
def splitChild (t : Trie) (n : Nat) : Trie :=
  ⟨t.sharedPath.drop (n + 1), t.value, t.left, t.right, t.valueLength, t.valueHash, t.childrenSize⟩

def splitNode (H : Bytes → Bytes) (t : Trie) (cp : List Bool) : Trie :=
  let b := TrieKeySlice.get t.sharedPath cp.length
  let C := splitChild t cp.length
  ⟨cp, none, (if b then .empty else .node C), (if b then .node C else .empty), 0, none,
    some (NodeRef.encS H (.node C)).2.1⟩

theorem split_spec (env : Env) (t : Trie) (hres : t.Resident) (hc : t.CacheOK env.H)
    (hne : t.isEmptyTrie = false) (cp : List Bool) :
    ∃ hs, t.split env cp = .ok ⟨splitNode env.H t cp, hs⟩ := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
  have hC : (splitChild ⟨p, v, l, r, vl, vh, cs⟩ cp.length).isEmptyTrie = false := hne
  have hRes : (NodeRef.node (splitChild ⟨p, v, l, r, vl, vh, cs⟩ cp.length)).Resident :=
    ⟨(Trie.Resident_path ⟨p, v, l, r, vl, vh, cs⟩ _).mpr hres, hC⟩
  have hCa : (NodeRef.node (splitChild ⟨p, v, l, r, vl, vh, cs⟩ cp.length)).CacheOK env.H :=
    (Trie.CacheOK_path env.H ⟨p, v, l, r, vl, vh, cs⟩ _).mpr hc
  refine ⟨rfl, ?_⟩
  unfold split
  have e1 : NodeRef.ofNode (some ⟨p.slice (cp.length + 1) p.length, v, l, r, vl, vh, cs⟩) =
      NodeRef.node (splitChild ⟨p, v, l, r, vl, vh, cs⟩ cp.length) := by
    simp only [NodeRef.ofNode, slice_eq_drop]
    simp only [splitChild] at hC ⊢; simp [hC]
  simp only [e1, NodeRef.refOK env _ hRes hCa, except_bind_ok]
  simp only [splitNode]
  by_cases hb : TrieKeySlice.get p cp.length = true
  · simp only [hb, Bool.true_eq_false, ↓reduceIte]; rfl
  · simp only [Bool.not_eq_true] at hb
    simp only [hb, Bool.false_eq_true, ↓reduceIte]; rfl

theorem splitNode_contents (H : Bytes → Bytes) (t : Trie) (cp : List Bool) (hcp : cp <+: t.sharedPath)
    (hlt : cp.length < t.sharedPath.length) (q : List Bool) :
    (splitNode H t cp).contents q = t.contents q := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
  simp only [splitNode, splitChild]
  rw [Trie.contents_merge cp _ 0 none _ _ vl vh cs q]
  congr 2
  simp only
  obtain ⟨u, rfl⟩ := hcp
  simp only [List.length_append] at hlt
  obtain ⟨b, u', rfl⟩ : ∃ b u', u = b :: u' := by
    cases u with
    | nil => simp at hlt
    | cons b u' => exact ⟨b, u', rfl⟩
  simp [TrieKeySlice.get, List.getD]

theorem lcp_next_ne (a b : List Bool) (ha : (lcp a b).length < a.length) (hb : (lcp a b).length < b.length) :
    TrieKeySlice.get a (lcp a b).length ≠ TrieKeySlice.get b (lcp a b).length := by
  induction a generalizing b with
  | nil => simp at ha
  | cons x xs ih =>
    cases b with
    | nil => simp at hb
    | cons y ys =>
      by_cases hxy : x = y
      · subst hxy
        simp only [lcp, ↓reduceIte, List.length_cons] at ha hb ⊢
        have := ih ys (by omega) (by omega)
        simpa [TrieKeySlice.get, List.getD] using this
      · simp [lcp, hxy, TrieKeySlice.get, List.getD]

theorem splitNode_props (H : Bytes → Bytes) (t : Trie) (hres : t.Resident) (hc : t.CacheOK H)
    (hcan : t.CanonNE) (cp : List Bool) :
    (splitNode H t cp).Resident ∧ (splitNode H t cp).CacheOK H ∧ (splitNode H t cp).CanonBelow ∧
    (splitNode H t cp).value = none ∧ (splitNode H t cp).valueLength = 0 ∧
    (splitNode H t cp).getNodeReference (TrieKeySlice.get t.sharedPath cp.length) ≠ .empty ∧
    (splitNode H t cp).getNodeReference (!TrieKeySlice.get t.sharedPath cp.length) = .empty := by
  have hne := Trie.CanonNE_nonempty hcan hres
  have hC : (splitChild t cp.length).isEmptyTrie = false := by
    obtain ⟨p, v, l, r, vl, vh, cs⟩ := t; exact hne
  have hR : (splitChild t cp.length).Resident := by
    obtain ⟨p, v, l, r, vl, vh, cs⟩ := t; exact (Trie.Resident_path ⟨p, v, l, r, vl, vh, cs⟩ _).mpr hres
  have hCa : (splitChild t cp.length).CacheOK H := by
    obtain ⟨p, v, l, r, vl, vh, cs⟩ := t; exact (Trie.CacheOK_path H ⟨p, v, l, r, vl, vh, cs⟩ _).mpr hc
  have hCn : (splitChild t cp.length).CanonNE := by
    obtain ⟨p, v, l, r, vl, vh, cs⟩ := t; exact (Trie.CanonNE_path ⟨p, v, l, r, vl, vh, cs⟩ _).mpr hcan
  have hsz := NodeRef.size_lt H (.node (splitChild t cp.length)) ⟨hR, hC⟩
  unfold splitNode
  cases TrieKeySlice.get t.sharedPath cp.length
  · refine ⟨?_, ?_, ?_, rfl, rfl, by simp [getNodeReference], rfl⟩
    all_goals simp only [Bool.false_eq_true, ↓reduceIte]
    · simp only [Trie.Resident, NodeRef.Resident]; exact ⟨by simp [ValueOK], ⟨hR, hC⟩, trivial⟩
    · simp only [Trie.CacheOK, NodeRef.CacheOK]
      refine ⟨Or.inr ?_, by simp, hCa, trivial⟩
      rw [encS_snd]; simp only [kidsSize, NodeRef.isEmpty, Bool.false_and, Bool.false_eq_true,
        ↓reduceIte, NodeRef.size_empty]
      congr 1; rw [show ((0:Nat):Int) = 0 from rfl, Int.add_zero, wrap64_nat _ hsz]
    · exact ⟨hCn, trivial⟩
  · refine ⟨?_, ?_, ?_, rfl, rfl, by simp [getNodeReference], rfl⟩
    all_goals simp only [↓reduceIte]
    · simp only [Trie.Resident, NodeRef.Resident]; exact ⟨by simp [ValueOK], trivial, ⟨hR, hC⟩⟩
    · simp only [Trie.CacheOK, NodeRef.CacheOK]
      refine ⟨Or.inr ?_, by simp, trivial, hCa⟩
      rw [encS_snd]; simp only [kidsSize, NodeRef.isEmpty, Bool.true_and, Bool.false_eq_true,
        ↓reduceIte, NodeRef.size_empty]
      congr 1; rw [show ((0:Nat):Int) = 0 from rfl, Int.zero_add, wrap64_nat _ hsz]
    · exact ⟨trivial, hCn⟩

mutual
/-- The delete-coalescing step (`Trie.coalesce`, Trie.java:787-820) on a well-formed
`internalPut` result `N` (denoted by `r`) yields a canonical node with the same contents. -/
theorem coalesce_spec (env : Env) (t N : Trie) (r : PutRes) (hr : r.node t = some N)
    (M : List Bool → Option Bytes) (hres : N.Resident) (hcache : N.CacheOK env.H)
    (hbelow : N.CanonBelow) (hcanon : N.CanonNE ∨ N.value = none) (hCN : ∀ q, N.contents q = M q) :
    ∃ r', N.coalesce env r = .ok r' ∧
      (∀ m, r'.node t = some m → m.Resident ∧ m.CacheOK env.H ∧ m.CanonNE) ∧
      ∀ q, optContents (r'.node t) q = M q := by
  unfold Trie.coalesce
  by_cases he : N.isEmptyTrie = true
  · simp only [he, ↓reduceIte]
    refine ⟨.null, rfl, fun m hm => by simp [PutRes.node] at hm, fun q => ?_⟩
    rw [← hCN q, Trie.contents_isEmpty hres he]; rfl
  · simp only [he, Bool.false_eq_true, ↓reduceIte]
    by_cases hvl : N.valueLength > 0
    · simp only [hvl, ↓reduceIte]
      have hcan : N.CanonNE := by
        rcases hcanon with h | h
        · exact h
        · exact absurd h (by
            obtain ⟨p, v, l, r, vl, vh, cs⟩ := N
            rcases hres.1 with ⟨h1, h2⟩ | ⟨x, h1, _, _, _⟩
            · simp at h2 hvl; omega
            · simp_all)
      exact ⟨_, rfl, fun m hm => by
        rw [hr] at hm; cases hm; exact ⟨hres, hcache, hcan⟩, fun q => by rw [hr]; exact hCN q⟩
    · simp only [hvl, ↓reduceIte]
      have hv0 := Trie.value_none_of_resident hres hvl
      by_cases hlr : (N.left.isEmpty == N.right.isEmpty) = true
      · simp only [hlr, ↓reduceIte]
        have hcan : N.CanonNE := by
          obtain ⟨p, v, l, r, vl, vh, cs⟩ := N
          simp only [isEmptyTrie, isEmptyTrieOf, hvl, ↓reduceIte] at he
          refine ⟨Or.inr ⟨?_, ?_⟩, hbelow.1, hbelow.2⟩ <;>
            (intro h0; subst h0; simp_all [NodeRef.isEmpty])
        exact ⟨_, rfl, fun m hm => by
          rw [hr] at hm; cases hm; exact ⟨hres, hcache, hcan⟩, fun q => by rw [hr]; exact hCN q⟩
      · simp only [hlr, Bool.false_eq_true, ↓reduceIte]
        obtain ⟨p, v, l, r, vl, vh, cs⟩ := N
        simp only at hv0 hvl hlr hres hcache hbelow hCN he ⊢
        subst hv0
        obtain ⟨_, hrl, hrr⟩ := hres
        obtain ⟨_, _, hcl, hcr⟩ := hcache
        cases hle : l.isEmpty
        · have hre : r.isEmpty = true := by cases hr0 : r.isEmpty <;> simp_all
          have hr0 := NodeRef.eq_empty_of_isEmpty hre
          subst hr0
          cases l with
          | empty => simp [NodeRef.isEmpty] at hle
          | hash => simp [NodeRef.Resident] at hrl
          | node c =>
            simp only [Bool.not_false, ↓reduceIte, NodeRef.getNode, except_bind_ok,
              ]
            refine ⟨_, rfl, fun m hm => ?_, fun q => ?_⟩
            · simp only [PutRes.node, Option.some.injEq] at hm; subst hm
              exact ⟨(Trie.Resident_path c _).mpr hrl.1, (Trie.CacheOK_path _ c _).mpr hcl,
                (Trie.CanonNE_path c _).mpr hbelow.1⟩
            · rw [← hCN q]
              have := Trie.contents_merge p false vl vh cs c c.valueLength c.valueHash
                c.childrenSize q
              simp only [Bool.false_eq_true, ↓reduceIte] at this
              simp only [optContents, PutRes.node, rebuildSharedPath]
              rw [this]
        · have hl0 := NodeRef.eq_empty_of_isEmpty hle
          subst hl0
          cases r with
          | empty => simp [NodeRef.isEmpty] at hlr
          | hash => simp [NodeRef.Resident] at hrr
          | node c =>
            simp only [Bool.not_true, Bool.false_eq_true, ↓reduceIte,
              NodeRef.getNode, except_bind_ok]
            refine ⟨_, rfl, fun m hm => ?_, fun q => ?_⟩
            · simp only [PutRes.node, Option.some.injEq] at hm; subst hm
              exact ⟨(Trie.Resident_path c _).mpr hrr.1, (Trie.CacheOK_path _ c _).mpr hcr,
                (Trie.CanonNE_path c _).mpr hbelow.2⟩
            · rw [← hCN q]
              have := Trie.contents_merge p true vl vh cs c c.valueLength c.valueHash
                c.childrenSize q
              simp only [↓reduceIte] at this
              simp only [optContents, PutRes.node, rebuildSharedPath]
              rw [this]

theorem putSlice_spec (env : Env) (t : Trie) (k : List Bool) (value : Option Bytes)
    (hpre : Pre env.H t k (normValue value)) (hv : VOK (normValue value)) :
    ∃ r, t.putSlice env k value false = .ok r ∧ PostPut env.H t k (normValue value) r := by
  obtain ⟨r, hr, hpost⟩ := internalPut_spec env t k (normValue value) (normValue_idem value) hpre hv
  rw [putSlice]
  simp only [hr, except_bind_ok]
  obtain ⟨hN, hC⟩ := hpost
  have gen : ∀ N, r.node t = some N → ∃ r', (do
      let trie ← (pure N : Except Err Trie)
      if (normValue value).isSome = true then pure r else trie.coalesce env r : Except Err PutRes) = .ok r' ∧
      PostPut env.H t k (normValue value) r' := by
    intro N hrN
    obtain ⟨hres, hcache, hbelow, hsome, hcanon⟩ := hN N hrN
    simp only [except_pure, except_bind_ok]
    by_cases hvs : (normValue value).isSome = true
    · simp only [hvs, ↓reduceIte]
      exact ⟨_, rfl, fun m hm => by rw [hrN] at hm; cases hm; exact ⟨hres, hcache, hsome hvs⟩, hC⟩
    · simp only [hvs, Bool.false_eq_true, ↓reduceIte]
      have hCN : ∀ q, N.contents q = upd t.contents k (normValue value) q := by
        intro q; have := hC q; rw [hrN] at this; exact this
      obtain ⟨r', h1, h2, h3⟩ := coalesce_spec env t N r hrN _ hres hcache hbelow hcanon hCN
      exact ⟨r', h1, h2, h3⟩
  rcases r with _ | _ | n
  · exact gen t rfl
  · refine ⟨.null, rfl, fun m hm => by simp [PutRes.node] at hm, fun q => ?_⟩
    exact hC q
  · exact gen n rfl
termination_by (k.length, splitRank t k, 1)
decreasing_by apply Prod.Lex.right; apply Prod.Lex.right; omega

theorem internalPut_spec (env : Env) : ∀ (t : Trie) (k : List Bool) (value : Option Bytes),
    normValue value = value → Pre env.H t k value → VOK value →
    ∃ r, t.internalPut env k value false = .ok r ∧ PostIP env.H t k value r
  | ⟨p, v, l, r, vl, vh, cs⟩, k, value, hn, hpre, hv => by
    obtain ⟨hres, hcache, hbelow, hcanon⟩ := hpre
    have hvne := normValue_eq value hn
    rw [internalPut]
    simp only [commonPath_eq_lcp]
    by_cases hA : (lcp k p).length < p.length
    · ------------------------------------------------------------------ split branch
      simp only [hA, ↓reduceDIte]
      have hnp : ¬ p <+: k := fun h => by rw [lcp_of_prefix h] at hA; omega
      have hcanNE : Trie.CanonNE ⟨p, v, l, r, vl, vh, cs⟩ := by
        rcases hcanon with (h | ⟨hp0, _⟩) | ⟨_, hsh⟩
        · exact h
        · simp only at hp0; subst hp0; simp at hA
        · exact absurd hsh.2.2.1 hnp
      cases value with
      | none =>
        simp only [Option.isNone_none, ↓reduceIte]
        refine ⟨.same, rfl, fun n hn' => ?_, fun q => ?_⟩
        · simp only [PutRes.node, Option.some.injEq] at hn'; subst hn'
          exact ⟨hres, hcache, hbelow, by simp, Or.inl hcanNE⟩
        · simp only [optContents, PutRes.node, upd]
          split
          · next hq => subst hq; exact Trie.contents_not_prefix' _ _ _ _ _ _ _ _ hnp
          · rfl
      | some x =>
        simp only [Option.isNone_some, Bool.false_eq_true, ↓reduceIte]
        have hne := Trie.CanonNE_nonempty hcanNE hres
        obtain ⟨hs, hsplit⟩ := split_spec env _ hres hcache hne (commonPath k p)
        rw [hsplit, except_bind_ok]
        simp only [commonPath_eq_lcp] at hs ⊢
        obtain ⟨sres, scache, sbelow, sval, svl, sb1, sb2⟩ :=
          splitNode_props env.H _ hres hcache hcanNE (lcp k p)
        have hpreS : Pre env.H (splitNode env.H ⟨p, v, l, r, vl, vh, cs⟩ (lcp k p)) k (normValue (some x)) := by
          rw [hn]
          refine ⟨sres, scache, sbelow, Or.inr ⟨rfl, sval, svl, lcp_prefix_left k p, _, sb1, sb2, ?_⟩⟩
          simp only [splitNode]
          have hle := lcp_length_le_left k p
          by_cases hk : (lcp k p).length = k.length
          · exact Or.inl hk.symm
          · right
            have := lcp_next_ne k p (by omega) hA
            revert this; cases TrieKeySlice.get k (lcp k p).length <;>
              cases TrieKeySlice.get p (lcp k p).length <;> simp
        have hvS : VOK (normValue (some x)) := by rw [hn]; exact hv
        obtain ⟨rr, hrr, hpost⟩ := putSlice_spec env (splitNode env.H ⟨p, v, l, r, vl, vh, cs⟩ (lcp k p))
          k (some x) hpreS hvS
        rw [hn] at hpost
        simp only [hrr, except_bind_ok]
        obtain ⟨hN, hC⟩ := hpost
        have hcont : ∀ q, (splitNode env.H ⟨p, v, l, r, vl, vh, cs⟩ (lcp k p)).contents q =
            Trie.contents ⟨p, v, l, r, vl, vh, cs⟩ q :=
          splitNode_contents env.H _ _ (lcp_prefix_right k p) hA
        have post : ∀ n, rr.node (splitNode env.H ⟨p, v, l, r, vl, vh, cs⟩ (lcp k p)) = some n →
            n.Resident ∧ n.CacheOK env.H ∧ n.CanonBelow ∧ ((some x).isSome → n.CanonNE) ∧
              (n.CanonNE ∨ n.value = none) := by
          intro n hn'
          obtain ⟨a1, a2, a3⟩ := hN n hn'
          exact ⟨a1, a2, Trie.CanonNE_below a3, fun _ => a3, Or.inl a3⟩
        rcases rr with _ | _ | n
        · refine ⟨_, rfl, fun m hm => post m (by simpa [PutRes.node] using hm), fun q => ?_⟩
          have := hC q; simp only [optContents, PutRes.node] at this ⊢
          rw [this]; unfold upd; split
          · rfl
          · exact hcont q
        · refine ⟨_, rfl, fun m hm => by simp [PutRes.node] at hm, fun q => ?_⟩
          have := hC q; simp only [optContents, PutRes.node] at this ⊢
          rw [this]; unfold upd; split
          · rfl
          · exact hcont q
        · refine ⟨_, rfl, fun m hm => post m (by simpa [PutRes.node] using hm), fun q => ?_⟩
          have := hC q; simp only [optContents, PutRes.node] at this ⊢
          rw [this]; unfold upd; split
          · rfl
          · exact hcont q
    · simp only [hA, ↓reduceDIte]
      have hle := lcp_length_le_right k p
      have hpre : p <+: k := (lcp_eq_iff_prefix k p).mp (by omega)
      by_cases hB : p.length ≥ k.length
      · ------------------------------------------------------------------ key ends here
        have hpk : p = k := by
          obtain ⟨u, hu⟩ := hpre
          have : u.length = 0 := by have := congrArg List.length hu; simp at this; omega
          rw [List.eq_nil_of_length_eq_zero this] at hu; simpa using hu
        subst hpk
        simp only [hB, ↓reduceIte]
        rw [getDataLength_spec value hv, except_bind_ok]
        rw [Trie.getValue_resident env _ hres.1]
        generalize hdl : dataLen value = dl
        have hvok : ValueOK value dl := by
          cases value with
          | none => subst hdl; exact Or.inl ⟨rfl, rfl⟩
          | some x =>
            have hx0 := hvne x rfl
            have hx1 := hv x rfl
            subst hdl
            simp only [dataLen]
            exact Or.inr ⟨x, rfl, rfl, by cases x <;> simp_all, hx1⟩
        -- the new node when the value changes
        have hnew : ∀ q, Trie.contents ⟨p, value, l, r, dl, none, cs⟩ q =
            upd (Trie.contents ⟨p, v, l, r, vl, vh, cs⟩) p value q :=
          Trie.contents_value_update p v value l r vl vh cs dl none cs
        have hsame : (vl = dl ∧ v = value) → ∃ r_1,
            (pure PutRes.same : Except Err PutRes) = .ok r_1 ∧
              PostIP env.H ⟨p, v, l, r, vl, vh, cs⟩ p value r_1 := by
          rintro ⟨_, rfl⟩
          refine ⟨.same, rfl, fun n hn' => ?_, fun q => ?_⟩
          · simp only [PutRes.node, Option.some.injEq] at hn'; subst hn'
            refine ⟨hres, hcache, hbelow, fun hsome => ?_, ?_⟩
            · rcases hcanon with h | ⟨_, h⟩
              · rcases h with h | ⟨_, h2, _⟩
                · exact h
                · simp at h2; simp [h2] at hsome
              · exact absurd h.1 (by cases v <;> simp_all)
            · rcases hcanon with h | ⟨_, h⟩
              · rcases h with h | ⟨_, h2, _⟩
                · exact Or.inl h
                · exact Or.inr h2
              · exact Or.inr h.1
          · simp only [optContents, PutRes.node, upd]
            split
            · next hq => subst hq; exact Trie.contents_self _ _ _ _ _ _ _
            · rfl
        have hrest : ¬ (vl = dl ∧ v = value) → ∃ r_1,
            (if isEmptyTrieOf dl l r = true then pure PutRes.null
              else pure (PutRes.new ⟨p, value, l, r, dl, none, cs⟩) : Except Err PutRes) = .ok r_1 ∧
              PostIP env.H ⟨p, v, l, r, vl, vh, cs⟩ p value r_1 := by
          intro _
          split
          · next hE =>
            refine ⟨.null, rfl, fun m hm => by simp [PutRes.node] at hm, fun q => ?_⟩
            rw [← hnew q]
            have hres' : Trie.Resident ⟨p, value, l, r, dl, none, cs⟩ := ⟨hvok, hres.2⟩
            rw [Trie.contents_isEmpty hres' hE]; rfl
          · next hE =>
            refine ⟨_, rfl, fun n hn' => ?_, fun q => hnew q⟩
            simp only [PutRes.node, Option.some.injEq] at hn'; subst hn'
            have hc' : Trie.CacheOK env.H ⟨p, value, l, r, dl, none, cs⟩ := by
              obtain ⟨h1, _, h3, h4⟩ := hcache
              refine ⟨?_, by simp, h3, h4⟩
              rw [encS_snd] at h1 ⊢; exact h1
            refine ⟨⟨hvok, hres.2⟩, hc', hbelow, fun hsome => ⟨Or.inl (by cases value <;> simp_all),
              hbelow.1, hbelow.2⟩, ?_⟩
            cases value with
            | none => exact Or.inr rfl
            | some x => exact Or.inl ⟨Or.inl (by simp), hbelow.1, hbelow.2⟩
        by_cases hvl : vl = dl
        · rw [ite_eq_left_of_eq_true _ _ (eq_true hvl)]
          simp only [except_map_ok, except_bind_ok]
          by_cases hvv : v = value
          · rw [ite_eq_left_of_eq_true _ _ (by simp [hvv])]; exact hsame ⟨hvl, hvv⟩
          · rw [ite_eq_right_of_eq_false _ _ (by simp [hvv])]
            simp only [Bool.false_eq_true, ↓reduceIte]
            exact hrest (fun h => hvv h.2)
        · rw [ite_eq_right_of_eq_false _ _ (eq_false hvl)]
          simp only [except_pure, except_bind_ok, Bool.false_eq_true, ↓reduceIte]
          exact hrest (fun h => hvl h.1)
      · simp only [hB, ↓reduceIte]
        have hlt : p.length < k.length := by omega
        have hk : k = p ++ TrieKeySlice.get k p.length :: k.drop (p.length + 1) := by
          rw [← drop_eq_cons_get hlt]; exact eq_append_drop hpre
        have hvok : ∀ x, value = some x → ValueOK value x.length := by
          intro x hx; subst hx
          exact Or.inr ⟨x, rfl, rfl, List.length_pos_iff.mpr (hvne x rfl), hv x rfl⟩
        by_cases hE : Trie.isEmptyTrie ⟨p, v, l, r, vl, vh, cs⟩ = true
        · ---------------------------------------------------------------- empty trie: new leaf
          rw [ite_eq_left_of_eq_true _ _ (eq_true hE)]
          simp only [leaf, getDataLength_spec value hv, except_bind_ok, except_pure, except_map_ok]
          have hvok' : ValueOK value (dataLen value) := by
            cases value with
            | none => exact Or.inl ⟨rfl, rfl⟩
            | some x => exact hvok x rfl
          refine ⟨_, rfl, fun n hn' => ?_, fun q => ?_⟩
          · simp only [PutRes.node, Option.some.injEq] at hn'; subst hn'
            refine ⟨⟨hvok', trivial, trivial⟩, ⟨by simp [encS_snd, kidsSize, NodeRef.isEmpty], by simp,
              trivial, trivial⟩, ⟨trivial, trivial⟩, fun hs => ⟨Or.inl (Option.isSome_iff_ne_none.mp hs),
              trivial, trivial⟩, ?_⟩
            cases value with
            | none => exact Or.inr rfl
            | some x => exact Or.inl ⟨Or.inl (by simp), trivial, trivial⟩
          · simp only [optContents, PutRes.node, Trie.contents_leaf, upd]
            split
            · rfl
            · rw [Trie.contents_isEmpty hres hE]
        · ---------------------------------------------------------------- descend into a child
          rw [ite_eq_right_of_eq_false _ _ (eq_false hE)]
          have hEf : Trie.isEmptyTrie ⟨p, v, l, r, vl, vh, cs⟩ = false := by simpa using hE
          generalize hpos : TrieKeySlice.get k p.length = pos at hk ⊢
          obtain ⟨c, hc1, hc2, cres, ccache, ccanon⟩ :=
            retrieveNodeOrEmpty_spec env _ hres hcache hbelow pos
          rw [hc1, except_bind_ok]
          have hcb : c.CanonBelow := by
            rcases ccanon with h | ⟨_, _, _, h4, h5⟩
            · exact Trie.CanonNE_below h
            · obtain ⟨_, _, cl, cr, _, _, _⟩ := c; simp only at h4 h5; subst h4 h5; exact ⟨trivial, trivial⟩
          have hpreC : Pre env.H c (k.drop (p.length + 1)) (normValue value) :=
            ⟨cres, ccache, hcb, Or.inl ccanon⟩
          have hvC : VOK (normValue value) := by rw [hn]; exact hv
          rw [slice_eq_drop]
          obtain ⟨rr, hrr, hpost⟩ := putSlice_spec env c (k.drop (p.length + 1)) value hpreC hvC
          rw [hn] at hpost
          rw [hrr, except_bind_ok]
          obtain ⟨hN, hC⟩ := hpost
          -- contents of the reference at `pos`
          have href : ∀ q, NodeRef.contents (getNodeReference ⟨p, v, l, r, vl, vh, cs⟩ pos) q = c.contents q := by
            intro q; rw [← hc2, NodeRef.contents_ofNode c cres]
          -- the other child is non-empty when inserting into a value-less node
          have hother : value.isSome = true → v = none →
              getNodeReference ⟨p, v, l, r, vl, vh, cs⟩ (!pos) ≠ .empty := by
            intro hs hv0
            rcases hcanon with (h | ⟨_, _, h3, h4, h5⟩) | ⟨_, h⟩
            · rcases h with ⟨h1 | ⟨h1, h2⟩, _, _⟩
              · exact absurd hv0 h1
              · cases pos <;> simp [getNodeReference, h1, h2]
            · exfalso; apply hE
              simp only at h3 h4 h5; subst h3 h4 h5
              simp [isEmptyTrie, isEmptyTrieOf, NodeRef.isEmpty]
            · obtain ⟨_, _, _, b, hb1, hb2, hb3⟩ := h
              rcases hb3 with hb3 | hb3
              · first | (simp only at hb3; omega) | omega
              · first | (simp only at hb3) | skip
                rw [hpos] at hb3; subst hb3; simpa using hb1
          by_cases hsm : rr.isSame = true
          · ------------------------------------------------------------ child unchanged
            rw [ite_eq_left_of_eq_true _ _ (eq_true hsm)]
            have hrr' : rr = .same := by
              cases rr
              · rfl
              · simp [PutRes.isSame] at hsm
              · simp [PutRes.isSame] at hsm
            subst hrr'
            have hcsub : c.contents (k.drop (p.length + 1)) = value := by
              have := hC (k.drop (p.length + 1)); simpa [optContents, PutRes.node, upd] using this
            have htk : Trie.contents ⟨p, v, l, r, vl, vh, cs⟩ k = value := by
              rw [hk, Trie.contents_mk]
              cases pos
              · rw [← hcsub, ← href]; rfl
              · rw [← hcsub, ← href]; rfl
            refine ⟨.same, rfl, fun n hn' => ?_, fun q => ?_⟩
            · simp only [PutRes.node, Option.some.injEq] at hn'; subst hn'
              have hnotempty_side : value.isSome = true → ¬ (c.isEmptyTrie = true) := by
                intro hs he
                rw [Trie.contents_isEmpty cres he] at hcsub
                rw [← hcsub] at hs; simp at hs
              refine ⟨hres, hcache, hbelow, fun hs => ?_, ?_⟩
              · rcases hcanon with (h | ⟨_, _, h3, h4, h5⟩) | ⟨_, hss⟩
                · exact h
                · exfalso; apply hE; simp only at h3 h4 h5; subst h3 h4 h5
                  simp [isEmptyTrie, isEmptyTrieOf, NodeRef.isEmpty]
                · obtain ⟨_, _, _, b, hb1, hb2, hb3⟩ := hss
                  exfalso; apply hnotempty_side hs
                  rcases hb3 with hb3 | hb3
                  · first | (simp only at hb3; omega) | omega
                  · first | (simp only at hb3) | skip
                    rw [hpos] at hb3; subst hb3
                    rw [hb2] at hc2
                    simp only [NodeRef.ofNode] at hc2; split at hc2
                    · assumption
                    · simp at hc2
              · rcases hcanon with (h | ⟨_, h2, _⟩) | ⟨_, hss⟩
                · exact Or.inl h
                · exact Or.inr h2
                · exact Or.inr hss.1
            · simp only [optContents, PutRes.node, upd]
              split
              · next hq => subst hq; exact htk
              · rfl
          · ------------------------------------------------------------ child changed
            rw [ite_eq_right_of_eq_false _ _ (eq_false hsm)]
            have hnode : rr.toOpt = rr.node c := by
              cases rr
              · simp [PutRes.isSame] at hsm
              · rfl
              · rfl
            obtain ⟨Rres, Rcache, Rcanon⟩ := NodeRef.ofNode_props env.H rr.toOpt (by rw [hnode]; exact hN)
            have hRc : ∀ q, NodeRef.contents (NodeRef.ofNode rr.toOpt) q =
                upd (NodeRef.contents (getNodeReference ⟨p, v, l, r, vl, vh, cs⟩ pos)) (k.drop (p.length + 1)) value q := by
              intro q
              have hrefF : NodeRef.contents (getNodeReference ⟨p, v, l, r, vl, vh, cs⟩ pos) = c.contents :=
                funext href
              rw [hrefF, ← hC q, hnode]
              cases hto : rr.node c with
              | none => rfl
              | some n => exact NodeRef.contents_ofNode n (hN n hto).1 q
            obtain ⟨nl, nr, cs', hrc, hshape, hcs'⟩ :=
              replaceChild_spec env _ hres hcache pos _ Rres Rcache
            rw [hrc, except_bind_ok]
            simp only
            -- contents of the new node
            have hNc : ∀ q, Trie.contents ⟨p, v, nl, nr, vl, vh, cs'⟩ q =
                upd (Trie.contents ⟨p, v, l, r, vl, vh, cs⟩) k value q := by
              intro q
              rw [hk]
              cases pos
              · simp only [↓reduceIte] at hshape; obtain ⟨h1, h2⟩ := hshape
                rw [h1, h2]
                exact Trie.contents_left_update p v l _ r vl vh cs vl vh cs' _ value hRc q
              · simp only [Bool.true_eq_false, ↓reduceIte] at hshape; obtain ⟨h1, h2⟩ := hshape
                rw [h1, h2]
                exact Trie.contents_right_update p v l r _ vl vh cs vl vh cs' _ value hRc q
            have hNres : Trie.Resident ⟨p, v, nl, nr, vl, vh, cs'⟩ := by
              refine ⟨hres.1, ?_, ?_⟩ <;> cases pos <;> simp only [↓reduceIte, Bool.true_eq_false] at hshape <;>
                obtain ⟨rfl, rfl⟩ := hshape <;> first | exact Rres | exact hres.2.1 | exact hres.2.2
            split
            · next hEN =>
              refine ⟨.null, rfl, fun m hm => by simp [PutRes.node] at hm, fun q => ?_⟩
              rw [← hNc q, Trie.contents_isEmpty hNres hEN]; rfl
            · next hEN =>
              refine ⟨_, rfl, fun n hn' => ?_, fun q => hNc q⟩
              simp only [PutRes.node, Option.some.injEq] at hn'; subst hn'
              have hNcache : Trie.CacheOK env.H ⟨p, v, nl, nr, vl, vh, cs'⟩ := by
                refine ⟨?_, hcache.2.1, ?_, ?_⟩
                · rw [encS_snd]; exact hcs'
                all_goals cases pos <;> simp only [↓reduceIte, Bool.true_eq_false] at hshape <;>
                  obtain ⟨rfl, rfl⟩ := hshape <;> first | exact Rcache | exact hcache.2.2.1 | exact hcache.2.2.2
              have hNbelow : Trie.CanonBelow ⟨p, v, nl, nr, vl, vh, cs'⟩ := by
                refine ⟨?_, ?_⟩ <;> cases pos <;> simp only [↓reduceIte, Bool.true_eq_false] at hshape <;>
                  obtain ⟨rfl, rfl⟩ := hshape <;> first | exact Rcanon | exact hbelow.1 | exact hbelow.2
              refine ⟨hNres, hNcache, hNbelow, fun hs => ?_, ?_⟩
              · refine ⟨?_, hNbelow.1, hNbelow.2⟩
                by_cases hv0 : v = none
                · right
                  have ho := hother hs hv0
                  -- the new child is non-empty: its contents has `value` at the sub-key
                  have hnew : NodeRef.ofNode rr.toOpt ≠ .empty := by
                    intro h0
                    have := hRc (k.drop (p.length + 1))
                    rw [h0] at this
                    simp only [NodeRef.contents, upd, ↓reduceIte] at this
                    rw [← this] at hs; exact absurd hs (by simp)
                  cases pos <;> simp only [↓reduceIte, Bool.true_eq_false] at hshape <;>
                    obtain ⟨rfl, rfl⟩ := hshape
                  · exact ⟨hnew, by simpa [getNodeReference] using ho⟩
                  · exact ⟨by simpa [getNodeReference] using ho, hnew⟩
                · left; exact hv0
              · by_cases hv0 : v = none
                · exact Or.inr hv0
                · exact Or.inl ⟨Or.inl hv0, hNbelow.1, hNbelow.2⟩
termination_by t k _ _ _ _ => (k.length, splitRank t k, 0)
decreasing_by
  · apply Prod.Lex.right; apply Prod.Lex.left
    rw [splitRank_split k p _ (by simp [splitNode, commonPath_eq_lcp])]
    have : splitRank ⟨p, v, l, r, vl, vh, cs⟩ k = 1 := by
      unfold splitRank; simp only [commonPath_eq_lcp]; split <;> simp_all
    omega
  · apply Prod.Lex.left
    simp only [List.length_drop]; omega
end

/-! ## Top-level `put` / `delete` / `get` -/

/-- The well-formedness invariant: resident, caches consistent, canonical shape. -/
def Trie.WF (H : Bytes → Bytes) (t : Trie) : Prop := t.Resident ∧ t.CacheOK H ∧ t.Canon

theorem Trie.WF_empty (H : Bytes → Bytes) : Trie.empty.WF H := by
  refine ⟨?_, ?_, Or.inr ⟨rfl, rfl, rfl, rfl, rfl⟩⟩
  · simp [Trie.empty, Trie.Resident, ValueOK, NodeRef.Resident]
  · simp [Trie.empty, Trie.CacheOK, NodeRef.CacheOK, encS_snd, kidsSize, NodeRef.isEmpty]

theorem Trie.contents_empty (q : List Bool) : Trie.empty.contents q = none := by
  simp [Trie.empty, Trie.contents_leaf]

theorem Trie.Canon_below {t : Trie} (h : t.Canon) : t.CanonBelow := by
  rcases h with h | ⟨_, _, _, h4, h5⟩
  · exact Trie.CanonNE_below h
  · obtain ⟨_, _, l, r, _, _, _⟩ := t; simp only at h4 h5; subst h4 h5; exact ⟨trivial, trivial⟩

/-- **put**: on a well-formed trie, `put(key, value)` succeeds (for values that fit a `Uint24`),
yields a well-formed trie, and changes the contents exactly at `key`, to `value` if it is non-empty
and to "absent" if it is empty. -/
theorem Trie.put_spec (env : Env) (t : Trie) (ht : t.WF env.H) (key : Bytes) (value : Option Bytes)
    (hv : VOK (normValue value)) :
    ∃ t', t.put env key value = .ok t' ∧ t'.WF env.H ∧
      ∀ q, t'.contents q = upd t.contents (TrieKeySlice.fromKey key) (normValue value) q := by
  obtain ⟨hres, hc, hcan⟩ := ht
  obtain ⟨r, hr, hN, hC⟩ := putSlice_spec env t (TrieKeySlice.fromKey key) value
    ⟨hres, hc, Trie.Canon_below hcan, Or.inl hcan⟩ hv
  unfold Trie.put
  rw [hr, except_bind_ok]
  rcases r with _ | _ | n
  · exact ⟨t, rfl, ⟨hres, hc, hcan⟩, fun q => hC q⟩
  · exact ⟨Trie.empty, rfl, Trie.WF_empty env.H, fun q => by rw [Trie.contents_empty]; exact hC q⟩
  · obtain ⟨a, b, c⟩ := hN n rfl
    exact ⟨n, rfl, ⟨a, b, Or.inl c⟩, fun q => hC q⟩

/-- **get after put**: `get(put(t, k, v), k) = v` for non-empty `v`, `null` for empty `v`, and other
keys are unchanged. -/
theorem Trie.get_put (env : Env) (t : Trie) (ht : t.WF env.H) (key : Bytes) (value : Option Bytes)
    (hv : VOK (normValue value)) :
    ∃ t', t.put env key value = .ok t' ∧ t'.WF env.H ∧
      t'.get env key = .ok (normValue value) ∧
      ∀ key', key' ≠ key → t'.get env key' = t.get env key' := by
  obtain ⟨t', h1, h2, h3⟩ := Trie.put_spec env t ht key value hv
  refine ⟨t', h1, h2, ?_, fun key' hne => ?_⟩
  · rw [Trie.get_eq_contents env t' h2.1, h3]; simp [upd]
  · rw [Trie.get_eq_contents env t' h2.1, Trie.get_eq_contents env t ht.1, h3]
    have : TrieKeySlice.fromKey key' ≠ TrieKeySlice.fromKey key := fun h => hne (fromKey_injective h)
    simp [upd, this]

theorem normValue_some (x : Bytes) (h : x ≠ []) : normValue (some x) = some x := by
  simp [normValue]; exact h

/-- `delete(k)` is `put(k, null)`, and `put(k, [])` behaves the same (Trie.java:470-472, 774-776). -/
theorem Trie.delete_eq_put_empty (env : Env) (t : Trie) (key : Bytes) :
    t.delete env key = t.put env key none ∧ t.put env key (some []) = t.put env key none := by
  refine ⟨rfl, ?_⟩
  unfold Trie.put putSlice
  simp [normValue]

/-- **get after delete**. -/
theorem Trie.get_delete (env : Env) (t : Trie) (ht : t.WF env.H) (key : Bytes) :
    ∃ t', t.delete env key = .ok t' ∧ t'.WF env.H ∧ t'.get env key = .ok none ∧
      ∀ key', key' ≠ key → t'.get env key' = t.get env key' :=
  Trie.get_put env t ht key none (by intro x hx; simp [normValue] at hx)

end RskjTrie
