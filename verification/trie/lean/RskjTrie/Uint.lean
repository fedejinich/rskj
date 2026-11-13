import RskjTrie.Basic
/-!
# `co.rsk.core.types.ints.Uint8`, `Uint16`, `Uint24`

Values are modelled as `Nat`; constructors that range-check in Java return `Except`.
-/
namespace RskjTrie

namespace Uint8
/-- `new Uint8(int)` — Uint8.java:29-35: throws unless `0 ≤ v ≤ 0xff`. -/
def mk (v : Nat) : Except Err Nat :=
  if v > 0xff then .error "IllegalArgumentException: Uint8" else .ok v
/-- `Uint8.encode()` — Uint8.java:41-45 (single byte `(byte) intValue`). -/
def encode (v : Nat) : Bytes := [v.toUInt8]
/-- `Uint8.decode(bytes, offset)` — Uint8.java:75-78. -/
def decode (bs : Bytes) (off : Nat) : Except Err Nat := do
  let b ← idx bs off
  mk b.toNat
end Uint8

namespace Uint16
/-- `Uint16.decodeToInt(bytes, offset)` — Uint16.java:29-32 (big-endian). The index `offset+1` is
read first, as in Java. -/
def decodeToInt (bs : Bytes) (off : Nat) : Except Err Nat := do
  let lo ← idx bs (off + 1)
  let hi ← idx bs off
  pure (lo.toNat + hi.toNat * 256)
end Uint16

namespace Uint24
def MAX : Nat := 0x00ffffff
/-- `new Uint24(int)` — Uint24.java:30-36: throws unless `0 ≤ v ≤ 0xffffff`. -/
def mk (v : Nat) : Except Err Nat :=
  if v > MAX then .error "IllegalArgumentException: Uint24" else .ok v
/-- `Uint24.encode()` — Uint24.java:38-44 (big-endian, 3 bytes). -/
def encode (v : Nat) : Bytes := [(v / 65536).toUInt8, (v / 256).toUInt8, v.toUInt8]
/-- `Uint24.decode(bytes, offset)` — Uint24.java:79-84. -/
def decode (bs : Bytes) (off : Nat) : Except Err Nat := do
  let b2 ← idx bs (off + 2)
  let b1 ← idx bs (off + 1)
  let b0 ← idx bs off
  mk (b2.toNat + b1.toNat * 256 + b0.toNat * 65536)
end Uint24

end RskjTrie
