import RskjTrie.PathEncoder
/-!
# `co.rsk.trie.TrieKeySlice`

Java: a view `(expandedKey, offset, limit)` over an expanded key (`byte[]` of 0/1).
Model: the viewed contents `expandedKey[offset..limit)` as a `List Bool`. Every method of the
class only observes the view through `get(i)` with `0 ≤ i < length()`, `length()`,
`Arrays.copyOfRange(expandedKey, offset, limit)` or `System.arraycopy` of the viewed range, so two
slices with the same contents are indistinguishable (see MODEL.md). `slice`'s
`IllegalArgumentException`s are not modelled: all call sites in `Trie` pass
`0 ≤ from ≤ to ≤ length()` (checked by the JBMC helper).
-/
namespace RskjTrie

abbrev TrieKeySlice := List Bool

namespace TrieKeySlice

-- `TrieKeySlice.length()` (TrieKeySlice.java:37-39) is `List.length` of the contents.

/-- `TrieKeySlice.get(int i)` — TrieKeySlice.java:41-43 (callers guarantee `i < length()`). -/
def get (s : TrieKeySlice) (i : Nat) : Bool := s.getD i false

/-- `TrieKeySlice.encode()` — TrieKeySlice.java:45-48. -/
def encode (s : TrieKeySlice) : Bytes := PathEncoder.encode s

/-- `TrieKeySlice.slice(int from, int to)` — TrieKeySlice.java:50-70 (for `from ≤ to ≤ length`). -/
def slice (s : TrieKeySlice) (fr to : Nat) : TrieKeySlice := (s.drop fr).take (to - fr)

/-- Loop of `commonPath` — TrieKeySlice.java:73-80: first index `i < max` with a mismatch
returns `slice(0, i)`, otherwise `slice(0, max)`. -/
def commonPathLoop (a b : TrieKeySlice) (max : Nat) : Nat → Nat → TrieKeySlice
  | 0, i => a.slice 0 i
  | fuel + 1, i =>
    if i < max then
      if a.get i != b.get i then a.slice 0 i else commonPathLoop a b max fuel (i + 1)
    else a.slice 0 max

