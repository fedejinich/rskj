import RskjTrie.Proofs.Resident
/-!
# Proofs: node serialization round trip and flags (RSKIP107 format)

`Trie.reparse H t` is what `fromMessage` must return for the message of a resident trie `t`:
the same node, except that
* a non-embedded child becomes a hash reference (`NodeRef.hash (hash of the child)`),
* an embedded child is itself re-parsed,
* a long value (> 32 bytes) becomes lazy (`value = none`, read from the store on demand),
* the caches hold the values Java computes while parsing (`valueHash = H value` for a present
  value, `childrenSize` = the serialized tree size).
-/
namespace RskjTrie
open Trie

mutual
def Trie.reparse (H : Bytes → Bytes) : Trie → Trie
  | ⟨p, v, l, r, vl, _, _⟩ =>
    ⟨p, (if vl > 32 then none else v), NodeRef.reparse H l, NodeRef.reparse H r, vl,
      (if vl > 0 then some (H (v.getD [])) else none),
      some (Trie.encS H ⟨p, v, l, r, vl, none, none⟩).2⟩
def NodeRef.reparse (H : Bytes → Bytes) : NodeRef Trie → NodeRef Trie
  | .empty => .empty
  | .hash h => .hash h
  | .node c =>
    if c.isTerminal && decide ((Trie.encS H c).1.length ≤ 44) then .node (Trie.reparse H c)
    else .hash (Trie.hashS H c)
end

mutual
/-- Every shared path fits Java's `int` VarInt read (`< 2^31` bits). -/
def Trie.PathsOK : Trie → Prop
  | ⟨p, _, l, r, _, _, _⟩ => p.length < 2 ^ 31 ∧ NodeRef.PathsOK l ∧ NodeRef.PathsOK r
def NodeRef.PathsOK : NodeRef Trie → Prop
  | .node t => Trie.PathsOK t
  | _ => True
end

/-! ## Flags -/

theorem bitSet_mkFlags (a b c d e f : Bool) :
    bitSet (mkFlags a b c d e f) 0b00100000 = a ∧
    bitSet (mkFlags a b c d e f) 0b00010000 = b ∧
    bitSet (mkFlags a b c d e f) 0b00001000 = c ∧
    bitSet (mkFlags a b c d e f) 0b00000100 = d ∧
    bitSet (mkFlags a b c d e f) 0b00000010 = e ∧
    bitSet (mkFlags a b c d e f) 0b00000001 = f := by
  revert a b c d e f; decide

/-- The version bits (7,6) of every flags byte are `01`. -/
theorem mkFlags_version (a b c d e f : Bool) :
    (mkFlags a b c d e f) &&& 0b11000000 = 0b01000000 := by
  revert a b c d e f; decide

theorem mkFlags_ne_arity (a b c d e f : Bool) : (mkFlags a b c d e f).toNat ≠ 2 := by
  revert a b c d e f; decide

/-! ## Pieces -/

theorem Uint24.decode_encode (v : Nat) (h : v ≤ Uint24.MAX) :
    Uint24.decode (Uint24.encode v) 0 = .ok v := by
  have h' : v ≤ 16777215 := h
  simp only [Uint24.decode, Uint24.encode, idx, List.getElem?_cons_zero, List.getElem?_cons_succ,
    except_bind_ok, toUInt8_toNat, Uint24.mk, Uint24.MAX]
  have : v % 256 + v / 256 % 256 * 256 + v / 65536 % 256 * 65536 = v := by omega
  rw [this]; simp; omega

theorem NodeRef.isEmpty_reparse (H : Bytes → Bytes) (r : NodeRef Trie) :
    (r.reparse H).isEmpty = r.isEmpty := by
  cases r with
  | empty => rfl
  | hash => rfl
  | node c => simp only [NodeRef.reparse]; split <;> rfl

theorem Trie.isEmptyTrie_reparse (H : Bytes → Bytes) (c : Trie) :
    (c.reparse H).isEmptyTrie = c.isEmptyTrie := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := c
  simp only [Trie.reparse, isEmptyTrie, isEmptyTrieOf, NodeRef.isEmpty_reparse]

