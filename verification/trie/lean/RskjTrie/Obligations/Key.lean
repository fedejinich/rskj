import RskjTrie.Obligations.Common
import RskjTrie.MutableRepository
import RskjTrie.Keccak
/-! # Obligations TRIE-KEY-* (key mapping, RSKIP108 / RSKIP112) -/
namespace RskjTrie.Obligations
open RskjTrie Trie TrieKeyMapper

/-- TRIE-KEY-01: `getAccountKey(a) = 0x00 ++ keccak256(a)[0..10) ++ a`, 31 bytes. -/
theorem trie_key_01 (H : Bytes → Bytes) (a : Bytes) (h20 : a.length = 20) (h32 : (H a).length = 32) :
    getAccountKey H a = [0x00] ++ (H a).take 10 ++ a ∧ (getAccountKey H a).length = 31 :=
  ⟨accountKey_layout H a, (address_recoverable H a h20 h32).1⟩

/-- TRIE-KEY-02 (Java): the hash prefix is exactly the first 10 bytes (80 bits) of the hash. -/
theorem trie_key_02 (H : Bytes → Bytes) (x : Bytes) (h : 10 ≤ (H x).length) :
    secureKeyPrefix H x = (H x).take 10 ∧ (secureKeyPrefix H x).length = 10 := by
  refine ⟨rfl, ?_⟩; simp [secureKeyPrefix, SECURE_KEY_SIZE]; omega

/-- TRIE-KEY-02 (literal `[0:9]` half-open reading, 9 bytes, does not hold). -/
theorem trie_key_02_rskip_counterexample (H : Bytes → Bytes) (x : Bytes) (h : 10 ≤ (H x).length) :
    (secureKeyPrefix H x).length ≠ 9 := by rw [(trie_key_02 H x h).2]; decide

/-- TRIE-KEY-03: `getCodeKey(a) = getAccountKey(a) ++ 0x80`, 32 bytes. -/
theorem trie_key_03 (H : Bytes → Bytes) (a : Bytes) (h20 : a.length = 20) (h32 : (H a).length = 32) :
    getCodeKey H a = getAccountKey H a ++ [0x80] ∧ (getCodeKey H a).length = 32 := by
  refine ⟨codeKey_layout H a, ?_⟩
  rw [codeKey_layout, List.length_append, (address_recoverable H a h20 h32).1]; rfl

/-- TRIE-KEY-04: `getAccountStoragePrefixKey(a) = getAccountKey(a) ++ 0x00`, 32 bytes. -/
theorem trie_key_04 (H : Bytes → Bytes) (a : Bytes) (h20 : a.length = 20) (h32 : (H a).length = 32) :
    getAccountStoragePrefixKey H a = getAccountKey H a ++ [0x00] ∧
      (getAccountStoragePrefixKey H a).length = 32 := by
  refine ⟨rfl, ?_⟩
  simp only [getAccountStoragePrefixKey, STORAGE_PREFIX, List.length_append,
    (address_recoverable H a h20 h32).1]; rfl

/-- TRIE-KEY-05 (Java): `MutableRepository.setupContract` stores `0x01` at the storage-root key
(MutableRepository.java:56, 105-109). -/
theorem trie_key_05 (env : Env) (t : Trie) (ht : Reachable env t) (a : Bytes) :
    ∃ t', MutableRepository.setupContract env t a = .ok t' ∧
      t'.get env (getAccountStoragePrefixKey env.H a) = .ok (some [0x01]) := by
  obtain ⟨t', h1, h2, h3, _⟩ := Trie.get_put env t ht.WF (getAccountStoragePrefixKey env.H a)
    (some MutableRepository.ONE_BYTE_ARRAY) (by intro x hx; simp [normValue, MutableRepository.ONE_BYTE_ARRAY] at hx; subst hx; simp [Uint24.MAX])
  exact ⟨t', h1, by rw [h3]; rfl⟩

/-- TRIE-KEY-05 (RSKIP108 table: the placeholder is `0x00`) does not hold. -/
theorem trie_key_05_rskip_counterexample (env : Env) (t : Trie) (ht : Reachable env t) (a : Bytes) :
    ∃ t', MutableRepository.setupContract env t a = .ok t' ∧
      t'.get env (getAccountStoragePrefixKey env.H a) ≠ .ok (some [0x00]) := by
  obtain ⟨t', h1, h2⟩ := trie_key_05 env t ht a
  exact ⟨t', h1, by rw [h2]; intro h; injection h with h; simp at h⟩

