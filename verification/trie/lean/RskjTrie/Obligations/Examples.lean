import RskjTrie.Obligations.Common
/-!
# Concrete reachable tries of the reproducer hints

Each is built by `put`s from `new Trie()`; `runOps_explicit` identifies it (up to caches) with an
explicit expected trie, whose message is then evaluated.
-/
namespace RskjTrie.Obligations
open RskjTrie Trie TrieKeySlice

set_option linter.unusedSimpArgs false

macro "enc_eval" : tactic => `(tactic| (simp (config := {decide := true}) [Trie.encS, NodeRef.encS,
    Trie.encP, NodeRef.encP, leafN, Trie.isTerminal, Trie.isEmptyTrie, Trie.isEmptyTrieOf,
    NodeRef.isEmpty, NodeRef.ofNode, SharedPathSerializer.isPresent, SharedPathSerializer.serializeInto,
    SharedPathSerializer.serializeBytes, SharedPathSerializer.lsharedPrefix, Trie.mkFlags,
    VarInt.encode, VarInt.sizeOf, wrap64, Uint8.encode, Uint24.encode, TrieKeySlice.encode,
    PathEncoder.encode, PathEncoder.encodeBinaryPath, PathEncoder.encodeLoop,
    PathEncoder.calculateEncodedLength]))

theorem ite_swap2 {α : Type} (q A B : List Bool) (x y z : α) (hAB : A ≠ B) :
    (if q = A then x else if q = B then y else z) = (if q = B then y else if q = A then x else z) := by
  by_cases h1 : q = A
  · subst h1; simp [hAB]
  · simp [h1]

theorem ops_ok (ops : List Op) (h : ∀ op ∈ ops, ∃ x, op.val = some x ∧ x.length ≤ Uint24.MAX) : OpsOK ops := by
  intro op hop x hx
  obtain ⟨y, hy, hl⟩ := h op hop
  rw [hy] at hx; cases hx; exact hl

/-! ## A: `{00: 01, 0000: 02}` (TRIE-NODE-04) -/

def exA : List Op := [.put [0x00] (some [0x01]), .put [0x00, 0x00] (some [0x02])]
def EA : Trie := ⟨List.replicate 8 false, some [0x01], .node (leafN (List.replicate 7 false) [0x02]),
  .empty, 1, none, none⟩

theorem exA_msg (env : Env) : ∃ t, runOps env Trie.empty exA = .ok t ∧ t.WF env.H ∧
    t.toMessage env = .ok [0x5a, 0x07, 0x00, 0x04, 0x50, 0x06, 0x00, 0x02, 0x04, 0x01] := by
  obtain ⟨t, h1, w, _, h2, _⟩ := runOps_explicit env exA
    (ops_ok _ (by intro op hop; simp [exA] at hop; rcases hop with rfl | rfl <;> simp [Op.val, normValue, Uint24.MAX]))
    EA (by
      refine ⟨⟨Or.inr ⟨_, rfl, rfl, by decide, by decide⟩, leafN_resident _ _ (by decide) (by decide), trivial⟩,
        by simp [EA, Trie.CacheOK, NodeRef.CacheOK, leafN], Or.inl ?_⟩
      simp [EA, Trie.CanonNE, NodeRef.Canon, leafN])
    (by
      intro q
      rw [show exA = [.put [0x00] (some [0x01]), .put [0x00, 0x00] (some [0x02])] from rfl, mapAfter_two,
        show fromKey [0x00] = List.replicate 8 false by decide,
        show fromKey [0x00, 0x00] = List.replicate 8 false ++ false :: List.replicate 7 false by decide]
      rw [EA, contents_val_left, normValue_some _ (by decide), normValue_some _ (by decide)]
      exact ite_swap2 _ _ _ _ _ _ (by decide))
  refine ⟨t, h1, w, ?_⟩
  rw [h2, EA]; congr 1

/-! ## B: `{00‖7x00: 32x5a, 80‖7x00: 32x5a}` (TRIE-EMB-03, TRIE-NODE-07) -/

def v32 : Bytes := List.replicate 32 0x5a
def kB1 : Bytes := List.replicate 8 0x00
def kB2 : Bytes := 0x80 :: List.replicate 7 0x00
def exB : List Op := [.put kB1 (some v32), .put kB2 (some v32)]
def EB : Trie := ⟨[], none, .node (leafN (List.replicate 63 false) v32),
  .node (leafN (List.replicate 63 false) v32), 0, none, none⟩
/-- The 43-byte leaf message: flags, escaped length 63, 8 path bytes, the value. -/
def leafB : Bytes := [0x50, 0xff, 0x3f] ++ List.replicate 8 0x00 ++ v32

set_option maxRecDepth 20000 in
theorem exB_msg (env : Env) : ∃ t, runOps env Trie.empty exB = .ok t ∧ t.WF env.H ∧
    t.toMessage env = .ok ([0x4f, 0x2b] ++ leafB ++ [0x2b] ++ leafB ++ [0x56]) ∧ leafB.length = 43 := by
  obtain ⟨t, h1, w, _, h2, _⟩ := runOps_explicit env exB
    (ops_ok _ (by intro op hop; simp [exB] at hop; rcases hop with rfl | rfl <;>
      simp [Op.val, normValue, v32, Uint24.MAX]))
    EB (by
      refine ⟨⟨Or.inl ⟨rfl, rfl⟩, leafN_resident _ _ (by decide) (by decide),
        leafN_resident _ _ (by decide) (by decide)⟩,
        by simp [EB, Trie.CacheOK, NodeRef.CacheOK, leafN], Or.inl ?_⟩
      simp [EB, Trie.CanonNE, NodeRef.Canon, leafN])
    (by
      intro q
      rw [show exB = [.put kB1 (some v32), .put kB2 (some v32)] from rfl, mapAfter_two,
        show fromKey kB1 = false :: List.replicate 63 false by decide,
        show fromKey kB2 = true :: List.replicate 63 false by decide]
      rw [EB, contents_two_leaves, normValue_some _ (by decide), List.nil_append, List.nil_append]
      exact ite_swap2 _ _ _ _ _ _ (by decide))
  refine ⟨t, h1, w, ?_, by decide⟩
  rw [h2, EB]; congr 1; enc_eval

/-! ## C: `{01: 33xab, 0101: 02}` (TRIE-NODE-08) -/

def v33 : Bytes := List.replicate 33 0xab
def exC : List Op := [.put [0x01] (some v33), .put [0x01, 0x01] (some [0x02])]
def pC : List Bool := [false, false, false, false, false, false, true]
def EC : Trie := ⟨List.replicate 7 false ++ [true], some v33, .node (leafN pC [0x02]), .empty, 33, none, none⟩

theorem exC_msg (env : Env) : ∃ t, runOps env Trie.empty exC = .ok t ∧ t.WF env.H ∧
    t.toMessage env = .ok ([0x7a, 0x07, 0x01, 0x04, 0x50, 0x06, 0x02, 0x02, 0x04] ++ env.H v33 ++
      [0x00, 0x00, 0x21]) := by
  obtain ⟨t, h1, w, _, h2, _⟩ := runOps_explicit env exC
    (ops_ok _ (by intro op hop; simp [exC] at hop; rcases hop with rfl | rfl <;>
      simp [Op.val, normValue, v33, Uint24.MAX]))
    EC (by
      refine ⟨⟨Or.inr ⟨_, rfl, rfl, by decide, by decide⟩, leafN_resident _ _ (by decide) (by decide), trivial⟩,
        by simp [EC, Trie.CacheOK, NodeRef.CacheOK, leafN], Or.inl ?_⟩
      simp [EC, Trie.CanonNE, NodeRef.Canon, leafN])
    (by
      intro q
      rw [show exC = [.put [0x01] (some v33), .put [0x01, 0x01] (some [0x02])] from rfl, mapAfter_two,
        show fromKey [0x01] = List.replicate 7 false ++ [true] by decide,
        show fromKey [0x01, 0x01] = (List.replicate 7 false ++ [true]) ++ false :: pC by decide]
      rw [EC, contents_val_left, normValue_some _ (by decide), normValue_some _ (by decide)]
      exact ite_swap2 _ _ _ _ _ _ (by decide))
  refine ⟨t, h1, w, ?_⟩
  rw [h2, EC]; congr 1

/-! ## D: `{0100: aa, 0180: bb}` (TRIE-OPS-09) -/

def exD : List Op := [.put [0x01, 0x00] (some [0xaa]), .put [0x01, 0x80] (some [0xbb])]
def ED : Trie := ⟨List.replicate 7 false ++ [true], none, .node (leafN (List.replicate 7 false) [0xaa]),
  .node (leafN (List.replicate 7 false) [0xbb]), 0, none, none⟩

theorem exD_trie (env : Env) : ∃ t, runOps env Trie.empty exD = .ok t ∧ t.WF env.H ∧
    t.erase = ED.erase ∧ ∀ q, t.contents q = ED.contents q := by
  obtain ⟨t, h1, w, he, _, _⟩ := runOps_explicit env exD
    (ops_ok _ (by intro op hop; simp [exD] at hop; rcases hop with rfl | rfl <;> simp [Op.val, normValue, Uint24.MAX]))
    ED (by
      refine ⟨⟨Or.inl ⟨rfl, rfl⟩, leafN_resident _ _ (by decide) (by decide),
        leafN_resident _ _ (by decide) (by decide)⟩,
        by simp [ED, Trie.CacheOK, NodeRef.CacheOK, leafN], Or.inl ?_⟩
      simp [ED, Trie.CanonNE, NodeRef.Canon, leafN])
    (by
      intro q
      rw [show exD = [.put [0x01, 0x00] (some [0xaa]), .put [0x01, 0x80] (some [0xbb])] from rfl, mapAfter_two,
        show fromKey [0x01, 0x00] = (List.replicate 7 false ++ [true]) ++ false :: List.replicate 7 false by decide,
        show fromKey [0x01, 0x80] = (List.replicate 7 false ++ [true]) ++ true :: List.replicate 7 false by decide]
      rw [ED, contents_two_leaves, normValue_some _ (by decide), normValue_some _ (by decide)]
      exact ite_swap2 _ _ _ _ _ _ (by decide))
  refine ⟨t, h1, w, he, fun q => ?_⟩
  have e1 : t.contents q = t.erase.contents q := (Trie.contents_erase t q).symm
  rw [e1, he, Trie.contents_erase]

end RskjTrie.Obligations