theorem readValue_ok (env : Env) (v : Option Bytes) (vl : Nat) (hv : ValueOK v vl)
    (hH : ∀ x, (env.H x).length = 32) :
    readValue env (decide (vl > 32))
      (if decide (vl > 32) then env.H (v.getD []) ++ Uint24.encode vl else if vl > 0 then v.getD [] else [])
      = .ok (((if vl > 32 then none else v), vl, (if vl > 0 then some (env.H (v.getD [])) else none)), []) := by
  rcases hv with ⟨rfl, rfl⟩ | ⟨x, rfl, hx, hpos, hmax⟩
  · simp only [readValue, gt_iff_lt, Nat.not_lt_zero, decide_false, Bool.false_eq_true, ↓reduceIte]
    rw [BB.bind_ok _ _ _ _ _ (BB.remaining_eq _)]
    simp
  · have hmax' : vl ≤ 16777215 := hmax
    by_cases hl : vl > 32
    · simp only [hl, decide_true, ↓reduceIte, readValue, Option.getD_some]
      rw [BB.bind_ok _ _ _ _ _ (BB.getN_append _ _ _ (hH x))]
      rw [BB.bind_ok _ _ _ _ _ (BB.getN_self _ _ (by simp [Uint24.encode]))]
      simp only [Uint24.decode_encode vl hmax]
      rw [BB.bind_ok _ _ _ _ _ (BB.lift_ok _ _)]
      simp [hpos]
    · simp only [hl, decide_false, Bool.false_eq_true, ↓reduceIte, hpos, readValue, Option.getD_some]
      rw [BB.bind_ok _ _ _ _ _ (BB.remaining_eq _)]
      have hne : x.length ≠ 0 := by omega
      simp only [hne, ne_eq, not_false_eq_true, ↓reduceIte]
      rw [BB.bind_ok _ _ _ _ _ (BB.getN_len x)]
      have : Uint24.mk x.length = .ok vl := by
        simp only [Uint24.mk, hx, show ¬ (vl > Uint24.MAX) from by omega, ↓reduceIte]
      rw [BB.bind_ok _ _ _ _ _ (by rw [this]; exact BB.lift_ok _ _)]
      simp

end RskjTrie

namespace RskjTrie
open Trie

theorem readChild_node (env : Env) (hH : ∀ x, (env.H x).length = 32) (c : Trie)
    (hne : c.isEmptyTrie = false) (fuel : Nat) (rest : Bytes)
    (ih : (c.isTerminal && decide ((Trie.encS env.H c).1.length ≤ 44)) = true →
      fromMessageRskip107 env fuel (Trie.encS env.H c).1 = .ok (c.reparse env.H)) :
    readChild (fromMessageRskip107 env fuel) true (NodeRef.encS env.H (.node c)).2.2
      ((NodeRef.encS env.H (.node c)).1 ++ rest) = .ok ((NodeRef.node c).reparse env.H, rest) := by
  simp only [NodeRef.encS, NodeRef.reparse, readChild, ↓reduceIte]
  by_cases hemb : (c.isTerminal && decide ((Trie.encS env.H c).1.length ≤ 44)) = true
  · simp only [hemb, ↓reduceIte]
    have hle : (Trie.encS env.H c).1.length ≤ 44 := by simp at hemb; exact hemb.2
    simp only [Uint8.encode, List.cons_append, List.nil_append]
    rw [BB.bind_ok _ _ _ _ _ (BB.getN_one_cons _ _)]
    have hdec : Uint8.decode [(Trie.encS env.H c).1.length.toUInt8] 0 =
        .ok (Trie.encS env.H c).1.length := by
      simp only [Uint8.decode, idx, List.getElem?_cons_zero, except_bind_ok, toUInt8_toNat,
        Uint8.mk, Nat.mod_eq_of_lt (show (Trie.encS env.H c).1.length < 256 by omega),
        show ¬ ((Trie.encS env.H c).1.length > 0xff) by omega, ↓reduceIte]
    rw [BB.bind_ok _ _ _ _ _ (by rw [hdec]; exact BB.lift_ok _ _)]
    rw [BB.bind_ok _ _ _ _ _ (BB.getN_append _ _ _ rfl)]
    rw [BB.bind_ok _ _ _ _ _ (by rw [ih hemb]; exact BB.lift_ok _ _)]
    simp [NodeRef.ofNode, Trie.isEmptyTrie_reparse, hne]
  · simp only [hemb, Bool.false_eq_true, ↓reduceIte]
    have hl : (if c.isEmptyTrie = true then env.H [0x80] else env.H (Trie.encS env.H c).1).length = 32 := by
      split <;> exact hH _
    rw [BB.bind_ok _ _ _ _ _ (BB.getN_append _ _ _ hl)]
    simp [Trie.hashS]


theorem deserialize_sp (p : TrieKeySlice) (hp : p.length < 2 ^ 31) (rest : Bytes) :
    SharedPathSerializer.deserialize (SharedPathSerializer.isPresent p)
      (SharedPathSerializer.serializeInto p ++ rest) = .ok (p, rest) := by
  by_cases h : SharedPathSerializer.isPresent p = true
  · rw [h]; exact SharedPathSerializer.deserialize_serializeInto p
      (by simp [SharedPathSerializer.isPresent] at h; omega) hp rest
  · have hp0 : p = [] := by
      simp [SharedPathSerializer.isPresent] at h; exact h
    subst hp0
    simp [SharedPathSerializer.isPresent, SharedPathSerializer.serializeInto,
      SharedPathSerializer.deserialize, TrieKeySlice.empty]

