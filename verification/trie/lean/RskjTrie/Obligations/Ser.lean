import RskjTrie.Obligations.Hash
import RskjTrie.TrieDTO
/-! # Obligations TRIE-SER-* (serialization) -/
namespace RskjTrie.Obligations
open RskjTrie Trie TrieKeySlice

set_option linter.unusedSimpArgs false

/-- TRIE-SER-01: for every node `n` with consistent caches (every node of a reachable trie) whose
shared paths fit Java's `int` (`< 2^31` bits) and `H` yielding 32 bytes: `m = n.toMessage()`
parses back to a node that re-encodes to `m` and has the same shared path, value length, inline
value (none for long values), `valueHash = H(value)`, the from-scratch `childrenSize`, and child
references that are the child's hash or the (re-parsed) embedded node. -/
theorem trie_ser_01 (env : Env) (hH : ∀ x, (env.H x).length = 32) (t : Trie) (hres : t.Resident)
    (hc : t.CacheOK env.H) (hp : t.PathsOK) :
    ∃ m t', t.toMessage env = .ok m ∧ Trie.fromMessage env m = .ok t' ∧ t'.toMessage env = .ok m ∧
      t' = t.reparse env.H ∧ t'.sharedPath = t.sharedPath ∧ t'.valueLength = t.valueLength ∧
      t'.value = (if t.valueLength > 32 then none else t.value) ∧
      t'.valueHash = (if t.valueLength > 0 then some (env.H (t.value.getD [])) else none) ∧
      (∃ c, t.getChildrenSize env FUEL = .ok c ∧ t'.childrenSize = some c) ∧
      t'.left = t.left.reparse env.H ∧ t'.right = t.right.reparse env.H := by
  obtain ⟨h1, h2⟩ := Trie.fromMessage_toMessage env hH t hres hc hp
  have hr := (Trie.reEnc env t hres) FUEL
  have he := (Trie.encOK env t hres hc FUEL).1
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
  refine ⟨_, _, h1, h2, hr.2.1, rfl, rfl, rfl, rfl, rfl, ⟨_, he, ?_⟩, rfl, rfl⟩
  simp only [Trie.reparse, Trie.encS_eq]

/-- TRIE-SER-02: equal messages of nodes with consistent caches (and shared paths `< 2^31` bits)
parse to the same node, hence equal shared path, value length, inline value, child references and
childrenSize. -/
theorem trie_ser_02 (env : Env) (hH : ∀ x, (env.H x).length = 32) (t1 t2 : Trie)
    (r1 : t1.Resident) (c1 : t1.CacheOK env.H) (p1 : t1.PathsOK)
    (r2 : t2.Resident) (c2 : t2.CacheOK env.H) (p2 : t2.PathsOK)
    (h : t1.toMessage env = t2.toMessage env) :
    t1.reparse env.H = t2.reparse env.H ∧ t1.sharedPath = t2.sharedPath ∧ t1.valueLength = t2.valueLength ∧
      t1.left.reparse env.H = t2.left.reparse env.H ∧ t1.right.reparse env.H = t2.right.reparse env.H := by
  have e := Trie.message_injective env hH t1 t2 r1 c1 p1 r2 c2 p2 h
  refine ⟨e, ?_⟩
  obtain ⟨_, _, _, _, _, _, _⟩ := t1; obtain ⟨_, _, _, _, _, _, _⟩ := t2
  simp only [Trie.reparse, Trie.mk.injEq] at e ⊢
  exact ⟨e.1, e.2.2.2.2.1, e.2.2.1, e.2.2.2.1⟩

/-- TRIE-SER-03 (Java): the embedded flag of an absent child is ignored, and an embedded child
that parses to the empty node becomes the empty reference. -/
theorem trie_ser_03 (parse : Bytes → Except Err Trie) :
    (∀ e s, readChild parse false e s = .ok (.empty, s)) ∧
    (∀ n : Trie, n.isEmptyTrie = true → NodeRef.ofNode (some n) = .empty) :=
  ⟨fun _ _ => rfl, fun n h => by simp [NodeRef.ofNode, h]⟩

/-- TRIE-SER-03 (canonical-parse reading) does not hold: `4201` (left-embedded flag without the
presence flag) and `4a01400001` (embedded empty node) are accepted; both re-encode to `4001`. -/
theorem trie_ser_03_rskip_counterexample (env : Env) :
    reencode env [0x42, 0x01] = .ok [0x40, 0x01] ∧ reencode env [0x4a, 0x01, 0x40, 0x00, 0x01] = .ok [0x40, 0x01] :=
  ⟨reencode_eq _ _ _ ⟨_, rfl, rfl, rfl⟩, reencode_eq _ _ _ ⟨_, rfl, rfl, rfl⟩⟩

/-- TRIE-SER-04: every RSKIP107 message starts with a byte in `0x40..0x7F` (never `0x02`), every
Orchid message with `0x02`, and `fromMessage` dispatches on exactly that byte. -/
theorem trie_ser_04 (env : Env) :
    (∀ (t : Trie) (m : Bytes), t.toMessage env = .ok m → ∃ (f : UInt8) (rest : Bytes), m = f :: rest ∧ 0x40 ≤ f.toNat ∧ f.toNat ≤ 0x7F) ∧
    (∀ s (t : Trie), t.Resident → ∃ rest, t.toMessageOrchid env s = .ok (0x02 :: rest)) ∧
    (∀ b rest, fromMessage env (b :: rest) =
      if b.toNat = 2 then fromMessageOrchid env (b :: rest) else fromMessageRskip107 env (rest.length + 1 + 1) (b :: rest)) := by
  refine ⟨fun t m h => ?_, fun s t h => ⟨_, Trie.toMessageOrchid_layout env s t h⟩, Trie.fromMessage_dispatch env⟩
  obtain ⟨a, b, c, d, e, f, rest, hm, _⟩ := Trie.internalToMessage_head env FUEL t m h
  exact ⟨_, rest, hm, mkFlags_range a b c d e f⟩

/-- TRIE-SER-05 (partial): `fromMessage` is total (a Lean function: it returns a node or an
error on every input). Memory is not modelled; the closest property: on `50 ff fe ffffff7f`
(`lshared = 2^31-1`) the parser computes `lencoded = 268435456` — the size of the `byte[]` Java
allocates (SharedPathSerializer.java:143) before reading — from a 7-byte input, then fails. -/
theorem trie_ser_05 (env : Env) :
    (∀ m, (∃ t, fromMessage env m = .ok t) ∨ ∃ e, fromMessage env m = .error e) ∧
    PathEncoder.calculateEncodedLengthInt (2 ^ 31 - 1) = 268435456 ∧
    SharedPathSerializer.getPathBitsLength [0xff, 0xfe, 0xff, 0xff, 0xff, 0x7f] = .ok (2 ^ 31 - 1, []) ∧
    ∃ e, fromMessage env [0x50, 0xff, 0xfe, 0xff, 0xff, 0xff, 0x7f] = .error e := by
  refine ⟨fun m => ?_, by decide, rfl, _, rfl⟩
  cases fromMessage env m with
  | ok t => exact .inl ⟨t, rfl⟩
  | error e => exact .inr ⟨e, rfl⟩

/-- TRIE-SER-06: the Orchid layout. -/
theorem trie_ser_06 (env : Env) (s : Bool) (t : Trie) (h : t.Resident) :
    t.toMessageOrchid env s = .ok (
      let lh := NodeRef.orchidHashS env.H s t.left
      let rh := NodeRef.orchidHashS env.H s t.right
      [(2 : UInt8), (if s then 1 else 0) ||| (if decide (t.valueLength > 32) then 2 else 0)] ++
      putShort ((if lh.isSome then 0b01 else 0) ||| (if rh.isSome then 0b10 else 0)) ++
      putShort t.sharedPath.length ++
      (if t.sharedPath.length > 0 then TrieKeySlice.encode t.sharedPath else []) ++
      lh.getD [] ++ rh.getD [] ++
      (if t.valueLength > 0 then
        (if t.valueLength > 32 then (match t.valueHash with | some vh => vh | none => env.H (t.value.getD []))
         else t.value.getD []) else [])) :=
  Trie.toMessageOrchid_layout env s t h

/-- TRIE-SER-07: `fromMessageOrchid(toMessageOrchid(s))` has the node's shared path and value and
references the children by their Orchid hashes (short values); a long value is read from the
store by `valueHash`, and bytes after the value hash are ignored (e.g. `02 02 0000 0000 <hash> ff`).
Shared paths are limited to `< 2^16` bits by the `int16` length field. -/
theorem trie_ser_07 (env : Env) (hH : ∀ x, (env.H x).length = 32) (s : Bool) :
    (∀ t : Trie, t.Resident → t.sharedPath.length < 2 ^ 16 → t.valueLength ≤ 32 →
      Trie.fromMessageOrchid env (t.orchidS env.H s) =
        .ok ⟨t.sharedPath, t.value, NodeRef.orchidRef env.H s t.left, NodeRef.orchidRef env.H s t.right,
          t.valueLength, none, none⟩) ∧
    (∀ t : Trie, t.Resident → t.CacheOK env.H → t.sharedPath.length < 2 ^ 16 → t.valueLength > 32 →
      env.db (env.H (t.value.getD [])) = some (t.value.getD []) → ∀ rest,
      Trie.fromMessageOrchid env (t.orchidS env.H s ++ rest) =
        .ok ⟨t.sharedPath, t.value, NodeRef.orchidRef env.H s t.left, NodeRef.orchidRef env.H s t.right,
          t.valueLength, some (env.H (t.value.getD [])), none⟩) ∧
    (∀ t : Trie, t.Resident → t.toMessageOrchid env s = .ok (t.orchidS env.H s)) :=
  ⟨fun t h1 h2 h3 => Trie.fromMessageOrchid_orchidS env hH s t h1 h2 h3,
   fun t h1 h2 h3 h4 h5 rest => Trie.fromMessageOrchid_orchidS_long env hH s t h1 h2 h3 h4 h5 rest,
   fun t h => (Trie.orchidOK env s t h FUEL).1⟩

/-! ### TRIE-SER-08 (TrieDTO) -/

/-- keccak256 of 33 × `ab` (read from the Java message below). -/
def hv33 : Bytes := [0x03, 0x4e, 0xf2, 0xad, 0xf2, 0xde, 0xaa, 0x46, 0xa3, 0xb4, 0xd9, 0xca, 0x2a, 0x21, 0xa4,
  0xab, 0x51, 0x3d, 0x60, 0x47, 0x7f, 0x6a, 0x45, 0x4b, 0xa9, 0xdd, 0xe6, 0x0a, 0x9b, 0x3e, 0x48, 0x03]
/-- Java `t3.toMessage()` for `t3 = {00: 33×ab, 01: 02}` (probe output): the left child is an
embedded long-value leaf `60 ‖ keccak(v) ‖ 000021`. -/
def m08 : Bytes := [0x5f, 0x06, 0x00, 0x24, 0x60] ++ hv33 ++ [0x00, 0x00, 0x21, 0x02, 0x40, 0x02, 0x47]
/-- Java `TrieDTO.decodeFromMessage(m, store).toMessage()` (probe output). -/
def m08dto : Bytes := [0x5f, 0x06, 0x00, 0x22, 0x60] ++ List.replicate 33 0xab ++ [0x02, 0x40, 0x02, 0x47]
/-- The store after `store.save(t3)` as far as the DTO parser reads it. -/
def ds08 : DB := DB.empty.put hv33 (List.replicate 33 0xab)

theorem hv33_eq : Keccak.keccak256 (List.replicate 33 0xab) = hv33 := by decide +kernel

/-- TRIE-SER-08 (Java): `TrieDTO.toMessage()` writes an embedded child as `Uint8(|e|) ‖ e` where
`e` is the child DTO's `encoded` (its sync encoding, TrieDTO.java:450-469), and a long value by
re-hashing the value it read from the store (TrieDTO.java:436-441). -/
theorem trie_ser_08 (H : Bytes → Bytes) (d : TrieDTO) :
    TrieDTO.toMessage H d = (do
      let lb ← TrieDTO.childBytes d.leftNodePresent d.leftNodeEmbedded d.left d.leftHash
      let rb ← TrieDTO.childBytes d.rightNodePresent d.rightNodeEmbedded d.right d.rightHash
      let v := d.value.getD []
      let vb ← if d.hasLongVal then do
          let l ← Uint24.mk v.length
          pure (H v ++ Uint24.encode l)
        else pure (if v.length > 0 then v else [])
      pure ([d.flags] ++
        (if d.sharedPrefixPresent then TrieDTO.prefixBytes (d.pathLength.getD 0) (d.path.getD []) else []) ++
        lb ++ rb ++ (if d.leftNodePresent || d.rightNodePresent then VarInt.encode d.childrenSize else []) ++ vb)) ∧
    (∀ e : Bytes, e.length < 256 → TrieDTO.childBytes true true (some e) none = .ok (Uint8.encode e.length ++ e)) :=
  ⟨rfl, fun e he => by simp [TrieDTO.childBytes, Uint8.mk, show ¬ (e.length > 0xff) by omega]⟩

set_option maxRecDepth 200000 in
/-- TRIE-SER-08 does not hold: `m08` is a canonical encoding (`Trie.fromMessage(m).toMessage() = m`),
but `TrieDTO.decodeFromMessage(m, store).toMessage()` is Java's `m08dto ≠ m08`: the embedded
long-value child is re-emitted in its sync form (value inline) with length `22`. -/
theorem trie_ser_08_rskip_counterexample (H : Bytes → Bytes) :
    reencode ⟨H, ds08⟩ m08 = .ok m08 ∧
    (TrieDTO.decode ds08 m08 >>= TrieDTO.toMessage H) = .ok m08dto ∧ m08dto ≠ m08 := by
  refine ⟨reencode_eq _ _ _ ⟨⟨List.replicate 7 false, none,
      .node ⟨[], none, .empty, .empty, 33, some hv33, some 0⟩,
      .node ⟨[], some [0x02], .empty, .empty, 1, some (H [0x02]), some 0⟩, 0, none, some 71⟩, ?_, rfl, ?_⟩, ?_, by decide⟩
  · rfl
  · enc_eval
  · rfl

end RskjTrie.Obligations