/-- `TrieKeySlice.slice(int from, int to)` *with* Java's argument checks — TrieKeySlice.java:50-70,
for a view with `offset = 0` and `limit = length()` (the model's slices are their contents). The
trie code calls the unchecked `slice` only with bounds that pass these checks. -/
def sliceJ (s : TrieKeySlice) (fr to : Int) : Except Err TrieKeySlice :=
  if fr < 0 then .error "IllegalArgumentException: The start position must not be lower than 0"
  else if fr > to then .error "IllegalArgumentException: The start position must not be greater than the end position"
  else if fr > s.length then .error "IllegalArgumentException: The start position must not exceed the key length"
  else if to > s.length then .error "IllegalArgumentException: The end position must not exceed the key length"
  else .ok (s.slice fr.toNat to.toNat)

/-- `TrieKeySlice.commonPath(TrieKeySlice other)` — TrieKeySlice.java:72-81. -/
def commonPath (a b : TrieKeySlice) : TrieKeySlice :=
  let max := Nat.min (List.length a) (List.length b)
  commonPathLoop a b max (max + 1) 0

/-- `TrieKeySlice.rebuildSharedPath(byte implicitByte, TrieKeySlice child)` —
TrieKeySlice.java:86-97: `[...this, implicitByte, ...child]`. -/
def rebuildSharedPath (s : TrieKeySlice) (implicitByte : Bool) (child : TrieKeySlice) : TrieKeySlice :=
  s ++ implicitByte :: child

/-- `TrieKeySlice.fromKey(byte[] key)` — TrieKeySlice.java:109-115:
`PathEncoder.decode(key, key.length * 8)`, which cannot fail since the array is long enough
(`PathEncoder.decode_full` in Proofs). -/
def fromKey (key : Bytes) : TrieKeySlice :=
  match PathEncoder.decode key (key.length * 8) with
  | .ok p => p
  | .error _ => []

/-- `TrieKeySlice.fromEncoded(src, offset, keyLength, encodedLength)` — TrieKeySlice.java:117-122
(`copyOfRange` zero-pads past the end of `src`; callers check the length first). -/
def fromEncoded (src : Bytes) (offset keyLength encodedLength : Nat) : Except Err TrieKeySlice :=
  let enc := ((src.drop offset).take encodedLength) ++
    List.replicate (encodedLength - (src.length - offset)) 0
  PathEncoder.decode enc keyLength

/-- `TrieKeySlice.empty()` — TrieKeySlice.java:124-126. -/
def empty : TrieKeySlice := []

/-! ## `commonPath` is the longest common prefix (used for `put`'s termination) -/

/-- Longest common prefix (specification of `commonPath`). -/
def lcp : List Bool → List Bool → List Bool
  | a :: as, b :: bs => if a = b then a :: lcp as bs else []
  | _, _ => []

theorem lcp_length_le_left (a b : List Bool) : (lcp a b).length ≤ a.length := by
  induction a generalizing b with
  | nil => simp [lcp]
  | cons x xs ih => cases b with
    | nil => simp [lcp]
    | cons y ys => simp only [lcp]; split <;> simp [ih]

theorem lcp_length_le_right (a b : List Bool) : (lcp a b).length ≤ b.length := by
  induction a generalizing b with
  | nil => simp [lcp]
  | cons x xs ih => cases b with
    | nil => simp [lcp]
    | cons y ys => simp only [lcp]; split <;> simp [ih]

theorem lcp_prefix_left (a b : List Bool) : lcp a b <+: a := by
  induction a generalizing b with
  | nil => simp [lcp]
  | cons x xs ih => cases b with
    | nil => simp [lcp]
    | cons y ys => simp only [lcp]; split <;> simp [ih]

theorem lcp_prefix_right (a b : List Bool) : lcp a b <+: b := by
  induction a generalizing b with
  | nil => simp [lcp]
  | cons x xs ih => cases b with
    | nil => simp [lcp]
    | cons y ys =>
      simp only [lcp]; split
      · next h => subst h; exact List.prefix_cons_inj _ |>.mpr (ih ys)
      · exact List.nil_prefix

theorem take_lcp (a b : List Bool) : a.take (lcp a b).length = lcp a b := by
  exact (List.prefix_iff_eq_take.mp (lcp_prefix_left a b)).symm

theorem commonPathLoop_eq (a b : List Bool) (mx : Nat) (h1 : mx ≤ a.length) (h2 : mx ≤ b.length)
    (h3 : mx = a.length ∨ mx = b.length) :
    ∀ fuel i, i ≤ mx → mx - i < fuel →
      commonPathLoop a b mx fuel i = a.take (i + (lcp (a.drop i) (b.drop i)).length) := by
  intro fuel
  induction fuel with
  | zero => intro i _ h; omega
  | succ n ih =>
    intro i hi hf
    simp only [commonPathLoop]
    by_cases hlt : i < mx
    · have ha : i < a.length := by omega
      have hb : i < b.length := by omega
      simp only [hlt, ↓reduceIte]
      have da : a.drop i = a[i] :: a.drop (i+1) := List.drop_eq_getElem_cons ha
      have db : b.drop i = b[i] :: b.drop (i+1) := List.drop_eq_getElem_cons hb
      have ga : TrieKeySlice.get a i = a[i] := by
        simp [TrieKeySlice.get, List.getD, List.getElem?_eq_getElem ha]
      have gb : TrieKeySlice.get b i = b[i] := by
        simp [TrieKeySlice.get, List.getD, List.getElem?_eq_getElem hb]
      rw [ga, gb, da, db]
      by_cases heq : a[i] = b[i]
      · simp only [heq, bne_self_eq_false, Bool.false_eq_true, ↓reduceIte, lcp, List.length_cons]
        rw [ih (i+1) (by omega) (by omega)]
        congr 1; omega
      · have : (a[i] != b[i]) = true := by simpa using heq
        simp [this, lcp, heq, slice]
    · simp only [hlt, ↓reduceIte]
      have hi' : i = mx := by omega
      subst hi'
      have hz : (lcp (a.drop i) (b.drop i)).length = 0 := by
        have g1 := lcp_length_le_left (a.drop i) (b.drop i)
        have g2 := lcp_length_le_right (a.drop i) (b.drop i)
        simp at g1 g2
        omega
      simp [hz, slice]

theorem commonPath_eq_lcp (a b : List Bool) : commonPath a b = lcp a b := by
  unfold commonPath
  
  have h1 := Nat.min_le_left a.length b.length
  have h2 := Nat.min_le_right a.length b.length
  have h3 : Nat.min a.length b.length = a.length ∨ Nat.min a.length b.length = b.length := by
    rcases Nat.le_total a.length b.length with h | h
    · left; exact Nat.min_eq_left h
    · right; exact Nat.min_eq_right h
  rw [commonPathLoop_eq a b _ h1 h2 h3 _ 0 (Nat.zero_le _) (by omega)]
  simp [take_lcp]

theorem lcp_of_prefix {a l : List Bool} (h : l <+: a) : lcp a l = l := by
  induction l generalizing a with
  | nil => cases a <;> simp [lcp]
  | cons x xs ih =>
    obtain ⟨t, rfl⟩ := h
    simp [lcp, ih (List.prefix_append xs t)]

theorem commonPath_idem (key p : List Bool) :
    (commonPath key (commonPath key p)).length = (commonPath key p).length := by
  simp only [commonPath_eq_lcp]
  rw [lcp_of_prefix (lcp_prefix_left key p)]

end TrieKeySlice
end RskjTrie
