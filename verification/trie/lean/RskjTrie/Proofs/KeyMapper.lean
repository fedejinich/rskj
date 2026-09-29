import RskjTrie.TrieKeyMapper
/-!
# Proofs: `TrieKeyMapper` key layout (RSKIP-Unitrie key mapping)
-/
namespace RskjTrie.TrieKeyMapper

variable (H : Bytes → Bytes)

/-- Account key: `0x00 ++ take 10 (H addr) ++ addr`. -/
theorem accountKey_layout (addr : Bytes) :
    getAccountKey H addr = [0x00] ++ (H addr).take 10 ++ addr := rfl

/-- Code key: `accountKey ++ 0x80`. -/
theorem codeKey_layout (addr : Bytes) : getCodeKey H addr = getAccountKey H addr ++ [0x80] := rfl

/-- Storage key: `accountKey ++ 0x00 ++ take 10 (H slot32) ++ stripLeadingZeroes slot32`
(the all-zero slot strips to `[0x00]`). -/
theorem storageKey_layout (addr slot : Bytes) :
    getAccountStorageKey H addr slot =
      getAccountKey H addr ++ [0x00] ++ ((H slot).take 10 ++ stripLeadingZeroes slot) := rfl

theorem stripLeadingZeroes_zero (n : Nat) : stripLeadingZeroes (List.replicate n 0) = [0x00] := by
  unfold stripLeadingZeroes
  have : (List.replicate n (0 : UInt8)).dropWhile (· == 0) = [] := by
    induction n with
    | zero => rfl
    | succ n ih => simp [List.replicate_succ, ih]
  rw [this]

/-- `stripLeadingZeroes` removes exactly the leading zero bytes of a non-zero word. -/
theorem stripLeadingZeroes_spec (slot : Bytes) :
    ∃ z, slot = List.replicate z 0 ++ slot.dropWhile (· == 0) ∧
      (slot.dropWhile (· == 0) = [] → stripLeadingZeroes slot = [0x00]) ∧
      (slot.dropWhile (· == 0) ≠ [] → stripLeadingZeroes slot = slot.dropWhile (· == 0)) := by
  refine ⟨slot.length - (slot.dropWhile (· == 0)).length, ?_, ?_, ?_⟩
  · induction slot with
    | nil => rfl
    | cons b bs ih =>
      by_cases hb : b = 0
      · subst hb
        simp only [List.dropWhile_cons, beq_self_eq_true, ↓reduceIte, List.length_cons]
        have hle : (bs.dropWhile (· == 0)).length ≤ bs.length := by
          have := List.dropWhile_suffix (p := (· == (0 : UInt8))) (l := bs); exact this.length_le
        rw [show bs.length + 1 - (bs.dropWhile (· == 0)).length =
          (bs.length - (bs.dropWhile (· == 0)).length) + 1 by omega, List.replicate_succ]
        simp only [List.cons_append]; exact congrArg _ ih
      · have : (b == 0) = false := by simpa using hb
        simp [this]
  · intro h; unfold stripLeadingZeroes; rw [h]
  · intro h; unfold stripLeadingZeroes; split
    · next h' => exact absurd h' h
    · rfl

/-- The address is recoverable from the account key (its last 20 bytes, key length 31). -/
theorem address_recoverable (addr : Bytes) (h20 : addr.length = 20) (h32 : (H addr).length = 32) :
    (getAccountKey H addr).length = 31 ∧ (getAccountKey H addr).drop 11 = addr := by
  simp [getAccountKey, mapRskAddressToKey, secureKeyPrefix, DOMAIN_PREFIX, SECURE_KEY_SIZE, h20, h32]

/-- Address and slot are recoverable from a storage key: the address from bytes 11..31, the
stripped slot from byte 42 on, and the full 32-byte slot is the stripped slot left-padded with
zeros (the all-zero slot is stored as the single byte `0x00`). -/
theorem storage_recoverable (addr slot : Bytes) (h20 : addr.length = 20) (hs : slot.length = 32)
    (hH : ∀ x, (H x).length = 32) :
    let key := getAccountStorageKey H addr slot
    (key.drop 11).take 20 = addr ∧ key.drop 42 = stripLeadingZeroes slot ∧
    slot = List.replicate (32 - (slot.dropWhile (· == 0)).length) 0 ++ slot.dropWhile (· == 0) := by
  intro key
  have e : key = ([0x00] ++ (H addr).take 10 ++ addr) ++ [0x00] ++
      ((H slot).take 10 ++ stripLeadingZeroes slot) := rfl
  have e2 : key = ([0x00] ++ (H addr).take 10) ++ (addr ++ ([0x00] ++
      ((H slot).take 10 ++ stripLeadingZeroes slot))) := by rw [e]; simp
  have l1 : ([0x00] ++ (H addr).take 10 : Bytes).length = 11 := by simp [hH]
  have e3 : key = ([0x00] ++ (H addr).take 10 ++ addr ++ [0x00] ++ (H slot).take 10) ++
      stripLeadingZeroes slot := by rw [e]; simp
  have l2 : ([0x00] ++ (H addr).take 10 ++ addr ++ [0x00] ++ (H slot).take 10 : Bytes).length = 42 := by
    simp [hH, h20]
  refine ⟨?_, ?_, ?_⟩
  · rw [e2, List.drop_left' l1, List.take_left' h20]
  · rw [e3, List.drop_left' l2]
  · obtain ⟨z, hz, _, _⟩ := stripLeadingZeroes_spec slot
    have hl := congrArg List.length hz
    simp only [List.length_append, List.length_replicate] at hl
    conv => lhs; rw [hz]
    congr 2; omega

end RskjTrie.TrieKeyMapper
