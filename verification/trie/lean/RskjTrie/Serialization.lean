import RskjTrie.Trie
/-!
# Serialization: `Trie.fromMessage*`, `Trie.toMessage*`, hashes and sizes

Also contains the store-reading methods these need (the read side of `TrieStoreImpl` and
`NodeReference.getNode`), and the store/serialization-dependent `NodeReference` methods, because
Java's `Trie` and `NodeReference` are mutually recursive through them.

Nested *store reads* inside a size/hash computation consume `fuel` (see `FUEL`); recursion into
resident (in-memory) children does not.
-/
namespace RskjTrie

/-- Flag test `(flags & m) == m` on the Java (signed) byte. -/
def bitSet (flags m : UInt8) : Bool := (flags &&& m) == m

namespace Trie

/-- `Trie.readVarInt(ByteBuffer)` — Trie.java:1149-1165 (same code as
`SharedPathSerializer.readVarInt`). -/
def readVarInt : BB Nat := SharedPathSerializer.readVarInt

/-- Reading one child reference in `fromMessageRskip107` — Trie.java:273-289 (left) and
291-307 (right), which are the same code: embedded → `Uint8` length, the node bytes, and a
recursive `fromMessageRskip107` of exactly those bytes wrapped in `new NodeReference(store, node,
null)`; otherwise a 32-byte hash. `parse` is the recursive call. -/
def readChild (parse : Bytes → Except Err Trie) (present embedded : Bool) : BB (NodeRef Trie) :=
  if present then
    if embedded then do
      let lengthBytes ← BB.getN 1
      let length ← StateT.lift (Uint8.decode lengthBytes 0)
      let serializedNode ← BB.getN length
      let node ← StateT.lift (parse serializedNode)
      pure (NodeRef.ofNode (some node))
    else do
      let valueHash ← BB.getN 32
      pure (NodeRef.hash valueHash)
  else pure NodeRef.empty

/-- Reading the value in `fromMessageRskip107` — Trie.java:314-338: a long value is its 32-byte
hash and `Uint24` length (value left in the store); otherwise all remaining bytes (hash computed
eagerly); nothing left means no value. Returns `(value, valueLength, valueHash)`. -/
def readValue (env : Env) (hasLongVal : Bool) : BB (Option Bytes × Nat × Option Bytes) :=
  if hasLongVal then do
    let valueHashBytes ← BB.getN 32
    let lvalueBytes ← BB.getN 3
    let lvalue ← StateT.lift (Uint24.decode lvalueBytes 0)
    pure (none, lvalue, some valueHashBytes)
  else do
    let remaining ← BB.remaining
    if remaining ≠ 0 then do
      let value ← BB.getN remaining
      let lvalue ← StateT.lift (Uint24.mk remaining)
      pure (some value, lvalue, some (env.H value))
    else pure (none, 0, none)

/-- `Trie.fromMessageRskip107(ByteBuffer, TrieStore)` — Trie.java:259-347. The first argument
bounds the nesting depth of embedded nodes for structural recursion; `fromMessage` passes
`message.length + 1`, which is never exhausted because every nesting level consumes at least the
flags and length bytes of its parent. -/
def fromMessageRskip107 (env : Env) : Nat → Bytes → Except Err Trie
  | 0, _ => .error "StackOverflowError"
  | fuel + 1, msg => StateT.run' (σ := Bytes) (m := Except Err) (s := msg) do
    let flags ← BB.get
    -- if we reached here, we don't need to check the version flag
    let hasLongVal := bitSet flags 0b00100000
    let sharedPrefixPresent := bitSet flags 0b00010000
    let leftNodePresent := bitSet flags 0b00001000
    let rightNodePresent := bitSet flags 0b00000100
    let leftNodeEmbedded := bitSet flags 0b00000010
    let rightNodeEmbedded := bitSet flags 0b00000001
    let sharedPath ← SharedPathSerializer.deserialize sharedPrefixPresent
    let left ← readChild (fromMessageRskip107 env fuel) leftNodePresent leftNodeEmbedded
    let right ← readChild (fromMessageRskip107 env fuel) rightNodePresent rightNodeEmbedded
    let childrenSize ← if leftNodePresent || rightNodePresent then readVarInt else pure 0
    let (value, lvalue, valueHash) ← readValue env hasLongVal
    if (← BB.remaining) > 0 then
      throw "IllegalArgumentException: The message had more data than expected"
    let t : Trie := ⟨sharedPath, value, left, right, lvalue, valueHash, some childrenSize⟩
    StateT.lift t.checkValueLength
    pure t

