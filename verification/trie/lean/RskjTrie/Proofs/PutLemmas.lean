import RskjTrie.Proofs.Contents
/-!
# Lemmas for the `put` proofs: 64-bit arithmetic, canonical shape, contents of constructed nodes
-/
namespace RskjTrie
open Trie TrieKeySlice

/-! ## `long` arithmetic -/

theorem wrap64_int (x : Int) : ((wrap64 x : Nat) : Int) = x % 2 ^ 64 := by
  unfold wrap64; rw [Int.toNat_of_nonneg (Int.emod_nonneg _ (by decide))]
theorem wrap64_lt (x : Int) : wrap64 x < 2 ^ 64 := by
  have := wrap64_int x; have := Int.emod_lt_of_pos x (show (0:Int) < 2^64 by decide); omega
theorem wrap64_congr (x y : Int) (h : x % 2 ^ 64 = y % 2 ^ 64) : wrap64 x = wrap64 y := by
  unfold wrap64; rw [h]
theorem wrap64_nat (n : Nat) (h : n < 2 ^ 64) : wrap64 n = n := by
  have := wrap64_int n; have : (n : Int) % 2 ^ 64 = n := Int.emod_eq_of_lt (by omega) (by omega); omega

/-! ## Sizes -/

/-- The from-scratch `childrenSize` of a node with children `l`, `r`. -/
def kidsSize (H : Bytes → Bytes) (l r : NodeRef Trie) : Nat :=
  if l.isEmpty && r.isEmpty then 0 else wrap64 (((NodeRef.encS H l).2.1 : Int) + (NodeRef.encS H r).2.1)

theorem encS_snd (H : Bytes → Bytes) (p v l r vl vh cs) :
    (Trie.encS H ⟨p, v, l, r, vl, vh, cs⟩).2 = kidsSize H l r := by
  simp [Trie.encS, kidsSize]

theorem NodeRef.size_lt (H : Bytes → Bytes) (r : NodeRef Trie) (h : r.Resident) :
    (NodeRef.encS H r).2.1 < 2 ^ 64 := by
  cases r with
  | empty => simp [NodeRef.encS]
  | hash => simp [NodeRef.Resident] at h
  | node c => simp only [NodeRef.encS]; exact wrap64_lt _

theorem NodeRef.size_empty (H : Bytes → Bytes) : (NodeRef.encS H .empty).2.1 = 0 := rfl

theorem kidsSize_lt (H : Bytes → Bytes) (l r : NodeRef Trie) : kidsSize H l r < 2 ^ 64 := by
  unfold kidsSize; split
  · decide
  · exact wrap64_lt _

theorem NodeRef.size_of_isEmpty (H : Bytes → Bytes) (r : NodeRef Trie) (h : r.isEmpty = true) :
    (NodeRef.encS H r).2.1 = 0 := by
  cases r <;> simp_all [NodeRef.isEmpty, NodeRef.encS]

theorem wrap_arith (a b c : Nat) (ha : a < 2 ^ 64) (hb : b < 2 ^ 64) (_hc : c < 2 ^ 64)
    (x y : Bool) (hx : x = true → a = 0) (hy : y = true → b = 0) (z : Bool) (hz : z = true → c = 0) :
    wrap64 (((if x && y then 0 else wrap64 ((a : Int) + b)) : Nat) - a + c) =
      (if z && y then 0 else wrap64 ((c : Int) + b)) := by
  have w1 := wrap64_int ((a : Int) + b)
  have w2 := wrap64_int ((c : Int) + b)
  have z0 : wrap64 ((0 : Nat) : Int) = 0 := wrap64_nat 0 (by decide)
  cases x <;> cases y <;> cases z <;> simp only [Bool.false_and, Bool.and_false,
    Bool.false_eq_true, ↓reduceIte, Bool.and_self] <;>
    simp only [forall_const, Bool.false_eq_true, false_implies] at hx hy hz
  all_goals first
    | (rw [← z0]; apply wrap64_congr; omega)
    | (apply wrap64_congr; omega)

