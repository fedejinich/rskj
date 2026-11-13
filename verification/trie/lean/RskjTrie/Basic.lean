/-!
# Basic types shared by the model

* `Bytes` models a Java `byte[]` by its contents (Java arrays are only ever read/copied by the
  trie code, never aliased and mutated after construction, so contents are all that matter).
* Java exceptions are modelled as `Except Err`; the error string names the Java exception.
* `BB` models a `java.nio.ByteBuffer` created by `ByteBuffer.wrap(msg)` that is only read with
  relative `get`s and one absolute `get(position())`: its state is exactly the list of remaining
  bytes (position..limit).
-/
namespace RskjTrie

abbrev Bytes := List UInt8
abbrev Err := String

/-- Java array read `a[i]` (throws `ArrayIndexOutOfBoundsException`). -/
def idx (a : Bytes) (i : Nat) : Except Err UInt8 :=
  match a[i]? with
  | some b => .ok b
  | none => .error "ArrayIndexOutOfBoundsException"

/-- A read-only `ByteBuffer` (state = remaining bytes). -/
abbrev BB := StateT Bytes (Except Err)

namespace BB
/-- `ByteBuffer.get()` (java.nio.ByteBuffer): relative read of one byte. -/
def get : BB UInt8 := fun s =>
  match s with
  | [] => .error "BufferUnderflowException"
  | b :: r => .ok (b, r)

/-- `ByteBuffer.get(byte[] dst)` with `dst = new byte[n]`: reads `n` bytes or throws
`BufferUnderflowException` without consuming anything. -/
def getN (n : Nat) : BB Bytes := fun s =>
  if n ≤ s.length then .ok (s.take n, s.drop n) else .error "BufferUnderflowException"

/-- `ByteBuffer.get(message.position())`: absolute read at the current position. -/
def peek : BB UInt8 := fun s =>
  match s with
  | [] => .error "IndexOutOfBoundsException"
  | b :: _ => .ok (b, s)

/-- `ByteBuffer.remaining()`. -/
def remaining : BB Nat := fun s => .ok (s.length, s)

/-- `ByteBuffer.wrap(bytes)` followed by running a reader; returns result and remaining bytes. -/
def run {α} (m : BB α) (bytes : Bytes) : Except Err (α × Bytes) := m bytes
end BB

/-! ## Hex helpers (runner only) -/

def hexDigit (n : Nat) : Char :=
  if n < 10 then Char.ofNat (48 + n) else Char.ofNat (87 + n)

def toHex (bs : Bytes) : String :=
  String.join (bs.map fun b => String.ofList [hexDigit (b.toNat / 16), hexDigit (b.toNat % 16)])

def hexVal (c : Char) : Option Nat :=
  if '0' ≤ c ∧ c ≤ '9' then some (c.toNat - 48)
  else if 'a' ≤ c ∧ c ≤ 'f' then some (c.toNat - 87)
  else if 'A' ≤ c ∧ c ≤ 'F' then some (c.toNat - 55)
  else none

def fromHexChars : List Char → Option Bytes
  | [] => some []
  | a :: b :: r => do
      let x ← hexVal a
      let y ← hexVal b
      let rest ← fromHexChars r
      pure ((x * 16 + y).toUInt8 :: rest)
  | [_] => none

/-- Parse lowercase hex, `-` meaning the empty array. -/
def fromHex (s : String) : Option Bytes :=
  if s == "-" then some [] else fromHexChars s.toList

/-- Little-endian value of a byte list. -/
def leNat : Bytes → Nat
  | [] => 0
  | b :: r => b.toNat + 256 * leNat r

/-- The `k` low bytes of `n`, little-endian (Java `(byte)(n >>> 8*i)` stores). -/
def natLE (n : Nat) : Nat → Bytes
  | 0 => []
  | k + 1 => (n % 256).toUInt8 :: natLE (n / 256) k

/-- Big-endian value of a byte list. -/
def beNat (bs : Bytes) : Nat := bs.foldl (fun acc b => acc * 256 + b.toNat) 0

end RskjTrie
