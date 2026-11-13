import RskjTrie.Proofs.Put
/-!
# Proofs: canonical shape — equal contents ⇒ equal tries ⇒ equal message and root hash

Two well-formed tries with the same key/value contents are equal up to the caches
(`valueHash`, `childrenSize`), which the encoder does not read once they are consistent. Hence
the serialization and the root hash of a trie built by any sequence of puts/deletes from the empty
trie depend only on the final contents, not on the order or history of the operations.
-/
namespace RskjTrie
open Trie TrieKeySlice

mutual
/-- Clear the caches (`valueHash`, `childrenSize`) everywhere. -/
def Trie.erase : Trie → Trie
  | ⟨p, v, l, r, vl, _, _⟩ => ⟨p, v, NodeRef.erase l, NodeRef.erase r, vl, none, none⟩
def NodeRef.erase : NodeRef Trie → NodeRef Trie
  | .node t => .node (Trie.erase t)
  | x => x
end

mutual
theorem Trie.encS_erase (H : Bytes → Bytes) : ∀ t : Trie, Trie.encS H t.erase = Trie.encS H t
  | ⟨p, v, l, r, vl, vh, cs⟩ => by
    have hl := NodeRef.encS_erase H l
    have hr := NodeRef.encS_erase H r
    have el : (NodeRef.erase l).isEmpty = l.isEmpty := by cases l <;> rfl
    have er : (NodeRef.erase r).isEmpty = r.isEmpty := by cases r <;> rfl
    simp only [Trie.erase, Trie.encS, hl, hr, el, er]
theorem NodeRef.encS_erase (H : Bytes → Bytes) : ∀ r : NodeRef Trie, NodeRef.encS H r.erase = NodeRef.encS H r
  | .empty => rfl
  | .hash _ => rfl
  | .node c => by
    have hc := Trie.encS_erase H c
    have e1 : (Trie.erase c).isTerminal = c.isTerminal := by
      obtain ⟨p, v, l, r, vl, vh, cs⟩ := c
      cases l <;> cases r <;> rfl
    have e2 : (Trie.erase c).valueLength = c.valueLength := by obtain ⟨p, v, l, r, vl, vh, cs⟩ := c; rfl
    have e3 : (Trie.erase c).isEmptyTrie = c.isEmptyTrie := by
      obtain ⟨p, v, l, r, vl, vh, cs⟩ := c
      cases l <;> cases r <;> rfl
    simp only [NodeRef.erase, NodeRef.encS, hc, e1, e2, e3]
end

theorem Trie.hashS_erase (H : Bytes → Bytes) (t : Trie) : t.erase.hashS H = t.hashS H := by
  have e3 : (Trie.erase t).isEmptyTrie = t.isEmptyTrie := by
    obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
    cases l <;> cases r <;> rfl
  simp [Trie.hashS, e3, Trie.encS_erase]

/-! ## Support -/

theorem Trie.contents_prefix (t : Trie) (q : List Bool) (h : t.contents q ≠ none) :
    t.sharedPath <+: q := by
  exact Classical.byContradiction fun hn => h (Trie.contents_not_prefix t q hn)

mutual
/-- A canonical non-empty node stores at least one value. -/
theorem Trie.support_nonempty : ∀ t : Trie, t.CanonNE → ∃ q, t.contents q ≠ none
  | ⟨p, v, l, r, vl, vh, cs⟩, ⟨h1, hl, hr⟩ => by
    rcases h1 with h1 | ⟨hl0, _⟩
    · exact ⟨p, by rw [Trie.contents_self]; exact h1⟩
    · obtain ⟨q, hq⟩ := NodeRef.support_nonempty l hl hl0
      refine ⟨p ++ false :: q, ?_⟩
      rw [Trie.contents_mk]; exact hq
theorem NodeRef.support_nonempty : ∀ r : NodeRef Trie, r.Canon → r ≠ .empty →
    ∃ q, NodeRef.contents r q ≠ none
  | .empty, _, h => absurd rfl h
  | .hash _, h, _ => absurd h (by simp [NodeRef.Canon])
  | .node c, h, _ => Trie.support_nonempty c h
end

