import RskjTrie.Proofs.RoundTrip
/-!
# Proofs: the legacy (Orchid, pre-RSKIP107) encoding

`Trie.orchidS` is a pure encoder for resident tries; `toMessageOrchid` computes it. Children are
referenced by their Orchid hashes.
-/
namespace RskjTrie
open Trie

set_option linter.unusedSimpArgs false

mutual
/-- Pure `toMessageOrchid(isSecure)` of a resident trie (Trie.java:525-583). -/
def Trie.orchidS (H : Bytes → Bytes) (s : Bool) : Trie → Bytes
  | ⟨p, v, l, r, vl, vh, _⟩ =>
    let lh := NodeRef.orchidHashS H s l
    let rh := NodeRef.orchidHashS H s r
    let bits : Nat := (if lh.isSome then 0b01 else 0) ||| (if rh.isSome then 0b10 else 0)
    let flags : UInt8 := (if s then 1 else 0) ||| (if decide (vl > 32) then 2 else 0)
    let vb := if vl > 0 then
        (if vl > 32 then (match vh with | some h => h | none => H (v.getD [])) else v.getD [])
      else []
    [(2 : UInt8), flags] ++ putShort bits ++ putShort p.length ++
      (if p.length > 0 then TrieKeySlice.encode p else []) ++ lh.getD [] ++ rh.getD [] ++ vb
/-- Pure `NodeReference.getHashOrchid(isSecure)` of a resident reference. -/
def NodeRef.orchidHashS (H : Bytes → Bytes) (s : Bool) : NodeRef Trie → Option Bytes
  | .node c => some (if c.isEmptyTrie then H [0x80] else H (Trie.orchidS H s c))
  | _ => none
end

mutual
theorem Trie.orchidOK (env : Env) (s : Bool) : ∀ (t : Trie), t.Resident → ∀ fuel,
    t.toMessageOrchidF env fuel s = .ok (t.orchidS env.H s) ∧
    t.getHashOrchidF env fuel s = .ok (if t.isEmptyTrie then env.H [0x80] else env.H (t.orchidS env.H s))
  | ⟨p, v, l, r, vl, vh, cs⟩, ⟨hv, hl, hr⟩, fuel => by
    have il := NodeRef.orchidOK env s l hl fuel
    have ir := NodeRef.orchidOK env s r hr fuel
    have hmsg : Trie.toMessageOrchidF env fuel s ⟨p, v, l, r, vl, vh, cs⟩ =
        .ok (Trie.orchidS env.H s ⟨p, v, l, r, vl, vh, cs⟩) := by
      rw [Trie.toMessageOrchidF]
      simp only [il, ir, except_bind_ok]
      rcases hv with ⟨rfl, rfl⟩ | ⟨x, rfl, hx, hpos, _⟩
      · simp [Trie.orchidS, hasLongValue]
      · by_cases hlong : vl > 32
        · cases vh with
          | none => simp [Trie.orchidS, hasLongValue, hlong, hpos, getValueHash, getValue]
          | some h => simp [Trie.orchidS, hasLongValue, hlong, hpos, getValueHash]
        · simp [Trie.orchidS, hasLongValue, hlong, hpos, getValue]
    refine ⟨hmsg, ?_⟩
    rw [Trie.getHashOrchidF]
    split
    · simp [emptyHash]
    · simp [hmsg]
theorem NodeRef.orchidOK (env : Env) (s : Bool) : ∀ (r : NodeRef Trie), r.Resident → ∀ fuel,
    r.getHashOrchid env fuel s = .ok (NodeRef.orchidHashS env.H s r)
  | .empty, _, fuel => by simp [NodeRef.getHashOrchid, NodeRef.orchidHashS]
  | .hash _, h, _ => absurd h (by simp [NodeRef.Resident])
  | .node c, ⟨hres, _⟩, fuel => by
    rw [NodeRef.getHashOrchid]
    simp [(Trie.orchidOK env s c hres fuel).2, NodeRef.orchidHashS]