/-- The incremental update of Trie.java:901 (left) yields the from-scratch value. -/
theorem kidsSize_update_left (H : Bytes → Bytes) (l l' r : NodeRef Trie) (hl : l.Resident)
    (hl' : l'.Resident) (hr : r.Resident) :
    wrap64 ((kidsSize H l r : Int) - (NodeRef.encS H l).2.1 + (NodeRef.encS H l').2.1) =
      kidsSize H l' r := by
  unfold kidsSize
  exact wrap_arith _ _ _ (NodeRef.size_lt H l hl) (NodeRef.size_lt H r hr) (NodeRef.size_lt H l' hl')
    _ _ (NodeRef.size_of_isEmpty H l) (NodeRef.size_of_isEmpty H r) _ (NodeRef.size_of_isEmpty H l')

/-- The incremental update of Trie.java:908 (right) yields the from-scratch value. -/
theorem kidsSize_update_right (H : Bytes → Bytes) (l r r' : NodeRef Trie) (hl : l.Resident)
    (hr : r.Resident) (hr' : r'.Resident) :
    wrap64 ((kidsSize H l r : Int) - (NodeRef.encS H r).2.1 + (NodeRef.encS H r').2.1) =
      kidsSize H l r' := by
  have e1 : kidsSize H l r = kidsSize H r l := by
    unfold kidsSize; rw [Bool.and_comm]; congr 2; omega
  have e2 : kidsSize H l r' = kidsSize H r' l := by
    unfold kidsSize; rw [Bool.and_comm]; congr 2; omega
  rw [e1, e2]; exact kidsSize_update_left H r r' l hr hr' hl

/-! ## Canonical shape -/

mutual
/-- A non-empty node in canonical (Patricia) shape: it has a value or two children, and so do
all its descendants. -/
def Trie.CanonNE : Trie → Prop
  | ⟨_, v, l, r, _, _, _⟩ => (v ≠ none ∨ (l ≠ .empty ∧ r ≠ .empty)) ∧ NodeRef.Canon l ∧ NodeRef.Canon r
def NodeRef.Canon : NodeRef Trie → Prop
  | .empty => True
  | .hash _ => False
  | .node t => Trie.CanonNE t
end

/-- Children are canonical. -/
def Trie.CanonBelow (t : Trie) : Prop := NodeRef.Canon t.left ∧ NodeRef.Canon t.right

/-- A canonical trie: a canonical non-empty node, or the empty trie `new Trie(store)`. -/
def Trie.Canon (t : Trie) : Prop :=
  t.CanonNE ∨ (t.sharedPath = [] ∧ t.value = none ∧ t.valueLength = 0 ∧ t.left = .empty ∧ t.right = .empty)

theorem Trie.CanonNE_below {t : Trie} (h : t.CanonNE) : t.CanonBelow := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t; exact ⟨h.2.1, h.2.2⟩

theorem Trie.CanonNE_nonempty {t : Trie} (h : t.CanonNE) (hr : t.Resident) : t.isEmptyTrie = false := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
  obtain ⟨h1, _, _⟩ := h
  obtain ⟨hv, _, _⟩ := hr
  simp only [isEmptyTrie, isEmptyTrieOf]
  rcases h1 with h1 | ⟨hl, hr⟩
  · rcases hv with ⟨rfl, _⟩ | ⟨x, _, _, hpos, _⟩
    · exact absurd rfl h1
    · simp [hpos]
  · split
    · rfl
    · cases l <;> cases r <;> simp_all [NodeRef.isEmpty]

/-! ## Contents of constructed nodes -/

/-- Point update of a map. -/
def upd (f : List Bool → Option Bytes) (k : List Bool) (x : Option Bytes) (q : List Bool) :
    Option Bytes := if q = k then x else f q

theorem eq_append_drop {p q : List Bool} (h : p <+: q) : q = p ++ q.drop p.length := by
  obtain ⟨t, rfl⟩ := h; simp

theorem Trie.contents_not_prefix (t : Trie) (k : List Bool) (h : ¬ t.sharedPath <+: k) :
    t.contents k = none := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t; simp only [Trie.contents]; simp_all

theorem Trie.contents_mk (p v l r vl vh cs) (rest : List Bool) :
    (Trie.contents ⟨p, v, l, r, vl, vh, cs⟩ (p ++ rest)) =
      match rest with
      | [] => v
      | false :: q => NodeRef.contents l q
      | true :: q => NodeRef.contents r q := by
  cases rest with
  | nil => simp [Trie.contents]
  | cons b q => cases b <;> simp [Trie.contents]

theorem Trie.contents_not_prefix' (p v l r vl vh cs) (k : List Bool) (h : ¬ p <+: k) :
    Trie.contents ⟨p, v, l, r, vl, vh, cs⟩ k = none :=
  Trie.contents_not_prefix ⟨p, v, l, r, vl, vh, cs⟩ k h

theorem Trie.contents_self (p v l r vl vh cs) :
    Trie.contents ⟨p, v, l, r, vl, vh, cs⟩ p = v := by
  have := Trie.contents_mk p v l r vl vh cs []; simpa using this

theorem Trie.contents_fields (p v l r vl vh cs vl' vh' cs') (q : List Bool) :
    Trie.contents ⟨p, v, l, r, vl, vh, cs⟩ q = Trie.contents ⟨p, v, l, r, vl', vh', cs'⟩ q := by
  simp [Trie.contents]

/-- Generic contents characterisation by cases on the key. -/
theorem Trie.contents_cases (P : List Bool → Option Bytes → Prop) (p v l r vl vh cs)
    (hnp : ∀ q, ¬ p <+: q → P q none)
    (hv : P p v)
    (hl : ∀ q', P (p ++ false :: q') (NodeRef.contents l q'))
    (hr : ∀ q', P (p ++ true :: q') (NodeRef.contents r q')) :
    ∀ q, P q (Trie.contents ⟨p, v, l, r, vl, vh, cs⟩ q) := by
  intro q
  by_cases h : p <+: q
  · rw [eq_append_drop h, Trie.contents_mk]
    generalize q.drop p.length = rest
    match rest with
    | [] => simpa using hv
    | false :: q' => exact hl q'
    | true :: q' => exact hr q'
  · rw [Trie.contents_not_prefix _ _ h]; exact hnp q h

theorem Trie.contents_value_update (p v x l r vl vh cs vl' vh' cs') (q : List Bool) :
    Trie.contents ⟨p, x, l, r, vl', vh', cs'⟩ q = upd (Trie.contents ⟨p, v, l, r, vl, vh, cs⟩) p x q := by
  unfold upd
  revert q
  apply Trie.contents_cases (fun q o => o = if q = p then x else Trie.contents ⟨p, v, l, r, vl, vh, cs⟩ q)
  · intro q h; have : q ≠ p := fun e => h (e ▸ List.prefix_refl _)
    simp [this, Trie.contents_not_prefix' _ _ _ _ _ _ _ _ h]
  · simp
  · intro q'; simp [Trie.contents_mk]
  · intro q'; simp [Trie.contents_mk]

theorem Trie.contents_left_update (p v l l' r vl vh cs vl' vh' cs') (sub : List Bool) (x : Option Bytes)
    (h : ∀ q, NodeRef.contents l' q = upd (NodeRef.contents l) sub x q) (q : List Bool) :
    Trie.contents ⟨p, v, l', r, vl', vh', cs'⟩ q =
      upd (Trie.contents ⟨p, v, l, r, vl, vh, cs⟩) (p ++ false :: sub) x q := by
  unfold upd
  revert q
  apply Trie.contents_cases (fun q o => o = if q = p ++ false :: sub then x
    else Trie.contents ⟨p, v, l, r, vl, vh, cs⟩ q)
  · intro q hq; have : q ≠ p ++ false :: sub := fun e => hq (e ▸ List.prefix_append _ _)
    simp [this, Trie.contents_not_prefix' _ _ _ _ _ _ _ _ hq]
  · simp [Trie.contents_self]
  · intro q'; rw [h q']; simp [upd, Trie.contents_mk]
  · intro q'; simp [Trie.contents_mk]

theorem Trie.contents_right_update (p v l r r' vl vh cs vl' vh' cs') (sub : List Bool) (x : Option Bytes)
    (h : ∀ q, NodeRef.contents r' q = upd (NodeRef.contents r) sub x q) (q : List Bool) :
    Trie.contents ⟨p, v, l, r', vl', vh', cs'⟩ q =
      upd (Trie.contents ⟨p, v, l, r, vl, vh, cs⟩) (p ++ true :: sub) x q := by
  unfold upd
  revert q
  apply Trie.contents_cases (fun q o => o = if q = p ++ true :: sub then x
    else Trie.contents ⟨p, v, l, r, vl, vh, cs⟩ q)
  · intro q hq; have : q ≠ p ++ true :: sub := fun e => hq (e ▸ List.prefix_append _ _)
    simp [this, Trie.contents_not_prefix' _ _ _ _ _ _ _ _ hq]
  · simp [Trie.contents_self]
  · intro q'; simp [Trie.contents_mk]
  · intro q'; rw [h q']; simp [upd, Trie.contents_mk]

theorem merge_aux (a : List Bool) (b : Bool) (c cv cl cr cvl cvh ccs vl' vh' cs') (q' : List Bool) :
    Trie.contents ⟨c, cv, cl, cr, cvl, cvh, ccs⟩ q' =
      Trie.contents ⟨a ++ b :: c, cv, cl, cr, vl', vh', cs'⟩ (a ++ b :: q') := by
  by_cases hc : c <+: q'
  · rw [eq_append_drop hc]
    rw [show a ++ b :: (c ++ q'.drop c.length) = (a ++ b :: c) ++ q'.drop c.length by simp]
    rw [Trie.contents_mk, Trie.contents_mk]
  · rw [Trie.contents_not_prefix' _ _ _ _ _ _ _ _ hc, Trie.contents_not_prefix']
    intro h; apply hc; simpa using h

/-- A value-less node with a single child `C` at side `b` has the contents of the merged node
`a ++ b :: C.sharedPath` (used for `split` and for delete-coalescing). -/
theorem Trie.contents_merge (a : List Bool) (b : Bool) (vl vh cs : _) (C : Trie) (vl' vh' cs') (q : List Bool) :
    Trie.contents ⟨a, none, (if b then .empty else .node C), (if b then .node C else .empty), vl, vh, cs⟩ q =
      Trie.contents ⟨a ++ b :: C.sharedPath, C.value, C.left, C.right, vl', vh', cs'⟩ q := by
  obtain ⟨c, cv, cl, cr, cvl, cvh, ccs⟩ := C
  revert q
  apply Trie.contents_cases (fun q o => o = Trie.contents ⟨a ++ b :: c, cv, cl, cr, vl', vh', cs'⟩ q)
  · intro q hq
    rw [Trie.contents_not_prefix]; intro h; exact hq (List.IsPrefix.trans (List.prefix_append _ _) h)
  · rw [Trie.contents_not_prefix]; intro h; have := h.length_le; simp at this; omega
  · intro q'
    cases b
    · simp only [Bool.false_eq_true, ↓reduceIte, NodeRef.contents]
      exact merge_aux a false c cv cl cr cvl cvh ccs vl' vh' cs' q'
    · simp only [↓reduceIte, NodeRef.contents]
      rw [Trie.contents_not_prefix]; simp
  · intro q'
    cases b
    · simp only [Bool.false_eq_true, ↓reduceIte, NodeRef.contents]
      rw [Trie.contents_not_prefix]; simp
    · simp only [↓reduceIte, NodeRef.contents]
      exact merge_aux a true c cv cl cr cvl cvh ccs vl' vh' cs' q'

theorem Trie.contents_leaf (k : List Bool) (x : Option Bytes) (vl vh cs) (q : List Bool) :
    Trie.contents ⟨k, x, .empty, .empty, vl, vh, cs⟩ q = if q = k then x else none := by
  revert q
  apply Trie.contents_cases (fun q o => o = if q = k then x else none)
  · intro q hq; have : q ≠ k := fun e => hq (e ▸ List.prefix_refl _); simp [this]
  · simp
  · intro q'; simp [NodeRef.contents]
  · intro q'; simp [NodeRef.contents]

end RskjTrie
