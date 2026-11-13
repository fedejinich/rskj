import RskjTrie.Proofs.Put
/-!
# Proofs: `deleteRecursive`

`deleteRecursive(k)` (Trie.java:475-480, `put(key, null, true)`) removes every key that extends
`k` **if `k` itself has a value**, and changes nothing otherwise — in particular it does nothing
when a value-less (branching) node sits exactly at `k`: `internalPut` returns the receiver
because `valueLength == 0 && getValue() == null` (Trie.java:847-849) before reaching the
`isRecursiveDelete` branch (Trie.java:851-853).
-/
namespace RskjTrie
open Trie TrieKeySlice

/-- The map after `deleteRecursive(k)`. -/
def drMap (f : List Bool → Option Bytes) (k : List Bool) (q : List Bool) : Option Bytes :=
  if f k ≠ none ∧ k <+: q then none else f q

def PreDR (H : Bytes → Bytes) (t : Trie) : Prop := t.Resident ∧ t.CacheOK H ∧ t.CanonBelow ∧ t.Canon

def PostPutDR (H : Bytes → Bytes) (t : Trie) (k : List Bool) (r : PutRes) : Prop :=
  (∀ n, r.node t = some n → n.Resident ∧ n.CacheOK H ∧ n.CanonNE) ∧
  (∀ q, optContents (r.node t) q = drMap t.contents k q)

def PostIPDR (H : Bytes → Bytes) (t : Trie) (k : List Bool) (r : PutRes) : Prop :=
  (∀ n, r.node t = some n → n.Resident ∧ n.CacheOK H ∧ n.CanonBelow ∧ (n.CanonNE ∨ n.value = none)) ∧
  (∀ q, optContents (r.node t) q = drMap t.contents k q)

