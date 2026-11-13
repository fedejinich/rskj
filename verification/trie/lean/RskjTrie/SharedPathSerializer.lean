import RskjTrie.TrieKeySlice
import RskjTrie.VarInt
/-!
# `co.rsk.trie.SharedPathSerializer`
-/
namespace RskjTrie.SharedPathSerializer

/-- `SharedPathSerializer.isPresent(TrieKeySlice)` — SharedPathSerializer.java:185-187. -/
def isPresent (p : TrieKeySlice) : Bool := decide (p.length > 0)

/-- `SharedPathSerializer.calculateVarIntSize(int lshared)` — SharedPathSerializer.java:104-114. -/
def calculateVarIntSize (lshared : Nat) : Nat :=
  if 1 ≤ lshared ∧ lshared ≤ 32 then 1
  else if 160 ≤ lshared ∧ lshared ≤ 382 then 1
  else 1 + VarInt.sizeOf lshared

/-- `lsharedSize(TrieKeySlice)` — SharedPathSerializer.java:96-102. -/
def lsharedSize (p : TrieKeySlice) : Nat :=
  if !isPresent p then 0 else calculateVarIntSize p.length

/-- `serializedLength()` / `getSerializedLength(TrieKeySlice)` — SharedPathSerializer.java:40-46,
189-195. -/
def serializedLength (p : TrieKeySlice) : Nat :=
  if !isPresent p then 0 else lsharedSize p + PathEncoder.calculateEncodedLength p.length

/-- The length prefix written by `serializeBytes` — SharedPathSerializer.java:66-75. -/
def lsharedPrefix (lshared : Nat) : Bytes :=
  if 1 ≤ lshared ∧ lshared ≤ 32 then [(lshared - 1).toUInt8]
  else if 160 ≤ lshared ∧ lshared ≤ 382 then [(lshared - 128).toUInt8]
  else 255 :: VarInt.encode lshared

/-- `serializeBytes(ByteBuffer, int lshared, byte[] encode)` — SharedPathSerializer.java:65-77. -/
def serializeBytes (lshared : Nat) (enc : Bytes) : Bytes := lsharedPrefix lshared ++ enc

/-- `serializeInto(TrieKeySlice, ByteBuffer)` — SharedPathSerializer.java:56-63: the bytes put
into the buffer. -/
def serializeInto (p : TrieKeySlice) : Bytes :=
  if !isPresent p then [] else serializeBytes p.length (TrieKeySlice.encode p)

/-- `readVarInt(ByteBuffer)` — SharedPathSerializer.java:167-183 (identical to
`Trie.readVarInt`, Trie.java:1149-1165). -/
def readVarInt : BB Nat := do
  let first := (← BB.peek).toNat
  let n := if first < 253 then 1 else if first = 253 then 3 else if first = 254 then 5 else 9
  let bytes ← BB.getN n
  StateT.lift (VarInt.decode bytes : Except Err Nat)

/-- Java `(int) longValue` on the 64-bit pattern `v`. -/
def toInt32 (v : Nat) : Int :=
  let x : Nat := v % 2 ^ 32
  if x ≥ 2 ^ 31 then (x : Int) - 2 ^ 32 else x

/-- `getPathBitsLength(ByteBuffer)` — SharedPathSerializer.java:120-135. -/
def getPathBitsLength : BB Int := do
  let first := (← BB.get).toNat
  if first ≤ 31 then pure (first + 1)
  else if 32 ≤ first ∧ first ≤ 254 then pure (first + 128)
  else pure (toInt32 (← readVarInt))

/-- `deserialize(ByteBuffer, boolean)` — SharedPathSerializer.java:137-148. `new byte[n]` with
`n < 0` throws `NegativeArraySizeException` (also inside `PathEncoder.decode`). -/
def deserialize (present : Bool) : BB TrieKeySlice := do
  if !present then return TrieKeySlice.empty
  let lshared ← getPathBitsLength
  let lencoded := PathEncoder.calculateEncodedLengthInt lshared
  if lencoded < 0 then throw "NegativeArraySizeException"
  let encodedKey ← BB.getN lencoded.toNat
  if lshared < 0 then throw "NegativeArraySizeException"
  StateT.lift (TrieKeySlice.fromEncoded encodedKey 0 lshared.toNat lencoded.toNat : Except Err TrieKeySlice)

end RskjTrie.SharedPathSerializer
