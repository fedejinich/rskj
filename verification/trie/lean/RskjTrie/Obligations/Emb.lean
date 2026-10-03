import RskjTrie.Obligations.Examples
import RskjTrie.Obligations.Node
/-! # Obligations TRIE-EMB-* (embedded nodes) and TRIE-VAL-* (long values) -/
namespace RskjTrie.Obligations
open RskjTrie Trie

set_option linter.unusedSimpArgs false

/-- TRIE-EMB-01: a child is marked embedded only if it is terminal (writer). -/
theorem trie_emb_01 (env : Env) (t : Trie) (hres : t.Resident) (hc : t.CacheOK env.H) :
    ∃ f rest, t.toMessage env = .ok (f :: rest) ∧
      (bitSet f 0b00000010 = true → ∃ c, t.left = .node c ∧ c.isTerminal = true) ∧
      (bitSet f 0b00000001 = true → ∃ c, t.right = .node c ∧ c.isTerminal = true) := by
  obtain ⟨f, rest, h, _, _, _, _, _, h5, h6⟩ := Trie.toMessage_flags env t hres hc
  refine ⟨f, rest, h, fun hb => ?_, fun hb => ?_⟩
  · rw [h5] at hb
    cases hl : t.left with
    | node c => rw [hl] at hb; simp [NodeRef.encS] at hb; exact ⟨c, rfl, hb.1⟩
    | _ => rw [hl] at hb; simp [NodeRef.encS] at hb
  · rw [h6] at hb
    cases hr : t.right with
    | node c => rw [hr] at hb; simp [NodeRef.encS] at hb; exact ⟨c, rfl, hb.1⟩
    | _ => rw [hr] at hb; simp [NodeRef.encS] at hb