/-- `Trie.readHash(byte[], int)` — Trie.java:1092-1102. -/
def readHash (bytes : Bytes) (position : Nat) : Except Err Bytes :=
  if bytes.length - position < 32 then .error "IllegalArgumentException: message too short for hash"
  else .ok ((bytes.drop position).take 32)

/-- `Trie.fromMessageOrchid(byte[], TrieStore)` — Trie.java:177-257 (pre-RSKIP107 format).
A long value is read from the store at parse time (`store.retrieveValue`); a missing value makes
Java throw `NullPointerException` at `value.length`. -/
def fromMessageOrchid (env : Env) (message : Bytes) : Except Err Trie := do
  let arity ← idx message 0
  if arity.toNat ≠ ARITY then throw "IllegalArgumentException: Invalid arity"
  let flags ← idx message 1
  let hasLongVal := (flags &&& 0x02) == 2
  let bhashes ← Uint16.decodeToInt message 2
  let lshared ← Uint16.decodeToInt message 4
  let current := 6
  let lencoded := PathEncoder.calculateEncodedLength lshared
  let (sharedPath, current) ← if lencoded > 0 then do
      if message.length - current < lencoded then
        throw "IllegalArgumentException: Left message is too short for encoded shared path"
      let sp ← TrieKeySlice.fromEncoded message current lshared lencoded
      pure (sp, current + lencoded)
    else pure (TrieKeySlice.empty, current)
  let (left, current, nhashes) ← if bhashes &&& 0b01 ≠ 0 then do
      let nodeHash ← readHash message current
      pure (NodeRef.hash nodeHash, current + 32, 1)
    else pure (NodeRef.empty, current, 0)
  let (right, current, nhashes) ← if bhashes &&& 0b10 ≠ 0 then do
      let nodeHash ← readHash message current
      pure (NodeRef.hash nodeHash, current + 32, nhashes + 1)
    else pure (NodeRef.empty, current, nhashes)
  let offset := MESSAGE_HEADER_LENGTH + lencoded + nhashes * 32
  let t ← if hasLongVal then do
      let valueHash ← readHash message current
      let value ← match env.db valueHash with
        | some v => pure v
        | none => throw "NullPointerException: long value not in store"
      let lvalue ← Uint24.mk value.length
      pure (⟨sharedPath, some value, left, right, lvalue, some valueHash, none⟩ : Trie)
    else do
      let remaining := message.length - offset
      if remaining > 0 then do
        if message.length - current < remaining then
          throw "IllegalArgumentException: Left message is too short for value"
        let value := (message.drop current).take remaining
        let lvalue ← Uint24.mk remaining
        pure ⟨sharedPath, some value, left, right, lvalue, none, none⟩
      else pure ⟨sharedPath, none, left, right, 0, none, none⟩
  t.checkValueLength
  pure t

/-- `Trie.fromMessage(byte[], TrieStore)` — Trie.java:163-175: `message[0] == ARITY` selects
the legacy (orchid) format. -/
def fromMessage (env : Env) (message : Bytes) : Except Err Trie := do
  let b0 ← idx message 0
  if b0.toNat = ARITY then fromMessageOrchid env message
  else fromMessageRskip107 env (message.length + 1) message

end Trie

namespace TrieStoreImpl
/-- `TrieStoreImpl.retrieveValue(byte[] hash)` — TrieStoreImpl.java:210-219. -/
def retrieveValue (env : Env) (hash : Bytes) : Option Bytes := env.db hash

/-- `TrieStoreImpl.retrieve(byte[] hash)` — TrieStoreImpl.java:152-168 (`markAsSaved` is not
modelled). -/
def retrieve (env : Env) (hash : Bytes) : Except Err (Option Trie) :=
  match env.db hash with
  | none => .ok none
  | some message => some <$> Trie.fromMessage env message
end TrieStoreImpl

/-- `NodeReference.getNode()` — NodeReference.java:87-126. A missing node makes Java call
`nodeStopper.stop(1)` (`System.exit(1)`); the model returns an error. The retrieved node is
cached in `lazyNode` by Java; the model re-reads it (the store maps a hash to a fixed message). -/
def NodeRef.getNode (env : Env) : NodeRef Trie → Except Err (Option Trie)
  | .empty => .ok none
  | .node t => .ok (some t)
  | .hash h => do
    match ← TrieStoreImpl.retrieve env h with
    | some t => pure (some t)
    | none => throw "System.exit(1): Broken database, execution can't continue"

namespace Trie

