import RskjTrie.Proofs.VarInt
import RskjTrie.Proofs.PathEncoder
/-!
# Proofs: `SharedPathSerializer` (shared-prefix length compression, RSKIP107)
-/
namespace RskjTrie.SharedPathSerializer
open PathEncoder

theorem calculateEncodedLengthInt_nat (n : Nat) :
    calculateEncodedLengthInt (n : Int) = ((calculateEncodedLength n : Nat) : Int) := by
  unfold calculateEncodedLengthInt calculateEncodedLength
  simp only [Int.natCast_tdiv_eq_ediv]
  have : ((n : Int).tmod 8 = 0) ↔ (n % 8 = 0) := by
    rw [Int.tmod_eq_emod_of_nonneg (by omega)]; omega
  by_cases h : n % 8 = 0
  · simp [h, this.mpr h]
  · simp [h, show ¬ ((n : Int).tmod 8 = 0) from fun h' => h (this.mp h')]

/-- The prefix is a single byte exactly for `lshared ∈ [1,32] ∪ [160,382]`. -/
theorem lsharedPrefix_length_one_iff (n : Nat) (h : n < 2 ^ 64) :
    (lsharedPrefix n).length = 1 ↔ (1 ≤ n ∧ n ≤ 32) ∨ (160 ≤ n ∧ n ≤ 382) := by
  unfold lsharedPrefix
  by_cases h1 : 1 ≤ n ∧ n ≤ 32
  · simp [h1]
  · by_cases h2 : 160 ≤ n ∧ n ≤ 382
    · simp [h1, h2]
    · simp only [h1, h2, ↓reduceIte, List.length_cons, false_or, iff_false]
      rw [VarInt.encode_length n h]; unfold VarInt.tableSize; split <;> (try split) <;> (try split) <;> omega

/-- The three ranges of RSKIP107 ("Shared Prefix Size Compression", IPs/RSKIP107.md:97-101):
first byte `lshared - 1 ∈ [0,31]` for `lshared ∈ [1,32]`, `lshared - 128 ∈ [32,254]` for
`lshared ∈ [160,382]`, else `255` followed by the VarInt of `lshared`. -/
theorem lsharedPrefix_ranges (n : Nat) :
    ((1 ≤ n ∧ n ≤ 32) → lsharedPrefix n = [(n - 1).toUInt8] ∧ n - 1 ≤ 31) ∧
    ((160 ≤ n ∧ n ≤ 382) → lsharedPrefix n = [(n - 128).toUInt8] ∧ 32 ≤ n - 128 ∧ n - 128 ≤ 254) ∧
    (¬ (1 ≤ n ∧ n ≤ 32) → ¬ (160 ≤ n ∧ n ≤ 382) → lsharedPrefix n = 255 :: VarInt.encode n) := by
  unfold lsharedPrefix
  refine ⟨fun h => ⟨by simp [h], by omega⟩, fun h => ⟨?_, by omega, by omega⟩, fun h1 h2 => by simp [h1, h2]⟩
  have : ¬ (1 ≤ n ∧ n ≤ 32) := by omega
  simp [this, h]

/-- `calculateVarIntSize` is the length of the prefix `serializeBytes` writes. -/
theorem calculateVarIntSize_eq (n : Nat) (h : n < 2 ^ 64) :
    calculateVarIntSize n = (lsharedPrefix n).length := by
  unfold calculateVarIntSize lsharedPrefix
  split
  · simp
  · split
    · simp
    · simp [VarInt.encode_length n h, VarInt.sizeOf_eq_table n h]; omega

/-- `serializedLength` is the number of bytes `serializeInto` writes. -/
theorem serializedLength_eq (p : TrieKeySlice) (h : p.length < 2 ^ 64) :
    serializedLength p = (serializeInto p).length := by
  unfold serializedLength serializeInto lsharedSize serializeBytes
  by_cases hp : isPresent p = true
  · simp [hp, calculateVarIntSize_eq _ h, TrieKeySlice.encode, encode_length,
      calculateEncodedLength_eq]
  · simp [hp]