end

/-- **Orchid layout** (TRIE-SER-06): `toMessageOrchid(s)` of a resident node is
`0x02 ++ flags (bit0 secure, bit1 hasLongValue) ++ uint16 child bitmask (bit0 left, bit1 right)
++ int16 lshared ++ encodedSharedPath (if lshared > 0) ++ left hash ++ right hash ++
(valueHash if hasLongValue else value)`, children by their Orchid hashes. -/
theorem Trie.toMessageOrchid_layout (env : Env) (s : Bool) (t : Trie) (h : t.Resident) :
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
         else t.value.getD []) else [])) := by
  rw [Trie.toMessageOrchid, (Trie.orchidOK env s t h FUEL).1]
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t; rfl

/-- **Orchid hash** (TRIE-HASH-05): `getHashOrchid(s) = keccak256(toMessageOrchid(s))` for a
non-empty node and `EMPTY_HASH = H [0x80]` for the empty node (any trie, by definition). -/
theorem Trie.getHashOrchid_eq (env : Env) (fuel : Nat) (s : Bool) (t : Trie) :
    t.getHashOrchidF env fuel s =
      if t.isEmptyTrie then .ok (env.H [0x80]) else env.H <$> t.toMessageOrchidF env fuel s := by
  rw [Trie.getHashOrchidF]
  split
  · rfl
  · cases t.toMessageOrchidF env fuel s <;> rfl

/-- The reference `fromMessageOrchid` builds for a child: its Orchid hash, or empty. -/
def NodeRef.orchidRef (H : Bytes → Bytes) (s : Bool) (r : NodeRef Trie) : NodeRef Trie :=
  match NodeRef.orchidHashS H s r with
  | some h => .hash h
  | none => .empty

theorem putShort_decode (n : Nat) (h : n < 2 ^ 16) (a b : UInt8) (rest : Bytes) :
    Uint16.decodeToInt (a :: b :: putShort n ++ rest) 2 = .ok n := by
  simp [Uint16.decodeToInt, putShort, idx, toUInt8_toNat]; omega

theorem orchidHashS_length (H : Bytes → Bytes) (hH : ∀ x, (H x).length = 32) (s : Bool) (r : NodeRef Trie) :
    ((NodeRef.orchidHashS H s r).getD []).length = if (NodeRef.orchidHashS H s r).isSome then 32 else 0 := by
  cases r with
  | node c => simp only [NodeRef.orchidHashS]; split <;> simp [hH]
  | _ => simp [NodeRef.orchidHashS]

/-! ## Parsing Orchid encodings -/

/-- The reference `fromMessageOrchid` builds from an optional child hash. -/
def optRef (o : Option Bytes) : NodeRef Trie := match o with | some h => .hash h | none => .empty

/-- The common tail of `fromMessageOrchid`: value, `checkValueLength`. -/
def orchidTail (env : Env) (M : Bytes) (hasLong : Bool) (p : List Bool) (l r : NodeRef Trie) (c : Nat) :
    Except Err Trie := do
  let t ← orchidValue env M hasLong p l r c c
  t.checkValueLength
  pure t

