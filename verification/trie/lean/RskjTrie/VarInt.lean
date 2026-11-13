import RskjTrie.Basic
/-!
# `co.rsk.bitcoinj.core.VarInt` (bitcoinj-thin 0.14.4-rsk-18, read with `javap -c -p`)

The Java `long value` is modelled as a `Nat` in `[0, 2^64)` holding its two's-complement bit
pattern (negative longs are the values `≥ 2^63`). The encoders only look at the bit pattern and
`sizeOf` treats negatives as 9 bytes, so this is exact.
-/
namespace RskjTrie.VarInt

def W : Nat := 2 ^ 64

/-- `VarInt.sizeOf(long)`: `value < 0 → 9; < 253 → 1; ≤ 0xFFFF → 3; ≤ 0xFFFFFFFF → 5; else 9`. -/
def sizeOf (v : Nat) : Nat :=
  if v ≥ 2 ^ 63 then 9
  else if v < 253 then 1
  else if v ≤ 0xFFFF then 3
  else if v ≤ 0xFFFFFFFF then 5
  else 9

/-- `VarInt.getSizeInBytes()` = `sizeOf(value)`. -/
def getSizeInBytes (v : Nat) : Nat := sizeOf v

/-- `VarInt.encode()`: `tableswitch` on `sizeOf`: 1 → `(byte) value`; 3 → `0xFD, lo, hi`;
5 → `0xFE` + `uint32ToByteArrayLE`; default (9) → `0xFF` + `uint64ToByteArrayLE`. -/
def encode (v : Nat) : Bytes :=
  match sizeOf v with
  | 1 => [v.toUInt8]
  | 3 => [0xFD, v.toUInt8, (v / 256).toUInt8]
  | 5 => 0xFE :: natLE v 4
  | _ => 0xFF :: natLE v 8

/-- `new VarInt(byte[] buf, int offset)` with `offset = 0`: first byte `< 253` → itself;
`253` → uint16 LE; `254` → `Utils.readUint32` (LE); `255` → `Utils.readInt64` (LE). -/
def decode (buf : Bytes) : Except Err Nat := do
  let first ← idx buf 0
  if first.toNat < 253 then pure first.toNat
  else if first.toNat = 253 then do
    let b1 ← idx buf 1; let b2 ← idx buf 2
    pure (b1.toNat ||| (b2.toNat <<< 8))
  else if first.toNat = 254 then do
    if buf.length < 5 then throw "ArrayIndexOutOfBoundsException"
    pure (leNat ((buf.drop 1).take 4))
  else do
    if buf.length < 9 then throw "ArrayIndexOutOfBoundsException"
    pure (leNat ((buf.drop 1).take 8))

end RskjTrie.VarInt