mutual
theorem Trie.parse_encS (env : Env) (hH : ∀ x, (env.H x).length = 32) :
    ∀ (t : Trie), t.Resident → t.PathsOK → ∀ F, (Trie.encS env.H t).1.length < F →
      fromMessageRskip107 env F (Trie.encS env.H t).1 = .ok (t.reparse env.H)
  | ⟨p, v, l, r, vl, vh, cs⟩, ⟨hv, hrl, hrr⟩, ⟨hp, hpl, hpr⟩, F, hF => by
    obtain ⟨F, rfl⟩ : ∃ F', F = F' + 1 := ⟨F - 1, by omega⟩
    have hlenL : (NodeRef.encS env.H l).1.length < F := by
      simp only [Trie.encS, List.length_append, List.length_cons] at hF; omega
    have hlenR : (NodeRef.encS env.H r).1.length < F := by
      simp only [Trie.encS, List.length_append, List.length_cons] at hF; omega
    have il := NodeRef.readChild_encS env hH l hrl hpl F hlenL
    have ir := NodeRef.readChild_encS env hH r hrr hpr F hlenR
    simp only [fromMessageRskip107, Trie.encS, StateT.run', List.cons_append, List.append_assoc]
    rw [BB.bind_ok _ _ _ _ _ (BB.get_cons _ _)]
    simp only [bitSet_mkFlags]
    rw [BB.bind_ok _ _ _ _ _ (deserialize_sp p hp _)]
    rw [BB.bind_ok _ _ _ _ _ (il _)]
    rw [BB.bind_ok _ _ _ _ _ (ir _)]
    have hrv := readValue_ok env v vl hv hH
    have hcvl : checkValueLength ⟨p, (if vl > 32 then none else v), NodeRef.reparse env.H l,
        NodeRef.reparse env.H r, vl, (if vl > 0 then some (env.H (v.getD [])) else none),
        some (Trie.encS env.H ⟨p, v, l, r, vl, none, none⟩).2⟩ = .ok () := by
      unfold checkValueLength
      rcases hv with ⟨rfl, rfl⟩ | ⟨x, rfl, hx, hpos, _⟩
      · simp
      · by_cases hl : vl > 32 <;> simp [hl, hx, hpos]
    by_cases hterm : (l.isEmpty && r.isEmpty) = true
    · have : (!l.isEmpty || !r.isEmpty) = false := by
        simp only [Bool.and_eq_true] at hterm; simp [hterm]
      simp only [this, hterm, Bool.not_true, Bool.false_eq_true, ↓reduceIte, List.nil_append]
      rw [BB.bind_ok _ _ _ _ _ (BB.pure_run _ _)]
      rw [BB.bind_ok _ _ _ _ _ hrv]
      rw [BB.bind_ok _ _ _ _ _ (BB.remaining_eq _)]
      simp only [List.length_nil, gt_iff_lt, Nat.lt_irrefl,
        ↓reduceIte]
      have e : (Trie.encS env.H ⟨p, v, l, r, vl, none, none⟩).2 = 0 := by simp [Trie.encS, hterm]
      rw [e] at hcvl
      rw [BB.bind_ok _ _ _ _ _ (by rw [hcvl]; exact BB.lift_ok _ _)]
      simp [Trie.reparse, e]
    · have : (!l.isEmpty || !r.isEmpty) = true := by
        simp only [Bool.and_eq_true, not_and] at hterm
        cases hle : l.isEmpty <;> simp_all
      simp only [this, hterm, Bool.not_false, Bool.false_eq_true, ↓reduceIte]
      rw [Trie.readVarInt, BB.bind_ok _ _ _ _ _ (readVarInt_encode _ (by unfold wrap64; omega) _)]
      rw [BB.bind_ok _ _ _ _ _ hrv]
      rw [BB.bind_ok _ _ _ _ _ (BB.remaining_eq _)]
      simp only [List.length_nil, gt_iff_lt, Nat.lt_irrefl,
        ↓reduceIte]
      have e : (Trie.encS env.H ⟨p, v, l, r, vl, none, none⟩).2 =
          wrap64 (((NodeRef.encS env.H l).2.1 : Int) + (NodeRef.encS env.H r).2.1) := by
        simp [Trie.encS, hterm]
      rw [e] at hcvl
      rw [BB.bind_ok _ _ _ _ _ (by rw [hcvl]; exact BB.lift_ok _ _)]
      simp [Trie.reparse, e]
theorem NodeRef.readChild_encS (env : Env) (hH : ∀ x, (env.H x).length = 32) :
    ∀ (r : NodeRef Trie), r.Resident → r.PathsOK → ∀ F, (NodeRef.encS env.H r).1.length < F →
      ∀ rest, readChild (fromMessageRskip107 env F) (!r.isEmpty) (NodeRef.encS env.H r).2.2
        ((NodeRef.encS env.H r).1 ++ rest) = .ok (r.reparse env.H, rest)
  | .empty, _, _, F, _, rest => by
    simp only [readChild, NodeRef.encS, NodeRef.reparse, NodeRef.isEmpty, Bool.not_true,
      Bool.false_eq_true, ↓reduceIte, List.nil_append, BB.pure_run]
  | .hash _, h, _, _, _, _ => absurd h (by simp [NodeRef.Resident])
  | .node c, ⟨hres, hne⟩, hpc, F, hF, rest => by
    apply readChild_node env hH c hne F rest
    intro hemb
    apply Trie.parse_encS env hH c hres hpc F
    simp only [NodeRef.encS, hemb, ↓reduceIte, Uint8.encode, List.length_append,
      List.length_cons, List.length_nil] at hF
    omega
end

/-- The first byte of a message is the flags byte `mkFlags …` of the node's fields. -/
theorem Trie.encS_head (H : Bytes → Bytes) (p v l r vl vh cs) :
    (Trie.encS H ⟨p, v, l, r, vl, vh, cs⟩).1 = Trie.mkFlags (decide (vl > 32))
      (SharedPathSerializer.isPresent p) (!l.isEmpty) (!r.isEmpty)
      (NodeRef.encS H l).2.2 (NodeRef.encS H r).2.2 :: (Trie.encS H ⟨p, v, l, r, vl, vh, cs⟩).1.tail := by
  simp [Trie.encS]

/-- **Flags** (RSKIP107 node format): the message of every resident node starts with a flags
byte whose version bits are `01` and whose bits 5..0 are set iff, respectively, the value is long
(`> 32` bytes), the shared path is non-empty, the left / right child is present, and the left /
right child is embedded. -/
theorem Trie.toMessage_flags (env : Env) (t : Trie) (hres : t.Resident) (hc : t.CacheOK env.H) :
    ∃ f rest, t.toMessage env = .ok (f :: rest) ∧
      f &&& 0b11000000 = 0b01000000 ∧
      bitSet f 0b00100000 = t.hasLongValue ∧
      bitSet f 0b00010000 = decide (t.sharedPath ≠ []) ∧
      bitSet f 0b00001000 = !t.left.isEmpty ∧
      bitSet f 0b00000100 = !t.right.isEmpty ∧
      bitSet f 0b00000010 = (NodeRef.encS env.H t.left).2.2 ∧
      bitSet f 0b00000001 = (NodeRef.encS env.H t.right).2.2 := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
  have h := ((Trie.encOK env _ hres hc) FUEL).2.1
  refine ⟨_, _, by rw [Trie.toMessage, h, Trie.encS_head], mkFlags_version .., ?_⟩
  obtain ⟨h1, h2, h3, h4, h5, h6⟩ := bitSet_mkFlags (decide (vl > 32)) (SharedPathSerializer.isPresent p)
    (!l.isEmpty) (!r.isEmpty) (NodeRef.encS env.H l).2.2 (NodeRef.encS env.H r).2.2
  refine ⟨by rw [h1]; rfl, ?_, h3, h4, h5, h6⟩
  rw [h2]; simp [SharedPathSerializer.isPresent, List.length_pos_iff]

/-- **Round trip** (RSKIP107 format): for every resident node with consistent caches and paths
shorter than `2^31` bits, and a hash function with 32-byte outputs, `toMessage` succeeds and
`fromMessage` of the result returns `t.reparse H`: the same node with every non-embedded child
replaced by its hash, every embedded child re-parsed the same way, long values made lazy
(`value = none`, same `valueLength`, `valueHash = H value`) and the caches filled. -/
theorem Trie.fromMessage_toMessage (env : Env) (hH : ∀ x, (env.H x).length = 32) (t : Trie)
    (hres : t.Resident) (hc : t.CacheOK env.H) (hp : t.PathsOK) :
    t.toMessage env = .ok (Trie.encS env.H t).1 ∧
    Trie.fromMessage env (Trie.encS env.H t).1 = .ok (t.reparse env.H) := by
  refine ⟨((Trie.encOK env _ hres hc) FUEL).2.1, ?_⟩
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
  unfold Trie.fromMessage
  rw [Trie.encS_head]
  simp only [idx, List.getElem?_cons_zero, except_bind_ok]
  simp only [ARITY, mkFlags_ne_arity, ↓reduceIte]
  rw [← Trie.encS_head]
  exact Trie.parse_encS env hH _ hres hp _ (by omega)

end RskjTrie
