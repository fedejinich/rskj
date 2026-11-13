import RskjTrie.Ops
import RskjTrie.Proofs.Resident
/-!
# The key/value contents of a resident trie, and `get`

`Trie.contents t k` is the value stored under the bit-path `k` (the specification of `find` +
`getValue`): a node with shared path `p` stores its value at `p`, its left subtree under
`p ++ [0] ++ _` and its right subtree under `p ++ [1] ++ _`.
-/
namespace RskjTrie
open Trie TrieKeySlice

mutual
def Trie.contents : Trie → List Bool → Option Bytes
  | ⟨p, v, l, r, _, _, _⟩, k =>
    if p <+: k then
      match k.drop p.length with
      | [] => v
      | false :: q => NodeRef.contents l q
      | true :: q => NodeRef.contents r q
    else none
def NodeRef.contents : NodeRef Trie → List Bool → Option Bytes
  | .node t, k => t.contents k
  | _, _ => none
end

theorem lcp_eq_iff_prefix (k p : List Bool) : (lcp k p).length = p.length ↔ p <+: k := by
  constructor
  · intro h
    have h1 := lcp_prefix_right k p
    have : lcp k p = p := by
      obtain ⟨t, ht⟩ := h1
      have : t.length = 0 := by have := congrArg List.length ht; simp at this; omega
      rw [List.eq_nil_of_length_eq_zero this] at ht; simpa using ht
    rw [← this]; exact lcp_prefix_left k p
  · intro h; rw [lcp_of_prefix h]

theorem drop_eq_cons_get {k : List Bool} {n : Nat} (h : n < k.length) :
    k.drop n = TrieKeySlice.get k n :: k.drop (n + 1) := by
  rw [List.drop_eq_getElem_cons h]
  simp [TrieKeySlice.get, List.getD, List.getElem?_eq_getElem h]

theorem slice_eq_drop (k : List Bool) (n : Nat) : TrieKeySlice.slice k n k.length = k.drop n := by
  simp only [TrieKeySlice.slice]; exact List.take_of_length_le (by simp)

/-- `find` + `getValue` on a resident trie compute `contents`. -/
theorem Trie.get_contents (env : Env) : ∀ (t : Trie), t.Resident → ∀ (key : TrieKeySlice),
    ((t.findSlice env key) >>= fun o => match o with
      | none => pure none
      | some n => n.getValue env) = .ok (t.contents key)
  | ⟨p, v, l, r, vl, vh, cs⟩, ⟨hv, hl, hr⟩, key => by
    rw [findSlice]
    simp only [commonPath_eq_lcp]
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
        · have : key.drop p.length = [] := by simp; omega
          simp [h3, Trie.contents, hpre, getValue_resident env ⟨p, v, l, r, vl, vh, cs⟩ hv]
        · simp only [h3, ↓reduceDIte]
          have hlt : p.length < key.length := by omega
          rw [Trie.contents]
          simp only [hpre, ↓reduceIte, drop_eq_cons_get hlt]
          simp only [retrieveNode, getNodeReference, slice_eq_drop, Nat.lt_irrefl, ↓reduceIte]
          cases hb : key.get p.length
          · simp only [↓reduceIte]
            cases l with
            | empty => simp [NodeRef.getNode, NodeRef.contents]
            | hash => exact absurd hl (by simp [NodeRef.Resident])
            | node c =>
              simp only [NodeRef.getNode, except_bind_ok, NodeRef.contents]
              exact Trie.get_contents env c hl.1 _
          · simp only [Bool.true_eq_false, ↓reduceIte]
            cases r with
            | empty => simp [NodeRef.getNode, NodeRef.contents]
            | hash => exact absurd hr (by simp [NodeRef.Resident])
            | node c =>
              simp only [NodeRef.getNode, except_bind_ok, NodeRef.contents]
              exact Trie.get_contents env c hr.1 _

/-- `Trie.get` on a resident trie is `contents` at the bits of the key. -/
theorem Trie.get_eq_contents (env : Env) (t : Trie) (h : t.Resident) (key : Bytes) :
    t.get env key = .ok (t.contents (TrieKeySlice.fromKey key)) := by
  have := Trie.get_contents env t h (TrieKeySlice.fromKey key)
  unfold Trie.get Trie.find
  exact this

end RskjTrie
