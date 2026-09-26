import RskjTrie.Proofs.Canonical
import RskjTrie.Proofs.Hash
import RskjTrie.Proofs.Store
import RskjTrie.Proofs.StoreWrites
import RskjTrie.Proofs.Injective
import RskjTrie.Proofs.EncP
import RskjTrie.Proofs.Flags
import RskjTrie.Proofs.Orchid
import RskjTrie.Proofs.DeleteRecursive
import RskjTrie.Proofs.PutErrors
import RskjTrie.Proofs.KeyMapper
/-!
# Shared definitions for the obligation theorems

* `Reachable env t` — the spec's "reachable trie" (spec/obligations.json `conventions`): obtained
  from `new Trie(store)` by `put`/`delete`/`deleteRecursive`. It implies the well-formedness
  invariant `Trie.WF` used by the phase-A theorems.
* `reencode` — Java `Trie.fromMessage(m, store).toMessage()`.
-/
namespace RskjTrie.Obligations
open RskjTrie Trie TrieKeySlice

/-- A trie reachable from `new Trie(store)` by `put`, `delete` and `deleteRecursive`. -/
inductive Reachable (env : Env) : Trie → Prop where
  | empty : Reachable env Trie.empty
  | put {t t' : Trie} (k : Bytes) (v : Option Bytes) :
      Reachable env t → t.put env k v = .ok t' → Reachable env t'
  | delete {t t' : Trie} (k : Bytes) : Reachable env t → t.delete env k = .ok t' → Reachable env t'
  | deleteRecursive {t t' : Trie} (k : Bytes) :
      Reachable env t → t.deleteRecursive env k = .ok t' → Reachable env t'

theorem put_WF (env : Env) (t t' : Trie) (ht : t.WF env.H) (k : Bytes) (v : Option Bytes)
    (h : t.put env k v = .ok t') : t'.WF env.H := by
  by_cases hv : VOK (normValue v)
  · obtain ⟨t'', h1, h2, _⟩ := Trie.put_spec env t ht k v hv
    rw [h1] at h; cases h; exact h2
  · exfalso
    unfold VOK at hv
    obtain ⟨x, hx'⟩ := Classical.not_forall.mp hv
    obtain ⟨hx, hlen⟩ := Classical.not_imp.mp hx'
    have hvx : v = some x := by
      cases v with
      | none => simp [normValue] at hx
      | some y => simp only [normValue] at hx; split at hx <;> simp_all
    subst hvx
    obtain ⟨e, he⟩ := Trie.put_too_long env t k x (by omega)
    rw [he] at h; cases h

/-- Reachable tries are well formed (resident, caches consistent, canonical). -/
theorem Reachable.WF {env : Env} {t : Trie} (h : Reachable env t) : t.WF env.H := by
  induction h with
  | empty => exact Trie.WF_empty env.H
  | put k v _ h ih => exact put_WF env _ _ ih k v h
  | delete k _ h ih => exact put_WF env _ _ ih k none h
  | deleteRecursive k _ h ih =>
    obtain ⟨t'', h1, h2, _⟩ := Trie.deleteRecursive_spec env _ ih k
    rw [h1] at h; cases h; exact h2

/-- Java `Trie.fromMessage(m, store).toMessage()`. -/
def reencode (env : Env) (m : Bytes) : Except Err Bytes := Trie.fromMessage env m >>= Trie.toMessage env

theorem reencode_eq (env : Env) (m out : Bytes)
    (h : ∃ t, Trie.fromMessage env m = .ok t ∧ t.pokB = true ∧ t.encP env.H = out) :
    reencode env m = .ok out := by
  obtain ⟨t, h1, h2, h3⟩ := h
  simp [reencode, h1, Trie.toMessage_encP env t (Trie.POK_of_pokB t h2), h3]

/-- A trie reached by a sequence of operations equals (up to caches) any explicit well-formed
trie with the same contents; so its message is that trie's pure encoding. -/
theorem runOps_explicit (env : Env) (ops : List Op) (hok : OpsOK ops) (E : Trie) (hE : E.WF env.H)
    (hc : ∀ q, E.contents q = mapAfter (fun _ => none) ops q) :
    ∃ t, runOps env Trie.empty ops = .ok t ∧ t.WF env.H ∧ t.erase = E.erase ∧
      t.toMessage env = .ok (E.encS env.H).1 ∧ t.getHash env = .ok (E.hashS env.H) := by
  obtain ⟨t, h1, w, c⟩ := runOps_spec env ops Trie.empty (Trie.WF_empty env.H) hok
  have hce : Trie.empty.contents = fun _ => none := funext Trie.contents_empty
  rw [hce] at c
  have heq : ∀ q, t.contents q = E.contents q := fun q => by rw [c, hc]
  obtain ⟨m, hs⟩ := Trie.WF_same_encoding env t E w hE heq
  refine ⟨t, h1, w, Trie.WF_unique env.H t E w hE heq, ?_, ?_⟩
  · rw [m, Trie.toMessage, (Trie.encOK env E hE.1 hE.2.1 FUEL).2.1]
  · rw [hs]; exact Trie.getHash_WF env E hE

/-- Lookups in the map of an operation sequence. -/
theorem mapAfter_two (k1 k2 : Bytes) (v1 v2 : Option Bytes) (q : List Bool) :
    mapAfter (fun _ => none) [.put k1 v1, .put k2 v2] q =
      if q = fromKey k2 then normValue v2 else if q = fromKey k1 then normValue v1 else none := by
  simp only [mapAfter, upd, Op.key, Op.val]; rfl

mutual
theorem Trie.contents_erase : ∀ (t : Trie) (q : List Bool), t.erase.contents q = t.contents q
  | ⟨p, v, l, r, vl, vh, cs⟩, q => by
    simp only [Trie.erase, Trie.contents]
    split
    · split <;> simp [NodeRef.contents_erase]
    · rfl
theorem NodeRef.contents_erase : ∀ (r : NodeRef Trie) (q : List Bool),
    NodeRef.contents r.erase q = NodeRef.contents r q
  | .node c, q => Trie.contents_erase c q
  | .empty, _ => rfl
  | .hash _, _ => rfl
end

/-- A leaf node (no caches). -/
def leafN (p : List Bool) (v : Bytes) : Trie := ⟨p, some v, .empty, .empty, v.length, none, none⟩

/-- Contents of a value-less node with two leaf children. -/
theorem contents_two_leaves (p pl pr : List Bool) (vl vr : Bytes) (q : List Bool) :
    Trie.contents ⟨p, none, .node (leafN pl vl), .node (leafN pr vr), 0, none, none⟩ q =
      if q = p ++ false :: pl then some vl else if q = p ++ true :: pr then some vr else none := by
  revert q
  apply Trie.contents_cases (fun q o => o = if q = p ++ false :: pl then some vl
    else if q = p ++ true :: pr then some vr else none)
  · intro q hq
    have a : q ≠ p ++ false :: pl := fun e => hq (e ▸ List.prefix_append _ _)
    have b : q ≠ p ++ true :: pr := fun e => hq (e ▸ List.prefix_append _ _)
    simp [a, b]
  · have a : p ≠ p ++ false :: pl := fun e => by have := congrArg List.length e; simp at this
    have b : p ≠ p ++ true :: pr := fun e => by have := congrArg List.length e; simp at this
    simp [a, b]
  · intro q'; simp [NodeRef.contents, leafN, Trie.contents_leaf]
  · intro q'; simp [NodeRef.contents, leafN, Trie.contents_leaf]

/-- Contents of a node with a value and a single left leaf. -/
theorem contents_val_left (p pl : List Bool) (v vl : Bytes) (n : Nat) (q : List Bool) :
    Trie.contents ⟨p, some v, .node (leafN pl vl), .empty, n, none, none⟩ q =
      if q = p then some v else if q = p ++ false :: pl then some vl else none := by
  revert q
  apply Trie.contents_cases (fun q o => o = if q = p then some v
    else if q = p ++ false :: pl then some vl else none)
  · intro q hq
    have a : q ≠ p := fun e => hq (e ▸ List.prefix_refl _)
    have b : q ≠ p ++ false :: pl := fun e => hq (e ▸ List.prefix_append _ _)
    simp [a, b]
  · simp
  · intro q'; simp [NodeRef.contents, leafN, Trie.contents_leaf]
  · intro q'; simp [NodeRef.contents]

theorem leafN_resident (p : List Bool) (v : Bytes) (h1 : v ≠ []) (h2 : v.length ≤ Uint24.MAX) :
    (NodeRef.node (leafN p v)).Resident := by
  have := List.length_pos_iff.mpr h1
  refine ⟨⟨Or.inr ⟨v, rfl, rfl, this, h2⟩, trivial, trivial⟩, ?_⟩
  simp [leafN, isEmptyTrie, isEmptyTrieOf, this]

end RskjTrie.Obligations