/-- `Trie.makeEmptyHash()` — Trie.java:1088-1090: `keccak256(RLP.encodeElement(EMPTY_BYTE_ARRAY))`
and `RLP.encodeElement(new byte[0]) = {0x80}`. -/
def emptyHash (env : Env) : Bytes := env.H [0x80]

/-- `Trie.getValue()` — Trie.java:985-992 with `retrieveLongValue` (Trie.java:1013-1015) and
`checkValueLengthAfterRetrieve` (Trie.java:1017-1025). A lazy long value (`value == null`,
`valueLength > 0`) is read from the store by its `valueHash` (non-null by `checkValueLength`). -/
def getValue (env : Env) (t : Trie) : Except Err (Option Bytes) :=
  match t.value with
  | some v => .ok (some v)
  | none =>
    if t.valueLength > 0 then
      match t.valueHash with
      | none => .error "unreachable: excluded by checkValueLength"
      | some h =>
        match TrieStoreImpl.retrieveValue env h with
        | none => .error "IllegalArgumentException: Invalid value length"
        | some v =>
          if v.length ≠ t.valueLength then .error "IllegalArgumentException: Invalid value length"
          else .ok (some v)
    else .ok none

/-- `Trie.getValueHash()` — Trie.java:975-983. -/
def getValueHash (env : Env) (t : Trie) : Except Err (Option Bytes) :=
  match t.valueHash with
  | some h => .ok (some h)
  | none =>
    if t.valueLength > 0 then do
      let v ← t.getValue env
      pure (some (env.H (v.getD [])))
    else .ok none

/-- The flags byte computed by `internalToMessage` — Trie.java:693-719. -/
def mkFlags (hasLongVal sharedPresent leftPresent rightPresent leftEmb rightEmb : Bool) : UInt8 :=
  let f : UInt8 := 0b01000000
  let f := if hasLongVal then f ||| 0b00100000 else f
  let f := if sharedPresent then f ||| 0b00010000 else f
  let f := if leftPresent then f ||| 0b00001000 else f
  let f := if rightPresent then f ||| 0b00000100 else f
  let f := if leftEmb then f ||| 0b00000010 else f
  let f := if rightEmb then f ||| 0b00000001 else f
  f

theorem sizeOf_left_lt (t : Trie) : sizeOf t.left < sizeOf t := by cases t; simp; omega
theorem sizeOf_right_lt (t : Trie) : sizeOf t.right < sizeOf t := by cases t; simp; omega

end Trie

mutual

/-- `Trie.internalToMessage()` — Trie.java:677-739 (the RSKIP107 encoding; `toMessage` returns
it, Trie.java:506-512). Java sizes a `ByteBuffer` with `serializedLength()`s and then `put`s the
same pieces; the model concatenates the pieces. -/
def Trie.internalToMessage (env : Env) (fuel : Nat) (t : Trie) : Except Err Bytes := do
  let lvalue := t.valueLength
  let hasLongVal := t.hasLongValue
  let childrenSize ← t.getChildrenSize env fuel
  let leftEmb ← t.left.isEmbeddable env fuel
  let rightEmb ← t.right.isEmbeddable env fuel
  let flags := Trie.mkFlags hasLongVal (SharedPathSerializer.isPresent t.sharedPath)
    (!t.left.isEmpty) (!t.right.isEmpty) leftEmb rightEmb
  let leftBytes ← t.left.serializeInto env fuel
  let rightBytes ← t.right.serializeInto env fuel
  let csBytes := if !t.isTerminal then VarInt.encode childrenSize else []
  let valueBytes ← if hasLongVal then do
      match ← t.getValueHash env with
      | some vh => pure (vh ++ Uint24.encode lvalue)
      | none => throw "NullPointerException"
    else if lvalue > 0 then do
      match ← t.getValue env with
      | some v => pure v
      | none => throw "NullPointerException"
    else pure []
  pure (flags :: SharedPathSerializer.serializeInto t.sharedPath ++ leftBytes ++ rightBytes ++
    csBytes ++ valueBytes)
termination_by (fuel, sizeOf t, 5)
decreasing_by
  all_goals first
    | (apply Prod.Lex.right; apply Prod.Lex.right; omega)
    | (apply Prod.Lex.right; apply Prod.Lex.left; first
        | exact Trie.sizeOf_left_lt t | exact Trie.sizeOf_right_lt t)

/-- `Trie.isEmbeddable()` — Trie.java:587-589: `isTerminal() && getMessageLength() <= 44`
(short-circuit: the message is only built for terminal nodes). -/
def Trie.isEmbeddable (env : Env) (fuel : Nat) (t : Trie) : Except Err Bool :=
  if t.isTerminal then do
    let m ← t.internalToMessage env fuel
    pure (decide (m.length ≤ Trie.MAX_EMBEDDED_NODE_SIZE_IN_BYTES))
  else .ok false