/-- `getPathBitsLength` inverts the prefix for every `1 ≤ lshared < 2^31` (Java reads the VarInt
into an `int`). -/
theorem getPathBitsLength_prefix (n : Nat) (h1 : 1 ≤ n) (h2 : n < 2 ^ 31) (rest : Bytes) :
    getPathBitsLength (lsharedPrefix n ++ rest) = .ok ((n : Int), rest) := by
  unfold getPathBitsLength lsharedPrefix
  by_cases r1 : 1 ≤ n ∧ n ≤ 32
  · simp only [r1, and_self, ↓reduceIte, List.cons_append, List.nil_append]
    rw [BB.bind_ok _ _ _ _ _ (BB.get_cons _ _)]
    simp only [toUInt8_toNat]
    have : (n - 1) % 256 ≤ 31 := by omega
    simp only [this, ↓reduceIte, BB.pure_run]
    congr 2; omega
  · by_cases r2 : 160 ≤ n ∧ n ≤ 382
    · simp only [r1, r2, and_self, ↓reduceIte, List.cons_append, List.nil_append]
      rw [BB.bind_ok _ _ _ _ _ (BB.get_cons _ _)]
      simp only [toUInt8_toNat]
      have : ¬ ((n - 128) % 256 ≤ 31) := by omega
      have h' : 32 ≤ (n - 128) % 256 ∧ (n - 128) % 256 ≤ 254 := by omega
      simp only [this, h', and_self, ↓reduceIte, BB.pure_run]
      congr 2; omega
    · simp only [r1, r2, ↓reduceIte, List.cons_append]
      rw [BB.bind_ok _ _ _ _ _ (BB.get_cons _ _)]
      simp only [show (255 : UInt8).toNat = 255 from rfl, show ¬ (255 ≤ 31) by decide,
        show ¬ (32 ≤ 255 ∧ 255 ≤ 254) by decide, ↓reduceIte]
      rw [BB.bind_ok _ _ _ _ _ (readVarInt_encode n (by omega) rest)]
      simp only [BB.pure_run, toInt32]
      rw [Nat.mod_eq_of_lt (by omega)]
      simp only [show ¬ (n ≥ 2 ^ 31) by omega, ↓reduceIte]

/-- **Negative result**: a shared-path length `≥ 2^31` (VarInt branch) is *not* decoded back:
Java reads the VarInt into an `int` (SharedPathSerializer.java:132, `(int) readVarInt(message).value`),
so `getPathBitsLength` returns the truncated signed value `toInt32 n ≠ n`. -/
theorem getPathBitsLength_large (n : Nat) (h1 : 2 ^ 31 ≤ n) (h2 : n < 2 ^ 64) (rest : Bytes) :
    getPathBitsLength (lsharedPrefix n ++ rest) = .ok (toInt32 n, rest) ∧ toInt32 n ≠ (n : Int) := by
  have r1 : ¬ (1 ≤ n ∧ n ≤ 32) := by omega
  have r2 : ¬ (160 ≤ n ∧ n ≤ 382) := by omega
  refine ⟨?_, ?_⟩
  · unfold getPathBitsLength lsharedPrefix
    simp only [r1, r2, ↓reduceIte, List.cons_append]
    rw [BB.bind_ok _ _ _ _ _ (BB.get_cons _ _)]
    simp only [show (255 : UInt8).toNat = 255 from rfl, show ¬ (255 ≤ 31) by decide,
      show ¬ (32 ≤ 255 ∧ 255 ≤ 254) by decide, ↓reduceIte]
    rw [BB.bind_ok _ _ _ _ _ (readVarInt_encode n h2 rest)]
    rfl
  · unfold toInt32
    have : n % 2 ^ 32 < 2 ^ 32 := Nat.mod_lt _ (by decide)
    simp only []
    split <;> omega

/-- **Round trip** of the serialized shared path. -/
theorem deserialize_serializeInto (p : TrieKeySlice) (h1 : 1 ≤ p.length) (h2 : p.length < 2 ^ 31)
    (rest : Bytes) : deserialize true (serializeInto p ++ rest) = .ok (p, rest) := by
  have hpres : isPresent p = true := by simp [isPresent]; omega
  have hl : (TrieKeySlice.encode p).length = calculateEncodedLength p.length := by
    simp [TrieKeySlice.encode, encode_length, calculateEncodedLength_eq]
  unfold deserialize serializeInto serializeBytes
  simp only [hpres, Bool.not_true, Bool.false_eq_true, ↓reduceIte, List.append_assoc]
  rw [BB.bind_ok _ _ _ _ _ (getPathBitsLength_prefix _ h1 h2 _)]
  simp only [calculateEncodedLengthInt_nat,
    show ¬ (((calculateEncodedLength p.length : Nat) : Int) < 0) by omega, ↓reduceIte,
    Int.toNat_natCast]
  rw [BB.bind_ok _ _ _ _ _ (BB.getN_append _ _ _ hl)]
  simp only [show ¬ ((p.length : Int) < 0) by omega, ↓reduceIte,
    TrieKeySlice.fromEncoded, List.drop_zero, hl, Nat.sub_zero, Nat.sub_self,
    List.replicate_zero, List.append_nil]
  rw [← hl, TrieKeySlice.encode, List.take_length, decode_encode]
  rfl

end RskjTrie.SharedPathSerializer