/-- A common prefix of all stored keys of a canonical node is a prefix of its shared path. -/
theorem Trie.prefix_of_all (t : Trie) (ht : t.CanonNE) (s : List Bool)
    (hs : ∀ q, t.contents q ≠ none → s <+: q) : s <+: t.sharedPath := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
  obtain ⟨h1, hl, hr⟩ := ht
  rcases h1 with h1 | ⟨hl0, hr0⟩
  · exact hs p (by rw [Trie.contents_self]; exact h1)
  · obtain ⟨q0, hq0⟩ := NodeRef.support_nonempty l hl hl0
    obtain ⟨q1, hq1⟩ := NodeRef.support_nonempty r hr hr0
    have a := hs (p ++ false :: q0) (by rw [Trie.contents_mk]; exact hq0)
    have b := hs (p ++ true :: q1) (by rw [Trie.contents_mk]; exact hq1)
    show s <+: p
    by_cases hlen : s.length ≤ p.length
    · exact List.prefix_of_prefix_length_le a (List.prefix_append p _) hlen
    · exfalso
      have ea := List.prefix_iff_eq_take.mp a
      have eb := List.prefix_iff_eq_take.mp b
      have hA : (p ++ false :: q0)[p.length]? = s[p.length]? := by
        rw [ea, List.getElem?_take]; simp; omega
      have hB : (p ++ true :: q1)[p.length]? = s[p.length]? := by
        rw [eb, List.getElem?_take]; simp; omega
      rw [← hA] at hB; simp at hB

theorem prefix_antisymm {a b : List Bool} (h1 : a <+: b) (h2 : b <+: a) : a = b :=
  List.IsPrefix.eq_of_length h1 (Nat.le_antisymm h1.length_le h2.length_le)

