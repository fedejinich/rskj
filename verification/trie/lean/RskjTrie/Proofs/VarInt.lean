import RskjTrie.SharedPathSerializer
/-!
# Proofs: `VarInt` (Bitcoin variable-length integer, RSKIP107 table)
-/
namespace RskjTrie

theorem toUInt8_toNat (n : Nat) : n.toUInt8.toNat = n % 256 := by
  simp [Nat.toUInt8, UInt8.toNat_ofNat']

theorem toUInt8_mod (n : Nat) : (n % 256).toUInt8 = n.toUInt8 := by
  apply UInt8.toNat_inj.mp; simp

@[simp] theorem except_bind_ok {ε α β : Type} (a : α) (f : α → Except ε β) :
    (Except.ok a >>= f) = f a := rfl
@[simp] theorem except_bind_error {ε α β : Type} (e : ε) (f : α → Except ε β) :
    (Except.error e >>= f) = .error e := rfl
@[simp] theorem except_map_ok {ε α β : Type} (a : α) (f : α → β) :
    (f <$> (Except.ok a : Except ε α)) = .ok (f a) := rfl
@[simp] theorem except_pure {ε α : Type} (a : α) : (pure a : Except ε α) = .ok a := rfl

theorem natLE_length (n k : Nat) : (natLE n k).length = k := by
  induction k generalizing n with
  | zero => rfl
  | succ k ih => simp [natLE, ih]

theorem leNat_natLE (n k : Nat) : leNat (natLE n k) = n % 256 ^ k := by
  induction k generalizing n with
  | zero => simp [natLE, leNat]; omega
  | succ k ih =>
    simp only [natLE, leNat, ih, toUInt8_toNat]
    rw [Nat.pow_succ, show 256^k*256 = 256 * 256^k from Nat.mul_comm _ _, Nat.mod_mul]; simp

namespace BB
@[simp] theorem get_cons (b : UInt8) (r : Bytes) : BB.get (b :: r) = .ok (b, r) := rfl
@[simp] theorem peek_cons (b : UInt8) (r : Bytes) : BB.peek (b :: r) = .ok (b, b :: r) := rfl
theorem getN_append (xs rest : Bytes) (n : Nat) (h : xs.length = n) :
    BB.getN n (xs ++ rest) = .ok (xs, rest) := by
  subst h; simp [BB.getN]
@[simp] theorem remaining_eq (s : Bytes) : BB.remaining s = .ok (s.length, s) := rfl
theorem bind_ok {α β : Type} (x : BB α) (f : α → BB β) (s s' : Bytes) (a : α)
    (h : x s = .ok (a, s')) : (x >>= f) s = f a s' := by
  show (StateT.bind x f) s = _
  simp only [StateT.bind, h]; rfl
theorem bind_err {α β : Type} (x : BB α) (f : α → BB β) (s : Bytes) (e : Err)
    (h : x s = .error e) : (x >>= f) s = .error e := by
  show (StateT.bind x f) s = _
  simp only [StateT.bind, h]; rfl
@[simp] theorem pure_run {α : Type} (a : α) (s : Bytes) : (pure a : BB α) s = .ok (a, s) := rfl
@[simp] theorem lift_ok {α : Type} (a : α) (s : Bytes) :
    (StateT.lift (Except.ok a) : BB α) s = .ok (a, s) := rfl
@[simp] theorem lift_err {α : Type} (e : Err) (s : Bytes) :
    (StateT.lift (Except.error e) : BB α) s = .error e := rfl
theorem ite_run {α : Type} (c : Prop) [Decidable c] (x y : BB α) (s : Bytes) :
    (if c then x else y) s = if c then x s else y s := by split <;> rfl
theorem getN_len (xs : Bytes) : BB.getN xs.length xs = .ok (xs, []) := by simp [BB.getN]
theorem getN_one_cons (b : UInt8) (s : Bytes) : BB.getN 1 (b :: s) = .ok ([b], s) := by
  simp [BB.getN]
theorem getN_self (xs : Bytes) (n : Nat) (h : xs.length = n) : BB.getN n xs = .ok (xs, []) := by
  subst h; exact getN_len xs
end BB

namespace VarInt

/-- The RSKIP107 "Variable length integer" table (IPs/RSKIP107.md:109-114). -/
def tableSize (n : Nat) : Nat :=
  if n < 0xFD then 1 else if n ≤ 0xFFFF then 3 else if n ≤ 0xFFFFFFFF then 5 else 9

/-- `sizeOf` agrees with the RSKIP107 table for every unsigned 64-bit value. -/
theorem sizeOf_eq_table (n : Nat) (h : n < 2 ^ 64) : sizeOf n = tableSize n := by
  unfold sizeOf tableSize
  by_cases h1 : n ≥ 2 ^ 63
  · simp only [h1, ↓reduceIte]
    have : ¬ n < 0xFD := by omega
    have : ¬ n ≤ 0xFFFF := by omega
    have : ¬ n ≤ 0xFFFFFFFF := by omega
    simp [*]
  · simp [h1]

/-- Little-endian layout: `encode` is the marker byte followed by the little-endian bytes. -/
theorem encode_eq (n : Nat) (h : n < 2 ^ 64) :
    encode n = if n < 0xFD then [n.toUInt8]
      else if n ≤ 0xFFFF then 0xFD :: natLE n 2
      else if n ≤ 0xFFFFFFFF then 0xFE :: natLE n 4
      else 0xFF :: natLE n 8 := by
  unfold encode
  rw [sizeOf_eq_table n h]
  unfold tableSize
  by_cases h1 : n < 0xFD
  · simp [h1]
  · by_cases h2 : n ≤ 0xFFFF
    · simp only [h1, h2, ↓reduceIte, natLE]
      rw [toUInt8_mod, toUInt8_mod]
    · by_cases h3 : n ≤ 0xFFFFFFFF
      · simp [h1, h2, h3]
      · simp [h1, h2, h3]


/-- The encoded size is `sizeOf n` (1, 3, 5 or 9 bytes). -/
theorem encode_length (n : Nat) (h : n < 2 ^ 64) : (encode n).length = tableSize n := by
  rw [encode_eq n h]; unfold tableSize
  split <;> (try split) <;> (try split) <;> simp [natLE_length]

/-- **Round trip**: `new VarInt(new VarInt(n).encode(), 0).value = n` for every `n < 2^64`. -/
theorem decode_encode (n : Nat) (h : n < 2 ^ 64) : decode (encode n) = .ok n := by
  rw [encode_eq n h]
  by_cases h1 : n < 0xFD
  · simp only [h1, ↓reduceIte, decode, idx]
    have : n.toUInt8.toNat = n := by rw [toUInt8_toNat]; omega
    simp [this, h1]
  · by_cases h2 : n ≤ 0xFFFF
    · simp only [h1, h2, ↓reduceIte, decode, idx, natLE]
      have e1 : (253 : UInt8).toNat = 253 := rfl
      simp only [List.getElem?_cons_zero, List.getElem?_cons_succ, except_bind_ok, e1,
        show ¬ (253 < 253) by decide, ↓reduceIte, toUInt8_toNat]
      congr 1
      rw [Nat.or_comm, ← Nat.shiftLeft_add_eq_or_of_lt (by omega : n % 256 % 256 < 2 ^ 8)]
      rw [Nat.shiftLeft_eq]; omega
    · by_cases h3 : n ≤ 0xFFFFFFFF
      · simp only [h1, h2, h3, ↓reduceIte, decode, idx]
        simp [natLE_length, leNat_natLE, List.take_of_length_le]
        omega
      · simp only [h1, h2, h3, ↓reduceIte, decode, idx]
        simp [natLE_length, leNat_natLE, List.take_of_length_le]
        omega

end VarInt

/-- `readVarInt` (both copies) consumes exactly the encoding of `n`. -/
theorem readVarInt_encode (n : Nat) (h : n < 2 ^ 64) (rest : Bytes) :
    SharedPathSerializer.readVarInt (VarInt.encode n ++ rest) = .ok (n, rest) := by
  have hd := VarInt.decode_encode n h
  have hl := VarInt.encode_length n h
  rw [VarInt.encode_eq n h] at hd hl ⊢
  unfold VarInt.tableSize at hl
  unfold SharedPathSerializer.readVarInt
  by_cases h1 : n < 0xFD
  · simp only [h1, ↓reduceIte] at hd hl ⊢
    simp only [List.cons_append, bind, StateT.bind, BB.peek_cons]
    have : n.toUInt8.toNat < 253 := by rw [toUInt8_toNat]; omega
    simp only [Except.bind, this, ↓reduceIte]
    rw [show n.toUInt8 :: ([] ++ rest) = [n.toUInt8] ++ rest from rfl, BB.getN_append _ _ 1 rfl]
    simp [StateT.lift, hd]
  · by_cases h2 : n ≤ 0xFFFF
    · simp only [h1, h2, ↓reduceIte] at hd hl ⊢
      simp only [List.cons_append, bind, StateT.bind, BB.peek_cons, Except.bind]
      simp only [show (0xFD : UInt8).toNat = 253 from rfl, show ¬ (253 < 253) by decide, ↓reduceIte]
      rw [show (0xFD : UInt8) :: (natLE n 2 ++ rest) = (0xFD :: natLE n 2) ++ rest from rfl,
        BB.getN_append _ _ _ hl]
      simp [StateT.lift, hd]
    · by_cases h3 : n ≤ 0xFFFFFFFF
      · simp only [h1, h2, h3, ↓reduceIte] at hd hl ⊢
        simp only [List.cons_append, bind, StateT.bind, BB.peek_cons, Except.bind]
        simp only [show (0xFE : UInt8).toNat = 254 from rfl, show ¬ (254 < 253) by decide,
          show ¬ (254 = 253) by decide, ↓reduceIte]
        rw [show (0xFE : UInt8) :: (natLE n 4 ++ rest) = (0xFE :: natLE n 4) ++ rest from rfl,
          BB.getN_append _ _ _ hl]
        simp [StateT.lift, hd]
      · simp only [h1, h2, h3, ↓reduceIte] at hd hl ⊢
        simp only [List.cons_append, bind, StateT.bind, BB.peek_cons, Except.bind]
        simp only [show (0xFF : UInt8).toNat = 255 from rfl, show ¬ (255 < 253) by decide,
          show ¬ (255 = 253) by decide, show ¬ (255 = 254) by decide, ↓reduceIte]
        rw [show (0xFF : UInt8) :: (natLE n 8 ++ rest) = (0xFF :: natLE n 8) ++ rest from rfl,
          BB.getN_append _ _ _ hl]
        simp [StateT.lift, hd]

end RskjTrie
