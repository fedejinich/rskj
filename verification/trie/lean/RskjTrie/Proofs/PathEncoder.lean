import RskjTrie.TrieKeySlice
/-!
# Proofs: `PathEncoder` (bit-path encoding)

`bitAt enc k` is bit `k` of an encoded path in the RSKIP107/Java convention: the `k`-th path
element is bit `7 - k % 8` (counting from the least significant bit) of byte `k / 8`, i.e. the
first element is the most significant bit of the first byte.
-/
namespace RskjTrie.PathEncoder

/-- Bit `k` of an encoded path, most significant bit first. -/
def bitAt (enc : Bytes) (k : Nat) : Bool := (enc.getD (k / 8) 0).toNat.testBit (7 - k % 8)

theorem testBit_u8 (b : UInt8) (s : Nat) (h : s < 8) :
    ((b >>> s.toUInt8) &&& 1 != 0) = b.toNat.testBit s := by
  have e : ((b >>> s.toUInt8) &&& 1).toNat = (b.toNat >>> s) % 2 := by
    rw [UInt8.toNat_and, UInt8.toNat_shiftRight]
    simp [Nat.toUInt8, UInt8.toNat_ofNat']
    rw [Nat.mod_eq_of_lt h]
  have : ((b >>> s.toUInt8) &&& 1 != 0) = (((b >>> s.toUInt8) &&& 1).toNat != 0) := by
    rw [Bool.eq_iff_iff]; simp [bne, ← UInt8.toNat_inj]
  rw [this, e, Nat.testBit, Nat.and_comm, Nat.and_one_is_mod]

theorem or_bit (a : UInt8) (o j : Nat) (ho : o < 8) :
    (a ||| ((0x80 : UInt8) >>> o.toUInt8)).toNat.testBit (7 - j % 8) =
      (a.toNat.testBit (7 - j % 8) || decide (o = j % 8)) := by
  have hj : j % 8 < 8 := Nat.mod_lt _ (by decide)
  rw [UInt8.toNat_or, Nat.testBit_or, UInt8.toNat_shiftRight]
  simp [Nat.toUInt8, UInt8.toNat_ofNat']
  rw [Nat.mod_eq_of_lt ho]
  have : (128 : Nat) = 2 ^ 7 := rfl
  rw [this, Nat.testBit_two_pow]
  by_cases h : o = j % 8 <;> simp [h] <;> omega

theorem getD_modify (l : Bytes) (i j : Nat) (f : UInt8 → UInt8) :
    (l.modify i f).getD j 0 = if i = j ∧ j < l.length then f (l.getD j 0) else l.getD j 0 := by
  simp only [List.getD_eq_getElem?_getD, List.getElem?_modify]
  by_cases hj : j < l.length
  · rw [List.getElem?_eq_getElem hj]; by_cases h : i = j <;> simp [h, hj]
  · rw [List.getElem?_eq_none (by omega)]; simp [hj]

theorem encodeLoop_spec (ps : List Bool) : ∀ (k nb : Nat) (enc : Bytes),
    (if k = 0 then nb = 0 else nb = (k - 1) / 8) →
    k + ps.length ≤ 8 * enc.length →
    (encodeLoop ps k nb enc).length = enc.length ∧
    ∀ j, bitAt (encodeLoop ps k nb enc) j =
      (bitAt enc j || (decide (k ≤ j) && ps.getD (j - k) false)) := by
  induction ps with
  | nil => intro k nb enc _ _; simp [encodeLoop]
  | cons p ps ih =>
    intro k nb enc hnb hlen
    simp only [encodeLoop]
    have hk : (if k > 0 ∧ k % 8 = 0 then nb + 1 else nb) = k / 8 := by
      split <;> split at hnb <;> omega
    rw [hk]
    have hnb' : (if k + 1 = 0 then k / 8 = 0 else k / 8 = (k + 1 - 1) / 8) := by simp
    simp only [List.length_cons] at hlen
    have hkb : k / 8 < enc.length := by omega
    -- one step
    have step : ∀ j, bitAt (if p = false then enc else
        enc.modify (k / 8) (· ||| ((0x80 : UInt8) >>> (k % 8).toUInt8))) j =
        (bitAt enc j || (p && decide (j = k))) := by
      intro j
      by_cases hp : p = false
      · simp [hp]
      · obtain rfl : p = true := by simpa using hp
        simp only [Bool.true_eq_false, ↓reduceIte, bitAt, getD_modify, Bool.true_and]
        split
        · next hj =>
          rw [or_bit _ _ _ (Nat.mod_lt _ (by decide))]
          have : (k % 8 = j % 8) ↔ j = k := by omega
          simp [this]
        · next hj =>
          have : j ≠ k := by intro h; subst h; exact hj ⟨rfl, hkb⟩
          simp [this]
    have hlen2 : (if p = false then enc else
        enc.modify (k / 8) (· ||| ((0x80 : UInt8) >>> (k % 8).toUInt8))).length = enc.length := by
      split <;> simp
    obtain ⟨h1, h2⟩ := ih (k + 1) (k / 8) _ hnb' (by rw [hlen2]; omega)
    refine ⟨by rw [h1, hlen2], fun j => ?_⟩
    rw [h2, step]
    by_cases hjk : j = k
    · subst hjk; simp; omega
    · by_cases hlt : k < j
      · have : j - k = (j - (k + 1)) + 1 := by omega
        rw [this]; simp [hjk, show k + 1 ≤ j by omega, show k ≤ j by omega]
      · simp [hjk, show ¬ (k + 1 ≤ j) by omega, show ¬ (k ≤ j) by omega]

/-- `calculateEncodedLength n = ⌈n / 8⌉`. -/
theorem calculateEncodedLength_eq (n : Nat) : calculateEncodedLength n = (n + 7) / 8 := by
  unfold calculateEncodedLength; split <;> omega

/-- The encoding of a path of `n` bits has `⌈n / 8⌉` bytes. -/
theorem encode_length (p : List Bool) : (encode p).length = (p.length + 7) / 8 := by
  unfold encode encodeBinaryPath
  rw [(encodeLoop_spec p 0 0 _ (by simp) (by simp [calculateEncodedLength_eq]; omega)).1]
  simp [calculateEncodedLength_eq]

theorem bitAt_replicate_zero (n j : Nat) : bitAt (List.replicate n 0) j = false := by
  simp only [bitAt, List.getD_eq_getElem?_getD, List.getElem?_replicate]
  split <;> simp

/-- Every bit of the encoding: bit `k` (MSB-first) is path element `k`, and every bit past the
end of the path (the unused low bits of the last byte, and anything beyond) is `0`. -/
theorem encode_bitAt (p : List Bool) (k : Nat) : bitAt (encode p) k = p.getD k false := by
  unfold encode encodeBinaryPath
  rw [(encodeLoop_spec p 0 0 _ (by simp) (by simp [calculateEncodedLength_eq]; omega)).2]
  simp [bitAt_replicate_zero]

/-- MSB-first bit order. -/
theorem encode_msb_first (p : List Bool) (k : Nat) (hk : k < p.length) :
    ((encode p).getD (k / 8) 0).toNat.testBit (7 - k % 8) = p[k] := by
  have := encode_bitAt p k
  simp only [bitAt] at this
  rw [this, List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hk]; rfl

/-- The unused low bits of the last byte are zero. -/
theorem encode_unused_bits_zero (p : List Bool) (k : Nat) (hk : p.length ≤ k) :
    ((encode p).getD (k / 8) 0).toNat.testBit (7 - k % 8) = false := by
  have := encode_bitAt p k
  simp only [bitAt] at this
  rw [this, List.getD_eq_getElem?_getD, List.getElem?_eq_none hk]; rfl

theorem mapM_except_ok {α β : Type} (f : α → Except Err β) (g : α → β) :
    ∀ (l : List α), (∀ x ∈ l, f x = .ok (g x)) → l.mapM f = .ok (l.map g)
  | [], _ => rfl
  | x :: xs, h => by
    simp only [List.mapM_cons, List.map_cons]
    rw [h x (by simp), mapM_except_ok f g xs (fun y hy => h y (by simp [hy]))]
    rfl

/-- `decode` of a long-enough array reads the bits MSB-first. -/
theorem decode_eq (enc : Bytes) (n : Nat) (h : n ≤ 8 * enc.length) :
    decode enc n = .ok ((List.range n).map (bitAt enc)) := by
  unfold decode decodeBinaryPath
  apply mapM_except_ok
  intro k hk
  simp only [List.mem_range] at hk
  have hb : k / 8 < enc.length := by omega
  simp only [idx, List.getElem?_eq_getElem hb, bitAt]
  show (Except.ok _ : Except Err _) = _
  rw [testBit_u8 _ _ (by omega), List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hb]
  rfl

/-- **Round trip**: `decode (encode p) p.length = p`. -/
theorem decode_encode (p : List Bool) : decode (encode p) p.length = .ok p := by
  rw [decode_eq _ _ (by rw [encode_length]; omega)]
  congr 1
  apply List.ext_getElem (by simp)
  intro i h1 h2
  simp only [List.getElem_map, List.getElem_range, encode_bitAt, List.getD_eq_getElem?_getD,
    List.getElem?_eq_getElem h2]
  rfl

/-- Decoding with a too-short array fails (`ArrayIndexOutOfBoundsException`). -/
theorem decode_short (enc : Bytes) (n : Nat) (h : 8 * enc.length < n) :
    ∃ e, decode enc n = .error e := by
  unfold decode decodeBinaryPath
  -- the first failing index is k = 8 * enc.length
  have key : ∀ (l : List Nat), (8 * enc.length) ∈ l →
      ∃ e, l.mapM (fun k => do
        let b ← idx enc (k / 8)
        pure (((b >>> (7 - k % 8).toUInt8) &&& 1) != 0) : Nat → Except Err Bool) = .error e := by
    intro l hl
    induction l with
    | nil => simp at hl
    | cons x xs ih =>
      simp only [List.mapM_cons]
      by_cases hx : x / 8 < enc.length
      · have hne : x ≠ 8 * enc.length := by omega
        have hxs : 8 * enc.length ∈ xs := by simp [hne.symm] at hl; exact hl
        obtain ⟨e, he⟩ := ih hxs
        have hi : idx enc (x / 8) = .ok enc[x / 8] := by simp [idx, List.getElem?_eq_getElem hx]
        refine ⟨e, ?_⟩
        rw [hi, he]; rfl
      · have hi : idx enc (x / 8) = .error "ArrayIndexOutOfBoundsException" := by
          simp [idx, List.getElem?_eq_none (by omega : enc.length ≤ x / 8)]
        rw [hi]; exact ⟨_, rfl⟩
  exact key _ (by simp; omega)

end RskjTrie.PathEncoder

namespace RskjTrie.TrieKeySlice
open PathEncoder

/-- `fromKey key` is the list of the `8 * key.length` bits of `key`, MSB first. -/
theorem fromKey_eq (key : Bytes) : fromKey key = (List.range (key.length * 8)).map (bitAt key) := by
  unfold fromKey
  rw [decode_eq _ _ (by omega)]

theorem fromKey_length (key : Bytes) : (fromKey key).length = 8 * key.length := by
  rw [fromKey_eq]; simp; omega

theorem byte_eq_of_bits (a b : UInt8) (h : ∀ i < 8, a.toNat.testBit i = b.toNat.testBit i) :
    a = b := by
  apply UInt8.toNat_inj.mp
  apply Nat.eq_of_testBit_eq
  intro i
  by_cases hi : i < 8
  · exact h i hi
  · have ha := UInt8.toNat_lt a
    have hb := UInt8.toNat_lt b
    rw [Nat.testBit_lt_two_pow (Nat.lt_of_lt_of_le ha (Nat.pow_le_pow_right (by decide) (by omega))),
      Nat.testBit_lt_two_pow (Nat.lt_of_lt_of_le hb (Nat.pow_le_pow_right (by decide) (by omega)))]

/-- `fromKey` is injective: distinct byte keys have distinct bit paths. -/
theorem fromKey_injective {a b : Bytes} (h : fromKey a = fromKey b) : a = b := by
  have hl : a.length = b.length := by
    have := congrArg List.length h; rw [fromKey_length, fromKey_length] at this; omega
  apply List.ext_getElem hl
  intro i ha hb
  apply byte_eq_of_bits
  intro s hs
  have hk : 8 * i + (7 - s) < a.length * 8 := by omega
  have hk' : 8 * i + (7 - s) < b.length * 8 := by omega
  have e := congrArg (fun l => l[8 * i + (7 - s)]?) h
  simp only [fromKey_eq, List.getElem?_map, List.getElem?_range hk, List.getElem?_range hk',
    Option.map_some, Option.some.injEq, bitAt] at e
  have d1 : (8 * i + (7 - s)) / 8 = i := by omega
  have d2 : 7 - (8 * i + (7 - s)) % 8 = s := by omega
  rw [d1, d2, List.getD_eq_getElem?_getD, List.getD_eq_getElem?_getD,
    List.getElem?_eq_getElem ha, List.getElem?_eq_getElem hb] at e
  exact e

end RskjTrie.TrieKeySlice
