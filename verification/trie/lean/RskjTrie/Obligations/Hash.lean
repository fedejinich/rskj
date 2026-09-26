import RskjTrie.Obligations.Ops
import RskjTrie.Operational
import RskjTrie.Proofs.BridgePut
import RskjTrie.Keccak
/-! # Obligations TRIE-HASH-* (node hashes) -/
namespace RskjTrie.Obligations
open RskjTrie Trie TrieKeySlice

set_option linter.unusedSimpArgs false

/-- TRIE-HASH-01: `getHash() = H(toMessage())` for every non-empty node (any trie, any store). -/
theorem trie_hash_01 (env : Env) (t : Trie) (h : t.isEmptyTrie = false) :
    t.getHash env = env.H <$> t.toMessage env :=
  Trie.getHash_nonempty env t h

def keccak80 : Bytes := [0x56, 0xe8, 0x1f, 0x17, 0x1b, 0xcc, 0x55, 0xa6, 0xff, 0x83, 0x45, 0xe6, 0x92, 0xc0,
  0xf8, 0x6e, 0x5b, 0x48, 0xe0, 0x1b, 0x99, 0x6c, 0xad, 0xc0, 0x01, 0x62, 0x2f, 0xb5, 0xe3, 0x63, 0xb4, 0x21]
def keccak40 : Bytes := [0xe7, 0x24, 0xd4, 0x06, 0x19, 0x44, 0x1c, 0xed, 0x66, 0xa2, 0x71, 0xe5, 0x96, 0x27,
  0xb7, 0xbc, 0xd3, 0x9c, 0x77, 0x44, 0x7a, 0x43, 0x15, 0x56, 0x1b, 0x4d, 0x21, 0xe7, 0xb7, 0xc9, 0x32, 0x1c]

theorem keccak_80 : Keccak.keccak256 [0x80] = keccak80 := by decide +kernel
theorem keccak_40 : Keccak.keccak256 [0x40] = keccak40 := by decide +kernel

/-- TRIE-HASH-02 (Java): `new Trie().toMessage() = 40` and `new Trie().getHash() = H(80)`; with
Keccak-256 these are `56e81f…b421` and (for comparison) `keccak256(40) = e724d4…321c`. -/
theorem trie_hash_02 (env : Env) :
    Trie.empty.toMessage env = .ok [0x40] ∧ Trie.empty.getHash env = .ok (env.H [0x80]) ∧
    (env.H = Keccak.keccak256 → Trie.empty.getHash env = .ok keccak80 ∧ env.H [0x40] = keccak40) := by
  obtain ⟨h1, h2⟩ := Trie.empty_message_and_hash env
  refine ⟨h1, h2, fun hk => ⟨by rw [h2, hk, keccak_80], by rw [hk, keccak_40]⟩⟩

/-- TRIE-HASH-02: the reading "the root hash is `keccak256(toMessage())`" does not hold for the
empty trie. -/
theorem trie_hash_02_rskip_counterexample (env : Env) (hk : env.H = Keccak.keccak256) :
    ∃ m h, Trie.empty.toMessage env = .ok m ∧ Trie.empty.getHash env = .ok h ∧ h ≠ Keccak.keccak256 m := by
  obtain ⟨h1, h2, h3⟩ := trie_hash_02 env
  refine ⟨_, _, h1, (h3 hk).1, ?_⟩
  rw [keccak_40]; decide

theorem pathsOK_of_reachable (env : Env) (t : Trie) (ht : Reachable env t)
    (hk : ∀ k, t.get env k ≠ .ok none → k.length < 2 ^ 28) : t.PathsOK := by
  apply Trie.WF_PathsOK env.H t ht.WF
  intro q hq
  obtain ⟨k, rfl⟩ := ht.keyOnly q hq
  have := hk k (by rw [Trie.get_eq_contents env _ ht.WF.1]; intro e; simp only [Except.ok.injEq] at e; exact hq e)
  rw [fromKey_length]; omega

