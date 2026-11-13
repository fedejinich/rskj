import RskjTrie.Proofs.RoundTrip
/-!
# Proofs: flag byte facts that hold for every node, and version-bit blindness of the parser
-/
namespace RskjTrie
open Trie

theorem except_bind_eq_ok {ε α β : Type} (x : Except ε α) (f : α → Except ε β) (b : β) :
    (x >>= f) = .ok b ↔ ∃ a, x = .ok a ∧ f a = .ok b := by
  cases x with
  | error e => simp [bind, Except.bind]
  | ok a => simp [bind, Except.bind]

/-- **Every** successful `toMessage` (any trie, any store) starts with the flags byte
`mkFlags …`, whose version bits are `01`. -/
theorem Trie.internalToMessage_head (env : Env) (fuel : Nat) (t : Trie) (m : Bytes)
    (h : t.internalToMessage env fuel = .ok m) :
    ∃ a b c d e f rest, m = Trie.mkFlags a b c d e f :: rest ∧
      (Trie.mkFlags a b c d e f) &&& 0b11000000 = 0b01000000 := by
  rw [Trie.internalToMessage] at h
  simp only [except_bind_eq_ok] at h
  obtain ⟨cs, _, le, _, re, _, lb, _, rb, _, vb, _, hm⟩ := h
  simp only [except_pure, Except.ok.injEq] at hm
  exact ⟨_, _, _, _, _, _, _, hm.symm, mkFlags_version ..⟩

/-- `bitSet f m` for `m < 0x40` only depends on the low six bits of `f`. -/
theorem bitSet_low (f g : UInt8) (h : f &&& 0x3F = g &&& 0x3F) (m : UInt8) (hm : 0x3F &&& m = m) :
    bitSet f m = bitSet g m := by
  unfold bitSet
  have e1 : f &&& m = (f &&& 0x3F) &&& m := by rw [UInt8.and_assoc, hm]
  have e2 : g &&& m = (g &&& 0x3F) &&& m := by rw [UInt8.and_assoc, hm]
  rw [e1, e2, h]

/-- **The RSKIP107 parser ignores the version bits**: two messages that differ only in bits 6-7
of the flags byte parse to the same result (Trie.java:260-261). -/
theorem Trie.fromMessageRskip107_version_blind (env : Env) (F : Nat) (f g : UInt8) (rest : Bytes)
    (h : f &&& 0x3F = g &&& 0x3F) :
    fromMessageRskip107 env F (f :: rest) = fromMessageRskip107 env F (g :: rest) := by
  cases F with
  | zero => rfl
  | succ F =>
    simp only [fromMessageRskip107, StateT.run']
    rw [BB.bind_ok _ _ _ _ _ (BB.get_cons f rest), BB.bind_ok _ _ _ _ _ (BB.get_cons g rest)]
    rw [bitSet_low f g h 0b00100000 (by decide), bitSet_low f g h 0b00010000 (by decide),
      bitSet_low f g h 0b00001000 (by decide), bitSet_low f g h 0b00000100 (by decide),
      bitSet_low f g h 0b00000010 (by decide), bitSet_low f g h 0b00000001 (by decide)]

/-- `fromMessage` selects the legacy parser iff the first byte is `0x02` (Trie.java:163-175). -/
theorem Trie.fromMessage_dispatch (env : Env) (b : UInt8) (rest : Bytes) :
    fromMessage env (b :: rest) =
      if b.toNat = 2 then fromMessageOrchid env (b :: rest)
      else fromMessageRskip107 env (rest.length + 1 + 1) (b :: rest) := by
  unfold fromMessage; simp only [idx, List.getElem?_cons_zero, except_bind_ok, ARITY, List.length_cons]
  by_cases h : b.toNat = 2 <;> simp [h]

/-- Flags bytes are in `0x40..0x7F`, so never `0x02` (TRIE-SER-04). -/
theorem mkFlags_range (a b c d e f : Bool) :
    0x40 ≤ (mkFlags a b c d e f).toNat ∧ (mkFlags a b c d e f).toNat ≤ 0x7F := by
  revert a b c d e f; decide

end RskjTrie