theorem oc_some (M h rest : Bytes) (hl : h.length = 32) (cur n : Nat) (hd : M.drop cur = h ++ rest) :
    orchidChild M true cur n = .ok (.hash h, cur + 32, n + 1) := by
  have hlen : M.length - cur = h.length + rest.length := by rw [← List.length_drop, hd, List.length_append]
  have : ¬ (M.length - cur < 32) := by omega
  simp only [orchidChild, readHash, this, ↓reduceIte, except_bind_ok, hd, List.take_left' hl]; rfl

theorem oc_none (M : Bytes) (cur n : Nat) : orchidChild M false cur n = .ok (.empty, cur, n) := rfl

theorem ov_short (env : Env) (M V : Bytes) (p : List Bool) (l r : NodeRef Trie) (cur : Nat)
    (hd : M.drop cur = V) (hV : V.length ≤ Uint24.MAX) :
    orchidTail env M false p l r cur =
      (.ok ⟨p, (if V = [] then none else some V), l, r, V.length, none, none⟩ : Except Err Trie) := by
  have hlen : M.length - cur = V.length := by rw [← List.length_drop, hd]
  unfold orchidTail orchidValue
  simp only [Bool.false_eq_true, ↓reduceIte, hlen]
  by_cases h0 : V.length > 0
  · have hne : V ≠ [] := List.ne_nil_of_length_pos h0
    have : ¬ (V.length > Uint24.MAX) := by omega
    simp only [h0, ↓reduceIte, Nat.lt_irrefl, hd, List.take_length, Uint24.mk, this, except_bind_ok, hne]
    simp [Trie.checkValueLength]
  · have : V = [] := List.eq_nil_of_length_eq_zero (by omega)
    subst this
    simp [Trie.checkValueLength]

theorem orchid_parse (env : Env) (F : UInt8) (p : List Bool)
    (hp : p.length < 2 ^ 16) (LH RH : Option Bytes)
    (hl : ∀ h, LH = some h → h.length = 32) (hr : ∀ h, RH = some h → h.length = 32) (V : Bytes) :
    ∃ M c, M = [2, F] ++
      putShort ((if LH.isSome then 0b01 else 0) ||| (if RH.isSome then 0b10 else 0)) ++
      putShort p.length ++ (if p.length > 0 then TrieKeySlice.encode p else []) ++
      LH.getD [] ++ RH.getD [] ++ V ∧ M.drop c = V ∧
      fromMessageOrchid env M = orchidTail env M (F &&& 0x02 == 2) p (optRef LH) (optRef RH) c := by
  generalize hE : (if p.length > 0 then TrieKeySlice.encode p else []) = E
  have hElen : E.length = PathEncoder.calculateEncodedLength p.length := by
    rw [← hE]; split
    · simp [TrieKeySlice.encode, PathEncoder.encode_length, PathEncoder.calculateEncodedLength_eq]
    · next h => have : p.length = 0 := by omega
                simp [this, PathEncoder.calculateEncodedLength]
  have hsp : ∀ rest : Bytes, E.length > 0 → PathEncoder.decode ((E ++ rest).take E.length) p.length = .ok p := by
    intro rest h
    rw [List.take_left' rfl, ← hE]
    have : p.length > 0 := by
      rw [← hE] at h; split at h
      · assumption
      · simp at h
    simp only [this, ↓reduceIte, TrieKeySlice.encode]; exact PathEncoder.decode_encode p
  have hp0 : E.length = 0 → p = [] := by
    intro h; rw [← hE] at h; split at h
    · simp [TrieKeySlice.encode, PathEncoder.encode_length] at h; omega
    · next h' => exact List.eq_nil_of_length_eq_zero (by omega)
  generalize hbits : ((if LH.isSome then 0b01 else 0) ||| (if RH.isSome then 0b10 else 0) : Nat) = bits
  have hb : bits < 2 ^ 16 := by rw [← hbits]; cases LH <;> cases RH <;> simp
  generalize hR : LH.getD [] ++ (RH.getD [] ++ V) = REST
  have hM : [2, F] ++ putShort bits ++ putShort p.length ++ E ++ LH.getD [] ++ RH.getD [] ++ V =
      2 :: F :: (bits / 256 % 256).toUInt8 :: (bits % 256).toUInt8 :: (p.length / 256 % 256).toUInt8 ::
        (p.length % 256).toUInt8 :: (E ++ REST) := by rw [← hR]; simp [putShort]
  refine ⟨_, 6 + E.length + (LH.getD []).length + (RH.getD []).length, rfl, ?_⟩
  rw [hM]
  generalize hMM : (2 :: F :: (bits / 256 % 256).toUInt8 :: (bits % 256).toUInt8 :: (p.length / 256 % 256).toUInt8 ::
        (p.length % 256).toUInt8 :: (E ++ REST) : Bytes) = M
  have f0 : idx M 0 = .ok 2 := by rw [← hMM]; rfl
  have f1 : idx M 1 = .ok F := by rw [← hMM]; rfl
  have f2 : Uint16.decodeToInt M 2 = .ok bits := by
    rw [← hMM]; simp [Uint16.decodeToInt, idx, toUInt8_toNat]; omega
  have f4 : Uint16.decodeToInt M 4 = .ok p.length := by
    rw [← hMM]; simp [Uint16.decodeToInt, idx, toUInt8_toNat]; omega
  have fL : M.length = 6 + E.length + REST.length := by rw [← hMM]; simp; omega
  have fD : M.drop 6 = E ++ REST := by rw [← hMM]; rfl
  have hpath : orchidPath M p.length = .ok (p, 6 + E.length) := by
    unfold orchidPath
    rw [← hElen]
    by_cases h0 : E.length > 0
    · have : ¬ (M.length - 6 < E.length) := by omega
      simp only [h0, this, ↓reduceIte, except_bind_ok, TrieKeySlice.fromEncoded, fD]
      rw [show E.length - (M.length - 6) = 0 by omega, List.replicate_zero, List.append_nil, hsp REST h0]
      rfl
    · simp only [h0, ↓reduceIte, hp0 (by omega), show E.length = 0 by omega]; rfl
  have fD' : ∀ k, M.drop (6 + k) = (E ++ REST).drop k := by
    intro k; rw [← List.drop_drop, fD]
  subst hR hbits
  refine ⟨by rw [Nat.add_assoc, Nat.add_assoc, fD', ← List.drop_drop, List.drop_left, ← List.drop_drop,
    List.drop_left, List.drop_left], ?_⟩
  unfold fromMessageOrchid
  simp only [f0, f1, f2, f4, except_bind_ok, show (2 : UInt8).toNat = ARITY from rfl, ne_eq,
    not_true_eq_false, ↓reduceIte, hpath, MESSAGE_HEADER_LENGTH, ← hElen]
  unfold orchidTail
  cases LH <;> cases RH <;> simp only [Option.isSome_none, Option.isSome_some, Bool.false_eq_true, ↓reduceIte,
    Option.getD_none, Option.getD_some, List.nil_append, List.length_nil, Nat.add_zero] at fL fD' ⊢
  · rw [show (decide ¬((0 : Nat) ||| 0) &&& 1 = 0) = false by decide, oc_none, except_bind_ok,
      show (decide ¬((0 : Nat) ||| 0) &&& 2 = 0) = false by decide, oc_none, except_bind_ok]
    rfl
  · rename_i h
    have hh := hr h rfl
    rw [show (decide ¬((0 : Nat) ||| 2) &&& 1 = 0) = false by decide, oc_none, except_bind_ok,
      show (decide ¬((0 : Nat) ||| 2) &&& 2 = 0) = true by decide,
      oc_some M h V hh _ _ (by rw [fD', List.drop_left]), except_bind_ok, hh]
    rfl
  · rename_i h
    have hh := hl h rfl
    rw [show (decide ¬((1 : Nat) ||| 0) &&& 1 = 0) = true by decide,
      oc_some M h V hh _ _ (by rw [fD', List.drop_left]), except_bind_ok,
      show (decide ¬((1 : Nat) ||| 0) &&& 2 = 0) = false by decide, oc_none, except_bind_ok, hh]
    rfl
  · rename_i h1 h2
    have hh1 := hl h1 rfl
    have hh2 := hr h2 rfl
    rw [show (decide ¬((1 : Nat) ||| 2) &&& 1 = 0) = true by decide,
      oc_some M h1 (h2 ++ V) hh1 _ _ (by rw [fD', List.drop_left]), except_bind_ok,
      show (decide ¬((1 : Nat) ||| 2) &&& 2 = 0) = true by decide,
      oc_some M h2 V hh2 _ _ (by rw [Nat.add_assoc, fD', ← List.drop_drop, List.drop_left, List.drop_left' hh1]),
      except_bind_ok, hh1, hh2]
    rfl

theorem ov_long (env : Env) (M h rest v : Bytes) (p : List Bool) (l r : NodeRef Trie) (cur : Nat)
    (hd : M.drop cur = h ++ rest) (hh : h.length = 32) (hdb : env.db h = some v) (hv : v.length ≤ Uint24.MAX) :
    orchidTail env M true p l r cur = .ok ⟨p, some v, l, r, v.length, some h, none⟩ := by
  have hlen : M.length - cur = h.length + rest.length := by rw [← List.length_drop, hd, List.length_append]
  have h1 : ¬ (M.length - cur < 32) := by omega
  have h2 : ¬ (v.length > Uint24.MAX) := by omega
  unfold orchidTail orchidValue
  have h3 : ¬ (Uint24.MAX < v.length) := by omega
  simp [readHash, h1, hd, List.take_left' hh, hdb, Uint24.mk, h3, Trie.checkValueLength]

theorem orchidRef_eq (H : Bytes → Bytes) (s : Bool) (r : NodeRef Trie) :
    NodeRef.orchidRef H s r = optRef (NodeRef.orchidHashS H s r) := by
  unfold NodeRef.orchidRef optRef; rfl

theorem orchidHash_len (H : Bytes → Bytes) (hH : ∀ x, (H x).length = 32) (s : Bool) (r : NodeRef Trie) :
    ∀ h, NodeRef.orchidHashS H s r = some h → h.length = 32 := by
  intro h e
  cases r with
  | node c => simp only [NodeRef.orchidHashS, Option.some.injEq] at e; subst e; split <;> simp [hH]
  | _ => simp [NodeRef.orchidHashS] at e

/-- **Orchid parser on Orchid encodings** (TRIE-SER-07), short values: for a resident node with
`valueLength ≤ 32` and a shared path of fewer than `2^16` bits, `fromMessageOrchid(toMessageOrchid(s))`
has the node's shared path, value and value length, references the children by their Orchid
hashes, and leaves the `valueHash` and `childrenSize` caches unset. -/
theorem Trie.fromMessageOrchid_orchidS (env : Env) (hH : ∀ x, (env.H x).length = 32) (s : Bool) (t : Trie)
    (hres : t.Resident) (hp : t.sharedPath.length < 2 ^ 16) (hshort : t.valueLength ≤ 32) :
    Trie.fromMessageOrchid env (t.orchidS env.H s) =
      .ok ⟨t.sharedPath, t.value, NodeRef.orchidRef env.H s t.left, NodeRef.orchidRef env.H s t.right,
        t.valueLength, none, none⟩ := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
  obtain ⟨hv, _, _⟩ := hres
  simp only at hp hshort ⊢
  have hnl : ¬ vl > 32 := by omega
  obtain ⟨M, c, hM, hd, e⟩ := orchid_parse env ((if s then 1 else 0) ||| (if decide (vl > 32) then 2 else 0)) p hp
    (NodeRef.orchidHashS env.H s l) (NodeRef.orchidHashS env.H s r) (orchidHash_len _ hH s l)
    (orchidHash_len _ hH s r) (if vl > 0 then v.getD [] else [])
  have hF : (((if s then 1 else 0) ||| (if decide (vl > 32) then 2 else 0) : UInt8) &&& 0x02 == 2) = false := by
    cases s <;> simp [hnl] <;> decide
  have hmsg : Trie.orchidS env.H s ⟨p, v, l, r, vl, vh, cs⟩ = M := by
    rw [hM]; simp only [Trie.orchidS, hnl, ↓reduceIte]
  rw [hmsg, e, hF, orchidRef_eq, orchidRef_eq]
  rcases hv with ⟨rfl, rfl⟩ | ⟨x, rfl, hx, hpos, _⟩
  · rw [ov_short env M [] p _ _ c (by simpa using hd) (by simp)]; rfl
  · have hne : x ≠ [] := List.ne_nil_of_length_pos (by omega)
    simp only [hpos, ↓reduceIte, Option.getD_some] at hd
    rw [ov_short env M x p _ _ c hd (by omega)]
    simp [hne, hx]

/-- TRIE-SER-07, long values: `fromMessageOrchid` reads the value from the store by the 32-byte
`valueHash` and ignores any bytes after it. -/
theorem Trie.fromMessageOrchid_orchidS_long (env : Env) (hH : ∀ x, (env.H x).length = 32) (s : Bool) (t : Trie)
    (hres : t.Resident) (hc : t.CacheOK env.H) (hp : t.sharedPath.length < 2 ^ 16) (hlong : t.valueLength > 32)
    (hdb : env.db (env.H (t.value.getD [])) = some (t.value.getD [])) (rest : Bytes) :
    Trie.fromMessageOrchid env (t.orchidS env.H s ++ rest) =
      .ok ⟨t.sharedPath, t.value, NodeRef.orchidRef env.H s t.left, NodeRef.orchidRef env.H s t.right,
        t.valueLength, some (env.H (t.value.getD [])), none⟩ := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
  obtain ⟨hv, _, _⟩ := hres
  simp only at hp hlong hdb ⊢
  obtain ⟨x, rfl, hx, hpos, hmax⟩ : ∃ x, v = some x ∧ x.length = vl ∧ 0 < vl ∧ vl ≤ Uint24.MAX := by
    rcases hv with ⟨_, h⟩ | h
    · omega
    · exact h
  have hvh := hc.2.1 x rfl
  clear hc
  obtain ⟨M, c, hM, hd, e⟩ := orchid_parse env ((if s then 1 else 0) ||| (if decide (vl > 32) then 2 else 0)) p hp
    (NodeRef.orchidHashS env.H s l) (NodeRef.orchidHashS env.H s r) (orchidHash_len _ hH s l)
    (orchidHash_len _ hH s r) (env.H x ++ rest)
  have hF : (((if s then 1 else 0) ||| (if decide (vl > 32) then 2 else 0) : UInt8) &&& 0x02 == 2) = true := by
    cases s <;> simp [hlong] <;> decide
  have hmsg : Trie.orchidS env.H s ⟨p, some x, l, r, vl, vh, cs⟩ ++ rest = M := by
    rw [hM]; rcases hvh with rfl | rfl <;>
      simp only [Trie.orchidS, hlong, hpos, ↓reduceIte, Option.getD_some, List.append_assoc]
  rw [hmsg, e, hF, orchidRef_eq, orchidRef_eq]
  simp only [Option.getD_some] at hdb
  rw [ov_long env M (env.H x) rest x p _ _ c hd (hH x) hdb (by omega), hx]; rfl

/-- TRIE-SER-07 sanity case: `02 02 0000 0000 <32-byte hash> ff` parses (the trailing `ff` is
ignored) to a node holding the store's value for that hash. -/
theorem orchid_trailing (env : Env) (h v : Bytes) (hh : h.length = 32) (hdb : env.db h = some v)
    (hv : v.length ≤ Uint24.MAX) :
    Trie.fromMessageOrchid env ([0x02, 0x02, 0x00, 0x00, 0x00, 0x00] ++ h ++ [0xff]) =
      .ok ⟨[], some v, .empty, .empty, v.length, some h, none⟩ := by
  obtain ⟨M, c, hM, hd, e⟩ := orchid_parse env 0x02 [] (by decide) none none (by simp) (by simp) (h ++ [0xff])
  have hmsg : [0x02, 0x02, 0x00, 0x00, 0x00, 0x00] ++ h ++ [0xff] = M := by rw [hM]; rfl
  rw [hmsg, e, show ((0x02 : UInt8) &&& 0x02 == 2) = true by decide, ov_long env M h [0xff] v [] _ _ c hd hh hdb hv]
  rfl
end RskjTrie
