import RskjTrie.Proofs.Put
/-!
# Proofs: `put` of a value that does not fit a `Uint24` fails

Every path through `put`/`internalPut` evaluates `getDataLength(value)` (`new Uint24(value.length)`,
Uint24.java:30-36) before building a node, so a value longer than `0xFFFFFF` bytes makes `put`
throw, whatever the trie (Java: `IllegalArgumentException: The supplied value doesn't fit in a
Uint24`; other errors such as a broken store may come first).
-/
namespace RskjTrie
open Trie TrieKeySlice

theorem except_bind_err_ex {α β : Type} (x : Except Err α) (f : α → Except Err β)
    (h : ∀ a, x = .ok a → ∃ e, f a = .error e) : ∃ e, (x >>= f) = .error e := by
  cases hx : x with
  | error e => exact ⟨e, rfl⟩
  | ok a => obtain ⟨e, he⟩ := h a hx; exact ⟨e, by simp [he]⟩

mutual
theorem putSlice_big (env : Env) (t : Trie) (k : List Bool) (x : Bytes) (hx : x.length > Uint24.MAX)
    (d : Bool) : ∃ e, t.putSlice env k (some x) d = .error e := by
  have h0 : x.length ≠ 0 := by have : x.length > 16777215 := hx; omega
  have hn : normValue (some x) = some x := by simp only [normValue, h0, ↓reduceIte]
  rw [putSlice]; simp only [hn]
  obtain ⟨e, he⟩ := internalPut_big env t k x hx d
  exact ⟨e, by simp [he]⟩
termination_by (k.length, splitRank t k, 1)
decreasing_by apply Prod.Lex.right; apply Prod.Lex.right; omega

theorem internalPut_big (env : Env) : ∀ (t : Trie) (k : List Bool) (x : Bytes), x.length > Uint24.MAX →
    ∀ (d : Bool), ∃ e, t.internalPut env k (some x) d = .error e
  | ⟨p, v, l, r, vl, vh, cs⟩, k, x, hx, d => by
    have hdl : getDataLength (some x) = .error "IllegalArgumentException: Uint24" := by
      simp [getDataLength, Uint24.mk, hx]
    rw [internalPut]
    simp only [commonPath_eq_lcp]
    by_cases hA : (lcp k p).length < p.length
    · simp only [hA, ↓reduceDIte, Option.isNone_some, Bool.false_eq_true, ↓reduceIte]
      apply except_bind_err_ex
      intro ⟨s, hs⟩ _
      apply except_bind_err_ex
      intro rr hrr
      obtain ⟨e, he⟩ := putSlice_big env s k x hx d
      rw [he] at hrr; cases hrr
    · simp only [hA, ↓reduceDIte]
      by_cases hB : p.length ≥ k.length
      · simp only [hB, ↓reduceIte, hdl]; exact ⟨_, rfl⟩
      · simp only [hB, ↓reduceIte]
        split
        · simp only [leaf, hdl]; exact ⟨_, rfl⟩
        · apply except_bind_err_ex
          intro node _
          rw [slice_eq_drop]
          apply except_bind_err_ex
          intro rr hrr
          obtain ⟨e, he⟩ := putSlice_big env node (k.drop (p.length + 1)) x hx d
          rw [he] at hrr; cases hrr
termination_by t k _ _ _ => (k.length, splitRank t k, 0)
decreasing_by
  · apply Prod.Lex.right; apply Prod.Lex.left
    rw [splitRank_split k p s (by rw [hs, commonPath_eq_lcp])]
    have : splitRank ⟨p, v, l, r, vl, vh, cs⟩ k = 1 := by
      unfold splitRank; simp only [commonPath_eq_lcp]; split <;> simp_all
    omega
  · apply Prod.Lex.left
    simp only [List.length_drop]; omega
end

/-- **Values must fit a `Uint24`**: `put(k, v)` with `|v| > 0xFFFFFF` fails on every trie. -/
theorem Trie.put_too_long (env : Env) (t : Trie) (key x : Bytes) (hx : x.length > Uint24.MAX) :
    ∃ e, t.put env key (some x) = .error e := by
  unfold Trie.put
  obtain ⟨e, he⟩ := putSlice_big env t (TrieKeySlice.fromKey key) x hx false
  exact ⟨e, by simp [he]⟩

end RskjTrie
