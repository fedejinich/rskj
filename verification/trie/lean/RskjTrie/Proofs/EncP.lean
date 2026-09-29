import RskjTrie.Proofs.Resident
/-!
# The encoder on "parsed-shape" tries

`Trie.encP` is a pure, structurally recursive encoder for tries whose every node has a set
`childrenSize` and whose values are either present or lazy long values with a stored hash — the
shape `fromMessageRskip107` produces, and the shape of tries built by `put`. Children may be
resident or hash references. `internalToMessage` computes `encP` on such tries without reading
the store. This lets concrete decode/re-encode examples be evaluated by `rfl`.
-/
namespace RskjTrie
open Trie

mutual
def Trie.encP (H : Bytes → Bytes) : Trie → Bytes
  | ⟨p, v, l, r, vl, vh, cs⟩ =>
    let lr := NodeRef.encP H l
    let rr := NodeRef.encP H r
    let term := l.isEmpty && r.isEmpty
    let hasLong := decide (vl > 32)
    let flags := Trie.mkFlags hasLong (SharedPathSerializer.isPresent p) (!l.isEmpty) (!r.isEmpty)
      lr.2 rr.2
    let vb := if hasLong then (match vh with | some h => h | none => H (v.getD [])) ++ Uint24.encode vl
      else if vl > 0 then v.getD [] else []
    flags :: SharedPathSerializer.serializeInto p ++ lr.1 ++ rr.1 ++
      (if !term then VarInt.encode (cs.getD 0) else []) ++ vb
/-- `(serializeInto, isEmbeddable)` of a reference. -/
def NodeRef.encP (H : Bytes → Bytes) : NodeRef Trie → Bytes × Bool
  | .empty => ([], false)
  | .hash h => (h, false)
  | .node c =>
    let m := Trie.encP H c
    let emb := c.isTerminal && decide (m.length ≤ 44)
    ((if emb then Uint8.encode m.length ++ m else if c.isEmptyTrie then H [0x80] else H m), emb)
end

mutual
/-- Parsed shape: `childrenSize` set everywhere, values present or lazy-long with a hash. -/
def Trie.POK : Trie → Prop
  | ⟨_, v, l, r, vl, vh, cs⟩ =>
    cs.isSome ∧ ((v = none ∧ vl = 0) ∨ (∃ x, v = some x ∧ x.length = vl ∧ vl ≤ 0xff) ∨
      (v = none ∧ vl > 32 ∧ vh.isSome)) ∧ NodeRef.POK l ∧ NodeRef.POK r
def NodeRef.POK : NodeRef Trie → Prop
  | .node t => Trie.POK t
  | _ => True
end

mutual
theorem Trie.encP_ok (env : Env) : ∀ (t : Trie), t.POK → ∀ fuel,
    t.internalToMessage env fuel = .ok (t.encP env.H) ∧
    t.isEmbeddable env fuel = .ok (t.isTerminal && decide ((t.encP env.H).length ≤ 44)) ∧
    t.getHashF env fuel = .ok (if t.isEmptyTrie then env.H [0x80] else env.H (t.encP env.H))
  | ⟨p, v, l, r, vl, vh, cs⟩, ⟨hcs, hv, hl, hr⟩, fuel => by
    obtain ⟨il1, il2⟩ := NodeRef.encP_ok env l hl fuel
    obtain ⟨ir1, ir2⟩ := NodeRef.encP_ok env r hr fuel
    obtain ⟨c, rfl⟩ := Option.isSome_iff_exists.mp hcs
    have hmsg : Trie.internalToMessage env fuel ⟨p, v, l, r, vl, vh, some c⟩ =
        .ok (Trie.encP env.H ⟨p, v, l, r, vl, vh, some c⟩) := by
      rw [Trie.internalToMessage]
      simp only [Trie.getChildrenSize, il1, il2, ir1, ir2, except_bind_ok]
      rcases hv with ⟨rfl, rfl⟩ | ⟨x, rfl, hx, hle⟩ | ⟨rfl, hlong, hvh⟩
      · simp [valueBytes, hasLongValue, Trie.encP, isTerminal]
      · by_cases hlong : vl > 32
        · cases vh with
          | none => simp [valueBytes, hasLongValue, hlong, getValueHash, getValue, Trie.encP, isTerminal,
              show vl > 0 by omega]
          | some h => simp [valueBytes, hasLongValue, hlong, getValueHash, Trie.encP, isTerminal]
        · by_cases hpos : vl > 0
          · simp [valueBytes, hasLongValue, hlong, hpos, getValue, Trie.encP, isTerminal]
          · simp [valueBytes, hasLongValue, hlong, hpos, Trie.encP, isTerminal]
      · obtain ⟨h, rfl⟩ := Option.isSome_iff_exists.mp hvh
        simp [valueBytes, hasLongValue, hlong, getValueHash, Trie.encP, isTerminal]
    refine ⟨hmsg, ?_, ?_⟩
    · rw [Trie.isEmbeddable]
      split
      · next h => simp only [hmsg, h, MAX_EMBEDDED_NODE_SIZE_IN_BYTES, except_bind_ok, Bool.true_and]; rfl
      · next h => simp [h]
    · rw [Trie.getHashF]
      split
      · simp [emptyHash]
      · simp [hmsg]
