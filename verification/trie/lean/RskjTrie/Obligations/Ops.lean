import RskjTrie.Obligations.Examples
import RskjTrie.Proofs.BridgePut
/-! # Obligations TRIE-OPS-* (map semantics) and TRIE-CMP-* (canonical shape) -/
namespace RskjTrie.Obligations
open RskjTrie Trie TrieKeySlice PathEncoder

set_option linter.unusedSimpArgs false

theorem fromKey_append (a b : Bytes) : fromKey (a ++ b) = fromKey a ++ fromKey b := by
  apply List.ext_getElem (by simp [fromKey_length]; omega)
  intro i h1 h2
  simp only [fromKey_eq, List.getElem_map, List.getElem_range, List.getElem_append] at h1 h2 ⊢
  simp only [List.length_map, List.length_range] at h2 ⊢
  split
  · simp only [List.getElem_map, List.getElem_range, bitAt]
    congr 2
    rw [List.getD_eq_getElem?_getD, List.getD_eq_getElem?_getD, List.getElem?_append_left (by omega)]
  · simp only [List.getElem_map, List.getElem_range, bitAt]
    have e1 : (i - a.length * 8) / 8 = i / 8 - a.length := by omega
    have e2 : (i - a.length * 8) % 8 = i % 8 := by omega
    rw [e1, e2, List.getD_eq_getElem?_getD, List.getD_eq_getElem?_getD,
      List.getElem?_append_right (by omega)]

theorem prefix_of_fromKey {a b : Bytes} (h : fromKey a <+: fromKey b) : a <+: b := by
  have hl := h.length_le
  rw [fromKey_length, fromKey_length] at hl
  obtain ⟨r, hr⟩ := h
  rw [← List.take_append_drop a.length b, fromKey_append] at hr
  have := List.append_inj hr (by rw [fromKey_length, fromKey_length, List.length_take]; omega)
  rw [fromKey_injective this.1]
  exact List.take_prefix _ _

theorem fromKey_prefix {a b : Bytes} (h : a <+: b) : fromKey a <+: fromKey b := by
  obtain ⟨r, rfl⟩ := h; rw [fromKey_append]; exact List.prefix_append _ _

