import RskjTrie.Basic
/-!
# Keccak-256 (executable, unverified, tested)

Mirrors `org.ethereum.crypto.Keccak256Helper.keccak256(byte[])` (BouncyCastle `KeccakDigest(256)`:
original Keccak padding `0x01 … 0x80`, rate 136 bytes, 32-byte output). Only used to *run* the
model; theorems never depend on it (they take the hash function as a parameter).
-/
namespace RskjTrie.Keccak

def RC : Array UInt64 := #[
  0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
  0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
  0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
  0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
  0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
  0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008]

/-- Rotation offsets, lane index `x + 5*y`. -/
def ROT : Array UInt64 := #[
  0, 1, 62, 28, 27,
  36, 44, 6, 55, 20,
  3, 10, 43, 25, 39,
  41, 45, 15, 21, 8,
  18, 2, 61, 56, 14]

def rotl (v n : UInt64) : UInt64 := if n == 0 then v else (v <<< n) ||| (v >>> (64 - n))

def round (a : Array UInt64) (rc : UInt64) : Array UInt64 := Id.run do
  let g := fun (i : Nat) => a[i]!
  -- θ
  let c := (List.range 5).toArray.map fun x => g x ^^^ g (x+5) ^^^ g (x+10) ^^^ g (x+15) ^^^ g (x+20)
  let d := (List.range 5).toArray.map fun x => c[(x + 4) % 5]! ^^^ rotl c[(x + 1) % 5]! 1
  let a := (List.range 25).toArray.map fun i => g i ^^^ d[i % 5]!
  -- ρ and π: B[y, 2x+3y] = rot(A[x,y], r[x,y])
  let mut b : Array UInt64 := Array.replicate 25 0
  for x in [0:5] do
    for y in [0:5] do
      b := b.set! (y + 5 * ((2 * x + 3 * y) % 5)) (rotl a[x + 5 * y]! ROT[x + 5 * y]!)
  -- χ
  let a := (List.range 25).toArray.map fun i =>
    let x := i % 5; let y := i / 5
    b[i]! ^^^ ((~~~ b[(x + 1) % 5 + 5 * y]!) &&& b[(x + 2) % 5 + 5 * y]!)
  -- ι
  a.set! 0 (a[0]! ^^^ rc)

def keccakF (a : Array UInt64) : Array UInt64 := RC.foldl round a

def laneOf (bs : Bytes) : UInt64 :=
  bs.foldr (fun b acc => (acc <<< 8) ||| b.toUInt64) 0

def rate : Nat := 136

def absorb (st : Array UInt64) (block : Bytes) : Array UInt64 :=
  keccakF <| (List.range 25).toArray.map fun i =>
    if i < rate / 8 then st[i]! ^^^ laneOf ((block.drop (8 * i)).take 8) else st[i]!

def blocks (bs : Bytes) (n : Nat) : List Bytes :=
  match n with
  | 0 => []
  | n + 1 => if bs.isEmpty then [] else bs.take rate :: blocks (bs.drop rate) n

/-- Keccak-256 of a byte list. -/
def keccak256 (msg : Bytes) : Bytes :=
  let padLen := rate - msg.length % rate
  let pad : Bytes :=
    if padLen = 1 then [0x81] else 0x01 :: List.replicate (padLen - 2) 0 ++ [0x80]
  let padded := msg ++ pad
  let st := (blocks padded (padded.length / rate + 1)).foldl absorb (Array.replicate 25 0)
  (List.range 4).flatMap fun i => (List.range 8).map fun j => (st[i]! >>> (8 * j).toUInt64).toUInt8

end RskjTrie.Keccak
