import RskjTrie.Serialization
/-!
# `co.rsk.trie.TrieDTO` — the second node parser (snapshot sync)

Only `decodeFromMessage(byte[] src, TrieStore ds)` (= `preloadChildren = false`, `hash = null`,
TrieDTO.java:79-128) and `toMessage()` (TrieDTO.java:417-470) are modelled. `decodeFromMessage`
builds a second, "sync" encoding in `encoded` while parsing: embedded children with a `Uint24`
length, and a long value *inline* (read from the store) instead of its hash and length.
`toMessage()` writes an embedded child as `Uint8(left.length) ++ left` where
`left = leftNode.getEncoded()` — the child's sync encoding, not its source bytes.
-/
namespace RskjTrie

/-- The fields of a `TrieDTO` read by `toMessage()` (TrieDTO.java:41-77). -/
structure TrieDTO where
  flags : UInt8
  hasLongVal : Bool
  sharedPrefixPresent : Bool
  leftNodePresent : Bool
  rightNodePresent : Bool
  leftNodeEmbedded : Bool
  rightNodeEmbedded : Bool
  pathLength : Option Int
  path : Option Bytes
  left : Option Bytes
  right : Option Bytes
  leftHash : Option Bytes
  rightHash : Option Bytes
  leftNode : Option TrieDTO
  rightNode : Option TrieDTO
  childrenSize : Nat
  value : Option Bytes
  encoded : Bytes
  source : Bytes
  deriving Repr, Inhabited

namespace TrieDTO

/-- `SharedPathSerializer.writeBytes(ByteArrayOutputStream, int lshared, byte[])` /
`serializeBytes(ByteBuffer, int, byte[])` (SharedPathSerializer.java:65-91) for an `int` length. -/
def prefixBytes (lshared : Int) (enc : Bytes) : Bytes :=
  (if 1 ≤ lshared ∧ lshared ≤ 32 then [(lshared - 1).toNat.toUInt8]
   else if 160 ≤ lshared ∧ lshared ≤ 382 then [(lshared - 128).toNat.toUInt8]
   else 255 :: VarInt.encode (wrap64 lshared)) ++ enc

/-- `SharedPathSerializer.deserializeEncoded(ByteBuffer, boolean, encoder)` —
SharedPathSerializer.java:150-165: `(lshared, encodedPathBytes)`, or `none` when absent. -/
def deserializeEncoded (present : Bool) : BB (Option (Int × Bytes)) := do
  if !present then return none
  let lshared ← SharedPathSerializer.getPathBitsLength
  let lencoded := PathEncoder.calculateEncodedLengthInt lshared
  if lencoded < 0 then throw "NegativeArraySizeException"
  let encodedKey ← BB.getN lencoded.toNat
  pure (some (lshared, encodedKey))

/-- `TrieDTO.readVarInt(ByteBuffer, encoder)` — TrieDTO.java:266-285: value and the raw bytes. -/
def readVarInt : BB (Nat × Bytes) := do
  let first := (← BB.peek).toNat
  let n := if first < 253 then 1 else if first = 253 then 3 else if first = 254 then 5 else 9
  let bytes ← BB.getN n
  let v ← StateT.lift (VarInt.decode bytes : Except Err Nat)
  pure (v, bytes)