theorem ValueOK_unique {v : Option Bytes} {vl vl' : Nat} (h : ValueOK v vl) (h' : ValueOK v vl') : vl = vl' := by
  rcases h with ⟨rfl, rfl⟩ | ⟨x, rfl, hx, _, _⟩ <;> rcases h' with ⟨h1, rfl⟩ | ⟨y, h1, hy, _, _⟩
  · rfl
  · simp at h1
  · simp at h1
  · simp at h1; subst h1; omega

mutual
/-- **Uniqueness**: canonical resident nodes with equal contents are equal up to caches. -/
theorem Trie.canon_unique : ∀ (t1 t2 : Trie), t1.Resident → t2.Resident → t1.CanonNE → t2.CanonNE →
    (∀ q, t1.contents q = t2.contents q) → t1.erase = t2.erase
  | ⟨p1, v1, l1, r1, vl1, vh1, cs1⟩, ⟨p2, v2, l2, r2, vl2, vh2, cs2⟩, hr1, hr2, hc1, hc2, heq => by
    have hp : p1 = p2 := by
      apply prefix_antisymm
      · exact Trie.prefix_of_all _ hc2 p1 (fun q hq => by
          rw [← heq] at hq; exact Trie.contents_prefix _ q hq)
      · exact Trie.prefix_of_all _ hc1 p2 (fun q hq => by
          rw [heq] at hq; exact Trie.contents_prefix _ q hq)
    subst hp
    have hv : v1 = v2 := by
      have := heq p1; rw [Trie.contents_self, Trie.contents_self] at this; exact this
    subst hv
    have hvl := ValueOK_unique hr1.1 hr2.1
    subst hvl
    have hl := NodeRef.canon_unique l1 l2 hr1.2.1 hr2.2.1 hc1.2.1 hc2.2.1 (fun q => by
      have := heq (p1 ++ false :: q); rw [Trie.contents_mk, Trie.contents_mk] at this; exact this)
    have hr := NodeRef.canon_unique r1 r2 hr1.2.2 hr2.2.2 hc1.2.2 hc2.2.2 (fun q => by
      have := heq (p1 ++ true :: q); rw [Trie.contents_mk, Trie.contents_mk] at this; exact this)
    simp only [Trie.erase, hl, hr]
theorem NodeRef.canon_unique : ∀ (r1 r2 : NodeRef Trie), r1.Resident → r2.Resident → r1.Canon → r2.Canon →
    (∀ q, NodeRef.contents r1 q = NodeRef.contents r2 q) → r1.erase = r2.erase
  | .empty, .empty, _, _, _, _, _ => rfl
  | .hash _, _, h, _, _, _, _ => absurd h (by simp [NodeRef.Resident])
  | _, .hash _, _, h, _, _, _ => absurd h (by simp [NodeRef.Resident])
  | .empty, .node c, _, _, _, hc, heq => by
    obtain ⟨q, hq⟩ := Trie.support_nonempty c hc
    exact absurd (heq q).symm (by simpa [NodeRef.contents] using hq)
  | .node c, .empty, _, _, hc, _, heq => by
    obtain ⟨q, hq⟩ := Trie.support_nonempty c hc
    exact absurd (heq q) (by simpa [NodeRef.contents] using hq)
  | .node c1, .node c2, h1, h2, hc1, hc2, heq => by
    simp only [NodeRef.erase, NodeRef.node.injEq]
    exact Trie.canon_unique c1 c2 h1.1 h2.1 hc1 hc2 (fun q => heq q)
end

/-- **Canonical form**: well-formed tries with the same contents are equal up to caches. -/
theorem Trie.WF_unique (H : Bytes → Bytes) (t1 t2 : Trie) (h1 : t1.WF H) (h2 : t2.WF H)
    (heq : ∀ q, t1.contents q = t2.contents q) : t1.erase = t2.erase := by
  obtain ⟨r1, _, c1⟩ := h1
  obtain ⟨r2, _, c2⟩ := h2
  rcases c1 with c1 | ⟨a1, b1, d1, e1, f1⟩ <;> rcases c2 with c2 | ⟨a2, b2, d2, e2, f2⟩
  · exact Trie.canon_unique t1 t2 r1 r2 c1 c2 heq
  · exfalso
    obtain ⟨q, hq⟩ := Trie.support_nonempty t1 c1
    rw [heq q] at hq
    obtain ⟨p, v, l, r, vl, vh, cs⟩ := t2; simp only at a2 b2 e2 f2; subst a2 b2 e2 f2
    exact hq (by rw [Trie.contents_leaf]; simp)
  · exfalso
    obtain ⟨q, hq⟩ := Trie.support_nonempty t2 c2
    rw [← heq q] at hq
    obtain ⟨p, v, l, r, vl, vh, cs⟩ := t1; simp only at a1 b1 e1 f1; subst a1 b1 e1 f1
    exact hq (by rw [Trie.contents_leaf]; simp)
  · obtain ⟨p, v, l, r, vl, vh, cs⟩ := t1
    obtain ⟨p', v', l', r', vl', vh', cs'⟩ := t2
    simp only at a1 b1 d1 e1 f1 a2 b2 d2 e2 f2
    subst a1 b1 d1 e1 f1 a2 b2 d2 e2 f2
    rfl

/-- Equal contents ⇒ equal `toMessage` and equal `getHash` (for any store). -/
theorem Trie.WF_same_encoding (env : Env) (t1 t2 : Trie) (h1 : t1.WF env.H) (h2 : t2.WF env.H)
    (heq : ∀ q, t1.contents q = t2.contents q) :
    t1.toMessage env = t2.toMessage env ∧ t1.getHash env = t2.getHash env := by
  have he := Trie.WF_unique env.H t1 t2 h1 h2 heq
  have m1 := (Trie.encOK env t1 h1.1 h1.2.1 FUEL)
  have m2 := (Trie.encOK env t2 h2.1 h2.2.1 FUEL)
  refine ⟨?_, ?_⟩
  · rw [Trie.toMessage, Trie.toMessage, m1.2.1, m2.2.1, ← Trie.encS_erase env.H t1,
      ← Trie.encS_erase env.H t2, he]
  · rw [Trie.getHash, Trie.getHash, m1.2.2.2.1, m2.2.2.2.1, ← Trie.hashS_erase env.H t1,
      ← Trie.hashS_erase env.H t2, he]

/-! ## Sequences of operations from the empty trie -/

/-- A `put` (value `none` or empty = delete) or a `delete`. -/
inductive Op where
  | put (key : Bytes) (value : Option Bytes)
  | delete (key : Bytes)

def Op.key : Op → Bytes
  | .put k _ => k
  | .delete k => k

/-- The stored value after the operation (normalised as Java does). -/
def Op.val : Op → Option Bytes
  | .put _ v => normValue v
  | .delete _ => none

def Op.run (env : Env) (t : Trie) : Op → Except Err Trie
  | .put k v => t.put env k v
  | .delete k => t.delete env k

def runOps (env : Env) : Trie → List Op → Except Err Trie
  | t, [] => .ok t
  | t, op :: ops => do runOps env (← op.run env t) ops

/-- The map a sequence of operations denotes, starting from `m`. -/
def mapAfter (m : List Bool → Option Bytes) : List Op → List Bool → Option Bytes
  | [] => m
  | op :: ops => mapAfter (upd m (TrieKeySlice.fromKey op.key) op.val) ops

def OpsOK (ops : List Op) : Prop := ∀ op ∈ ops, VOK op.val

theorem runOps_spec (env : Env) : ∀ (ops : List Op) (t : Trie), t.WF env.H → OpsOK ops →
    ∃ t', runOps env t ops = .ok t' ∧ t'.WF env.H ∧ ∀ q, t'.contents q = mapAfter t.contents ops q
  | [], t, ht, _ => ⟨t, rfl, ht, fun _ => rfl⟩
  | op :: ops, t, ht, hok => by
    obtain ⟨t1, h1, w1, c1⟩ : ∃ t1, op.run env t = .ok t1 ∧ t1.WF env.H ∧
        ∀ q, t1.contents q = upd t.contents (TrieKeySlice.fromKey op.key) op.val q := by
      cases op with
      | put k v => exact Trie.put_spec env t ht k v (hok (Op.put k v) (by simp))
      | delete k =>
        exact Trie.put_spec env t ht k none (by intro x hx; simp [normValue] at hx)
    obtain ⟨t2, h2, w2, c2⟩ := runOps_spec env ops t1 w1 (fun o ho => hok o (by simp [ho]))
    refine ⟨t2, by simp [runOps, h1, h2], w2, fun q => ?_⟩
    rw [c2]; simp only [mapAfter]
    have : t1.contents = upd t.contents (TrieKeySlice.fromKey op.key) op.val := funext c1
    rw [this]

theorem mapAfter_support : ∀ (ops : List Op) (m : List Bool → Option Bytes) (q : List Bool),
    mapAfter m ops q ≠ none → m q ≠ none ∨ ∃ key, q = TrieKeySlice.fromKey key
  | [], _, _, h => Or.inl h
  | op :: ops, m, q, h => by
    rcases mapAfter_support ops _ q h with h' | h'
    · simp only [upd] at h'
      split at h'
      · next he => exact Or.inr ⟨op.key, he⟩
      · exact Or.inl h'
    · exact Or.inr h'

/-- **History independence**: any two sequences of `put`/`delete` operations from the empty trie
that end with the same value for every byte key give tries that are equal up to caches, hence
have the same serialization and the same root hash. Both results are well formed: the root is
the empty trie or a node with a value or two children, every other node has a value or two
children, and no reference points to an empty node. -/
theorem history_independent (env : Env) (ops1 ops2 : List Op) (h1 : OpsOK ops1) (h2 : OpsOK ops2)
    (hsame : ∀ key : Bytes, mapAfter (fun _ => none) ops1 (TrieKeySlice.fromKey key) =
      mapAfter (fun _ => none) ops2 (TrieKeySlice.fromKey key)) :
    ∃ t1 t2, runOps env Trie.empty ops1 = .ok t1 ∧ runOps env Trie.empty ops2 = .ok t2 ∧
      t1.WF env.H ∧ t2.WF env.H ∧ t1.erase = t2.erase ∧
      t1.toMessage env = t2.toMessage env ∧ t1.getHash env = t2.getHash env := by
  obtain ⟨t1, e1, w1, c1⟩ := runOps_spec env ops1 Trie.empty (Trie.WF_empty env.H) h1
  obtain ⟨t2, e2, w2, c2⟩ := runOps_spec env ops2 Trie.empty (Trie.WF_empty env.H) h2
  have hce : Trie.empty.contents = fun _ => none := funext Trie.contents_empty
  have heq : ∀ q, t1.contents q = t2.contents q := by
    intro q
    rw [c1, c2, hce]
    by_cases hq : ∃ key, q = TrieKeySlice.fromKey key
    · obtain ⟨key, rfl⟩ := hq; exact hsame key
    · have a : mapAfter (fun _ => none) ops1 q = none := Classical.byContradiction fun h => by
        rcases mapAfter_support ops1 _ q h with h' | h'
        · exact h' rfl
        · exact hq h'
      have b : mapAfter (fun _ => none) ops2 q = none := Classical.byContradiction fun h => by
        rcases mapAfter_support ops2 _ q h with h' | h'
        · exact h' rfl
        · exact hq h'
      rw [a, b]
  obtain ⟨m, hs⟩ := Trie.WF_same_encoding env t1 t2 w1 w2 heq
  exact ⟨t1, t2, e1, e2, w1, w2, Trie.WF_unique env.H t1 t2 w1 w2 heq, m, hs⟩

/-! ## childrenSize (RSKIP107 `treeSize`) -/

/-- **childrenSize**: in a well-formed trie (e.g. any trie built by put/delete from the empty
trie) the incrementally maintained `childrenSize` of every node is either not yet computed or
equal to what Java's `getChildrenSize()` computes from scratch (`childrenSize == null`):
`left.referenceSize() + right.referenceSize()`. -/
theorem Trie.childrenSize_from_scratch (env : Env) (t : Trie) (ht : t.WF env.H) (fuel : Nat) :
    ∃ c, ({ t with childrenSize := none } : Trie).getChildrenSize env fuel = .ok c ∧
      (t.childrenSize = none ∨ t.childrenSize = some c) ∧ t.getChildrenSize env fuel = .ok c := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
  obtain ⟨hres, hc, _⟩ := ht
  have hc' : Trie.CacheOK env.H ⟨p, v, l, r, vl, vh, none⟩ := ⟨Or.inl rfl, hc.2⟩
  have hres' : Trie.Resident ⟨p, v, l, r, vl, vh, none⟩ := hres
  have h0 := (Trie.encOK env ⟨p, v, l, r, vl, vh, none⟩ hres' hc' fuel).1
  have h1 := (Trie.encOK env _ hres hc fuel).1
  refine ⟨_, h0, ?_, ?_⟩
  · rcases hc.1 with h | h
    · exact Or.inl h
    · right; rw [h, encS_snd, encS_snd]
  · rw [h1, encS_snd, encS_snd]

end RskjTrie
