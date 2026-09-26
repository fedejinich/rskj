import RskjTrie.Serialization
import RskjTrie.Proofs.SharedPath
/-!
# Resident tries and a pure specification of the encoder

A trie is *resident* when every node is in memory (no `NodeRef.hash`) and every value is present
(no lazy long value). For such tries the store is never read, and the faithful `Except`/fuel
encoder of `Serialization.lean` computes the pure, structurally recursive `Trie.encS`
(message and from-scratch `childrenSize`) — provided the caches are consistent (`CacheOK`).
-/
namespace RskjTrie
open Trie

/-- Value fields of a resident node: either no value, or a resident non-empty value whose length
is `valueLength` (Java `checkValueLength`), fitting a `Uint24`. -/
def ValueOK (v : Option Bytes) (vl : Nat) : Prop :=
  (v = none ∧ vl = 0) ∨ (∃ x, v = some x ∧ x.length = vl ∧ 0 < vl ∧ vl ≤ Uint24.MAX)

mutual
/-- Every node in memory, every value resident, no empty node referenced. -/
def Trie.Resident : Trie → Prop
  | ⟨_, v, l, r, vl, _, _⟩ => ValueOK v vl ∧ NodeRef.Resident l ∧ NodeRef.Resident r
def NodeRef.Resident : NodeRef Trie → Prop
  | .empty => True
  | .hash _ => False
  | .node t => Trie.Resident t ∧ t.isEmptyTrie = false
end

mutual
/-- Pure encoder of a resident trie: `(toMessage, from-scratch childrenSize)`. -/
def Trie.encS (H : Bytes → Bytes) : Trie → Bytes × Nat
  | ⟨p, v, l, r, vl, _, _⟩ =>
    let lr := NodeRef.encS H l
    let rr := NodeRef.encS H r
    let term := l.isEmpty && r.isEmpty
    let csv := if term then 0 else wrap64 ((lr.2.1 : Int) + rr.2.1)
    let hasLong := decide (vl > 32)
    let flags := Trie.mkFlags hasLong (SharedPathSerializer.isPresent p) (!l.isEmpty) (!r.isEmpty)
      lr.2.2 rr.2.2
    let vb := if hasLong then H (v.getD []) ++ Uint24.encode vl
      else if vl > 0 then v.getD [] else []
    (flags :: SharedPathSerializer.serializeInto p ++ lr.1 ++ rr.1 ++
      (if !term then VarInt.encode csv else []) ++ vb, csv)
/-- Pure `(serializeInto, referenceSize, isEmbeddable)` of a reference. -/
def NodeRef.encS (H : Bytes → Bytes) : NodeRef Trie → Bytes × Nat × Bool
  | .empty => ([], 0, false)
  | .hash h => (h, 0, false)
  | .node c =>
    let e := Trie.encS H c
    let emb := c.isTerminal && decide (e.1.length ≤ 44)
    let ext : Nat := if c.valueLength > 32 then c.valueLength else 0
    ((if emb then Uint8.encode e.1.length ++ e.1 else if c.isEmptyTrie then H [0x80] else H e.1),
      wrap64 ((e.2 : Int) + ext + e.1.length), emb)
end

/-- `encS` ignores the caches. -/
theorem Trie.encS_eq (H : Bytes → Bytes) (p v l r vl vh cs) :
    Trie.encS H ⟨p, v, l, r, vl, vh, cs⟩ = Trie.encS H ⟨p, v, l, r, vl, none, none⟩ := by
  simp only [Trie.encS]

/-- `getHash` of a resident trie. -/
def Trie.hashS (H : Bytes → Bytes) (t : Trie) : Bytes :=
  if t.isEmptyTrie then H [0x80] else H (t.encS H).1

mutual
/-- Caches agree with what they cache: `childrenSize` (if set) is the from-scratch value and
`valueHash` (if set, for a present value) is the hash of the value. -/
def Trie.CacheOK (H : Bytes → Bytes) : Trie → Prop
  | ⟨p, v, l, r, vl, vh, cs⟩ =>
    (cs = none ∨ cs = some (Trie.encS H ⟨p, v, l, r, vl, none, none⟩).2) ∧
    (∀ x, v = some x → vh = none ∨ vh = some (H x)) ∧
    NodeRef.CacheOK H l ∧ NodeRef.CacheOK H r
def NodeRef.CacheOK (H : Bytes → Bytes) : NodeRef Trie → Prop
  | .node t => Trie.CacheOK H t
  | _ => True
end

section
variable (env : Env)

/-- What the faithful encoder computes on a resident, cache-consistent trie. -/
def Trie.EncOK (t : Trie) : Prop :=
  ∀ fuel,
    t.getChildrenSize env fuel = .ok (t.encS env.H).2 ∧
    t.internalToMessage env fuel = .ok (t.encS env.H).1 ∧
    t.isEmbeddable env fuel = .ok (t.isTerminal && decide ((t.encS env.H).1.length ≤ 44)) ∧
    t.getHashF env fuel = .ok (t.hashS env.H) ∧
    t.nodeSize env fuel = .ok (wrap64 (((t.encS env.H).2 : Int) +
      (if t.valueLength > 32 then t.valueLength else 0) + (t.encS env.H).1.length))