/-- TRIE-KEY-06: storage cell key layout (hash input = the 32-byte word). -/
theorem trie_key_06 (H : Bytes → Bytes) (a s : Bytes) :
    getAccountStorageKey H a s =
      getAccountStoragePrefixKey H a ++ ((H s).take 10 ++ stripLeadingZeroes s) := rfl

/-- TRIE-KEY-07 (Java): the storage prefix hashes the full 32-byte word. -/
theorem trie_key_07 (H : Bytes → Bytes) (a s : Bytes) (h32a : (H a).length = 32) (h20 : a.length = 20)
    (h32s : (H s).length = 32) :
    ((getAccountStorageKey H a s).drop 32).take 10 = (H s).take 10 := by
  rw [trie_key_06, List.drop_left' (trie_key_04 H a h20 h32a).2]
  exact List.take_left' (by simp [h32s])

/-- TRIE-KEY-07 (reading (b): hash of the trimmed address) gives a different key: slot 1
with Keccak-256 (`keccak256(0x00…01)[0..10) ≠ keccak256(0x01)[0..10)`). -/
theorem trie_key_07_rskip_counterexample :
    (Keccak.keccak256 (List.replicate 31 0 ++ [1])).take 10 ≠
      (Keccak.keccak256 (stripLeadingZeroes (List.replicate 31 0 ++ [1]))).take 10 := by
  decide +kernel

/-- TRIE-KEY-08: `stripLeadingZeroes` implements `trimmed_storage_address` on 32-byte words:
the word without its leading zero bytes, and `[0x00]` for the zero word. -/
theorem trie_key_08 (s : Bytes) :
    (s.dropWhile (· == 0) = [] → stripLeadingZeroes s = [0x00]) ∧
    (s.dropWhile (· == 0) ≠ [] → stripLeadingZeroes s = s.dropWhile (· == 0)) ∧
    s = List.replicate (s.length - (s.dropWhile (· == 0)).length) 0 ++ s.dropWhile (· == 0) := by
  obtain ⟨z, hz, h1, h2⟩ := stripLeadingZeroes_spec s
  refine ⟨h1, h2, ?_⟩
  have hl := congrArg List.length hz
  simp only [List.length_append, List.length_replicate] at hl
  conv => lhs; rw [hz]
  congr 2; omega

theorem dropWhile_head_ne (s : Bytes) (b : UInt8) (r : Bytes) (h : s.dropWhile (· == 0) = b :: r) : b ≠ 0 := by
  induction s with
  | nil => simp at h
  | cons x xs ih =>
    by_cases hx : x = 0
    · subst hx; simp only [List.dropWhile_cons, beq_self_eq_true, ↓reduceIte] at h; exact ih h
    · have : (x == 0) = false := by simpa using hx
      simp only [List.dropWhile_cons, this] at h; simp at h; rw [← h.1]; exact hx

theorem strip_injective (s s' : Bytes) (hs : s.length = 32) (hs' : s'.length = 32)
    (h : stripLeadingZeroes s = stripLeadingZeroes s') : s = s' := by
  obtain ⟨_, _, e⟩ := trie_key_08 s
  obtain ⟨_, _, e'⟩ := trie_key_08 s'
  have hd : s.dropWhile (· == 0) = s'.dropWhile (· == 0) := by
    unfold stripLeadingZeroes at h
    cases h1 : s.dropWhile (· == 0) with
    | nil =>
      cases h2 : s'.dropWhile (· == 0) with
      | nil => rfl
      | cons b r =>
        rw [h1, h2] at h; simp at h; exact absurd h.1.symm (dropWhile_head_ne s' b r h2)
    | cons b r =>
      cases h2 : s'.dropWhile (· == 0) with
      | nil => rw [h1, h2] at h; simp at h; exact absurd h.1 (dropWhile_head_ne s b r h1)
      | cons b' r' => rw [h1, h2] at h; exact h
  rw [e, e', hd, hs, hs']

theorem strip_length (s : Bytes) (hs : s.length = 32) :
    1 ≤ (stripLeadingZeroes s).length ∧ (stripLeadingZeroes s).length ≤ 32 := by
  unfold stripLeadingZeroes
  have := (List.dropWhile_suffix (p := (· == (0 : UInt8))) (l := s)).length_le
  cases h : s.dropWhile (· == 0) with
  | nil => simp
  | cons b r => rw [h] at this; simp at this ⊢; omega

/-- TRIE-KEY-09: the key mapping is injective and the key kinds are disjoint. -/
theorem trie_key_09 (H : Bytes → Bytes) (hH : ∀ x, (H x).length = 32) :
    (∀ a a', a.length = 20 → a'.length = 20 → getAccountKey H a = getAccountKey H a' → a = a') ∧
    (∀ a, a.length = 20 → (getAccountKey H a).length = 31) ∧
    (∀ a, a.length = 20 → (getCodeKey H a).length = 32 ∧ (getCodeKey H a).getLast? = some 0x80) ∧
    (∀ a, a.length = 20 → (getAccountStoragePrefixKey H a).length = 32 ∧
      (getAccountStoragePrefixKey H a).getLast? = some 0x00) ∧
    (∀ a s, a.length = 20 → s.length = 32 → 43 ≤ (getAccountStorageKey H a s).length ∧
      (getAccountStorageKey H a s).length ≤ 74) ∧
    (∀ a s a' s', a.length = 20 → s.length = 32 → a'.length = 20 → s'.length = 32 →
      getAccountStorageKey H a s = getAccountStorageKey H a' s' → a = a' ∧ s = s') := by
  refine ⟨fun a a' h1 h2 h => ?_, fun a h => (address_recoverable H a h (hH a)).1,
    fun a h => ⟨(trie_key_03 H a h (hH a)).2, by simp [getCodeKey, CODE_PREFIX]⟩,
    fun a h => ⟨(trie_key_04 H a h (hH a)).2, by simp [getAccountStoragePrefixKey, STORAGE_PREFIX]⟩,
    fun a s ha hs => ?_, fun a s a' s' ha hs ha' hs' h => ?_⟩
  · rw [← (address_recoverable H a h1 (hH a)).2, ← (address_recoverable H a' h2 (hH a')).2, h]
  · rw [trie_key_06, List.length_append, (trie_key_04 H a ha (hH a)).2]
    have := strip_length s hs
    simp only [List.length_append, List.length_take, hH]; omega
  · obtain ⟨r1, r2, _⟩ := storage_recoverable H a s ha hs hH
    obtain ⟨r1', r2', _⟩ := storage_recoverable H a' s' ha' hs' hH
    refine ⟨by rw [← r1, ← r1', h], ?_⟩
    apply strip_injective s s' hs hs'
    rw [← r2, ← r2', h]

/-- TRIE-KEY-10 (Java): the storage-root placeholder is stored as the raw byte `0x01`, with no
RSKIP112 type specifier. -/
theorem trie_key_10 (env : Env) (t : Trie) (ht : Reachable env t) (a : Bytes) :
    ∃ t' v, MutableRepository.setupContract env t a = .ok t' ∧
      t'.get env (getAccountStoragePrefixKey env.H a) = .ok (some v) ∧ v = [0x01] := by
  obtain ⟨t', h1, h2⟩ := trie_key_05 env t ht a
  exact ⟨t', _, h1, h2, rfl⟩

/-- TRIE-KEY-10 (RSKIP112: every non-zero value starts with 'A', 'S', 'R' or 'D') does not hold. -/
theorem trie_key_10_rskip_counterexample (env : Env) (t : Trie) (ht : Reachable env t) (a : Bytes) :
    ∃ t' v, MutableRepository.setupContract env t a = .ok t' ∧
      t'.get env (getAccountStoragePrefixKey env.H a) = .ok (some v) ∧ v ≠ [] ∧
      v.head? ∉ ([some 0x41, some 0x53, some 0x52, some 0x44] : List (Option UInt8)) := by
  obtain ⟨t', v, h1, h2, rfl⟩ := trie_key_10 env t ht a
  exact ⟨t', _, h1, h2, by decide, by decide⟩

end RskjTrie.Obligations