theorem drMap_left (p v l l' r vl vh cs vl' vh' cs') (sub : List Bool)
    (h : ∀ q, NodeRef.contents l' q = drMap (NodeRef.contents l) sub q) (q : List Bool) :
    Trie.contents ⟨p, v, l', r, vl', vh', cs'⟩ q =
      drMap (Trie.contents ⟨p, v, l, r, vl, vh, cs⟩) (p ++ false :: sub) q := by
  unfold drMap
  rw [Trie.contents_mk]
  revert q
  apply Trie.contents_cases (fun q o => o = if NodeRef.contents l sub ≠ none ∧ p ++ false :: sub <+: q
    then none else Trie.contents ⟨p, v, l, r, vl, vh, cs⟩ q)
  · intro q hq
    have : ¬ (p ++ false :: sub <+: q) := fun e => hq ((List.prefix_append _ _).trans e)
    simp [this, Trie.contents_not_prefix' _ _ _ _ _ _ _ _ hq]
  · have : ¬ (p ++ false :: sub <+: p) := fun e => by have := e.length_le; simp at this; omega
    simp [this, Trie.contents_self]
  · intro q'; rw [h q']; simp [drMap, Trie.contents_mk]
  · intro q'; simp [Trie.contents_mk]

theorem drMap_right (p v l r r' vl vh cs vl' vh' cs') (sub : List Bool)
    (h : ∀ q, NodeRef.contents r' q = drMap (NodeRef.contents r) sub q) (q : List Bool) :
    Trie.contents ⟨p, v, l, r', vl', vh', cs'⟩ q =
      drMap (Trie.contents ⟨p, v, l, r, vl, vh, cs⟩) (p ++ true :: sub) q := by
  unfold drMap
  rw [Trie.contents_mk]
  revert q
  apply Trie.contents_cases (fun q o => o = if NodeRef.contents r sub ≠ none ∧ p ++ true :: sub <+: q
    then none else Trie.contents ⟨p, v, l, r, vl, vh, cs⟩ q)
  · intro q hq
    have : ¬ (p ++ true :: sub <+: q) := fun e => hq ((List.prefix_append _ _).trans e)
    simp [this, Trie.contents_not_prefix' _ _ _ _ _ _ _ _ hq]
  · have : ¬ (p ++ true :: sub <+: p) := fun e => by have := e.length_le; simp at this; omega
    simp [this, Trie.contents_self]
  · intro q'; simp [Trie.contents_mk]
  · intro q'; rw [h q']; simp [drMap, Trie.contents_mk]

theorem drMap_self_of_none (f : List Bool → Option Bytes) (k : List Bool) (h : f k = none) (q : List Bool) :
    drMap f k q = f q := by simp [drMap, h]

mutual
theorem putSlice_dr (env : Env) (t : Trie) (k : List Bool) (hpre : PreDR env.H t) :
    ∃ r, t.putSlice env k none true = .ok r ∧ PostPutDR env.H t k r := by
  obtain ⟨r, hr, hN, hC⟩ := internalPut_dr env t k hpre
  rw [putSlice]
  simp only [normValue, hr, except_bind_ok]
  have gen : ∀ N, r.node t = some N → ∃ r', (do
      let trie ← (pure N : Except Err Trie)
      if (none : Option Bytes).isSome = true then pure r else trie.coalesce env r : Except Err PutRes) = .ok r' ∧
      PostPutDR env.H t k r' := by
    intro N hrN
    obtain ⟨hres, hcache, hbelow, hcanon⟩ := hN N hrN
    simp only [except_pure, except_bind_ok, Option.isSome_none, Bool.false_eq_true, ↓reduceIte]
    have hCN : ∀ q, N.contents q = drMap t.contents k q := by
      intro q; have := hC q; rw [hrN] at this; exact this
    exact coalesce_spec env t N r hrN _ hres hcache hbelow hcanon hCN
  rcases r with _ | _ | n
  · exact gen t rfl
  · exact ⟨.null, rfl, fun m hm => by simp [PutRes.node] at hm, fun q => hC q⟩
  · exact gen n rfl
termination_by (k.length, splitRank t k, 1)
decreasing_by apply Prod.Lex.right; apply Prod.Lex.right; omega

theorem internalPut_dr (env : Env) : ∀ (t : Trie) (k : List Bool), PreDR env.H t →
    ∃ r, t.internalPut env k none true = .ok r ∧ PostIPDR env.H t k r
  | ⟨p, v, l, r, vl, vh, cs⟩, k, hpre => by
    obtain ⟨hres, hcache, hbelow, hcanon⟩ := hpre
    rw [internalPut]
    simp only [commonPath_eq_lcp]
    by_cases hA : (lcp k p).length < p.length
    · -- split branch: a delete never splits
      simp only [hA, ↓reduceDIte, Option.isNone_none, ↓reduceIte]
      have hnp : ¬ p <+: k := fun h => by rw [lcp_of_prefix h] at hA; omega
      refine ⟨.same, rfl, fun n hn' => ?_, fun q => ?_⟩
      · simp only [PutRes.node, Option.some.injEq] at hn'; subst hn'
        refine ⟨hres, hcache, hbelow, ?_⟩
        rcases hcanon with h | ⟨_, h2, _⟩
        · exact Or.inl h
        · exact Or.inr h2
      · simp only [optContents, PutRes.node]
        rw [drMap_self_of_none _ _ (Trie.contents_not_prefix' _ _ _ _ _ _ _ _ hnp)]
    · simp only [hA, ↓reduceDIte]
      have hle := lcp_length_le_right k p
      have hpre : p <+: k := (lcp_eq_iff_prefix k p).mp (by omega)
      by_cases hB : p.length ≥ k.length
      · ------------------------------------------------------------ key ends here
        have hpk : p = k := by
          obtain ⟨u, hu⟩ := hpre
          have : u.length = 0 := by have := congrArg List.length hu; simp at this; omega
          rw [List.eq_nil_of_length_eq_zero this] at hu; simpa using hu
        subst hpk
        simp only [hB, ↓reduceIte, getDataLength, except_bind_ok]
        rw [Trie.getValue_resident env _ hres.1]
        by_cases hvl : vl = 0
        · -- no value at `k`: nothing is removed
          subst hvl
          have hv0 : v = none := Trie.value_none_of_resident (t := ⟨p, v, l, r, 0, vh, cs⟩) hres (by simp)
          subst hv0
          simp only [↓reduceIte, except_map_ok, except_bind_ok, decide_true]
          refine ⟨.same, rfl, fun n hn' => ?_, fun q => ?_⟩
          · simp only [PutRes.node, Option.some.injEq] at hn'; subst hn'
            refine ⟨hres, hcache, hbelow, ?_⟩
            rcases hcanon with h | ⟨_, h2, _⟩
            · exact Or.inl h
            · exact Or.inr h2
          · simp only [optContents, PutRes.node]
            rw [drMap_self_of_none _ _ (Trie.contents_self _ _ _ _ _ _ _)]
        · rw [ite_eq_right_of_eq_false _ _ (eq_false hvl)]
          simp only [except_pure, except_bind_ok, Bool.false_eq_true, ↓reduceIte]
          refine ⟨_, rfl, fun n hn' => ?_, fun q => ?_⟩
          · simp only [PutRes.node, Option.some.injEq] at hn'; subst hn'
            refine ⟨⟨Or.inl ⟨rfl, rfl⟩, trivial, trivial⟩, ⟨?_, by simp, trivial, trivial⟩,
              ⟨trivial, trivial⟩, Or.inr rfl⟩
            right; simp [encS_snd, kidsSize, NodeRef.isEmpty]
          · simp only [optContents, PutRes.node, Trie.contents_leaf]
            have hv : v ≠ none := by
              rcases hres.1 with ⟨_, h0⟩ | ⟨x, h1, _, _, _⟩
              · exact absurd h0 hvl
              · simp [h1]
            unfold drMap; rw [Trie.contents_self]
            by_cases hq : p <+: q
            · simp [hv, hq]
            · simp [hq, Trie.contents_not_prefix' _ _ _ _ _ _ _ _ hq]
      · simp only [hB, ↓reduceIte]
        have hlt : p.length < k.length := by omega
        have hk : k = p ++ TrieKeySlice.get k p.length :: k.drop (p.length + 1) := by
          rw [← drop_eq_cons_get hlt]; exact eq_append_drop hpre
        by_cases hE : Trie.isEmptyTrie ⟨p, v, l, r, vl, vh, cs⟩ = true
        · ------------------------------------------------------------ empty trie
          rw [ite_eq_left_of_eq_true _ _ (eq_true hE)]
          simp only [leaf, getDataLength, except_bind_ok, except_pure, except_map_ok]
          refine ⟨_, rfl, fun n hn' => ?_, fun q => ?_⟩
          · simp only [PutRes.node, Option.some.injEq] at hn'; subst hn'
            refine ⟨⟨Or.inl ⟨rfl, rfl⟩, trivial, trivial⟩, ⟨?_, by simp, trivial, trivial⟩,
              ⟨trivial, trivial⟩, Or.inr rfl⟩
            right; simp [encS_snd, kidsSize, NodeRef.isEmpty]
          · simp only [optContents, PutRes.node, Trie.contents_leaf]
            simp [drMap, Trie.contents_isEmpty hres hE]
        · ------------------------------------------------------------ descend into a child
          rw [ite_eq_right_of_eq_false _ _ (eq_false hE)]
          generalize hpos : TrieKeySlice.get k p.length = pos at hk ⊢
          obtain ⟨c, hc1, hc2, cres, ccache, ccanon⟩ :=
            retrieveNodeOrEmpty_spec env _ hres hcache hbelow pos
          rw [hc1, except_bind_ok]
          have hcb : c.CanonBelow := by
            rcases ccanon with h | ⟨_, _, _, h4, h5⟩
            · exact Trie.CanonNE_below h
            · obtain ⟨_, _, cl, cr, _, _, _⟩ := c; simp only at h4 h5; subst h4 h5; exact ⟨trivial, trivial⟩
          rw [slice_eq_drop]
          obtain ⟨rr, hrr, hN, hC⟩ := putSlice_dr env c (k.drop (p.length + 1)) ⟨cres, ccache, hcb, ccanon⟩
          rw [hrr, except_bind_ok]
          have href : ∀ q, NodeRef.contents (getNodeReference ⟨p, v, l, r, vl, vh, cs⟩ pos) q = c.contents q := by
            intro q; rw [← hc2, NodeRef.contents_ofNode c cres]
          have hkq : ∀ q, Trie.contents ⟨p, v, l, r, vl, vh, cs⟩ (p ++ pos :: q) = c.contents q := by
            intro q; rw [Trie.contents_mk, ← href]; cases pos <;> rfl
          by_cases hsm : rr.isSame = true
          · ------------------------------------------------------------ child unchanged
            rw [ite_eq_left_of_eq_true _ _ (eq_true hsm)]
            have hrr' : rr = .same := by
              cases rr
              · rfl
              · simp [PutRes.isSame] at hsm
              · simp [PutRes.isSame] at hsm
            subst hrr'
            refine ⟨.same, rfl, fun n hn' => ?_, fun q => ?_⟩
            · simp only [PutRes.node, Option.some.injEq] at hn'; subst hn'
              refine ⟨hres, hcache, hbelow, ?_⟩
              rcases hcanon with h | ⟨_, h2, _⟩
              · exact Or.inl h
              · exact Or.inr h2
            · -- the child's contents are unchanged, hence so are the node's
              simp only [optContents, PutRes.node]
              have hcs : ∀ q, c.contents q = drMap c.contents (k.drop (p.length + 1)) q := fun q => hC q
              unfold drMap
              rw [hk, hkq]
              by_cases hn : c.contents (k.drop (p.length + 1)) = none
              · simp [hn]
              · simp only [ne_eq, hn, not_false_eq_true, true_and]
                split
                · next hq =>
                  obtain ⟨w, hw⟩ := hq
                  have e : q = p ++ pos :: (k.drop (p.length + 1) ++ w) := by rw [← hw]; simp
                  rw [e, hkq, hcs]; simp [drMap, hn]
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
                drMap (NodeRef.contents (getNodeReference ⟨p, v, l, r, vl, vh, cs⟩ pos)) (k.drop (p.length + 1)) q := by
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
            have hNc : ∀ q, Trie.contents ⟨p, v, nl, nr, vl, vh, cs'⟩ q =
                drMap (Trie.contents ⟨p, v, l, r, vl, vh, cs⟩) k q := by
              intro q
              rw [hk]
              cases pos
              · simp only [↓reduceIte] at hshape; obtain ⟨h1, h2⟩ := hshape
                rw [h1, h2]
                exact drMap_left p v l _ r vl vh cs vl vh cs' _ hRc q
              · simp only [Bool.true_eq_false, ↓reduceIte] at hshape; obtain ⟨h1, h2⟩ := hshape
                rw [h1, h2]
                exact drMap_right p v l r _ vl vh cs vl vh cs' _ hRc q
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
              refine ⟨hNres, hNcache, hNbelow, ?_⟩
              by_cases hv0 : v = none
              · exact Or.inr hv0
              · exact Or.inl ⟨Or.inl hv0, hNbelow.1, hNbelow.2⟩
termination_by t k _ => (k.length, splitRank t k, 0)
decreasing_by
  apply Prod.Lex.left
  simp only [List.length_drop]; omega
end

/-- **deleteRecursive**: on a well-formed trie, `deleteRecursive(key)` succeeds, keeps the trie
well formed, and removes exactly the keys that extend `key` — provided `key` has a value; if
`key` has no value (including when a value-less branching node sits exactly at `key`) the contents
are unchanged. -/
theorem Trie.deleteRecursive_spec (env : Env) (t : Trie) (ht : t.WF env.H) (key : Bytes) :
    ∃ t', t.deleteRecursive env key = .ok t' ∧ t'.WF env.H ∧
      ∀ q, t'.contents q = drMap t.contents (TrieKeySlice.fromKey key) q := by
  obtain ⟨hres, hc, hcan⟩ := ht
  obtain ⟨r, hr, hN, hC⟩ := putSlice_dr env t (TrieKeySlice.fromKey key)
    ⟨hres, hc, Trie.Canon_below hcan, hcan⟩
  unfold Trie.deleteRecursive
  rw [hr, except_bind_ok]
  rcases r with _ | _ | n
  · exact ⟨t, rfl, ⟨hres, hc, hcan⟩, fun q => hC q⟩
  · exact ⟨Trie.empty, rfl, Trie.WF_empty env.H, fun q => by rw [Trie.contents_empty]; exact hC q⟩
  · obtain ⟨a, b, c⟩ := hN n rfl
    exact ⟨n, rfl, ⟨a, b, Or.inl c⟩, fun q => hC q⟩

end RskjTrie
