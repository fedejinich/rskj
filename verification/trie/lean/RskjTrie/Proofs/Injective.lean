import RskjTrie.Proofs.Store
import RskjTrie.Proofs.Flags
/-!
# Proofs: the encoding is injective on canonical nodes; the root hash binds the map
-/
namespace RskjTrie
open Trie

/-- **Message injectivity** (TRIE-SER-02): two resident nodes (consistent caches, paths shorter
than `2^31` bits) with the same `toMessage` have the same re-parsed form: equal shared path, value
(inline) or value hash (long), value length, `childrenSize` and child references (equal hash or
equal embedded node). -/
theorem Trie.message_injective (env : Env) (hH : ∀ x, (env.H x).length = 32) (t1 t2 : Trie)
    (r1 : t1.Resident) (c1 : t1.CacheOK env.H) (p1 : t1.PathsOK)
    (r2 : t2.Resident) (c2 : t2.CacheOK env.H) (p2 : t2.PathsOK)
    (h : t1.toMessage env = t2.toMessage env) : t1.reparse env.H = t2.reparse env.H := by
  obtain ⟨m1, f1⟩ := Trie.fromMessage_toMessage env hH t1 r1 c1 p1
  obtain ⟨m2, f2⟩ := Trie.fromMessage_toMessage env hH t2 r2 c2 p2
  rw [m1, m2] at h
  injection h with h
  rw [h] at f1
  rw [f1] at f2
  injection f2

