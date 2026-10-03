import RskjTrie.Basic
/-!
# `co.rsk.trie.PathEncoder`

A path is modelled as `List Bool` (Java: `byte[]` of 0/1 values, "expanded" form; `true` = 1).
Java's `encode`/`decode` throw `IllegalArgumentException` on `null`; there are no nulls here.
-/
namespace RskjTrie.PathEncoder

/-- `PathEncoder.calculateEncodedLength(int keyLength)` — PathEncoder.java:90-92, for
`keyLength ≥ 0`. -/
def calculateEncodedLength (keyLength : Nat) : Nat :=
  keyLength / 8 + (if keyLength % 8 = 0 then 0 else 1)

/-- The same method on a Java `int` that may be negative (Java `/` and `%` truncate toward zero).
Only reachable from `SharedPathSerializer.deserialize` with a VarInt length cast to `int`. -/
def calculateEncodedLengthInt (keyLength : Int) : Int :=
  keyLength.tdiv 8 + (if keyLength.tmod 8 = 0 then 0 else 1)

/-- Loop body of `encodeBinaryPath` — PathEncoder.java:56-67: `k` is the bit index, `nbyte` the
current byte index, `enc` the output array. -/
def encodeLoop : List Bool → Nat → Nat → Bytes → Bytes
  | [], _, _, enc => enc
  | p :: ps, k, nbyte, enc =>
    let offset := k % 8
    let nbyte := if k > 0 ∧ offset = 0 then nbyte + 1 else nbyte
    let enc := if p = false then enc else enc.modify nbyte (· ||| ((0x80 : UInt8) >>> offset.toUInt8))
    encodeLoop ps (k + 1) nbyte enc

/-- `PathEncoder.encodeBinaryPath(byte[] path)` — PathEncoder.java:49-70 (first bit is the most
significant bit of the first byte). -/
def encodeBinaryPath (path : List Bool) : Bytes :=
  encodeLoop path 0 0 (List.replicate (calculateEncodedLength path.length) 0)

/-- `PathEncoder.encode(byte[] path)` — PathEncoder.java:30-36. -/
def encode (path : List Bool) : Bytes := encodeBinaryPath path

/-- `PathEncoder.decodeBinaryPath(byte[] encoded, int bitlength)` — PathEncoder.java:75-88.
`encoded[nbyte]` throws `ArrayIndexOutOfBoundsException` when `encoded` is too short.
The Java test `((encoded[nbyte] >> (7 - offset)) & 0x01) != 0` sign-extends the byte first, but
for shifts `≤ 7` bit 0 of the result is bit `7 - offset` of the byte, as tested here. -/
def decodeBinaryPath (encoded : Bytes) (bitlength : Nat) : Except Err (List Bool) :=
  (List.range bitlength).mapM fun k => do
    let b ← idx encoded (k / 8)
    pure (((b >>> (7 - k % 8).toUInt8) &&& 1) != 0)

/-- `PathEncoder.decode(byte[] encoded, int length)` — PathEncoder.java:39-45. -/
def decode (encoded : Bytes) (length : Nat) : Except Err (List Bool) :=
  decodeBinaryPath encoded length

end RskjTrie.PathEncoder
