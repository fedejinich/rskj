import RskjTrie.Obligations.Examples
/-! # Obligations TRIE-NODE-* (node format) -/
namespace RskjTrie.Obligations
open RskjTrie Trie

set_option linter.unusedSimpArgs false

/-- TRIE-NODE-01: every message `toMessage` produces (any trie, any store) has version bits `01`. -/
theorem trie_node_01 (env : Env) (t : Trie) (m : Bytes) (h : t.toMessage env = .ok m) :
    ∃ f rest, m = f :: rest ∧ f &&& 0xC0 = 0x40 := by
  obtain ⟨a, b, c, d, e, f, rest, hm, hv⟩ := Trie.internalToMessage_head env FUEL t m h
  exact ⟨_, rest, hm, hv⟩

/-- TRIE-NODE-02 (Java): `fromMessage` dispatches on `message[0] == 0x02` only, and the RSKIP107
parser ignores the version bits (6-7) of the flags byte. -/
theorem trie_node_02 (env : Env) :
    (∀ b rest, fromMessage env (b :: rest) =
      if b.toNat = 2 then fromMessageOrchid env (b :: rest)
      else fromMessageRskip107 env (rest.length + 1 + 1) (b :: rest)) ∧
    (∀ F f g rest, f &&& 0x3F = g &&& 0x3F →
      fromMessageRskip107 env F (f :: rest) = fromMessageRskip107 env F (g :: rest)) :=
  ⟨Trie.fromMessage_dispatch env, fun F f g rest h => Trie.fromMessageRskip107_version_blind env F f g rest h⟩

/-- TRIE-NODE-02 (versions `10`, `11` and non-Orchid `00` rejected) does not hold: `c001`,
`8001`, `00` and `0101` are accepted as RSKIP107 nodes. -/
theorem trie_node_02_rskip_counterexample (env : Env) :
    reencode env [0xc0, 0x01] = .ok [0x40, 0x01] ∧ reencode env [0x80, 0x01] = .ok [0x40, 0x01] ∧
    reencode env [0x00] = .ok [0x40] ∧ reencode env [0x01, 0x01] = .ok [0x40, 0x01] :=
  ⟨reencode_eq _ _ _ ⟨_, rfl, rfl, rfl⟩, reencode_eq _ _ _ ⟨_, rfl, rfl, rfl⟩,
   reencode_eq _ _ _ ⟨_, rfl, rfl, rfl⟩, reencode_eq _ _ _ ⟨_, rfl, rfl, rfl⟩⟩

/-- TRIE-NODE-03: flag bit 5 is set iff `hasLongValue()`; the parser takes the long-value branch
iff bit 5 is set (and the re-parsed node has the same `valueLength`, its value lazy iff > 32). -/
theorem trie_node_03 (env : Env) (hH : ∀ x, (env.H x).length = 32) (t : Trie) (hres : t.Resident)
    (hc : t.CacheOK env.H) (hp : t.PathsOK) :
    (∃ f rest, t.toMessage env = .ok (f :: rest) ∧ bitSet f 0b00100000 = t.hasLongValue) ∧
    (∃ t', t.toMessage env >>= fromMessage env = .ok t' ∧ t'.valueLength = t.valueLength ∧
      (t.valueLength > 32 → t'.value = none ∧ t'.valueHash.isSome)) := by
  obtain ⟨f, rest, h, _, h1, _⟩ := Trie.toMessage_flags env t hres hc
  obtain ⟨m1, m2⟩ := Trie.fromMessage_toMessage env hH t hres hc hp
  refine ⟨⟨f, rest, h, h1⟩, t.reparse env.H, by rw [m1]; exact m2, ?_, fun hl => ?_⟩
  · obtain ⟨p, v, l, r, vl, vh, cs⟩ := t; rfl
  · obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
    simp only at hl
    simp [Trie.reparse, hl, show vl > 0 by omega]

/-- TRIE-NODE-04 (Java): the four low flag bits are left present `0x08`, right present `0x04`,
left embedded `0x02`, right embedded `0x01`. -/
theorem trie_node_04 (env : Env) (t : Trie) (hres : t.Resident) (hc : t.CacheOK env.H) :
    ∃ f rest, t.toMessage env = .ok (f :: rest) ∧
      bitSet f 0b00001000 = !t.left.isEmpty ∧ bitSet f 0b00000100 = !t.right.isEmpty ∧
      bitSet f 0b00000010 = (NodeRef.encS env.H t.left).2.2 ∧
      bitSet f 0b00000001 = (NodeRef.encS env.H t.right).2.2 := by
  obtain ⟨f, rest, h, _, _, _, h3, h4, h5, h6⟩ := Trie.toMessage_flags env t hres hc
  exact ⟨f, rest, h, h3, h4, h5, h6⟩