theorem NodeRef.encP_ok (env : Env) : ∀ (r : NodeRef Trie), r.POK → ∀ fuel,
    r.serializeInto env fuel = .ok (r.encP env.H).1 ∧ r.isEmbeddable env fuel = .ok (r.encP env.H).2
  | .empty, _, fuel => by simp [NodeRef.serializeInto, NodeRef.isEmbeddable, NodeRef.encP]
  | .hash h, _, fuel => by simp [NodeRef.serializeInto, NodeRef.isEmbeddable, NodeRef.encP]
  | .node c, hc, fuel => by
    obtain ⟨i1, i2, i3⟩ := Trie.encP_ok env c hc fuel
    refine ⟨?_, ?_⟩
    · rw [NodeRef.serializeInto]
      simp only [i2, except_bind_ok, NodeRef.encP]
      split
      · next hemb =>
        have hle : (Trie.encP env.H c).length ≤ 44 := by simp at hemb; exact hemb.2
        simp [i1, Uint8.mk, show ¬ ((Trie.encP env.H c).length > 255) by omega]
      · next hemb => simp only [i3]; try (split <;> rfl)
    · rw [NodeRef.isEmbeddable]; simp only [i2, NodeRef.encP]
end

mutual
/-- Decidable version of `POK`, for concrete examples (`by rfl`). -/
def Trie.pokB : Trie → Bool
  | ⟨_, v, l, r, vl, vh, cs⟩ =>
    cs.isSome && (match v with
      | none => vl == 0 || (decide (vl > 32) && vh.isSome)
      | some x => x.length == vl && decide (vl ≤ 0xff)) && NodeRef.pokB l && NodeRef.pokB r
def NodeRef.pokB : NodeRef Trie → Bool
  | .node t => Trie.pokB t
  | _ => true
end

mutual
theorem Trie.POK_of_pokB : ∀ t : Trie, t.pokB = true → t.POK
  | ⟨p, v, l, r, vl, vh, cs⟩, h => by
    simp only [Trie.pokB, Bool.and_eq_true] at h
    obtain ⟨⟨⟨h1, h2⟩, h3⟩, h4⟩ := h
    refine ⟨h1, ?_, NodeRef.POK_of_pokB l h3, NodeRef.POK_of_pokB r h4⟩
    cases v with
    | none =>
      simp only [Bool.or_eq_true, beq_iff_eq, Bool.and_eq_true, decide_eq_true_eq] at h2
      rcases h2 with h2 | ⟨h2, h2'⟩
      · exact Or.inl ⟨rfl, h2⟩
      · exact Or.inr (Or.inr ⟨rfl, h2, h2'⟩)
    | some x =>
      simp only [Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq] at h2
      exact Or.inr (Or.inl ⟨x, rfl, h2.1, h2.2⟩)
theorem NodeRef.POK_of_pokB : ∀ r : NodeRef Trie, r.pokB = true → r.POK
  | .node t, h => Trie.POK_of_pokB t h
  | .empty, _ => trivial
  | .hash _, _ => trivial
end

/-- `toMessage` of a parsed-shape trie. -/
theorem Trie.toMessage_encP (env : Env) (t : Trie) (h : t.POK) : t.toMessage env = .ok (t.encP env.H) :=
  (Trie.encP_ok env t h FUEL).1

/-- `getHash` of a parsed-shape trie. -/
theorem Trie.getHash_encP (env : Env) (t : Trie) (h : t.POK) :
    t.getHash env = .ok (if t.isEmptyTrie then env.H [0x80] else env.H (t.encP env.H)) :=
  (Trie.encP_ok env t h FUEL).2.2

end RskjTrie