termination_by (fuel, sizeOf t, 6)
decreasing_by apply Prod.Lex.right; apply Prod.Lex.right; omega

/-- `Trie.getHash()` — Trie.java:362-376. -/
def Trie.getHashF (env : Env) (fuel : Nat) (t : Trie) : Except Err Bytes :=
  if t.isEmptyTrie then .ok (Trie.emptyHash env)
  else do
    let m ← t.internalToMessage env fuel
    pure (env.H m)
termination_by (fuel, sizeOf t, 6)
decreasing_by apply Prod.Lex.right; apply Prod.Lex.right; omega

/-- `Trie.getChildrenSize()` — Trie.java:1001-1011: the cached/deserialized value, or (if null)
`0` for terminal nodes, else `left.referenceSize() + right.referenceSize()` (long addition). -/
def Trie.getChildrenSize (env : Env) (fuel : Nat) (t : Trie) : Except Err Nat :=
  match t.childrenSize with
  | some c => .ok c
  | none =>
    if t.isTerminal then .ok 0
    else do
      let l ← t.left.referenceSize env fuel
      let r ← t.right.referenceSize env fuel
      pure (wrap64 ((l : Int) + r))
termination_by (fuel, sizeOf t, 4)
decreasing_by
  all_goals apply Prod.Lex.right; apply Prod.Lex.left
  · exact Trie.sizeOf_left_lt t
  · exact Trie.sizeOf_right_lt t

/-- `NodeReference.nodeSize(Trie)` — NodeReference.java:192-195:
`trie.getChildrenSize().value + externalValueLength + trie.getMessageLength()` (long). -/
def Trie.nodeSize (env : Env) (fuel : Nat) (t : Trie) : Except Err Nat := do
  let ext : Nat := if t.hasLongValue then t.valueLength else 0
  let cs ← t.getChildrenSize env fuel
  let m ← t.internalToMessage env fuel
  pure (wrap64 ((cs : Int) + ext + m.length))
termination_by (fuel, sizeOf t, 7)
decreasing_by all_goals apply Prod.Lex.right; apply Prod.Lex.right; omega

/-- `NodeReference.referenceSize()` — NodeReference.java:188-190:
`getNode().map(this::nodeSize).orElse(0L)`. Reading a hashed node from the store costs one unit
of fuel. -/
def NodeRef.referenceSize (env : Env) (fuel : Nat) (r : NodeRef Trie) : Except Err Nat :=
  match r with
  | .empty => .ok 0
  | .node t => t.nodeSize env fuel
  | .hash h =>
    match fuel with
    | 0 => .error "StackOverflowError (store-read nesting bound)"
    | fuel' + 1 => do
      match ← (NodeRef.hash h).getNode env with
      | some t => t.nodeSize env fuel'
      | none => pure 0
termination_by (fuel, sizeOf r, 3)
decreasing_by
  · apply Prod.Lex.right; apply Prod.Lex.left; simp
  · apply Prod.Lex.left; omega

/-- `NodeReference.isEmbeddable()` — NodeReference.java:141-148: only a resident node can be
embedded. -/
def NodeRef.isEmbeddable (env : Env) (fuel : Nat) (r : NodeRef Trie) : Except Err Bool :=
  match r with
  | .node t => t.isEmbeddable env fuel
  | _ => .ok false
termination_by (fuel, sizeOf r, 7)
decreasing_by apply Prod.Lex.right; apply Prod.Lex.left; simp

/-- `NodeReference.serializeInto(ByteBuffer)` — NodeReference.java:168-180: nothing for an empty
reference, `Uint8(length) ++ message` for an embeddable node, else the 32-byte hash. -/
def NodeRef.serializeInto (env : Env) (fuel : Nat) (r : NodeRef Trie) : Except Err Bytes :=
  match r with
  | .empty => .ok []
  | .hash h => .ok h
  | .node t => do
    if ← t.isEmbeddable env fuel then
      let serialized ← t.internalToMessage env fuel
      let len ← Uint8.mk serialized.length
      pure (Uint8.encode len ++ serialized)
    else
      -- `getHash()` of a resident reference is `lazyNode.getHash()` (`NodeRef.getHash`)
      let h ← t.getHashF env fuel
      pure h
termination_by (fuel, sizeOf r, 7)
decreasing_by all_goals apply Prod.Lex.right; apply Prod.Lex.left; simp

