import RskjTrie.Obligations.Common
/-! # Obligations TRIE-LSH-* (shared-prefix length compression, RSKIP107) and TRIE-VARINT-* -/
namespace RskjTrie.Obligations
open RskjTrie Trie SharedPathSerializer

set_option linter.unusedSimpArgs false

theorem getPathBitsLength_small (b : UInt8) (rest : Bytes) (h : b.toNat ≤ 31) :
    getPathBitsLength (b :: rest) = .ok ((b.toNat : Int) + 1, rest) := by
  unfold getPathBitsLength
  rw [BB.bind_ok _ _ _ _ _ (BB.get_cons _ _)]
  simp [h]

theorem getPathBitsLength_mid (b : UInt8) (rest : Bytes) (h1 : 32 ≤ b.toNat) (h2 : b.toNat ≤ 254) :
    getPathBitsLength (b :: rest) = .ok ((b.toNat : Int) + 128, rest) := by
  unfold getPathBitsLength
  rw [BB.bind_ok _ _ _ _ _ (BB.get_cons _ _)]
  have : ¬ b.toNat ≤ 31 := by omega
  simp [this, h1, h2]

/-- TRIE-LSH-01: lengths 1..32 are the single byte `l-1`; first bytes 0..31 decode to `byte+1`. -/
theorem trie_lsh_01 :
    (∀ l enc, 1 ≤ l → l ≤ 32 → serializeBytes l enc = [(l - 1).toUInt8] ++ enc) ∧
    (∀ b rest, b.toNat ≤ 31 → getPathBitsLength (b :: rest) = .ok ((b.toNat : Int) + 1, rest)) :=
  ⟨fun l enc h1 h2 => by simp [serializeBytes, lsharedPrefix, h1, h2],
   fun b rest h => getPathBitsLength_small b rest h⟩

/-- TRIE-LSH-02: lengths 160..382 are the single byte `l-128` (32..254); first bytes 32..254
decode to `byte+128`. -/
theorem trie_lsh_02 :
    (∀ l enc, 160 ≤ l → l ≤ 382 → serializeBytes l enc = [(l - 128).toUInt8] ++ enc ∧
      32 ≤ l - 128 ∧ l - 128 ≤ 254) ∧
    (∀ b rest, 32 ≤ b.toNat → b.toNat ≤ 254 → getPathBitsLength (b :: rest) = .ok ((b.toNat : Int) + 128, rest)) :=
  ⟨fun l enc h1 h2 => ⟨by
      have : ¬ (1 ≤ l ∧ l ≤ 32) := by omega
      simp [serializeBytes, lsharedPrefix, this, h1, h2], by omega, by omega⟩,
   fun b rest h1 h2 => getPathBitsLength_mid b rest h1 h2⟩

/-- TRIE-LSH-03 (Java): other lengths are `0xFF ++ VarInt(l)` (the VarInt carries `l` itself) and
`calculateVarIntSize(l) = 1 + VarInt.sizeOf(l)`. -/
theorem trie_lsh_03 (l : Nat) (h1 : ¬ (1 ≤ l ∧ l ≤ 32)) (h2 : ¬ (160 ≤ l ∧ l ≤ 382)) :
    lsharedPrefix l = 255 :: VarInt.encode l ∧ calculateVarIntSize l = 1 + VarInt.sizeOf l := by
  refine ⟨(lsharedPrefix_ranges l).2.2 h1 h2, ?_⟩
  simp [calculateVarIntSize, h1, h2]

/-- TRIE-LSH-03: the "2 additional bytes" reading does not hold: 33 → `ff21` (1 extra byte),
159 → `ff9f`, 383 → `fffd7f01` (3 extra bytes). -/
theorem trie_lsh_03_rskip_counterexample :
    lsharedPrefix 33 = [0xff, 0x21] ∧ lsharedPrefix 159 = [0xff, 0x9f] ∧
    lsharedPrefix 383 = [0xff, 0xfd, 0x7f, 0x01] ∧
    (lsharedPrefix 33).length - 1 ≠ 2 ∧ (lsharedPrefix 383).length - 1 ≠ 2 := by decide

/-- TRIE-LSH-04: flag bit 4 is set iff the shared path is non-empty, and the length prefix and the
encoded path are written iff it is set. -/
theorem trie_lsh_04 (env : Env) (t : Trie) (hres : t.Resident) (hc : t.CacheOK env.H) :
    (∃ f rest, t.toMessage env = .ok (f :: rest) ∧ bitSet f 0b00010000 = decide (t.sharedPath ≠ [])) ∧
    (serializeInto t.sharedPath = [] ↔ t.sharedPath = []) := by
  obtain ⟨f, rest, h, _, _, h2, _⟩ := Trie.toMessage_flags env t hres hc
  refine ⟨⟨f, rest, h, h2⟩, ?_⟩
  unfold serializeInto isPresent
  cases hp : t.sharedPath with
  | nil => simp
  | cons b p => simp [serializeBytes, lsharedPrefix]; split <;> (try split) <;> simp

/-- TRIE-LSH-05: for every path of 1 ≤ |p| < 2^31 bits (Java `int` lengths), `deserialize`
inverts `serializeInto` and consumes exactly `getSerializedLength(p)` bytes. -/
theorem trie_lsh_05 (p : List Bool) (h1 : 1 ≤ p.length) (h2 : p.length < 2 ^ 31) (rest : Bytes) :
    deserialize true (serializeInto p ++ rest) = .ok (p, rest) ∧
    (serializeInto p).length = serializedLength p :=
  ⟨deserialize_serializeInto p h1 h2 rest, (serializedLength_eq p (by omega)).symm⟩