def NodeRef.EncOK (r : NodeRef Trie) : Prop :=
  ∀ fuel,
    r.serializeInto env fuel = .ok (r.encS env.H).1 ∧
    r.referenceSize env fuel = .ok (r.encS env.H).2.1 ∧
    r.isEmbeddable env fuel = .ok (r.encS env.H).2.2
end

theorem Trie.getValue_resident (env : Env) (t : Trie) (h : ValueOK t.value t.valueLength) :
    t.getValue env = .ok t.value := by
  unfold getValue
  rcases h with ⟨h1, h2⟩ | ⟨x, h1, _, _, _⟩ <;> simp [*]

mutual
theorem Trie.encOK (env : Env) : ∀ (t : Trie), t.Resident → t.CacheOK env.H → t.EncOK env
  | ⟨p, v, l, r, vl, vh, cs⟩, hres, hc => by
    obtain ⟨hv, hrl, hrr⟩ := hres
    obtain ⟨hcs, hvh, hcl, hcr⟩ := hc
    have il := NodeRef.encOK env l hrl hcl
    have ir := NodeRef.encOK env r hrr hcr
    intro fuel
    obtain ⟨il1, il2, il3⟩ := il fuel
    obtain ⟨ir1, ir2, ir3⟩ := ir fuel
    -- childrenSize
    have hcsz : Trie.getChildrenSize env fuel ⟨p, v, l, r, vl, vh, cs⟩ =
        .ok (Trie.encS env.H ⟨p, v, l, r, vl, vh, cs⟩).2 := by
      rw [Trie.getChildrenSize]
      rcases hcs with h | h
      · simp only [h, Trie.encS, isTerminal]
        split
        · next hterm => simp [hterm]
        · next hterm => simp [hterm, il2, ir2]
      · subst h
        show Except.ok _ = _
        rw [Trie.encS_eq env.H p v l r vl vh]
    -- message
    have hmsg : Trie.internalToMessage env fuel ⟨p, v, l, r, vl, vh, cs⟩ =
        .ok (Trie.encS env.H ⟨p, v, l, r, vl, vh, cs⟩).1 := by
      rw [Trie.internalToMessage]
      simp only [hcsz]
      simp only [il3, ir3, il1, ir1, except_bind_ok]
      rcases hv with ⟨rfl, rfl⟩ | ⟨x, rfl, hx, hpos, hmax⟩
      · simp [valueBytes, hasLongValue, Trie.encS, isTerminal]
      · by_cases hlong : vl > 32
        · have hgvh : getValueHash env ⟨p, some x, l, r, vl, vh, cs⟩ = .ok (some (env.H x)) := by
            unfold getValueHash
            rcases hvh x rfl with h | h
            · simp [h, getValue, hpos]
            · simp [h]
          simp [valueBytes, hasLongValue, hlong, hgvh, Trie.encS, isTerminal]
        · simp [valueBytes, hasLongValue, hlong, hpos, getValue, Trie.encS, isTerminal]
    refine ⟨hcsz, hmsg, ?_, ?_, ?_⟩
    · rw [Trie.isEmbeddable]
      split
      · next h => simp only [hmsg, h, MAX_EMBEDDED_NODE_SIZE_IN_BYTES, except_bind_ok, Bool.true_and]; rfl
      · next h => simp [h]
    · rw [Trie.getHashF]
      unfold Trie.hashS
      split
      · rfl
      · simp [hmsg]
    · rw [Trie.nodeSize]
      simp [hcsz, hmsg, hasLongValue]
theorem NodeRef.encOK (env : Env) : ∀ (r : NodeRef Trie), r.Resident → r.CacheOK env.H → r.EncOK env
  | .empty, _, _ => by
    intro fuel
    simp [NodeRef.serializeInto, NodeRef.referenceSize, NodeRef.isEmbeddable, NodeRef.encS]
  | .hash _, h, _ => absurd h (by simp [NodeRef.Resident])
  | .node c, ⟨hres, hne⟩, hc => by
    have ic := Trie.encOK env c hres hc
    intro fuel
    obtain ⟨i1, i2, i3, i4, i5⟩ := ic fuel
    refine ⟨?_, ?_, ?_⟩
    · rw [NodeRef.serializeInto]
      simp only [i3, except_bind_ok, NodeRef.encS]
      split
      · next h =>
        have hle : (Trie.encS env.H c).1.length ≤ 44 := by simp at h; exact h.2
        simp [i2, Uint8.mk, show ¬ ((Trie.encS env.H c).1.length > 255) by omega]
      · next h =>
        simp only [i4, Trie.hashS]
        try (split <;> rfl)
    · rw [NodeRef.referenceSize]; simp [i5, NodeRef.encS]
    · rw [NodeRef.isEmbeddable]; simp [i3, NodeRef.encS]
end

end RskjTrie