/-- TRIE-HASH-03: assuming `H` is injective and yields 32 bytes, reachable tries (with keys shorter
than `2^28` bytes) with equal `getHash()` have the same key → value map. -/
theorem trie_hash_03 (env : Env) (hH : ∀ x, (env.H x).length = 32) (hinj : ∀ x y, env.H x = env.H y → x = y)
    (t1 t2 : Trie) (h1 : Reachable env t1) (h2 : Reachable env t2)
    (k1 : ∀ k, t1.get env k ≠ .ok none → k.length < 2 ^ 28) (k2 : ∀ k, t2.get env k ≠ .ok none → k.length < 2 ^ 28)
    (heq : t1.getHash env = t2.getHash env) : ∀ k, t1.get env k = t2.get env k := by
  have hc := Trie.hash_binds_map env hH t1 t2 h1.WF h2.WF (pathsOK_of_reachable env t1 h1 k1)
    (pathsOK_of_reachable env t2 h2 k2) (t1.vals env.H ++ t2.vals env.H ++ [[0x80]])
    (fun a _ b _ e => hinj a b e) (fun x hx => by simp [hx]) (fun x hx => by simp [hx]) (by simp) heq
  intro k
  rw [Trie.get_eq_contents env _ h1.WF.1, Trie.get_eq_contents env _ h2.WF.1, hc]