/-- `decodeFromMessage(src, ds, false, null)` — TrieDTO.java:83-128 with `handleLeft`,
`handleRight` (:130-158), `handleValue` (:160-177), `readChildEmbedded` (:224-230). The first
argument bounds the nesting of embedded nodes (as for `Trie.fromMessageRskip107`). -/
def decodeFromMessage (ds : Bytes → Option Bytes) : Nat → Bytes → Except Err TrieDTO
  | 0, _ => .error "StackOverflowError"
  | fuel + 1, src => StateT.run' (σ := Bytes) (m := Except Err) (s := src) do
    let flags ← BB.get
    let hasLongVal := bitSet flags 0b00100000
    let sharedPrefixPresent := bitSet flags 0b00010000
    let leftNodePresent := bitSet flags 0b00001000
    let rightNodePresent := bitSet flags 0b00000100
    let leftNodeEmbedded := bitSet flags 0b00000010
    let rightNodeEmbedded := bitSet flags 0b00000001
    let pathTuple ← deserializeEncoded sharedPrefixPresent
    let enc0 : Bytes := [flags] ++
      (match pathTuple with | some (l, p) => prefixBytes l p | none => [])
    -- handleLeft
    let (left, leftHash, leftNode, encL) ← if leftNodePresent && leftNodeEmbedded then do
        let lengthBytes ← BB.getN 1
        let length ← StateT.lift (Uint8.decode lengthBytes 0)
        let serializedNode ← BB.getN length
        let node ← StateT.lift (decodeFromMessage ds fuel serializedNode)
        let l := node.encoded
        let l24 ← StateT.lift (Uint24.mk l.length)
        pure (some l, (none : Option Bytes), some node, Uint24.encode l24 ++ l)
      else if leftNodePresent then do
        let vh ← BB.getN 32
        pure (none, some vh, none, [])
      else pure (none, none, none, [])
    -- handleRight
    let (right, rightHash, rightNode, encR) ← if rightNodePresent && rightNodeEmbedded then do
        let lengthBytes ← BB.getN 1
        let length ← StateT.lift (Uint8.decode lengthBytes 0)
        let serializedNode ← BB.getN length
        let node ← StateT.lift (decodeFromMessage ds fuel serializedNode)
        let r := node.encoded
        let r24 ← StateT.lift (Uint24.mk r.length)
        pure (some r, (none : Option Bytes), some node, Uint24.encode r24 ++ r)
      else if rightNodePresent then do
        let vh ← BB.getN 32
        pure (none, some vh, none, [])
      else pure (none, none, none, [])
    let (childrenSize, encC) ← if leftNodePresent || rightNodePresent then readVarInt
      else pure (0, [])
    -- handleValue
    let (value, encV) ← if hasLongVal then do
        let valueHashBytes ← BB.getN 32
        let _lvalueBytes ← BB.getN 3
        match ds valueHashBytes with
        | some v => pure (some v, v)
        | none => throw "NullPointerException: encoder.write(null)"
      else do
        let remaining ← BB.remaining
        let v ← BB.getN remaining
        pure (some v, v)
    if (← BB.remaining) > 0 then throw "IllegalArgumentException: The srcWrap had more data than expected"
    pure { flags, hasLongVal, sharedPrefixPresent, leftNodePresent, rightNodePresent,
           leftNodeEmbedded, rightNodeEmbedded,
           pathLength := pathTuple.map (·.1), path := pathTuple.map (·.2),
           left, right, leftHash, rightHash, leftNode, rightNode, childrenSize, value,
           encoded := enc0 ++ encL ++ encR ++ encC ++ encV, source := src }

/-- `TrieDTO.decodeFromMessage(byte[] src, TrieStore ds)` — TrieDTO.java:79-81. -/
def decode (ds : Bytes → Option Bytes) (src : Bytes) : Except Err TrieDTO :=
  decodeFromMessage ds (src.length + 1) src

/-- `toMessageHandleLeftNode` / `toMessageHandleRightNode` — TrieDTO.java:450-469
(`encodeUint8` is `new Uint8(length).encode()`, which throws above 255). -/
def childBytes (present embedded : Bool) (enc hash : Option Bytes) : Except Err Bytes :=
  if present then
    if embedded then do
      let e := enc.getD []
      let n ← Uint8.mk e.length
      pure (Uint8.encode n ++ e)
    else pure (hash.getD [])
  else pure []

/-- `TrieDTO.toMessage()` — TrieDTO.java:417-448. -/
def toMessage (H : Bytes → Bytes) (d : TrieDTO) : Except Err Bytes := do
  let lb ← childBytes d.leftNodePresent d.leftNodeEmbedded d.left d.leftHash
  let rb ← childBytes d.rightNodePresent d.rightNodeEmbedded d.right d.rightHash
  let v := d.value.getD []
  let vb ← if d.hasLongVal then do
      let l ← Uint24.mk v.length
      pure (H v ++ Uint24.encode l)
    else pure (if v.length > 0 then v else [])
  pure ([d.flags] ++
    (if d.sharedPrefixPresent then prefixBytes (d.pathLength.getD 0) (d.path.getD []) else []) ++
    lb ++ rb ++ (if d.leftNodePresent || d.rightNodePresent then VarInt.encode d.childrenSize else []) ++
    vb)

end TrieDTO
end RskjTrie