theorem Trie.contents_congr (p v l r vl vh cs l' r' vl' vh' cs')
    (hl : ∀ q, NodeRef.contents l q = NodeRef.contents l' q)
    (hr : ∀ q, NodeRef.contents r q = NodeRef.contents r' q) (q : List Bool) :
    Trie.contents ⟨p, v, l, r, vl, vh, cs⟩ q = Trie.contents ⟨p, v, l', r', vl', vh', cs'⟩ q := by
  simp only [Trie.contents, hl, hr]

theorem vals_sub_left (H : Bytes → Bytes) (p v l r vl vh cs) (x : Bytes) (hx : x ∈ NodeRef.vals H l) :
    x ∈ Trie.vals H ⟨p, v, l, r, vl, vh, cs⟩ := by simp [Trie.vals, hx]
theorem vals_sub_right (H : Bytes → Bytes) (p v l r vl vh cs) (x : Bytes) (hx : x ∈ NodeRef.vals H r) :
    x ∈ Trie.vals H ⟨p, v, l, r, vl, vh, cs⟩ := by simp [Trie.vals, hx]

mutual
/-- The re-parsed form determines the contents, when `H` is injective on the nodes' messages and
long values. -/
theorem Trie.contents_of_reparse (env : Env) (hH : ∀ x, (env.H x).length = 32) (S : List Bytes)
    (hinj : InjOn env.H S) : ∀ (t1 t2 : Trie), t1.Resident → t1.CacheOK env.H → t1.PathsOK →
      t2.Resident → t2.CacheOK env.H → t2.PathsOK → (∀ x ∈ t1.vals env.H, x ∈ S) →
      (∀ x ∈ t2.vals env.H, x ∈ S) → t1.reparse env.H = t2.reparse env.H →
      ∀ q, t1.contents q = t2.contents q
  | ⟨p1, v1, l1, r1, vl1, vh1, cs1⟩, ⟨p2, v2, l2, r2, vl2, vh2, cs2⟩,
    ⟨hv1, hl1, hr1⟩, ⟨_, _, hcl1, hcr1⟩, ⟨_, hpl1, hpr1⟩,
    ⟨hv2, hl2, hr2⟩, ⟨_, _, hcl2, hcr2⟩, ⟨_, hpl2, hpr2⟩, hS1, hS2, heq => by
    simp only [Trie.reparse, Trie.mk.injEq] at heq
    obtain ⟨rfl, hval, hl, hr, rfl, hvh, _⟩ := heq
    have hv : v1 = v2 := by
      by_cases hlong : vl1 > 32
      · -- long values: equal hashes of values in S
        have hpos : vl1 > 0 := by omega
        simp only [hpos, ↓reduceIte, Option.some.injEq] at hvh
        have i1 : v1.getD [] ∈ S := hS1 _ (by simp [Trie.vals, hlong])
        have i2 : v2.getD [] ∈ S := hS2 _ (by simp [Trie.vals, hlong])
        have e := hinj _ i1 _ i2 hvh
        rcases hv1 with ⟨_, h0⟩ | ⟨x, rfl, _, _, _⟩
        · omega
        · rcases hv2 with ⟨_, h0⟩ | ⟨y, rfl, _, _, _⟩
          · omega
          · simp at e; rw [e]
      · simpa [hlong] using hval
    subst hv
    intro q
    apply Trie.contents_congr
    · exact NodeRef.contents_of_reparse env hH S hinj l1 l2 hl1 hcl1 hpl1 hl2 hcl2 hpl2
        (fun x hx => hS1 x (vals_sub_left _ _ _ _ _ _ _ _ x hx))
        (fun x hx => hS2 x (vals_sub_left _ _ _ _ _ _ _ _ x hx)) hl
    · exact NodeRef.contents_of_reparse env hH S hinj r1 r2 hr1 hcr1 hpr1 hr2 hcr2 hpr2
        (fun x hx => hS1 x (vals_sub_right _ _ _ _ _ _ _ _ x hx))
        (fun x hx => hS2 x (vals_sub_right _ _ _ _ _ _ _ _ x hx)) hr
theorem NodeRef.contents_of_reparse (env : Env) (hH : ∀ x, (env.H x).length = 32) (S : List Bytes)
    (hinj : InjOn env.H S) : ∀ (r1 r2 : NodeRef Trie), r1.Resident → r1.CacheOK env.H → r1.PathsOK →
      r2.Resident → r2.CacheOK env.H → r2.PathsOK → (∀ x ∈ NodeRef.vals env.H r1, x ∈ S) →
      (∀ x ∈ NodeRef.vals env.H r2, x ∈ S) → r1.reparse env.H = r2.reparse env.H →
      ∀ q, NodeRef.contents r1 q = NodeRef.contents r2 q
  | .empty, .empty, _, _, _, _, _, _, _, _, _ => fun _ => rfl
  | .hash _, _, h, _, _, _, _, _, _, _, _ => absurd h (by simp [NodeRef.Resident])
  | _, .hash _, _, _, _, h, _, _, _, _, _ => absurd h (by simp [NodeRef.Resident])
  | .empty, .node c, _, _, _, _, _, _, _, _, heq => by
    simp only [NodeRef.reparse] at heq; split at heq <;> simp at heq
  | .node c, .empty, _, _, _, _, _, _, _, _, heq => by
    simp only [NodeRef.reparse] at heq; split at heq <;> simp at heq
  | .node c1, .node c2, ⟨hr1, hn1⟩, hc1, hp1, ⟨hr2, hn2⟩, hc2, hp2, hS1, hS2, heq => by
    have hre : c1.reparse env.H = c2.reparse env.H := by
      simp only [NodeRef.reparse] at heq
      split at heq <;> split at heq
      · simpa using heq
      · simp at heq
      · simp at heq
      · simp only [NodeRef.hash.injEq, Trie.hashS_nonempty _ _ hn1, Trie.hashS_nonempty _ _ hn2] at heq
        have hm := hinj _ (hS1 _ (Trie.vals_head _ c1)) _ (hS2 _ (Trie.vals_head _ c2)) heq
        apply Trie.message_injective env hH c1 c2 hr1 hc1 hp1 hr2 hc2 hp2
        simp only [Trie.toMessage, (Trie.encOK env c1 hr1 hc1 FUEL).2.1,
          (Trie.encOK env c2 hr2 hc2 FUEL).2.1, hm]
    intro q
    exact Trie.contents_of_reparse env hH S hinj c1 c2 hr1 hc1 hp1 hr2 hc2 hp2 hS1 hS2 hre q
end

theorem encS_ne_80 (H : Bytes → Bytes) (t : Trie) : (t.encS H).1 ≠ [0x80] := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
  rw [Trie.encS_head]
  intro h
  simp only [List.cons.injEq] at h
  have := (mkFlags_range (decide (vl > 32)) (SharedPathSerializer.isPresent p) (!l.isEmpty) (!r.isEmpty)
    (NodeRef.encS H l).2.2 (NodeRef.encS H r).2.2).2
  rw [h.1] at this; exact absurd this (by decide)

/-- **The root hash binds the map** (TRIE-HASH-03): for well-formed tries whose shared paths fit an
`int`, with a 32-byte hash function injective on their messages, long values and `[0x80]`, equal
`getHash()` implies equal key → value maps. -/
theorem Trie.hash_binds_map (env : Env) (hH : ∀ x, (env.H x).length = 32) (t1 t2 : Trie)
    (w1 : t1.WF env.H) (w2 : t2.WF env.H) (p1 : t1.PathsOK) (p2 : t2.PathsOK) (S : List Bytes)
    (hinj : InjOn env.H S) (hS1 : ∀ x ∈ t1.vals env.H, x ∈ S) (hS2 : ∀ x ∈ t2.vals env.H, x ∈ S)
    (h80 : [0x80] ∈ S) (heq : t1.getHash env = t2.getHash env) : ∀ q, t1.contents q = t2.contents q := by
  rw [Trie.getHash_WF env t1 w1, Trie.getHash_WF env t2 w2] at heq
  injection heq with heq
  unfold Trie.hashS at heq
  have m1 := Trie.vals_head env.H t1
  have m2 := Trie.vals_head env.H t2
  by_cases e1 : t1.isEmptyTrie = true <;> by_cases e2 : t2.isEmptyTrie = true <;>
    simp only [e1, e2, ↓reduceIte, Bool.false_eq_true] at heq
  · intro q; rw [Trie.contents_isEmpty w1.1 e1, Trie.contents_isEmpty w2.1 e2]
  · exact absurd (hinj _ h80 _ (hS2 _ m2) heq).symm (encS_ne_80 _ _)
  · exact absurd (hinj _ (hS1 _ m1) _ h80 heq) (encS_ne_80 _ _)
  · have hm := hinj _ (hS1 _ m1) _ (hS2 _ m2) heq
    have hre := Trie.message_injective env hH t1 t2 w1.1 w1.2.1 p1 w2.1 w2.2.1 p2 (by
      rw [Trie.toMessage, Trie.toMessage, (Trie.encOK env t1 w1.1 w1.2.1 FUEL).2.1,
        (Trie.encOK env t2 w2.1 w2.2.1 FUEL).2.1, hm])
    exact Trie.contents_of_reparse env hH S hinj t1 t2 w1.1 w1.2.1 p1 w2.1 w2.2.1 p2 hS1 hS2 hre

end RskjTrie