/-- TRIE-HASH-04 (Java): the embedding decision for a child depends on whether it was loaded —
an unloaded reference (`lazyNode == null`) is never embeddable, a loaded one is embeddable iff its
node is (NodeReference.java:141-148). For a store written by `TrieStoreImpl.save` this cannot
change the hash (operational layer, `Proofs/BridgePut.lean`): `retrieve(hash)` of a saved
well-formed trie `t` yields an object represented by `t`; every `get` (which loads and caches
children) leaves it represented; and `getHash()` of every represented object is `t`'s hash. -/
theorem trie_hash_04 (H : Bytes → Bytes) (hH : ∀ x, (H x).length = 32) :
    (∀ env f h, Op.ORef.isEmbeddable env (f + 1) (.hash h) = .ok (false, .hash h)) ∧
    (∀ env f (c : Op.OTrie) lh, Op.ORef.isEmbeddable env (f + 1) (.node c lh) =
      (do let (e, c) ← Op.OTrie.isEmbeddable env f c; pure (e, .node c lh))) ∧
    (∀ (db : DB) (t : Trie), t.WF H → t.PathsOK → t.isEmptyTrie = false → InjOn H (t.vals H) →
      ∃ db' o, TrieStoreImpl.save H db t = .ok db' ∧ Op.retrieve ⟨H, db'⟩ (t.hashS H) = .ok (some o) ∧
        Op.OTrie.Rep ⟨H, db'⟩ o t ∧
        (∀ o1 key v o2, Op.OTrie.Rep ⟨H, db'⟩ o1 t → o1.get ⟨H, db'⟩ key = .ok (v, o2) →
          Op.OTrie.Rep ⟨H, db'⟩ o2 t) ∧
        (∀ o1 h o2, Op.OTrie.Rep ⟨H, db'⟩ o1 t → o1.hashOf ⟨H, db'⟩ = .ok (h, o2) → h = t.hashS H)) := by
  refine ⟨fun _ _ _ => rfl, fun _ _ _ _ => rfl, fun db t hwf hp hne hinj => ?_⟩
  obtain ⟨db', o, h1, h2, h3, _⟩ := Op.retrieve_bridge H hH db t hwf hp hne hinj
  refine ⟨db', o, h1, h2, h3, fun o1 key v o2 ho1 e => ?_, fun o1 h o2 ho1 e => ?_⟩
  · exact ((Op.reads_agree ⟨H, db'⟩ hH o1 t hwf.1 ho1).2.2 key v o2 e).2
  · exact ((Op.reads_agree ⟨H, db'⟩ hH o1 t hwf.1 ho1).1 h o2 e).1

/-! ### TRIE-HASH-04 reproducer (cases/reproducers.cases `repro-hash-04-*`) -/

/-- The child `C = 50060001` (leaf, path `00000`, value `01`) and the parent
`P = 48 ‖ keccak(C) ‖ 04` that references it by hash although it is embeddable. -/
def C04 : Bytes := [0x50, 0x06, 0x00, 0x01]
def P04 : Bytes := [0x48] ++ Keccak.keccak256 C04 ++ [0x04]
/-- The crafted store: `keccak(C) ↦ C`, `keccak(P) ↦ P`. -/
def env04 : Env := ⟨Keccak.keccak256, (DB.empty.put (Keccak.keccak256 C04) C04).put (Keccak.keccak256 P04) P04⟩
def hash04 : Bytes := [0x04, 0xf3, 0x4e, 0xe9, 0x7c, 0xf2, 0xa1, 0x40, 0x00, 0xf8, 0x50, 0x19, 0x45, 0x4f, 0xad,
  0xba, 0x55, 0x2e, 0x3f, 0x43, 0xcc, 0xf5, 0xc6, 0x53, 0x24, 0xfc, 0x25, 0x6c, 0xff, 0x19, 0xb1, 0x9b]
def hash04loaded : Bytes := [0xd8, 0x92, 0x1f, 0xa4, 0xeb, 0x08, 0xdd, 0x7a, 0x6e, 0x7c, 0x2b, 0x65, 0xfc, 0x78,
  0xed, 0xe7, 0xff, 0xcd, 0xf3, 0x5b, 0x2d, 0x4b, 0xd0, 0x2e, 0x3d, 0xa0, 0x8d, 0x20, 0xb3, 0xd0, 0x85, 0xde]

/-- `load keccak(P); hash`. -/
def hashUnloaded04 : Except Err (Bytes × Bytes) := do
  let some t ← Op.retrieve env04 hash04 | throw "missing"
  let (h, t) ← t.hashOf env04
  let (m, _) ← t.messageOf env04
  pure (h, m)
/-- `load keccak(P); getk 00; hash`. -/
def hashLoaded04 : Except Err (Option Bytes × Bytes × Bytes) := do
  let some t ← Op.retrieve env04 hash04 | throw "missing"
  let (v, t) ← t.get env04 [0x00]
  let (h, t) ← t.hashOf env04
  let (m, _) ← t.messageOf env04
  pure (v, h, m)

def okEq {α} [DecidableEq α] (x : Except Err α) (y : α) : Bool :=
  match x with | .ok a => decide (a = y) | .error _ => false

theorem okEq_iff {α} [DecidableEq α] (x : Except Err α) (y : α) : okEq x y = true ↔ x = .ok y := by
  cases x <;> simp [okEq]

theorem hash04_eq : Keccak.keccak256 P04 = hash04 := by decide +kernel

/-- TRIE-HASH-04 does not hold: on the crafted store, a fresh parse of `P` hashes to
`keccak(P) = 04f34e…b19b` with message `P`; after `get(00)` loads the child, `getHash()` is
`d8921f…85de` and `toMessage()` is `4a045006000104` (child embedded) — Java's output
(differential/results/reproducers.lean.out, `repro-hash-04-*`). -/
theorem trie_hash_04_rskip_counterexample :
    hashUnloaded04 = .ok (hash04, P04) ∧
    hashLoaded04 = .ok (some [0x01], hash04loaded, [0x4a, 0x04, 0x50, 0x06, 0x00, 0x01, 0x04]) ∧
    hash04 ≠ hash04loaded := by
  refine ⟨(okEq_iff _ _).1 ?_, (okEq_iff _ _).1 ?_, by decide⟩ <;> decide +kernel

/-- TRIE-HASH-05: `getHashOrchid(s) = H(toMessageOrchid(s))` for non-empty nodes and `EMPTY_HASH`
for the empty node; the Orchid message references children by their Orchid hashes. -/
theorem trie_hash_05 (env : Env) (s : Bool) (t : Trie) :
    t.getHashOrchidF env FUEL s = if t.isEmptyTrie then .ok (env.H [0x80]) else env.H <$> t.toMessageOrchidF env FUEL s :=
  Trie.getHashOrchid_eq env FUEL s t

end RskjTrie.Obligations
