import RskjTrie.Obligations.Common
/-! # Obligations TRIE-PATH-* (bit paths) -/
namespace RskjTrie.Obligations
open RskjTrie Trie TrieKeySlice PathEncoder

set_option linter.unusedSimpArgs false

/-- TRIE-PATH-01 (Java): `fromKey(k)` has `8|k|` bits and bit `8i+j` is bit `7-j` of `k[i]`
(most significant bit first). -/
theorem trie_path_01 (k : Bytes) :
    (fromKey k).length = 8 * k.length ∧
    ∀ i j, (hi : i < k.length) → j < 8 → (fromKey k)[8 * i + j]? = some (k[i].toNat.testBit (7 - j)) := by
  refine ⟨fromKey_length k, fun i j hi hj => ?_⟩
  rw [fromKey_eq, List.getElem?_map, List.getElem?_range (by omega)]
  simp only [Option.map_some, Option.some.injEq, bitAt]
  have d1 : (8 * i + j) / 8 = i := by omega
  have d2 : (8 * i + j) % 8 = j := by omega
  rw [d1, d2, List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hi]; rfl

/-- TRIE-PATH-01: the least-significant-bit-first reading does not hold: `fromKey([0x80])` starts
with a 1 bit. -/
theorem trie_path_01_rskip_counterexample :
    fromKey [0x80] = [true, false, false, false, false, false, false, false] ∧
    fromKey [0x80] ≠ [false, false, false, false, false, false, false, true] := by
  constructor <;> decide

theorem fromKey_00 : fromKey [0x00] = List.replicate 8 false := by decide
theorem fromKey_80 : fromKey [0x80] = true :: List.replicate 7 false := by decide

/-- The trie of TRIE-PATH-02's reproducer: `{00: v1, 80: v2}`. -/
def path02Expected (v1 v2 : Bytes) : Trie :=
  ⟨[], none, .node ⟨List.replicate 7 false, some v1, .empty, .empty, v1.length, none, none⟩,
    .node ⟨List.replicate 7 false, some v2, .empty, .empty, v2.length, none, none⟩, 0, none, none⟩

/-- TRIE-PATH-02 (Java): the branch bit is implicit and `0` selects the left child: putting
`0x00` and `0x80` into the empty trie gives a root with an empty shared path whose left child
holds `0x00`'s value with the 7-bit shared path `0000000` (and the right child `0x80`'s). -/
theorem trie_path_02 (env : Env) (v1 v2 : Bytes) (h1 : v1 ≠ []) (h2 : v2 ≠ [])
    (l1 : v1.length ≤ Uint24.MAX) (l2 : v2.length ≤ Uint24.MAX) :
    ∃ t, runOps env Trie.empty [.put [0x00] (some v1), .put [0x80] (some v2)] = .ok t ∧
      t.erase = (path02Expected v1 v2).erase := by
  have hn1 := normValue_some v1 h1
  have hn2 := normValue_some v2 h2
  have hp1 : 0 < v1.length := List.length_pos_iff.mpr h1
  have hp2 : 0 < v2.length := List.length_pos_iff.mpr h2
  obtain ⟨t, h, _, he, _⟩ := runOps_explicit env [.put [0x00] (some v1), .put [0x80] (some v2)] (by
      intro op hop; simp only [List.mem_cons, List.mem_nil_iff, or_false] at hop; rcases hop with rfl | rfl
      · intro x hx; simp [Op.val, hn1] at hx; subst hx; exact l1
      · intro x hx; simp [Op.val, hn2] at hx; subst hx; exact l2)
    (path02Expected v1 v2) (by
      refine ⟨?_, ?_, Or.inl ?_⟩
      · simp only [path02Expected, Trie.Resident, NodeRef.Resident, ValueOK]
        simp [isEmptyTrie, isEmptyTrieOf, hp1, hp2, l1, l2]
      · simp [path02Expected, Trie.CacheOK, NodeRef.CacheOK]
      · simp [path02Expected, Trie.CanonNE, NodeRef.Canon])
    (by
      intro q
      rw [mapAfter_two, fromKey_00, fromKey_80, hn1, hn2]
      rcases q with _ | ⟨b, q⟩
      · simp [path02Expected, Trie.contents]
      · have := Trie.contents_mk [] none
          (.node ⟨List.replicate 7 false, some v1, .empty, .empty, v1.length, none, none⟩)
          (.node ⟨List.replicate 7 false, some v2, .empty, .empty, v2.length, none, none⟩) 0 none none (b :: q)
        simp only [List.nil_append] at this
        rw [path02Expected, this]
        cases b <;> simp only [NodeRef.contents, Trie.contents_leaf] <;>
          by_cases hq : q = List.replicate 7 false <;> simp [hq, List.replicate_succ])
  exact ⟨t, h, he⟩

