import RskjTrie.Proofs.Store
/-!
# Proofs: exactly what `TrieStoreImpl.save` writes
-/
namespace RskjTrie

-- simp sets shared across `<;>` branches (each argument is used in some branch)
set_option linter.unusedSimpArgs false
open Trie

mutual
/-- The `(key, value)` writes of `save(t, isRootNode)` in order (TrieStoreImpl.java:92-145): the
loaded children's writes, the long value under its hash, then — unless the node is embeddable
and not the root — the node's message under its hash. -/
def Trie.saveWrites (H : Bytes → Bytes) : Trie → Bool → List (Bytes × Bytes)
  | ⟨p, v, l, r, vl, vh, cs⟩, isRoot =>
    NodeRef.saveWrites H l ++ NodeRef.saveWrites H r ++
    (if vl > 32 then [(H (v.getD []), v.getD [])] else []) ++
    (if (Trie.isTerminal ⟨p, v, l, r, vl, vh, cs⟩ &&
          decide ((Trie.encS H ⟨p, v, l, r, vl, vh, cs⟩).1.length ≤ 44)) && !isRoot then []
     else [(Trie.hashS H ⟨p, v, l, r, vl, vh, cs⟩, (Trie.encS H ⟨p, v, l, r, vl, vh, cs⟩).1)])
def NodeRef.saveWrites (H : Bytes → Bytes) : NodeRef Trie → List (Bytes × Bytes)
  | .node c => Trie.saveWrites H c false
  | _ => []
end

def applyWrites (db : DB) (ws : List (Bytes × Bytes)) : DB := ws.foldl (fun d kv => d.put kv.1 kv.2) db

theorem applyWrites_append (db : DB) (a b : List (Bytes × Bytes)) :
    applyWrites db (a ++ b) = applyWrites (applyWrites db a) b := by simp [applyWrites, List.foldl_append]

mutual
/-- **What `save` writes**: for a resident trie with consistent caches, `save` succeeds on any
store and applies exactly `saveWrites` (no store reads are needed). -/
theorem Trie.saveRec_writes (H : Bytes → Bytes) : ∀ (t : Trie) (db : DB) (isRoot : Bool),
    t.Resident → t.CacheOK H →
    TrieStoreImpl.saveRec H db t isRoot = .ok (applyWrites db (t.saveWrites H isRoot))
  | ⟨p, v, l, r, vl, vh, cs⟩, db, isRoot, hres, hc => by
    rw [TrieStoreImpl.saveRec]
    simp only [Trie.getHash, ((Trie.encOK ⟨H, db⟩ _ hres hc) FUEL).2.2.2.1, except_bind_ok]
    rw [NodeRef.saveRef_writes H l db hres.2.1 hc.2.2.1, except_bind_ok]
    rw [NodeRef.saveRef_writes H r _ hres.2.2 hc.2.2.2, except_bind_ok]
    simp only [Trie.saveWrites, applyWrites_append]
    generalize applyWrites (applyWrites db (NodeRef.saveWrites H l)) (NodeRef.saveWrites H r) = db2
    unfold TrieStoreImpl.saveTail
    by_cases hlong : vl > 32
    · obtain ⟨x, rfl, hx⟩ : ∃ x, v = some x ∧ x.length = vl := by
        rcases hres.1 with ⟨_, h0⟩ | ⟨x, h1, h2, _, _⟩
        · omega
        · exact ⟨x, h1, h2⟩
      have hgvh : getValueHash ⟨H, db2⟩ ⟨p, some x, l, r, vl, vh, cs⟩ = .ok (some (H x)) := by
        unfold getValueHash
        rcases hc.2.1 x rfl with h | h
        · subst h; simp [getValue]; omega
        · subst h; rfl
      simp only [hasLongValue, hlong, decide_true, ↓reduceIte, hgvh, getValue, except_bind_ok,
        except_pure, Option.getD_some]
      have eo := (Trie.encOK ⟨H, db2.put (H x) x⟩ _ hres hc FUEL)
      simp only [eo.2.2.1, except_bind_ok, Trie.toMessage, eo.2.1]
      split
      · next h => simp [h, applyWrites]
      · next h => simp [h, applyWrites]
    · simp only [hasLongValue, hlong, decide_false, Bool.false_eq_true, ↓reduceIte, except_pure,
        except_bind_ok, List.nil_append]
      have eo := (Trie.encOK ⟨H, db2⟩ _ hres hc FUEL)
      simp only [eo.2.2.1, except_bind_ok, Trie.toMessage, eo.2.1]
      split
      · next h => simp [h, applyWrites]
      · next h => simp [h, applyWrites]
theorem NodeRef.saveRef_writes (H : Bytes → Bytes) : ∀ (R : NodeRef Trie) (db : DB),
    R.Resident → R.CacheOK H → TrieStoreImpl.saveRef H db R = .ok (applyWrites db (NodeRef.saveWrites H R))
  | .empty, db, _, _ => rfl
  | .hash _, _, h, _ => absurd h (by simp [NodeRef.Resident])
  | .node c, db, ⟨hres, _⟩, hc => by
    rw [TrieStoreImpl.saveRef]
    exact Trie.saveRec_writes H c db false hres hc
end

/-- **Embedded nodes are not stored separately** (TRIE-STORE-03): `save(t)` of a resident trie
writes (1) the root, always; (2) every non-embeddable descendant, under its hash; (3) the long
values; and nothing for an embeddable non-root node (`saveWrites` has no entry for it). -/
theorem Trie.save_writes (H : Bytes → Bytes) (db : DB) (t : Trie) (hres : t.Resident) (hc : t.CacheOK H) :
    TrieStoreImpl.save H db t = .ok (applyWrites db (t.saveWrites H true)) :=
  Trie.saveRec_writes H t db true hres hc

mutual
/-- Every entry `save` writes for a non-empty node or a long value is content-addressed:
`key = H value` (TRIE-STORE-02 for non-empty nodes). -/
theorem Trie.saveWrites_content_addressed (H : Bytes → Bytes) : ∀ (t : Trie) (isRoot : Bool),
    t.Resident → t.isEmptyTrie = false → ∀ kv ∈ t.saveWrites H isRoot, kv.1 = H kv.2
  | ⟨p, v, l, r, vl, vh, cs⟩, isRoot, hres, hne => by
    intro kv hkv
    simp only [Trie.saveWrites, List.mem_append] at hkv
    rcases hkv with ((h | h) | h) | h
    · exact NodeRef.saveWrites_content_addressed H l hres.2.1 kv h
    · exact NodeRef.saveWrites_content_addressed H r hres.2.2 kv h
    · split at h
      · simp at h; subst h; rfl
      · simp at h
    · split at h
      · simp at h
      · simp only [List.mem_singleton] at h; subst h
        exact Trie.hashS_nonempty _ _ hne
theorem NodeRef.saveWrites_content_addressed (H : Bytes → Bytes) : ∀ (R : NodeRef Trie), R.Resident →
    ∀ kv ∈ NodeRef.saveWrites H R, kv.1 = H kv.2
  | .empty, _ => by simp [NodeRef.saveWrites]
  | .hash _, h => absurd h (by simp [NodeRef.Resident])
  | .node c, ⟨hres, hne⟩ => Trie.saveWrites_content_addressed H c false hres hne
end

end RskjTrie