/-- TRIE-NODE-04: neither RSKIP reading holds: for `{00: 01, 0000: 02}` Java writes flags `0x5a`
where both readings give `0x55`. -/
theorem trie_node_04_rskip_counterexample (env : Env) :
    ∃ t, runOps env Trie.empty exA = .ok t ∧
      t.toMessage env = .ok [0x5a, 0x07, 0x00, 0x04, 0x50, 0x06, 0x00, 0x02, 0x04, 0x01] ∧
      (0x5a : UInt8) ≠ 0x55 := by
  obtain ⟨t, h1, _, h2⟩ := exA_msg env
  exact ⟨t, h1, h2, by decide⟩

/-- TRIE-NODE-05: `toMessage = flags ++ [lsharedCompressed ++ encodedSharedPath] ++ [left
reference] ++ [right reference] ++ rest`, and the parser reads them in that order (round trip,
`Trie.fromMessage_toMessage`). -/
theorem trie_node_05 (env : Env) (t : Trie) (hres : t.Resident) (hc : t.CacheOK env.H) :
    ∃ f rest, t.toMessage env = .ok (f :: (SharedPathSerializer.serializeInto t.sharedPath ++
      ((NodeRef.encS env.H t.left).1 ++ ((NodeRef.encS env.H t.right).1 ++ rest)))) := by
  rw [Trie.toMessage, (Trie.encOK env t hres hc FUEL).2.1]
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
  refine ⟨?f, ?rest, ?_⟩
  show Except.ok (Trie.encS env.H ⟨p, v, l, r, vl, vh, cs⟩).1 = _
  rw [Trie.encS]
  simp only [List.cons_append, List.append_assoc]
  rfl

/-- TRIE-NODE-06: a present non-embedded child is written as its 32-byte hash, an embedded child as
`uint8 length ++ child.toMessage()`. -/
theorem trie_node_06 (env : Env) (hH : ∀ x, (env.H x).length = 32) (c : Trie) (hres : c.Resident)
    (hne : c.isEmptyTrie = false) (hc : c.CacheOK env.H) :
    ∃ m, c.toMessage env = .ok m ∧
      (NodeRef.node c).serializeInto env FUEL = .ok
        (if c.isTerminal && decide (m.length ≤ 44) then Uint8.encode m.length ++ m else env.H m) ∧
      (env.H m).length = 32 := by
  refine ⟨_, by rw [Trie.toMessage, (Trie.encOK env c hres hc FUEL).2.1], ?_, hH _⟩
  rw [((NodeRef.encOK env (.node c) ⟨hres, hne⟩ hc) FUEL).1]
  simp [NodeRef.encS, hne]

/-- TRIE-NODE-07 (Java): `childrenSize` is written iff the node has at least one child. -/
theorem trie_node_07 (H : Bytes → Bytes) (p v l r vl vh cs) :
    ∃ pre vb, (Trie.encS H ⟨p, v, l, r, vl, vh, cs⟩).1 =
      pre ++ (if !(l.isEmpty && r.isEmpty) then VarInt.encode (kidsSize H l r) else []) ++ vb := by
  exact ⟨_, _, by simp only [Trie.encS, kidsSize]; rfl⟩

/-- TRIE-NODE-07: the literal reading (treeSize iff no children) does not hold: in the reproducer
trie the 43-byte leaves carry no treeSize and the root carries childrenSize 86 (`0x56`). -/
theorem trie_node_07_rskip_counterexample (env : Env) :
    ∃ t, runOps env Trie.empty exB = .ok t ∧
      t.toMessage env = .ok ([0x4f, 0x2b] ++ leafB ++ [0x2b] ++ leafB ++ [0x56]) ∧
      leafB = [0x50, 0xff, 0x3f] ++ List.replicate 8 0x00 ++ v32 := by
  obtain ⟨t, h1, _, h2, _⟩ := exB_msg env
  exact ⟨t, h1, h2, rfl⟩

/-- TRIE-NODE-08 (Java): for a node with children and a long value, `childrenSize` precedes
`valueHash ++ valueLength`. -/
theorem trie_node_08 (H : Bytes → Bytes) (p v l r vl vh cs) (hl : vl > 32) (hch : !(l.isEmpty && r.isEmpty)) :
    ∃ pre, (Trie.encS H ⟨p, v, l, r, vl, vh, cs⟩).1 =
      pre ++ VarInt.encode (kidsSize H l r) ++ (H (v.getD []) ++ Uint24.encode vl) := by
  exact ⟨_, by simp only [Trie.encS, kidsSize, hch, ↓reduceIte, hl, decide_true]; rfl⟩

/-- TRIE-NODE-08: the literal order (treeSize after valueLength) does not hold: for
`{01: 33xab, 0101: 02}` the root is `7a 07 01 04 50060202 04 <H(value)> 000021`. -/
theorem trie_node_08_rskip_counterexample (env : Env) :
    ∃ t, runOps env Trie.empty exC = .ok t ∧
      t.toMessage env = .ok ([0x7a, 0x07, 0x01, 0x04, 0x50, 0x06, 0x02, 0x02, 0x04] ++ env.H v33 ++
        [0x00, 0x00, 0x21]) := by
  obtain ⟨t, h1, _, h2⟩ := exC_msg env
  exact ⟨t, h1, h2⟩

