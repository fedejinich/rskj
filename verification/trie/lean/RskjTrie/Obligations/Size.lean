import RskjTrie.Obligations.Examples
/-! # Obligations TRIE-SIZE-* (childrenSize, RSKIP107 `treeSize`) -/
namespace RskjTrie.Obligations
open RskjTrie Trie TrieKeySlice

set_option linter.unusedSimpArgs false

/-- The size a child reference contributes (`NodeReference.referenceSize()`): its node's
childrenSize, plus its long value's length, plus its message length (Java `long` arithmetic). -/
def refSize (H : Bytes → Bytes) (c : Trie) : Nat :=
  wrap64 (((c.encS H).2 : Int) + (if c.valueLength > 32 then c.valueLength else 0) + (c.encS H).1.length)

/-- TRIE-SIZE-01: for every node with consistent caches (every node of a reachable trie),
`getChildrenSize()` is `0` for a terminal node and otherwise the sum over its children `c` of
`c.getChildrenSize() + (c.hasLongValue() ? c.getValueLength() : 0) + c.getMessageLength()`
(embedded children included; the node itself excluded). -/
theorem trie_size_01 (env : Env) (t : Trie) (hres : t.Resident) (hc : t.CacheOK env.H) (fuel : Nat) :
    t.getChildrenSize env fuel = .ok (kidsSize env.H t.left t.right) ∧
    kidsSize env.H t.left t.right = (if t.isTerminal then 0 else
      wrap64 (((match t.left with | .node c => refSize env.H c | _ => 0 : Nat) : Int) +
        (match t.right with | .node c => refSize env.H c | _ => 0 : Nat))) ∧
    (∀ c, (t.left = .node c ∨ t.right = .node c) →
      c.getChildrenSize env fuel = .ok (c.encS env.H).2 ∧ c.getMessageLength env = .ok (c.encS env.H).1.length) := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
  refine ⟨by rw [(Trie.encOK env _ hres hc fuel).1, encS_snd], ?_, fun c hcase => ?_⟩
  · unfold kidsSize isTerminal
    cases l <;> cases r <;> simp [NodeRef.encS, refSize, NodeRef.isEmpty]
  · have ⟨hr, hcc⟩ : c.Resident ∧ c.CacheOK env.H := by
      obtain ⟨_, hl, hr⟩ := hres
      obtain ⟨_, _, cl, cr⟩ := hc
      rcases hcase with e | e <;> simp only at e <;> subst e
      · exact ⟨hl.1, cl⟩
      · exact ⟨hr.1, cr⟩
    have := Trie.encOK env c hr hcc
    refine ⟨(this fuel).1, ?_⟩
    rw [getMessageLength, toMessage, (this FUEL).2.1]; rfl

/-- TRIE-SIZE-01 sanity run: the root of two 43-byte embedded leaves (`exB`) has
`childrenSize = 86` (the last byte `56` of its message, a VarInt). -/
theorem trie_size_01_sanity (env : Env) : ∃ t, runOps env Trie.empty exB = .ok t ∧
    t.toMessage env = .ok ([0x4f, 0x2b] ++ leafB ++ [0x2b] ++ leafB ++ [0x56]) ∧ (0x56 : UInt8).toNat = 86 := by
  obtain ⟨t, h1, _, h2, _⟩ := exB_msg env
  exact ⟨t, h1, h2, rfl⟩