/-- TRIE-PATH-02: the reading where the branch bit is stored in the child's shared path (8 bits)
does not hold: the child's shared path has 7 bits. -/
theorem trie_path_02_rskip_counterexample (env : Env) (v1 v2 : Bytes) (h1 : v1 ≠ []) (h2 : v2 ≠ [])
    (l1 : v1.length ≤ Uint24.MAX) (l2 : v2.length ≤ Uint24.MAX) :
    ∃ t, runOps env Trie.empty [.put [0x00] (some v1), .put [0x80] (some v2)] = .ok t ∧
      ∃ c, t.left = .node c ∧ c.sharedPath.length = 7 ∧ c.sharedPath.length ≠ 8 := by
  obtain ⟨t, h, he⟩ := trie_path_02 env v1 v2 h1 h2 l1 l2
  refine ⟨t, h, ?_⟩
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
  simp only [path02Expected, Trie.erase, Trie.mk.injEq] at he
  obtain ⟨_, _, hl, _⟩ := he
  cases l with
  | node c =>
    simp only [NodeRef.erase, NodeRef.node.injEq] at hl
    obtain ⟨p', v', l', r', vl', vh', cs'⟩ := c
    simp only [Trie.erase, Trie.mk.injEq] at hl
    exact ⟨_, rfl, by simp [hl.1], by simp [hl.1]⟩
  | _ => simp [NodeRef.erase] at hl

/-- TRIE-PATH-03: `encode(p)` has `⌈|p|/8⌉` bytes, packs MSB first, zero-pads, and
`decode(encode(p), |p|) = p`. -/
theorem trie_path_03 (p : List Bool) :
    (PathEncoder.encode p).length = (p.length + 7) / 8 ∧ calculateEncodedLength p.length = (p.length + 7) / 8 ∧
    (∀ k, (hk : k < p.length) → ((PathEncoder.encode p).getD (k / 8) 0).toNat.testBit (7 - k % 8) = p[k]) ∧
    (∀ k, p.length ≤ k → ((PathEncoder.encode p).getD (k / 8) 0).toNat.testBit (7 - k % 8) = false) ∧
    PathEncoder.decode (PathEncoder.encode p) p.length = .ok p :=
  ⟨encode_length p, calculateEncodedLength_eq _, encode_msb_first p, encode_unused_bits_zero p,
    decode_encode p⟩

/-- TRIE-PATH-04 (Java): `decode` reads only the first `n` bits; bits beyond are never examined,
so two encodings that agree on those bits decode equally. -/
theorem trie_path_04 (enc enc' : Bytes) (n : Nat) (h1 : n ≤ 8 * enc.length) (h2 : n ≤ 8 * enc'.length)
    (h : ∀ k < n, bitAt enc k = bitAt enc' k) : PathEncoder.decode enc n = PathEncoder.decode enc' n := by
  rw [decode_eq _ _ h1, decode_eq _ _ h2]
  congr 1
  apply List.map_congr_left
  intro k hk; simp at hk; exact h k hk

/-- TRIE-PATH-04 (canonical-parse reading) does not hold: `5000ff01` (padding bits set) is
accepted and re-encodes to `50008001`. -/
theorem trie_path_04_rskip_counterexample (env : Env) :
    reencode env [0x50, 0x00, 0xff, 0x01] = .ok [0x50, 0x00, 0x80, 0x01] ∧
    [0x50, 0x00, 0x80, 0x01] ≠ ([0x50, 0x00, 0xff, 0x01] : Bytes) :=
  ⟨reencode_eq _ _ _ ⟨_, rfl, rfl, rfl⟩, by decide⟩

theorem lcp_maximal : ∀ (a b c : List Bool), c <+: a → c <+: b → c <+: lcp a b
  | _, _, [], _, _ => List.nil_prefix
  | a :: as, b :: bs, x :: xs, ha, hb => by
    simp only [List.cons_prefix_cons] at ha hb
    obtain ⟨rfl, ha⟩ := ha; obtain ⟨rfl, hb⟩ := hb
    simp only [lcp, ↓reduceIte, List.cons_prefix_cons, true_and]
    exact lcp_maximal as bs xs ha hb
  | [], _, _ :: _, ha, _ => by simp at ha
  | _ :: _, [], _ :: _, _, hb => by simp at hb

/-- TRIE-PATH-05: `commonPath` is the longest common prefix, `slice(i, j)` (with Java's checks)
returns bits `i..j-1` or throws, `rebuildSharedPath(b, c) = a ++ [b] ++ c`. -/
theorem trie_path_05 :
    (∀ a b : List Bool, commonPath a b <+: a ∧ commonPath a b <+: b ∧
      ∀ c, c <+: a → c <+: b → c <+: commonPath a b) ∧
    (∀ (s : List Bool) (i j : Int), (0 ≤ i ∧ i ≤ j ∧ j ≤ s.length) →
      sliceJ s i j = .ok ((s.drop i.toNat).take (j.toNat - i.toNat))) ∧
    (∀ (s : List Bool) (i j : Int), ¬ (0 ≤ i ∧ i ≤ j ∧ j ≤ s.length) → ∃ e, sliceJ s i j = .error e) ∧
    (∀ (a c : List Bool) (b : Bool), rebuildSharedPath a b c = a ++ b :: c) := by
  refine ⟨fun a b => ?_, fun s i j h => ?_, fun s i j h => ?_, fun _ _ _ => rfl⟩
  · rw [commonPath_eq_lcp]; exact ⟨lcp_prefix_left a b, lcp_prefix_right a b, lcp_maximal a b⟩
  · unfold sliceJ
    have : ¬ i < 0 := by omega
    have : ¬ i > j := by omega
    have : ¬ i > (s.length : Int) := by omega
    have : ¬ j > (s.length : Int) := by omega
    simp [*, slice]
  · unfold sliceJ
    by_cases a : i < 0
    · simp [a]
    · by_cases b : i > j
      · simp [a, b]
      · by_cases c : i > (s.length : Int)
        · simp [a, b, c]
        · have d : j > (s.length : Int) := by omega
          simp [a, b, c, d]

end RskjTrie.Obligations