/-- TRIE-NODE-09: without a long value the message ends with exactly the value bytes (none if
there is no value), and the parser takes all remaining bytes as the value. -/
theorem trie_node_09 (env : Env) :
    (∀ (p : List Bool) v l r vl vh cs, ¬ vl > 32 →
      ∃ pre, (Trie.encS env.H ⟨p, v, l, r, vl, vh, cs⟩).1 = pre ++ (if vl > 0 then v.getD [] else [])) ∧
    (∀ s : Bytes, s.length ≤ Uint24.MAX →
      readValue env false s = .ok ((if s = [] then (none, 0, none) else (some s, s.length, some (env.H s))), [])) := by
  refine ⟨fun p v l r vl vh cs hl => ?_, fun s hs => ?_⟩
  · exact ⟨_, by simp only [Trie.encS, hl, decide_false, Bool.false_eq_true, ↓reduceIte]; rfl⟩
  unfold readValue
  simp only [Bool.false_eq_true, ↓reduceIte]
  rw [BB.bind_ok _ _ _ _ _ (BB.remaining_eq _)]
  cases s with
  | nil => simp
  | cons b r =>
    simp only [List.length_cons, ne_eq, Nat.add_one_ne_zero, not_false_eq_true, ↓reduceIte, reduceCtorEq]
    rw [BB.bind_ok _ _ _ _ _ (BB.getN_self (b :: r) (r.length + 1) rfl)]
    have : Uint24.mk (r.length + 1) = .ok (r.length + 1) := by
      have h' : ¬ (r.length + 1 > Uint24.MAX) := by simp at hs; omega
      simp only [Uint24.mk, h', ↓reduceIte]
    rw [BB.bind_ok _ _ _ _ _ (by rw [this]; exact BB.lift_ok _ _)]
    rfl

/-- TRIE-NODE-10: bytes left after the long-value fields make the parser throw: for every
32-byte hash, 3-byte length and non-empty trailer, `60 ‖ hash ‖ length ‖ trailer` is rejected
(the reproducer `60 <32 bytes> 000021 00`). -/
theorem trie_node_10 (env : Env) (h : Bytes) (hl : h.length = 32) (a b c : UInt8) (x : UInt8) (extra : Bytes) :
    ∃ e, fromMessage env (0x60 :: (h ++ ([a, b, c] ++ (x :: extra)))) = .error e := by
  simp only [fromMessage, idx, List.getElem?_cons_zero, except_bind_ok,
    show (0x60 : UInt8).toNat = 96 from rfl, ARITY, show (96 : Nat) ≠ 2 by decide, ↓reduceIte]
  simp only [fromMessageRskip107, StateT.run']
  rw [BB.bind_ok _ _ _ _ _ (BB.get_cons _ _)]
  simp only [show bitSet 0x60 0b00100000 = true by decide, show bitSet 0x60 0b00010000 = false by decide,
    show bitSet 0x60 0b00001000 = false by decide, show bitSet 0x60 0b00000100 = false by decide,
    show bitSet 0x60 0b00000010 = false by decide, show bitSet 0x60 0b00000001 = false by decide]
  rw [BB.bind_ok _ _ _ _ _ (show SharedPathSerializer.deserialize false _ = _ from rfl)]
  rw [BB.bind_ok _ _ _ _ _ (show readChild _ false false _ = _ from rfl)]
  rw [BB.bind_ok _ _ _ _ _ (show readChild _ false false _ = _ from rfl)]
  simp only [Bool.or_self, Bool.false_eq_true, ↓reduceIte]
  rw [BB.bind_ok _ _ _ _ _ (BB.pure_run _ _)]
  have hv : readValue env true (h ++ ([a, b, c] ++ (x :: extra))) =
      .ok ((none, c.toNat + b.toNat * 256 + a.toNat * 65536, some h), x :: extra) := by
    unfold readValue; simp only [↓reduceIte]
    rw [BB.bind_ok _ _ _ _ _ (BB.getN_append h _ 32 hl)]
    rw [BB.bind_ok _ _ _ _ _ (BB.getN_append [a, b, c] _ 3 rfl)]
    have hd : Uint24.decode [a, b, c] 0 = .ok (c.toNat + b.toNat * 256 + a.toNat * 65536) := by
      simp only [Uint24.decode, idx, List.getElem?_cons_zero, List.getElem?_cons_succ, except_bind_ok]
      have := a.toNat_lt; have := b.toNat_lt; have := c.toNat_lt
      have h' : ¬ (c.toNat + b.toNat * 256 + a.toNat * 65536 > Uint24.MAX) := by unfold Uint24.MAX; omega
      simp only [Uint24.mk, h', ↓reduceIte]
    rw [BB.bind_ok _ _ _ _ _ (by rw [hd]; exact BB.lift_ok _ _)]
    rfl
  rw [BB.bind_ok _ _ _ _ _ hv, BB.bind_ok _ _ _ _ _ (BB.remaining_eq _)]
  simp only [List.length_cons, gt_iff_lt, Nat.zero_lt_succ, decide_true, ↓reduceIte]
  exact ⟨_, rfl⟩

end RskjTrie.Obligations
