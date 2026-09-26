import RskjTrie.Proofs.Canonical
/-!
# Proofs: node hash and root hash
-/
namespace RskjTrie
open Trie

/-- **Hash of a node**: `getHash` of a non-empty trie is `H (toMessage t)` (whatever the trie and
the store: this is the definition of `Trie.getHash`, Trie.java:362-376). -/
theorem Trie.getHash_nonempty (env : Env) (t : Trie) (h : t.isEmptyTrie = false) :
    t.getHash env = env.H <$> t.toMessage env := by
  unfold Trie.getHash Trie.toMessage
  rw [Trie.getHashF]; simp only [h, Bool.false_eq_true, ↓reduceIte]
  cases t.internalToMessage env FUEL <;> rfl

/-- **Hash of the empty trie**: `keccak256(RLP.encodeElement(new byte[0])) = H [0x80]`
(Trie.java:1088-1090), independently of the (empty) node's message `[0x40]`. -/
theorem Trie.getHash_empty (env : Env) (t : Trie) (h : t.isEmptyTrie = true) :
    t.getHash env = .ok (env.H [0x80]) := by
  unfold Trie.getHash; rw [Trie.getHashF]; simp [h, Trie.emptyHash]

/-- The empty trie `new Trie(store)` serializes to the single flags byte `0x40`, but its hash is
`H [0x80]`, not `H [0x40]`. -/
theorem Trie.empty_message_and_hash (env : Env) :
    Trie.empty.toMessage env = .ok [0x40] ∧ Trie.empty.getHash env = .ok (env.H [0x80]) := by
  refine ⟨?_, Trie.getHash_empty env _ rfl⟩
  have := (Trie.encOK env Trie.empty (Trie.WF_empty env.H).1 (Trie.WF_empty env.H).2.1 FUEL).2.1
  rw [Trie.toMessage, this]; rfl

/-- For a well-formed trie the hash is the pure `hashS`. -/
theorem Trie.getHash_WF (env : Env) (t : Trie) (h : t.WF env.H) : t.getHash env = .ok (t.hashS env.H) :=
  (Trie.encOK env t h.1 h.2.1 FUEL).2.2.2.1

end RskjTrie