end

/-- `NodeReference.getHash()` — NodeReference.java:69-80. -/
def NodeRef.getHash (env : Env) (fuel : Nat) (r : NodeRef Trie) : Except Err (Option Bytes) :=
  match r with
  | .empty => .ok none
  | .hash h => .ok (some h)
  | .node t => some <$> t.getHashF env fuel

namespace Trie

/-- `Trie.toMessage()` — Trie.java:506-512. -/
def toMessage (env : Env) (t : Trie) : Except Err Bytes := t.internalToMessage env FUEL

/-- `Trie.getMessageLength()` — Trie.java:514-520. -/
def getMessageLength (env : Env) (t : Trie) : Except Err Nat := List.length <$> t.toMessage env

/-- `Trie.getHash()` — Trie.java:362-376. -/
def getHash (env : Env) (t : Trie) : Except Err Bytes := t.getHashF env FUEL

end Trie

/-! ## Legacy (orchid) encoding -/

/-- Java `ByteBuffer.putShort((short) v)` (big-endian, truncated to 16 bits). -/
def putShort (v : Nat) : Bytes := [(v / 256 % 256).toUInt8, (v % 256).toUInt8]

mutual
/-- `Trie.toMessageOrchid(boolean isSecure)` — Trie.java:525-583. -/
def Trie.toMessageOrchidF (env : Env) (fuel : Nat) (isSecure : Bool) (t : Trie) : Except Err Bytes := do
  let lvalue := t.valueLength
  let lshared := t.sharedPath.length
  -- `lencoded` only sizes the Java buffer; the encoded path below has exactly that length
  let hasLongVal := t.hasLongValue
  let leftHashOpt ← t.left.getHashOrchid env fuel isSecure
  let rightHashOpt ← t.right.getHashOrchid env fuel isSecure
  let bits : Nat := (if leftHashOpt.isSome then 0b01 else 0) ||| (if rightHashOpt.isSome then 0b10 else 0)
  let flags : UInt8 := (if isSecure then 1 else 0) ||| (if hasLongVal then 2 else 0)
  let valueBytes ← if lvalue > 0 then
      if hasLongVal then do
        match ← t.getValueHash env with
        | some vh => pure vh
        | none => throw "NullPointerException"
      else do
        match ← t.getValue env with
        | some v => pure v
        | none => throw "NullPointerException"
    else pure []
  pure ([(2 : UInt8), flags] ++ putShort bits ++ putShort lshared ++
    (if lshared > 0 then t.sharedPath.encode else []) ++
    leftHashOpt.getD [] ++ rightHashOpt.getD [] ++ valueBytes)
termination_by (fuel, sizeOf t, 2)
decreasing_by
  all_goals apply Prod.Lex.right; apply Prod.Lex.left
  · exact Trie.sizeOf_left_lt t
  · exact Trie.sizeOf_right_lt t

/-- `Trie.getHashOrchid(boolean)` — Trie.java:381-395. -/
def Trie.getHashOrchidF (env : Env) (fuel : Nat) (isSecure : Bool) (t : Trie) : Except Err Bytes :=
  if t.isEmptyTrie then .ok (Trie.emptyHash env)
  else do
    let m ← t.toMessageOrchidF env fuel isSecure
    pure (env.H m)
termination_by (fuel, sizeOf t, 3)
decreasing_by apply Prod.Lex.right; apply Prod.Lex.right; omega

/-- `NodeReference.getHashOrchid(boolean)` — NodeReference.java:132-134:
`getNode().map(trie -> trie.getHashOrchid(isSecure))` (reads hashed nodes from the store). -/
def NodeRef.getHashOrchid (env : Env) (fuel : Nat) (isSecure : Bool) (r : NodeRef Trie) :
    Except Err (Option Bytes) :=
  match r with
  | .empty => .ok none
  | .node t => some <$> t.getHashOrchidF env fuel isSecure
  | .hash h =>
    match fuel with
    | 0 => .error "StackOverflowError (store-read nesting bound)"
    | fuel' + 1 => do
      match ← (NodeRef.hash h).getNode env with
      | some t => some <$> t.getHashOrchidF env fuel' isSecure
      | none => pure none
termination_by (fuel, sizeOf r, 1)
decreasing_by
  · apply Prod.Lex.right; apply Prod.Lex.left; simp
  · apply Prod.Lex.left; omega
end

def Trie.toMessageOrchid (env : Env) (isSecure : Bool) (t : Trie) : Except Err Bytes :=
  t.toMessageOrchidF env FUEL isSecure

end RskjTrie