/-- `put` succeeded ⇒ its specification (values that do not fit make `put` throw). -/
theorem put_ok_spec (env : Env) (t t' : Trie) (ht : t.WF env.H) (k : Bytes) (v : Option Bytes)
    (h : t.put env k v = .ok t') :
    t'.WF env.H ∧ ∀ q, t'.contents q = upd t.contents (fromKey k) (normValue v) q := by
  by_cases hv : VOK (normValue v)
  · obtain ⟨t'', h1, h2, h3⟩ := Trie.put_spec env t ht k v hv
    rw [h1] at h; cases h; exact ⟨h2, h3⟩
  · exact ⟨put_WF env t t' ht k v h, by
      exfalso
      obtain ⟨x, hx'⟩ := Classical.not_forall.mp hv
      obtain ⟨hx, hlen⟩ := Classical.not_imp.mp hx'
      have hvx : v = some x := by
        cases v with
        | none => simp [normValue] at hx
        | some y => simp only [normValue] at hx; split at hx <;> simp_all
      subst hvx
      obtain ⟨e, he⟩ := Trie.put_too_long env t k x (by omega)
      rw [he] at h; cases h⟩

/-- Reachable tries only hold values at byte-aligned paths `fromKey k`. -/
def KeyOnly (t : Trie) : Prop := ∀ q, t.contents q ≠ none → ∃ k, q = fromKey k

theorem Reachable.keyOnly {env : Env} {t : Trie} (h : Reachable env t) : KeyOnly t := by
  induction h with
  | empty => intro q hq; simp [Trie.contents_empty] at hq
  | put k v hr h ih =>
    intro q hq
    rw [(put_ok_spec env _ _ hr.WF k v h).2 q] at hq
    unfold upd at hq; split at hq
    · exact ⟨k, by assumption⟩
    · exact ih q hq
  | delete k hr h ih =>
    intro q hq
    rw [(put_ok_spec env _ _ hr.WF k none h).2 q] at hq
    unfold upd at hq; split at hq
    · simp [normValue] at hq
    · exact ih q hq
  | deleteRecursive k hr h ih =>
    intro q hq
    obtain ⟨t'', h1, _, h3⟩ := Trie.deleteRecursive_spec env _ hr.WF k
    rw [h1] at h; cases h
    rw [h3 q] at hq; unfold drMap at hq; split at hq
    · simp at hq
    · exact ih q hq

/-- TRIE-OPS-01: `new Trie().get(k) == null`. -/
theorem trie_ops_01 (env : Env) (k : Bytes) : Trie.empty.get env k = .ok none := by
  rw [Trie.get_eq_contents env _ (Trie.WF_empty env.H).1, Trie.contents_empty]

/-- TRIE-OPS-02: `t.put(k, v).get(k) = v` for `1 ≤ |v| ≤ 0xFFFFFF`. -/
theorem trie_ops_02 (env : Env) (t : Trie) (ht : Reachable env t) (k v : Bytes) (h1 : v ≠ [])
    (h2 : v.length ≤ Uint24.MAX) :
    ∃ t', t.put env k (some v) = .ok t' ∧ Reachable env t' ∧ t'.get env k = .ok (some v) := by
  obtain ⟨t', e, _, g, _⟩ := Trie.get_put env t ht.WF k (some v)
    (by rw [normValue_some v h1]; intro x hx; cases hx; exact h2)
  exact ⟨t', e, .put k _ ht e, by rw [g, normValue_some v h1]⟩

/-- TRIE-OPS-03: `t.put(k, v).get(k') = t.get(k')` for `k' ≠ k`. -/
theorem trie_ops_03 (env : Env) (t t' : Trie) (ht : Reachable env t) (k : Bytes) (v : Option Bytes)
    (h : t.put env k v = .ok t') (k' : Bytes) (hne : k' ≠ k) : t'.get env k' = t.get env k' := by
  obtain ⟨w, c⟩ := put_ok_spec env t t' ht.WF k v h
  rw [Trie.get_eq_contents env _ w.1, Trie.get_eq_contents env _ ht.WF.1, c]
  have : fromKey k' ≠ fromKey k := fun e => hne (fromKey_injective e)
  simp [upd, this]

/-- TRIE-OPS-04: `t.delete(k).get(k) == null`. -/
theorem trie_ops_04 (env : Env) (t : Trie) (ht : Reachable env t) (k : Bytes) :
    ∃ t', t.delete env k = .ok t' ∧ Reachable env t' ∧ t'.get env k = .ok none := by
  obtain ⟨t', e, _, g, _⟩ := Trie.get_delete env t ht.WF k
  exact ⟨t', e, .delete k ht e, g⟩

/-- TRIE-OPS-05: `t.delete(k).get(k') = t.get(k')` for `k' ≠ k` (node coalescing included:
`delete` is `internalPut` + `coalesce`, both covered by `Trie.put_spec`). -/
theorem trie_ops_05 (env : Env) (t : Trie) (ht : Reachable env t) (k : Bytes) :
    ∃ t', t.delete env k = .ok t' ∧ ∀ k', k' ≠ k → t'.get env k' = t.get env k' := by
  obtain ⟨t', e, _, _, g⟩ := Trie.get_delete env t ht.WF k
  exact ⟨t', e, g⟩

/-- TRIE-OPS-06: `put(k, [])`, `put(k, null)` and `delete(k)` return the same trie (hence the
same hash and lookups), e.g. for the sanity case `t = {01: aa, 02: bb}`, `k = 01`. -/
theorem trie_ops_06 (env : Env) (t : Trie) (k : Bytes) :
    t.put env k (some []) = t.delete env k ∧ t.put env k none = t.delete env k := by
  have := Trie.delete_eq_put_empty env t k
  exact ⟨by rw [this.2, this.1], this.1.symm⟩

/-- TRIE-OPS-07: a key and its extension coexist, in either insertion order. -/
theorem trie_ops_07 (env : Env) (t : Trie) (ht : Reachable env t) (k s v1 v2 : Bytes) (hs : s ≠ [])
    (h1 : v1 ≠ []) (h2 : v2 ≠ []) (l1 : v1.length ≤ Uint24.MAX) (l2 : v2.length ≤ Uint24.MAX) :
    (∃ ta tb, t.put env k (some v1) = .ok ta ∧ ta.put env (k ++ s) (some v2) = .ok tb ∧
      tb.get env k = .ok (some v1) ∧ tb.get env (k ++ s) = .ok (some v2)) ∧
    (∃ ta tb, t.put env (k ++ s) (some v2) = .ok ta ∧ ta.put env k (some v1) = .ok tb ∧
      tb.get env k = .ok (some v1) ∧ tb.get env (k ++ s) = .ok (some v2)) := by
  have hne : k ++ s ≠ k := by intro e; apply hs; simpa using e
  constructor
  · obtain ⟨ta, ea, ra, ga⟩ := trie_ops_02 env t ht k v1 h1 l1
    obtain ⟨tb, eb, _, gb⟩ := trie_ops_02 env ta ra (k ++ s) v2 h2 l2
    exact ⟨ta, tb, ea, eb, by rw [trie_ops_03 env ta tb ra _ _ eb k (Ne.symm hne), ga], gb⟩
  · obtain ⟨ta, ea, ra, ga⟩ := trie_ops_02 env t ht (k ++ s) v2 h2 l2
    obtain ⟨tb, eb, _, gb⟩ := trie_ops_02 env ta ra k v1 h1 l1
    exact ⟨ta, tb, ea, eb, gb, by rw [trie_ops_03 env ta tb ra _ _ eb (k ++ s) hne, ga]⟩

/-- TRIE-OPS-08 (partial): tries are immutable values in the model, so `t` after `t.put(…)` is the
same value; its lookups and hash are determined by its contents alone. Java array aliasing and
the cache writes Java performs on the receiver are not covered here (see MODEL.md). -/
theorem trie_ops_08 (env : Env) (t t2 : Trie) (ht : Reachable env t) (k : Bytes) (v : Option Bytes)
    (_h : t.put env k v = .ok t2) :
    (∀ k', t.get env k' = .ok (t.contents (fromKey k'))) ∧ t.getHash env = .ok (t.hashS env.H) :=
  ⟨Trie.get_eq_contents env t ht.WF.1, Trie.getHash_WF env t ht.WF⟩

/-- TRIE-OPS-08 on the operational layer: Java's `put` mutates caches of the receiver (it loads
and caches children, fills `childrenSize`s); the mutated receiver still represents the original
trie, so its later `getHash()`, `toMessage()` and `get(k)` are unchanged. -/
theorem trie_ops_08_operational (env : Env) (hH : ∀ x, (env.H x).length = 32) (o : Op.OTrie) (t : Trie)
    (ht : t.Resident) (hc : t.CacheOK env.H) (h : Op.OTrie.Rep env o t) (k : Bytes) (v : Option Bytes) (d : Bool)
    (r : Op.OPutRes) (o' : Op.OTrie) (e : Op.OTrie.putSlice env Op.OFUEL o (fromKey k) v d = .ok (r, o')) :
    Op.OTrie.Rep env o' t ∧
    (∀ hsh o'', o'.hashOf env = .ok (hsh, o'') → hsh = t.hashS env.H) ∧
    (∀ key w o'', o'.get env key = .ok (w, o'') → w = t.contents (fromKey key)) := by
  have ho' : Op.OTrie.Rep env o' t := by
    rcases (Op.putOK env hH Op.OFUEL).put o t (fromKey k) v d ht hc h with e' | ⟨_, _, e'⟩ | ⟨_, _, _, _, e', _, h'⟩
    · rw [e'] at e; cases e
    · rw [e'] at e; cases e
    · rw [e'] at e; cases e; exact h'
  obtain ⟨r1, _, r3⟩ := Op.reads_agree env hH o' t ht ho'
  exact ⟨ho', fun hsh o'' e => (r1 hsh o'' e).1, fun key w o'' e => (r3 key w o'' e).1⟩

/-- TRIE-OPS-09 (Java): `deleteRecursive(k)` removes every key extending `k` iff `k` itself has a
value; otherwise (even when a value-less branching node sits exactly at `k`) nothing changes. -/
theorem trie_ops_09 (env : Env) (t : Trie) (ht : Reachable env t) (k : Bytes) :
    ∃ t', t.deleteRecursive env k = .ok t' ∧ Reachable env t' ∧
      (t.get env k ≠ .ok none →
        (∀ s, t'.get env (k ++ s) = .ok none) ∧ ∀ k', ¬ k <+: k' → t'.get env k' = t.get env k') ∧
      (t.get env k = .ok none → ∀ k', t'.get env k' = t.get env k') := by
  obtain ⟨t', e, w, c⟩ := Trie.deleteRecursive_spec env t ht.WF k
  have gk := Trie.get_eq_contents env t ht.WF.1 k
  refine ⟨t', e, .deleteRecursive k ht e, fun hk => ⟨fun s => ?_, fun k' hk' => ?_⟩, fun hk k' => ?_⟩
  · have hc : t.contents (fromKey k) ≠ none ∧ fromKey k <+: fromKey (k ++ s) :=
      ⟨fun h0 => hk (by rw [gk, h0]), fromKey_prefix (List.prefix_append _ _)⟩
    rw [Trie.get_eq_contents env _ w.1, c, drMap, ite_eq_left_of_eq_true _ _ (eq_true hc)]
  · have hc : ¬ (t.contents (fromKey k) ≠ none ∧ fromKey k <+: fromKey k') :=
      fun ⟨_, hp⟩ => hk' (prefix_of_fromKey hp)
    rw [Trie.get_eq_contents env _ w.1, c, drMap, ite_eq_right_of_eq_false _ _ (eq_false hc),
      ← Trie.get_eq_contents env _ ht.WF.1]
  · rw [gk] at hk; simp only [Except.ok.injEq] at hk
    have hc : ¬ (t.contents (fromKey k) ≠ none ∧ fromKey k <+: fromKey k') := fun ⟨h0, _⟩ => h0 hk
    rw [Trie.get_eq_contents env _ w.1, c, drMap, ite_eq_right_of_eq_false _ _ (eq_false hc),
      ← Trie.get_eq_contents env _ ht.WF.1]

theorem runOps_reachable (env : Env) : ∀ (ops : List Op) {t t' : Trie}, Reachable env t →
    runOps env t ops = .ok t' → Reachable env t'
  | [], _, _, ht, h => by cases h; exact ht
  | op :: ops, t, t', ht, h => by
    cases hop : op.run env t with
    | error e => simp [runOps, hop, bind, Except.bind] at h
    | ok t1 =>
      simp only [runOps, hop, bind, Except.bind] at h
      refine runOps_reachable env ops ?_ h
      cases op with
      | put k v => exact .put k v ht hop
      | delete k => exact .delete k ht hop

/-- TRIE-OPS-09 does not hold: in `{0100: aa, 0180: bb}` the root node sits exactly at key `01`
(shared path = the 8 bits of `01`), yet `deleteRecursive(01)` leaves `get(0100) = aa`. -/
theorem trie_ops_09_rskip_counterexample (env : Env) :
    ∃ t t', runOps env Trie.empty exD = .ok t ∧ t.sharedPath = fromKey [0x01] ∧
      t.deleteRecursive env [0x01] = .ok t' ∧ t'.get env [0x01, 0x00] = .ok (some [0xaa]) := by
  obtain ⟨t, h1, w, he, hc⟩ := exD_trie env
  have hr := runOps_reachable env exD .empty h1
  have hp : t.sharedPath = fromKey [0x01] := by
    obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
    simp only [Trie.erase, ED, Trie.mk.injEq] at he
    show p = _; rw [he.1]; decide
  obtain ⟨t', e, _, _, h⟩ := trie_ops_09 env t hr [0x01]
  have g0 : t.get env [0x01] = .ok none := by
    rw [Trie.get_eq_contents env _ w.1, hc]
    simp only [ED, show fromKey [0x01] = (List.replicate 7 false ++ [true]) ++ [] by decide, Trie.contents_mk]
  refine ⟨t, t', h1, hp, e, ?_⟩
  rw [h g0, Trie.get_eq_contents env _ w.1, hc]
  simp only [ED, show fromKey [0x01, 0x00] = (List.replicate 7 false ++ [true]) ++ false :: List.replicate 7 false by decide,
    Trie.contents_mk, NodeRef.contents, leafN, Trie.contents_leaf, ↓reduceIte]

/-- TRIE-OPS-09 sanity run (reproducer hint): `{0102: aa}.deleteRecursive(01).get(0102) == aa`. -/
theorem trie_ops_09_sanity (env : Env) :
    ∃ t t', Trie.empty.put env [0x01, 0x02] (some [0xaa]) = .ok t ∧
      t.deleteRecursive env [0x01] = .ok t' ∧ t'.get env [0x01, 0x02] = .ok (some [0xaa]) := by
  obtain ⟨t, e, hr, g⟩ := trie_ops_02 env _ .empty [0x01, 0x02] [0xaa] (by decide) (by decide)
  obtain ⟨t', e', _, _, h⟩ := trie_ops_09 env t hr [0x01]
  refine ⟨t, t', e, e', ?_⟩
  rw [h (by rw [trie_ops_03 env _ _ .empty _ _ e _ (by decide), trie_ops_01]), g]

/-- TRIE-CMP-01: in every reachable trie, every non-root node has a value or two children, the root
is the empty node or has a value or two children, and no reference points to a hash or to an
empty node. -/
theorem trie_cmp_01 (env : Env) (t : Trie) (ht : Reachable env t) :
    t.CanonNE ∨ (t.sharedPath = [] ∧ t.value = none ∧ t.valueLength = 0 ∧ t.left = .empty ∧ t.right = .empty) :=
  ht.WF.2.2

theorem contents_eq_of_get (env : Env) (t1 t2 : Trie) (h1 : Reachable env t1) (h2 : Reachable env t2)
    (h : ∀ k, t1.get env k = t2.get env k) : ∀ q, t1.contents q = t2.contents q := by
  intro q
  by_cases hq : ∃ k, q = fromKey k
  · obtain ⟨k, rfl⟩ := hq
    have := h k
    rw [Trie.get_eq_contents env _ h1.WF.1, Trie.get_eq_contents env _ h2.WF.1] at this
    simp only [Except.ok.injEq] at this; exact this
  · have a := Classical.byContradiction fun c => hq (h1.keyOnly q c)
    have b := Classical.byContradiction fun c => hq (h2.keyOnly q c)
    rw [a, b]

/-- TRIE-CMP-02: reachable tries with the same key → value map are equal up to caches, whatever
put/delete/deleteRecursive sequences produced them. -/
theorem trie_cmp_02 (env : Env) (t1 t2 : Trie) (h1 : Reachable env t1) (h2 : Reachable env t2)
    (h : ∀ k, t1.get env k = t2.get env k) : t1.erase = t2.erase :=
  Trie.WF_unique env.H t1 t2 h1.WF h2.WF (contents_eq_of_get env t1 t2 h1 h2 h)

/-- TRIE-CMP-03: reachable tries with the same key → value map have equal `getHash()` and equal
root `toMessage()`. -/
theorem trie_cmp_03 (env : Env) (t1 t2 : Trie) (h1 : Reachable env t1) (h2 : Reachable env t2)
    (h : ∀ k, t1.get env k = t2.get env k) :
    t1.toMessage env = t2.toMessage env ∧ t1.getHash env = t2.getHash env :=
  Trie.WF_same_encoding env t1 t2 h1.WF h2.WF (contents_eq_of_get env t1 t2 h1 h2 h)

end RskjTrie.Obligations