/-- TRIE-EMB-02 (Java): the embedded bytes are parsed recursively with no terminal check — any
node `c` that parses on its own (terminal or not, up to 255 bytes) is accepted as an embedded left
child. -/
theorem trie_emb_02 (env : Env) (F : Nat) (c : Bytes) (node : Trie) (hc : c.length < 256)
    (hp : fromMessageRskip107 env F c = .ok node) :
    fromMessageRskip107 env (F + 1) ([0x4a, c.length.toUInt8] ++ c ++ [0x00]) =
      .ok ⟨[], none, NodeRef.ofNode (some node), .empty, 0, none, some 0⟩ := by
  simp only [fromMessageRskip107, StateT.run', List.cons_append, List.nil_append, List.append_assoc]
  rw [BB.bind_ok _ _ _ _ _ (BB.get_cons _ _)]
  simp only [show bitSet 0x4a 0b00100000 = false by decide, show bitSet 0x4a 0b00010000 = false by decide,
    show bitSet 0x4a 0b00001000 = true by decide, show bitSet 0x4a 0b00000100 = false by decide,
    show bitSet 0x4a 0b00000010 = true by decide, show bitSet 0x4a 0b00000001 = false by decide]
  rw [BB.bind_ok _ _ _ _ _ (show SharedPathSerializer.deserialize false _ = _ from rfl)]
  have hdec : Uint8.decode [c.length.toUInt8] 0 = .ok c.length := by
    simp only [Uint8.decode, idx, List.getElem?_cons_zero, except_bind_ok, toUInt8_toNat,
      Nat.mod_eq_of_lt hc, Uint8.mk, show ¬ (c.length > 0xff) by omega, ↓reduceIte]
  have hl : readChild (fromMessageRskip107 env F) true true (c.length.toUInt8 :: (c ++ [0x00])) =
      .ok (NodeRef.ofNode (some node), [0x00]) := by
    simp only [readChild, ↓reduceIte]
    rw [BB.bind_ok _ _ _ _ _ (BB.getN_one_cons _ _)]
    rw [BB.bind_ok _ _ _ _ _ (by rw [hdec]; exact BB.lift_ok _ _)]
    rw [BB.bind_ok _ _ _ _ _ (BB.getN_append _ _ _ rfl)]
    rw [BB.bind_ok _ _ _ _ _ (by rw [hp]; exact BB.lift_ok _ _)]
    rfl
  rw [BB.bind_ok _ _ _ _ _ hl]
  rw [BB.bind_ok _ _ _ _ _ (show readChild _ false false _ = _ from rfl)]
  simp only [Bool.true_or, ↓reduceIte]
  rw [BB.bind_ok _ _ _ _ _ (show readVarInt [0x00] = .ok (0, []) from readVarInt_encode 0 (by decide) [])]
  rfl

/-- TRIE-EMB-02 (canonical-parse reading) does not hold: the reproducer's non-terminal embedded
child is accepted, and re-encoded by hash. -/
theorem trie_emb_02_rskip_counterexample (env : Env) :
    reencode env ([0x4a, 0x22, 0x48] ++ List.replicate 32 0x11 ++ [0x00, 0x00]) =
      .ok ([0x48] ++ env.H ([0x48] ++ List.replicate 32 0x11 ++ [0x00]) ++ [0x00]) :=
  reencode_eq _ _ _ ⟨_, rfl, rfl, by enc_eval; rfl⟩

/-- TRIE-EMB-03 (Java): a child is embedded iff it is terminal and its message has at most 44
bytes. -/
theorem trie_emb_03 (env : Env) (c : Trie) (hres : c.Resident) (hc : c.CacheOK env.H) :
    ∃ m, c.toMessage env = .ok m ∧
      (NodeRef.node c).isEmbeddable env FUEL = .ok (c.isTerminal && decide (m.length ≤ 44)) := by
  refine ⟨_, by rw [Trie.toMessage, (Trie.encOK env c hres hc FUEL).2.1], ?_⟩
  rw [NodeRef.isEmbeddable, (Trie.encOK env c hres hc FUEL).2.2.1]

/-- TRIE-EMB-03 (RSKIP107: embedded encodings are at most 40 bytes) does not hold: the
reproducer's 43-byte leaves are embedded (flags `0x4f`, size byte `0x2b`). -/
theorem trie_emb_03_rskip_counterexample (env : Env) :
    ∃ t, runOps env Trie.empty exB = .ok t ∧
      t.toMessage env = .ok ([0x4f, 0x2b] ++ leafB ++ [0x2b] ++ leafB ++ [0x56]) ∧
      leafB.length = 43 ∧ ¬ (leafB.length ≤ 40) := by
  obtain ⟨t, h1, _, h2, h3⟩ := exB_msg env
  exact ⟨t, h1, h2, h3, by rw [h3]; decide⟩

/-- TRIE-EMB-04: in a reachable trie, a child is serialized embedded iff it is terminal and its
message has at most 44 bytes — a function of the child's content (independent of its caches). -/
theorem trie_emb_04 (H : Bytes → Bytes) (c : Trie) :
    (NodeRef.encS H (.node c)).2.2 = (c.isTerminal && decide ((Trie.encS H c).1.length ≤ 44)) ∧
    (NodeRef.encS H (.node c.erase)).2.2 = (NodeRef.encS H (.node c)).2.2 := by
  refine ⟨rfl, ?_⟩
  have := NodeRef.encS_erase H (.node c)
  rw [show NodeRef.erase (.node c) = .node c.erase from rfl] at this
  rw [this]

/-- TRIE-EMB-05: an embedded child is `Uint8(len) ++ message`, and the parser consumes exactly
that many bytes. -/
theorem trie_emb_05 (env : Env) (hH : ∀ x, (env.H x).length = 32) (c : Trie) (hres : c.Resident)
    (hne : c.isEmptyTrie = false) (hp : c.PathsOK) (hemb : (NodeRef.encS env.H (.node c)).2.2 = true)
    (F : Nat) (hF : (NodeRef.encS env.H (.node c)).1.length < F) (rest : Bytes) :
    (NodeRef.encS env.H (.node c)).1 = Uint8.encode (Trie.encS env.H c).1.length ++ (Trie.encS env.H c).1 ∧
    readChild (fromMessageRskip107 env F) true true ((NodeRef.encS env.H (.node c)).1 ++ rest) =
      .ok ((NodeRef.node c).reparse env.H, rest) := by
  refine ⟨by simp only [NodeRef.encS] at hemb ⊢; simp [hemb], ?_⟩
  have := NodeRef.readChild_encS env hH (.node c) ⟨hres, hne⟩ hp F hF rest
  rw [hemb] at this; exact this

/-- TRIE-VAL-01: `hasLongValue() == (valueLength > 32)`. -/
theorem trie_val_01 (t : Trie) : t.hasLongValue = decide (t.valueLength > 32) := rfl

/-- TRIE-VAL-02: a long value is written as its 32-byte hash followed by the `uint24` length, and
nothing else. -/
theorem trie_val_02 (H : Bytes → Bytes) (p v l r vl vh cs) (hl : vl > 32) :
    ∃ pre, (Trie.encS H ⟨p, v, l, r, vl, vh, cs⟩).1 = pre ++ (H (v.getD []) ++ Uint24.encode vl) :=
  ⟨_, by simp only [Trie.encS, hl, decide_true, ↓reduceIte]; rfl⟩

/-- TRIE-VAL-03: in a trie with consistent caches (every reachable trie), `getValueHash()` of a
node with a value is `H(value)`. -/
theorem trie_val_03 (env : Env) (t : Trie) (hc : t.CacheOK env.H) (hres : t.Resident) (x : Bytes)
    (hx : t.value = some x) : t.getValueHash env = .ok (some (env.H x)) := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
  simp only at hx; subst hx
  unfold getValueHash
  rcases hc.2.1 x rfl with h | h
  · subst h
    have : vl > 0 := by
      rcases hres.1 with ⟨h0, _⟩ | ⟨y, _, _, hp, _⟩
      · simp at h0
      · exact hp
    simp [this, getValue]
  · subst h; rfl

/-- TRIE-VAL-04 (Java): `Uint24.encode(n) = [n >> 16, n >> 8, n]` (big-endian). -/
theorem trie_val_04 (n : Nat) : Uint24.encode n = [(n / 65536).toUInt8, (n / 256).toUInt8, n.toUInt8] := rfl

/-- TRIE-VAL-04: the little-endian reading does not hold: 33 is `000021`, not `210000`. -/
theorem trie_val_04_rskip_counterexample : Uint24.encode 33 = [0x00, 0x00, 0x21] ∧
    Uint24.encode 33 ≠ [0x21, 0x00, 0x00] := by decide

/-- TRIE-VAL-05 (Java): the parser takes any number of remaining bytes as an inline value, and
accepts any `valueLength` after a value hash. -/
theorem trie_val_05 (env : Env) :
    (∀ s : Bytes, s.length ≤ Uint24.MAX → readValue env false s =
      .ok ((if s = [] then (none, 0, none) else (some s, s.length, some (env.H s))), [])) ∧
    (∀ (h : Bytes) (a b c : UInt8) (rest : Bytes), h.length = 32 →
      readValue env true (h ++ ([a, b, c] ++ rest)) =
        .ok ((none, c.toNat + b.toNat * 256 + a.toNat * 65536, some h), rest)) := by
  refine ⟨(trie_node_09 env).2, fun h a b c rest hl => ?_⟩
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

set_option maxRecDepth 20000 in
/-- TRIE-VAL-05 (canonical-parse reading) does not hold: `40‖33x00` is accepted and re-encoded as
a long value; `60‖32xaa‖000001` parses to a node with `valueLength` 1 (not long); `60‖32xaa‖000000`
parses to the empty node (`40`). -/
theorem trie_val_05_rskip_counterexample (env : Env) :
    reencode env (0x40 :: List.replicate 33 0x00) =
      .ok ([0x60] ++ env.H (List.replicate 33 0x00) ++ [0x00, 0x00, 0x21]) ∧
    fromMessage env ([0x60] ++ List.replicate 32 0xaa ++ [0x00, 0x00, 0x01]) =
      .ok ⟨[], none, .empty, .empty, 1, some (List.replicate 32 0xaa), some 0⟩ ∧
    reencode env ([0x60] ++ List.replicate 32 0xaa ++ [0x00, 0x00, 0x00]) = .ok [0x40] :=
  ⟨reencode_eq _ _ _ ⟨_, rfl, rfl, by enc_eval⟩, rfl, reencode_eq _ _ _ ⟨⟨[], none, .empty, .empty, 0, some (List.replicate 32 0xaa), some 0⟩, rfl, rfl, rfl⟩⟩

/-- TRIE-VAL-06 (Java): a lazy long value is whatever the store holds under `valueHash`, provided
its length is `valueLength` (Trie.java:1013-1037: only the length is checked). -/
theorem trie_val_06 (env : Env) (t : Trie) (h v : Bytes) (hv : t.value = none) (hl : t.valueLength > 0)
    (hh : t.valueHash = some h) (hdb : env.db h = some v) (hlen : v.length = t.valueLength) :
    t.getValue env = .ok (some v) := by
  unfold getValue; simp [hv, hl, hh, TrieStoreImpl.retrieveValue, hdb, hlen]

/-- TRIE-VAL-06 does not hold: parse `60 ‖ H(v) ‖ 000021` from a store holding `v' ≠ v` (same
length) under `H(v)`: `getValue()` returns `v'`, whose hash differs from `valueHash` (for `H`
injective on `{v, v'}`). -/
theorem trie_val_06_rskip_counterexample (env : Env) (v v' : Bytes) (_hl : v.length = 33) (hl' : v'.length = 33)
    (hne : v ≠ v') (hH : (env.H v).length = 32) (hinj : env.H v' = env.H v → v' = v)
    (hdb : env.db (env.H v) = some v') :
    ∃ t, fromMessage env ([0x60] ++ env.H v ++ [0x00, 0x00, 0x21]) = .ok t ∧
      t.getValue env = .ok (some v') ∧ t.valueHash = some (env.H v) ∧ env.H v' ≠ env.H v := by
  have hp : fromMessage env ([0x60] ++ env.H v ++ [0x00, 0x00, 0x21]) =
      .ok ⟨[], none, .empty, .empty, 33, some (env.H v), some 0⟩ := by
    have hv := (trie_val_05 env).2 (env.H v) 0 0 0x21 [] hH
    simp only [List.append_nil] at hv
    simp only [fromMessage, idx, List.cons_append, List.nil_append, List.getElem?_cons_zero, except_bind_ok,
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
    rw [BB.bind_ok _ _ _ _ _ hv, BB.bind_ok _ _ _ _ _ (BB.remaining_eq _)]
    simp [Trie.checkValueLength]
    rfl
  refine ⟨_, hp, ?_, rfl, fun e => hne (hinj e).symm⟩
  exact trie_val_06 env _ (env.H v) v' rfl (by show 0 < 33; omega) rfl hdb (by rw [hl'])

/-- TRIE-VAL-07: `put(k, v)` with `|v| > 0xFFFFFF` throws, on every trie; every value stored in a
reachable trie has length at most `0xFFFFFF`. -/
theorem trie_val_07 (env : Env) :
    (∀ t key x, x.length > Uint24.MAX → ∃ e, Trie.put env t key (some x) = .error e) ∧
    (∀ t, Reachable env t → ValueOK t.value t.valueLength) :=
  ⟨fun t key x hx => Trie.put_too_long env t key x hx, fun t ht => by
    obtain ⟨p, v, l, r, vl, vh, cs⟩ := t; exact ht.WF.1.1⟩

end RskjTrie.Obligations