/-- TRIE-LSH-06 (Java): the exact acceptance set of `getPathBitsLength`: first byte 0..31 →
`byte+1`; 32..254 → `byte+128`; 255 → any VarInt (minimal or not, any value including 0),
truncated to an `int`. -/
theorem trie_lsh_06 (b : UInt8) (rest : Bytes) :
    getPathBitsLength (b :: rest) =
      if b.toNat ≤ 31 then .ok ((b.toNat : Int) + 1, rest)
      else if b.toNat ≤ 254 then .ok ((b.toNat : Int) + 128, rest)
      else (fun (x : Nat × Bytes) => (toInt32 x.1, x.2)) <$> SharedPathSerializer.readVarInt rest := by
  unfold getPathBitsLength
  rw [BB.bind_ok _ _ _ _ _ (BB.get_cons _ _)]
  by_cases h1 : b.toNat ≤ 31
  · simp [h1]
  · by_cases h2 : b.toNat ≤ 254
    · have : 32 ≤ b.toNat := by omega
      simp [h1, h2, this]
    · simp only [h1, h2, ↓reduceIte, and_false]
      show (SharedPathSerializer.readVarInt >>= fun x => pure (toInt32 x)) rest = _
      cases h : SharedPathSerializer.readVarInt rest with
      | error e => rw [BB.bind_err _ _ _ _ h]; rfl
      | ok x => rw [BB.bind_ok _ _ _ _ _ h]; rfl

/-- TRIE-LSH-06 (canonical-parse reading) does not hold: the four non-canonical encodings of the
reproducer are accepted and re-serialize differently. -/
theorem trie_lsh_06_rskip_counterexample (env : Env) :
    reencode env [0x50, 0xff, 0x05, 0x00, 0x01] = .ok [0x50, 0x04, 0x00, 0x01] ∧
    reencode env [0x50, 0xff, 0xfd, 0x05, 0x00, 0x00, 0x01] = .ok [0x50, 0x04, 0x00, 0x01] ∧
    reencode env [0x50, 0xff, 0xff, 0x05, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x01] =
      .ok [0x50, 0x04, 0x00, 0x01] ∧
    reencode env [0x50, 0xff, 0x00, 0x01] = .ok [0x40, 0x01] :=
  ⟨reencode_eq _ _ _ ⟨_, rfl, rfl, rfl⟩, reencode_eq _ _ _ ⟨_, rfl, rfl, rfl⟩,
   reencode_eq _ _ _ ⟨_, rfl, rfl, rfl⟩, reencode_eq _ _ _ ⟨_, rfl, rfl, rfl⟩⟩

/-- TRIE-VARINT-01: the RSKIP107 VarInt table, little-endian. -/
theorem trie_varint_01 (v : Nat) (h : v < 2 ^ 64) :
    VarInt.encode v = (if v < 0xFD then [v.toUInt8]
      else if v ≤ 0xFFFF then 0xFD :: natLE v 2
      else if v ≤ 0xFFFFFFFF then 0xFE :: natLE v 4 else 0xFF :: natLE v 8) ∧
    (VarInt.encode v).length = VarInt.tableSize v :=
  ⟨VarInt.encode_eq v h, VarInt.encode_length v h⟩

/-- TRIE-VARINT-02: both `readVarInt`s return `v` and consume exactly `encode(v)`. -/
theorem trie_varint_02 (v : Nat) (h : v < 2 ^ 64) (rest : Bytes) :
    Trie.readVarInt (VarInt.encode v ++ rest) = .ok (v, rest) ∧
    SharedPathSerializer.readVarInt (VarInt.encode v ++ rest) = .ok (v, rest) :=
  ⟨readVarInt_encode v h rest, readVarInt_encode v h rest⟩

/-- TRIE-VARINT-03 (Java): `new VarInt(byte[], 0)` has no minimality check: every 3-byte form
decodes, whatever its value. -/
theorem trie_varint_03 (lo hi : UInt8) :
    VarInt.decode [0xFD, lo, hi] = .ok (lo.toNat ||| (hi.toNat <<< 8)) := by
  simp [VarInt.decode, idx]

/-- TRIE-VARINT-03 (canonical-parse reading) does not hold: `treeSize` 4 written as `fd0400` is
accepted and re-encoded minimally. -/
theorem trie_varint_03_rskip_counterexample (env : Env) :
    reencode env [0x5a, 0x07, 0x00, 0x04, 0x50, 0x06, 0x00, 0x02, 0xfd, 0x04, 0x00, 0x01] =
      .ok [0x5a, 0x07, 0x00, 0x04, 0x50, 0x06, 0x00, 0x02, 0x04, 0x01] :=
  reencode_eq _ _ _ ⟨_, rfl, rfl, by simp (config := {decide := true}) [Trie.encP, NodeRef.encP,
    Trie.isTerminal, Trie.isEmptyTrie, Trie.isEmptyTrieOf, NodeRef.isEmpty, NodeRef.ofNode,
    SharedPathSerializer.isPresent, SharedPathSerializer.serializeInto, SharedPathSerializer.serializeBytes,
    SharedPathSerializer.lsharedPrefix, Trie.mkFlags, VarInt.encode, VarInt.sizeOf]⟩

end RskjTrie.Obligations