/-- TRIE-SIZE-02: the carried `childrenSize` of every node with consistent caches (every node
of a reachable trie: `put`, `split`, delete coalescing all preserve `CacheOK`) is unset or equal to
what `getChildrenSize()` computes from scratch on a copy with `childrenSize = null`. -/
theorem trie_size_02 (env : Env) (t : Trie) (hres : t.Resident) (hc : t.CacheOK env.H) (fuel : Nat) :
    ∃ c, ({ t with childrenSize := none } : Trie).getChildrenSize env fuel = .ok c ∧
      (t.childrenSize = none ∨ t.childrenSize = some c) ∧ t.getChildrenSize env fuel = .ok c := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
  have hc' : Trie.CacheOK env.H ⟨p, v, l, r, vl, vh, none⟩ := ⟨Or.inl rfl, hc.2⟩
  have h0 := (Trie.encOK env ⟨p, v, l, r, vl, vh, none⟩ hres hc' fuel).1
  have h1 := (Trie.encOK env _ hres hc fuel).1
  refine ⟨_, h0, ?_, ?_⟩
  · rcases hc.1 with h | h
    · exact Or.inl h
    · right; rw [h, encS_snd, encS_snd]
  · rw [h1, encS_snd, encS_snd]

/-- TRIE-SIZE-02 for reachable tries (root). -/
theorem trie_size_02_reachable (env : Env) (t : Trie) (ht : Reachable env t) (fuel : Nat) :
    ∃ c, ({ t with childrenSize := none } : Trie).getChildrenSize env fuel = .ok c ∧
      (t.childrenSize = none ∨ t.childrenSize = some c) ∧ t.getChildrenSize env fuel = .ok c :=
  trie_size_02 env t ht.WF.1 ht.WF.2.1 fuel

/-- TRIE-SIZE-03 (Java): a cached `childrenSize` — e.g. the `treeSize` read by the parser — is
returned as is by `getChildrenSize()`, without being checked. -/
theorem trie_size_03 (env : Env) (t : Trie) (c : Nat) (h : t.childrenSize = some c) (fuel : Nat) :
    t.getChildrenSize env fuel = .ok c := by
  unfold getChildrenSize; rw [h]

/-- The node `fromMessage(5a070004500600020501)` builds. -/
def size03 (H : Bytes → Bytes) : Trie :=
  ⟨List.replicate 8 false, some [0x01], .node ⟨List.replicate 7 false, some [0x02], .empty, .empty, 1,
    some (H [0x02]), some 0⟩, .empty, 1, some (H [0x01]), some 5⟩

/-- TRIE-SIZE-03 (canonical-parse reading) does not hold: `5a070004500600020501` (`treeSize = 5`)
is accepted; `getChildrenSize()` is `5` (and `toMessage()` returns the input), while the value
computed from its children is `4` (the canonical message `5a070004500600020401` of TRIE-SIZE's
`exA` trie). -/
theorem trie_size_03_rskip_counterexample (env : Env) :
    fromMessage env [0x5a, 0x07, 0x00, 0x04, 0x50, 0x06, 0x00, 0x02, 0x05, 0x01] = .ok (size03 env.H) ∧
    (size03 env.H).getChildrenSize env FUEL = .ok 5 ∧
    ({ size03 env.H with childrenSize := none } : Trie).getChildrenSize env FUEL = .ok 4 ∧
    reencode env [0x5a, 0x07, 0x00, 0x04, 0x50, 0x06, 0x00, 0x02, 0x05, 0x01] =
      .ok [0x5a, 0x07, 0x00, 0x04, 0x50, 0x06, 0x00, 0x02, 0x05, 0x01] := by
  have hres : Trie.Resident ({ size03 env.H with childrenSize := none } : Trie) := by
    simp [size03, Trie.Resident, NodeRef.Resident, ValueOK, isEmptyTrie, isEmptyTrieOf, Uint24.MAX]
  have hc : Trie.CacheOK env.H ({ size03 env.H with childrenSize := none } : Trie) := by
    simp [size03, Trie.CacheOK, NodeRef.CacheOK, Trie.encS, NodeRef.isEmpty]
  refine ⟨rfl, trie_size_03 env _ 5 rfl FUEL, ?_, reencode_eq _ _ _ ⟨_, rfl, rfl, by enc_eval⟩⟩
  rw [(Trie.encOK env _ hres hc FUEL).1]
  simp [Trie.encS, size03, NodeRef.encS, isTerminal, NodeRef.isEmpty, isEmptyTrie, isEmptyTrieOf, wrap64,
    SharedPathSerializer.serializeInto, SharedPathSerializer.isPresent]
  decide

end RskjTrie.Obligations
