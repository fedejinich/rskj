import RskjTrie.Proofs.Bridge
import RskjTrie.Proofs.Put
/-!
# Bridge for `put` / `delete` / `deleteRecursive`

The operational `putSlice`/`internalPut`/`split` (with Java's caches, loading and caching
children, mutating the receiver's caches) simulate the pure ones step by step: on a represented
object of a resident, cache-consistent trie, the operational call either runs out of fuel, or fails
exactly when the pure call fails (with the same error), or returns a result represented by the pure
result — and the receiver stays represented. Along the way the pure results are resident and
cache-consistent (no canonicity is needed).
-/
namespace RskjTrie.Op
open RskjTrie Trie TrieKeySlice

set_option linter.unusedSimpArgs false

def RepRes (env : Env) : OPutRes → PutRes → Prop
  | .same, .same => True
  | .null, .null => True
  | .new n, .new N => OTrie.Rep env n N ∧ N.Resident ∧ N.CacheOK env.H
  | _, _ => False

/-- The operational `put` step either ran out of fuel, failed like the pure one, or returned a
represented result with a still-represented receiver. -/
def GoodP (env : Env) (t : Trie) (pr : Except Err PutRes) (res : Except Err (OPutRes × OTrie)) : Prop :=
  res = .error "fuel" ∨ (∃ e, pr = .error e ∧ res = .error e) ∨
  ∃ R r o, pr = .ok R ∧ res = .ok (r, o) ∧ RepRes env r R ∧ OTrie.Rep env o t

theorem Rep_mk' {env : Env} {p : TrieKeySlice} {v : Option Bytes} {l r : ORef OTrie} {vl : Nat}
    {vh : Option Bytes} {cs : Option Nat} {T : Trie} (h1 : p = T.sharedPath) (h2 : vl = T.valueLength)
    (h3 : v = T.value ∨ (T.valueLength > 32 ∧ v = none ∧ vh = some (env.H (T.value.getD [])) ∧
      env.db (env.H (T.value.getD [])) = some (T.value.getD [])))
    (h4 : T.valueLength > 0 → vh = none ∨ vh = some (env.H (T.value.getD [])))
    (h5 : cs = none ∨ cs = some (Trie.encS env.H T).2)
    (h6 : ORef.Rep env l T.left) (h7 : ORef.Rep env r T.right) :
    OTrie.Rep env (OTrie.mk' p v l r vl vh cs) T := by
  rw [OTrie.Rep_iff]; exact ⟨h1, h2, h3, h4, h5, Or.inl rfl, Or.inl rfl, h6, h7⟩

theorem ORef.Rep_ofNode {env : Env} {n : OTrie} {N : Trie} (h : OTrie.Rep env n N) :
    ORef.Rep env (ORef.ofNode (some n)) (NodeRef.ofNode (some N)) := by
  simp only [ORef.ofNode, NodeRef.ofNode, OTrie.Rep_isEmptyTrie h]
  split
  · trivial
  · unfold ORef.Rep; exact ⟨h, Or.inl rfl⟩

theorem ORef.Rep_ofNode_none {env : Env} : ORef.Rep env (ORef.ofNode none) (NodeRef.ofNode none) := trivial

theorem NodeRef.ofNode_ok (H : Bytes → Bytes) (N : Trie) (h1 : N.Resident) (h2 : N.CacheOK H) :
    (NodeRef.ofNode (some N)).Resident ∧ (NodeRef.ofNode (some N)).CacheOK H := by
  simp only [NodeRef.ofNode]
  split
  · exact ⟨trivial, trivial⟩
  · next he => exact ⟨⟨h1, by simpa using he⟩, h2⟩

theorem getDataLength_ok {value : Option Bytes} {dl : Nat} (hn : normValue value = value)
    (h : getDataLength value = .ok dl) : ValueOK value dl := by
  cases value with
  | none => simp [getDataLength] at h; subst h; exact Or.inl ⟨rfl, rfl⟩
  | some x =>
    simp only [getDataLength, Uint24.mk] at h
    split at h
    · cases h
    · next hle =>
      simp only [Except.ok.injEq] at h; subst h
      have hne := normValue_eq _ hn x rfl
      exact Or.inr ⟨x, rfl, rfl, List.length_pos_iff.mpr hne, by omega⟩

/-! ## `split` -/

theorem split_Rep (env : Env) (hH : ∀ x, (env.H x).length = 32) (f : Nat) (o : OTrie) (t : Trie)
    (ht : t.Resident) (hc : t.CacheOK env.H) (h : OTrie.Rep env o t) (cp : TrieKeySlice) :
    OTrie.split env (f + 1) o cp = .error "fuel" ∨
      ∃ s o', t.split env cp = .ok s ∧ OTrie.split env (f + 1) o cp = .ok o' ∧ OTrie.Rep env o' s.1 ∧
        s.1.Resident ∧ s.1.CacheOK env.H := by
  have h' := (OTrie.Rep_iff env o t).1 h
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
  obtain ⟨hv, hl, hr⟩ := ht
  obtain ⟨hcs, hvh, hcl, hcr⟩ := hc
  simp only at h'
  obtain ⟨hsp, hvl, hval, hvh', hcs', _, _, hL, hR⟩ := h'
  let C : Trie := ⟨p.slice (cp.length + 1) p.length, v, l, r, vl, vh, cs⟩
  have hCres : C.Resident := ⟨hv, hl, hr⟩
  have hCc : C.CacheOK env.H := ⟨by rw [encS_snd]; rw [encS_snd] at hcs; exact hcs, hvh, hcl, hcr⟩
  have hn : OTrie.Rep env (OTrie.mk' (o.sharedPath.slice (cp.length + 1) o.sharedPath.length) o.value o.left
      o.right o.valueLength o.valueHash o.childrenSize) C := by
    refine Rep_mk' (by rw [hsp]) hvl hval hvh' ?_ hL hR
    rcases hcs' with e | e
    · exact Or.inl e
    · right; rw [e, encS_snd, encS_snd]
  have hNR := ORef.Rep_ofNode hn
  obtain ⟨hNres, hNc⟩ := NodeRef.ofNode_ok env.H C hCres hCc
  have hsz := NodeRef.refOK env _ hNres hNc FUEL
  simp only [OTrie.split]; unfold Trie.split; dsimp only
  rw [show (⟨p.slice (cp.length + 1) p.length, v, l, r, vl, vh, cs⟩ : Trie) = C from rfl]
  simp only [hsz, except_bind_ok]
  rcases (readOK env hH f).rsize _ _ hNres hNR with e | ⟨r1, e, hr1⟩
  · left; simp only [e, bind, Except.bind]
  rw [e]
  right
  have hsize := NodeRef.size_lt env.H _ hNres
  refine ⟨_, _, rfl, rfl, ?_⟩
  dsimp only
  have hk : ∀ (L R : NodeRef Trie), ((L = NodeRef.ofNode (some C) ∧ R = .empty) ∨
      (L = .empty ∧ R = NodeRef.ofNode (some C))) →
      kidsSize env.H L R = (NodeRef.encS env.H (NodeRef.ofNode (some C))).2.1 := by
    intro L R hLR
    have e0 : (NodeRef.empty : NodeRef Trie).isEmpty = true := rfl
    unfold kidsSize
    by_cases he : (NodeRef.ofNode (some C)).isEmpty = true
    · have : (NodeRef.encS env.H (NodeRef.ofNode (some C))).2.1 = 0 := NodeRef.size_of_isEmpty _ _ he
      rcases hLR with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;> simp only [he, e0, Bool.and_self, ↓reduceIte, this]
    · simp only [Bool.not_eq_true] at he
      rcases hLR with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
        simp only [he, e0, Bool.and_true, Bool.true_and, Bool.false_eq_true, ↓reduceIte, NodeRef.size_empty,
          Int.natCast_zero, Int.add_zero, Int.zero_add, wrap64_nat _ hsize]
  simp only [hsp]
  cases hb : p.get cp.length
  · simp only [↓reduceIte]
    refine ⟨Rep_mk' rfl rfl (Or.inl rfl) (fun h => by simp at h) (Or.inr ?_) hr1 trivial, ?_, ?_⟩
    · rw [encS_snd, hk _ _ (Or.inl ⟨rfl, rfl⟩)]
    · exact ⟨Or.inl ⟨rfl, rfl⟩, hNres, trivial⟩
    · refine ⟨Or.inr ?_, fun x hx => by simp at hx, hNc, trivial⟩
      rw [encS_snd, hk _ _ (Or.inl ⟨rfl, rfl⟩)]
  · simp only [Bool.true_eq_false, ↓reduceIte]
    refine ⟨Rep_mk' rfl rfl (Or.inl rfl) (fun h => by simp at h) (Or.inr ?_) trivial hr1, ?_, ?_⟩
    · rw [encS_snd, hk _ _ (Or.inr ⟨rfl, rfl⟩)]
    · exact ⟨Or.inl ⟨rfl, rfl⟩, trivial, hNres⟩
    · refine ⟨Or.inr ?_, fun x hx => by simp at hx, trivial, hNc⟩
      rw [encS_snd, hk _ _ (Or.inr ⟨rfl, rfl⟩)]

theorem split_Rep' (env : Env) (hH : ∀ x, (env.H x).length = 32) (f : Nat) (o : OTrie) (t : Trie)
    (ht : t.Resident) (hc : t.CacheOK env.H) (h : OTrie.Rep env o t) (cp : TrieKeySlice) :
    OTrie.split env f o cp = .error "fuel" ∨
      ∃ s o', t.split env cp = .ok s ∧ OTrie.split env f o cp = .ok o' ∧ OTrie.Rep env o' s.1 ∧
        s.1.Resident ∧ s.1.CacheOK env.H := by
  cases f with
  | zero => exact Or.inl rfl
  | succ f => exact split_Rep env hH f o t ht hc h cp

/-! ## `retrieveNodeOrEmpty` -/

theorem empty_Rep (env : Env) : OTrie.Rep env OTrie.empty Trie.empty :=
  Rep_mk' rfl rfl (Or.inl rfl) (fun h => by simp [Trie.empty] at h) (Or.inr (by simp [Trie.empty, Trie.encS, NodeRef.isEmpty, NodeRef.encS]))
    trivial trivial

theorem empty_ok (H : Bytes → Bytes) : Trie.empty.Resident ∧ Trie.empty.CacheOK H :=
  ⟨(Trie.WF_empty H).1, (Trie.WF_empty H).2.1⟩

theorem rne_Rep (env : Env) (hH : ∀ x, (env.H x).length = 32) (f : Nat) (o : OTrie) (T : Trie)
    (hT : T.Resident) (hc : T.CacheOK env.H) (h : OTrie.Rep env o T) (pos : Bool) :
    OTrie.retrieveNodeOrEmpty env f o pos = .error "fuel" ∨
    ∃ n fresh o1 N, T.retrieveNodeOrEmpty env pos = .ok N ∧
      OTrie.retrieveNodeOrEmpty env f o pos = .ok (n, fresh, o1) ∧
      OTrie.Rep env n N ∧ N.Resident ∧ N.CacheOK env.H ∧ OTrie.Rep env o1 T ∧
      (fresh = true → N = Trie.empty ∧ T.getNodeReference pos = .empty) ∧
      (fresh = false → T.getNodeReference pos = .node N ∧
        ∀ n', OTrie.Rep env n' N → OTrie.Rep env (o1.writeBack pos n') T) := by
  have RK := readOK env hH f
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := T
  obtain ⟨_, hl, hr⟩ := hT
  obtain ⟨_, _, hcl, hcr⟩ := hc
  unfold OTrie.retrieveNodeOrEmpty Trie.retrieveNodeOrEmpty Trie.retrieveNode Trie.getNodeReference
  cases pos
  · simp only [↓reduceIte]
    rcases RK.node o.left l hl h.left with e | hn
    · left; simp [e, bind, Except.bind]
    · right
      cases l with
      | hash => exact absurd hl (by simp [NodeRef.Resident])
      | empty =>
        simp only at hn
        refine ⟨_, _, _, Trie.empty, rfl, by rw [hn]; rfl, empty_Rep env, (empty_ok env.H).1, (empty_ok env.H).2,
          Rep_left h (show ORef.Rep env ORef.empty NodeRef.empty from trivial), fun _ => ⟨rfl, rfl⟩,
          fun h => by cases h⟩
      | node c =>
        obtain ⟨o', lh, e, hr'⟩ := hn
        have h' := hr'; unfold ORef.Rep at h'
        refine ⟨o', false, _, c, rfl, by rw [e]; rfl, h'.1, hl.1, hcl, Rep_left h hr', fun h => (by cases h),
          fun _ => ⟨rfl, fun n' hn' => ?_⟩⟩
        simp only [OTrie.writeBack, ↓reduceIte]
        exact Rep_left h (by unfold ORef.Rep; exact ⟨hn', h'.2⟩)
  · simp only [Bool.true_eq_false, ↓reduceIte]
    rcases RK.node o.right r hr h.right with e | hn
    · left; simp [e, bind, Except.bind]
    · right
      cases r with
      | hash => exact absurd hr (by simp [NodeRef.Resident])
      | empty =>
        simp only at hn
        refine ⟨_, _, _, Trie.empty, rfl, by rw [hn]; rfl, empty_Rep env, (empty_ok env.H).1, (empty_ok env.H).2,
          Rep_right h (show ORef.Rep env ORef.empty NodeRef.empty from trivial), fun _ => ⟨rfl, rfl⟩,
          fun h => by cases h⟩
      | node c =>
        obtain ⟨o', lh, e, hr'⟩ := hn
        have h' := hr'; unfold ORef.Rep at h'
        refine ⟨o', false, _, c, rfl, by rw [e]; rfl, h'.1, hr.1, hcr, Rep_right h hr', fun h => (by cases h),
          fun _ => ⟨rfl, fun n' hn' => ?_⟩⟩
        simp only [OTrie.writeBack, Bool.true_eq_false, ↓reduceIte]
        exact Rep_right h (by unfold ORef.Rep; exact ⟨hn', h'.2⟩)

/-! ## `internalPut` / `putSlice` -/

theorem _root_.RskjTrie.Trie.Resident.valueOK {t : Trie} (h : t.Resident) : ValueOK t.value t.valueLength := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t; exact h.1

structure PutOK (env : Env) (f : Nat) : Prop where
  put : ∀ o t k v d, t.Resident → t.CacheOK env.H → OTrie.Rep env o t →
    GoodP env t (t.putSlice env k v d) (OTrie.putSlice env f o k v d)
  ip : ∀ o t k v d, normValue v = v → t.Resident → t.CacheOK env.H → OTrie.Rep env o t →
    GoodP env t (t.internalPut env k v d) (OTrie.internalPut env f o k v d)

theorem putOK_zero (env : Env) : PutOK env 0 := ⟨fun _ _ _ _ _ _ _ _ => Or.inl rfl, fun _ _ _ _ _ _ _ _ _ => Or.inl rfl⟩

theorem GoodP.ok {env : Env} {t : Trie} {R : PutRes} {r : OPutRes} {o : OTrie} (h1 : RepRes env r R)
    (h2 : OTrie.Rep env o t) : GoodP env t (.ok R) (.ok (r, o)) := Or.inr (Or.inr ⟨R, r, o, rfl, rfl, h1, h2⟩)

theorem RepRes.new {env : Env} {n : OTrie} {N : Trie} (h1 : OTrie.Rep env n N) (h2 : N.Resident)
    (h3 : N.CacheOK env.H) : RepRes env (.new n) (.new N) := ⟨h1, h2, h3⟩

theorem GoodP.err {env : Env} {t : Trie} (e : Err) : GoodP env t (.error e) (.error e) := Or.inr (Or.inl ⟨e, rfl, rfl⟩)

theorem isEmptyTrieOf_Rep {env : Env} {l r : ORef OTrie} {L R : NodeRef Trie} (hl : ORef.Rep env l L)
    (hr : ORef.Rep env r R) (dl : Nat) : OTrie.isEmptyTrieOf dl l r = Trie.isEmptyTrieOf dl L R := by
  simp [OTrie.isEmptyTrieOf, Trie.isEmptyTrieOf, ORef.Rep_isEmpty hl, ORef.Rep_isEmpty hr]

theorem tailB (env : Env) {T : Trie} {o1 : OTrie} {v : Option Bytes} {dl : Nat} (hT : T.Resident)
    (hc : T.CacheOK env.H) (h1 : OTrie.Rep env o1 T) (hv : ValueOK v dl) (d u : Bool) :
    GoodP env T
      (if u = true then pure PutRes.same
       else if d = true then pure (PutRes.new ⟨T.sharedPath, none, .empty, .empty, 0, none, some 0⟩)
       else if isEmptyTrieOf dl T.left T.right = true then pure PutRes.null
       else pure (PutRes.new ⟨T.sharedPath, v, T.left, T.right, dl, none, T.childrenSize⟩))
      (if u = true then pure (OPutRes.same, o1)
       else if d = true then pure (OPutRes.new (OTrie.mk' o1.sharedPath none .empty .empty 0 none (some 0)), o1)
       else if OTrie.isEmptyTrieOf dl o1.left o1.right = true then pure (OPutRes.null, o1)
       else pure (OPutRes.new (OTrie.mk' o1.sharedPath v o1.left o1.right dl none o1.childrenSize), o1)) := by
  have hsp := h1.sp
  cases u
  · simp only [Bool.false_eq_true, ↓reduceIte]
    cases d
    · simp only [Bool.false_eq_true, ↓reduceIte, isEmptyTrieOf_Rep h1.left h1.right]
      split
      · exact GoodP.ok trivial h1
      · obtain ⟨p, tv, l, r, vl, vh, cs⟩ := T
        obtain ⟨_, hl, hr⟩ := hT
        obtain ⟨hcs, _, hcl, hcr⟩ := hc
        refine GoodP.ok ⟨Rep_mk' hsp rfl (Or.inl rfl) (fun _ => Or.inl rfl) ?_ h1.left h1.right,
          ⟨hv, hl, hr⟩, ⟨?_, fun _ _ => Or.inl rfl, hcl, hcr⟩⟩ h1
        · rcases ((OTrie.Rep_iff env o1 _).1 h1).2.2.2.2.1 with e | e
          · exact Or.inl e
          · right; rw [e, encS_snd, encS_snd]
        · rcases hcs with e | e
          · exact Or.inl e
          · right; rw [e, encS_snd, encS_snd]
    · simp only [↓reduceIte]
      refine GoodP.ok ⟨Rep_mk' hsp rfl (Or.inl rfl) (fun h => by simp at h) (Or.inr ?_) trivial trivial,
        ⟨Or.inl ⟨rfl, rfl⟩, trivial, trivial⟩, ⟨Or.inr ?_, fun _ h => by simp at h, trivial, trivial⟩⟩ h1
      all_goals simp [Trie.encS, NodeRef.isEmpty]
  · exact GoodP.ok trivial h1

theorem newD_ok (env : Env) {T : Trie} (hT : T.Resident) (hc : T.CacheOK env.H) {nl nr : NodeRef Trie}
    {cs' : Option Nat} (hnl : nl.Resident) (hnlc : nl.CacheOK env.H) (hnr : nr.Resident)
    (hnrc : nr.CacheOK env.H) (hcs : cs' = none ∨ cs' = some (kidsSize env.H nl nr)) :
    (⟨T.sharedPath, T.value, nl, nr, T.valueLength, T.valueHash, cs'⟩ : Trie).Resident ∧
      (⟨T.sharedPath, T.value, nl, nr, T.valueLength, T.valueHash, cs'⟩ : Trie).CacheOK env.H := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := T
  exact ⟨⟨hT.1, hnl, hnr⟩, ⟨by rw [encS_snd]; exact hcs, hc.2.1, hnlc, hnrc⟩⟩

theorem newD_Rep {env : Env} {t : OTrie} {T : Trie} (ht : OTrie.Rep env t T) {nl' nr' : ORef OTrie}
    {nl nr : NodeRef Trie} {ocs cs' : Option Nat} (hl : ORef.Rep env nl' nl) (hr : ORef.Rep env nr' nr)
    (hcs : ocs = none ∨ ocs = some (kidsSize env.H nl nr)) :
    OTrie.Rep env (OTrie.mk' t.sharedPath t.value nl' nr' t.valueLength t.valueHash ocs)
      ⟨T.sharedPath, T.value, nl, nr, T.valueLength, T.valueHash, cs'⟩ := by
  have h' := (OTrie.Rep_iff env t T).1 ht
  exact Rep_mk' h'.1 h'.2.1 h'.2.2.1 h'.2.2.2.1 (by rw [encS_snd]; exact hcs) hl hr

theorem _root_.RskjTrie.Trie.CacheOK.left {H : Bytes → Bytes} {t : Trie} (h : t.CacheOK H) : NodeRef.CacheOK H t.left := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t; exact h.2.2.1
theorem _root_.RskjTrie.Trie.CacheOK.right {H : Bytes → Bytes} {t : Trie} (h : t.CacheOK H) : NodeRef.CacheOK H t.right := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t; exact h.2.2.2
theorem _root_.RskjTrie.Trie.Resident.left {t : Trie} (h : t.Resident) : NodeRef.Resident t.left := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t; exact h.2.1
theorem _root_.RskjTrie.Trie.Resident.right {t : Trie} (h : t.Resident) : NodeRef.Resident t.right := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t; exact h.2.2

theorem kids_of_cs {env : Env} {t : OTrie} {T : Trie} (ht : OTrie.Rep env t T) {c : Nat}
    (hc : t.childrenSize = some c) : c = kidsSize env.H T.left T.right := by
  rcases ((OTrie.Rep_iff env t T).1 ht).2.2.2.2.1 with e | e
  · rw [hc] at e; cases e
  · rw [hc] at e; simp only [Option.some.injEq] at e; rw [e]
    obtain ⟨p, v, l, r, vl, vh, cs⟩ := T; exact encS_snd _ _ _ _ _ _ _ _

/-- The end of `internalPut`'s last branch: replace the child, update `childrenSize`. -/
theorem finishD (env : Env) (hH : ∀ x, (env.H x).length = 32) (f : Nat) {T : Trie} (hT : T.Resident)
    (hc : T.CacheOK env.H) {t2 : OTrie} (ht2 : OTrie.Rep env t2 T) {newRef : ORef OTrie} {Rp : NodeRef Trie}
    (hNR : ORef.Rep env newRef Rp) (hRr : Rp.Resident) (hRc : Rp.CacheOK env.H) (pos : Bool) :
    GoodP env T
      (do
        let __x ← replaceChild env T pos Rp
        if isEmptyTrieOf T.valueLength __x.fst __x.2.fst = true then pure PutRes.null
        else pure (PutRes.new ⟨T.sharedPath, T.value, __x.fst, __x.2.fst, T.valueLength, T.valueHash, __x.2.snd⟩))
      (if pos = false then
        match t2.childrenSize with
        | some c => do
          let __x ← ORef.referenceSize env f t2.left
          let __x_1 ← ORef.referenceSize env f newRef
          let __x ← pure (__x_1.snd, t2.right, some (wrap64 (↑c - ↑__x.fst + ↑__x_1.fst)),
                  { t2 with left := __x.snd })
          if OTrie.isEmptyTrieOf __x.2.2.snd.valueLength __x.fst __x.2.fst = true then pure (OPutRes.null, __x.2.2.snd)
          else pure (OPutRes.new (OTrie.mk' __x.2.2.snd.sharedPath __x.2.2.snd.value __x.fst __x.2.fst
            __x.2.2.snd.valueLength __x.2.2.snd.valueHash __x.2.2.fst), __x.2.2.snd)
        | none => do
          let __x ← pure (newRef, t2.right, none, t2)
          if OTrie.isEmptyTrieOf __x.2.2.snd.valueLength __x.fst __x.2.fst = true then pure (OPutRes.null, __x.2.2.snd)
          else pure (OPutRes.new (OTrie.mk' __x.2.2.snd.sharedPath __x.2.2.snd.value __x.fst __x.2.fst
            __x.2.2.snd.valueLength __x.2.2.snd.valueHash __x.2.2.fst), __x.2.2.snd)
      else
        match t2.childrenSize with
        | some c => do
          let __x ← ORef.referenceSize env f t2.right
          let __x_1 ← ORef.referenceSize env f newRef
          let __x ← pure (t2.left, __x_1.snd, some (wrap64 (↑c - ↑__x.fst + ↑__x_1.fst)),
                  { t2 with right := __x.snd })
          if OTrie.isEmptyTrieOf __x.2.2.snd.valueLength __x.fst __x.2.fst = true then pure (OPutRes.null, __x.2.2.snd)
          else pure (OPutRes.new (OTrie.mk' __x.2.2.snd.sharedPath __x.2.2.snd.value __x.fst __x.2.fst
            __x.2.2.snd.valueLength __x.2.2.snd.valueHash __x.2.2.fst), __x.2.2.snd)
        | none => do
          let __x ← pure (t2.left, newRef, none, t2)
          if OTrie.isEmptyTrieOf __x.2.2.snd.valueLength __x.fst __x.2.fst = true then pure (OPutRes.null, __x.2.2.snd)
          else pure (OPutRes.new (OTrie.mk' __x.2.2.snd.sharedPath __x.2.2.snd.value __x.fst __x.2.fst
            __x.2.2.snd.valueLength __x.2.2.snd.valueHash __x.2.2.fst), __x.2.2.snd)) := by
  have RK := readOK env hH f
  obtain ⟨nl, nr, cs', e, hshape, hcs'⟩ := replaceChild_spec env T hT hc pos Rp hRr hRc
  rw [e]
  simp only [except_bind_ok]
  have hvl := ht2.vl
  cases pos
  · simp only [↓reduceIte] at hshape ⊢
    obtain ⟨rfl, rfl⟩ := hshape
    obtain ⟨hres, hcache⟩ := newD_ok env hT hc hRr hRc hT.right hc.right hcs'
    cases hcs2 : t2.childrenSize with
    | none =>
      have hE : OTrie.isEmptyTrieOf t2.valueLength newRef t2.right = isEmptyTrieOf T.valueLength nl T.right := by
        rw [hvl, isEmptyTrieOf_Rep hNR ht2.right]
      simp only [except_bind_ok, except_pure, hE]
      split
      · exact GoodP.ok (show RepRes env .null .null from trivial) ht2
      · exact GoodP.ok (RepRes.new (newD_Rep ht2 hNR ht2.right (Or.inl rfl)) hres hcache) ht2
    | some c =>
      simp only
      refine GoodR.bind (RK.rsize _ _ hT.left ht2.left) (Or.inl rfl) (fun l' hl' => ?_)
      refine GoodR.bind (RK.rsize _ _ hRr hNR) (Or.inl rfl) (fun r' hr' => ?_)
      have ht3 := Rep_left ht2 hl'
      rw [hcs2] at ht3
      have hE : OTrie.isEmptyTrieOf t2.valueLength r' t2.right = isEmptyTrieOf T.valueLength nl T.right := by
        rw [hvl, isEmptyTrieOf_Rep hr' ht2.right]
      simp only [except_bind_ok, except_pure, hE]
      split
      · exact GoodP.ok (show RepRes env .null .null from trivial) ht3
      · refine GoodP.ok (RepRes.new (newD_Rep ht3 hr' ht2.right (Or.inr ?_)) hres hcache) ht3
        rw [kids_of_cs ht2 hcs2, kidsSize_update_left env.H _ _ _ hT.left hRr hT.right]
  · simp only [Bool.true_eq_false, ↓reduceIte] at hshape ⊢
    obtain ⟨rfl, rfl⟩ := hshape
    obtain ⟨hres, hcache⟩ := newD_ok env hT hc hT.left hc.left hRr hRc hcs'
    cases hcs2 : t2.childrenSize with
    | none =>
      have hE : OTrie.isEmptyTrieOf t2.valueLength t2.left newRef = isEmptyTrieOf T.valueLength T.left nr := by
        rw [hvl, isEmptyTrieOf_Rep ht2.left hNR]
      simp only [except_bind_ok, except_pure, hE]
      split
      · exact GoodP.ok (show RepRes env .null .null from trivial) ht2
      · exact GoodP.ok (RepRes.new (newD_Rep ht2 ht2.left hNR (Or.inl rfl)) hres hcache) ht2
    | some c =>
      simp only
      refine GoodR.bind (RK.rsize _ _ hT.right ht2.right) (Or.inl rfl) (fun l' hl' => ?_)
      refine GoodR.bind (RK.rsize _ _ hRr hNR) (Or.inl rfl) (fun r' hr' => ?_)
      have ht3 := Rep_right ht2 hl'
      rw [hcs2] at ht3
      have hE : OTrie.isEmptyTrieOf t2.valueLength t2.left r' = isEmptyTrieOf T.valueLength T.left nr := by
        rw [hvl, isEmptyTrieOf_Rep ht2.left hr']
      simp only [except_bind_ok, except_pure, hE]
      split
      · exact GoodP.ok (show RepRes env .null .null from trivial) ht3
      · refine GoodP.ok (RepRes.new (newD_Rep ht3 ht2.left hr' (Or.inr ?_)) hres hcache) ht3
        rw [kids_of_cs ht2 hcs2, kidsSize_update_right env.H _ _ _ hT.left hT.right hRr]

theorem step_ip (env : Env) (hH : ∀ x, (env.H x).length = 32) (f : Nat) (IH : PutOK env f) (o : OTrie) (T : Trie)
    (k : TrieKeySlice) (v : Option Bytes) (d : Bool) (hn : normValue v = v) (hT : T.Resident)
    (hc : T.CacheOK env.H) (h : OTrie.Rep env o T) :
    GoodP env T (T.internalPut env k v d) (OTrie.internalPut env (f + 1) o k v d) := by
  have hsp := h.sp
  have hvl := h.vl
  have c1 : o.sharedPath.length = T.sharedPath.length := by rw [hsp]
  have c2 : k.commonPath o.sharedPath = k.commonPath T.sharedPath := by rw [hsp]
  simp only [OTrie.internalPut, c1, c2]
  rw [Trie.internalPut]
  by_cases hsplit : (k.commonPath T.sharedPath).length < T.sharedPath.length
  · simp only [hsplit, ↓reduceIte, ↓reduceDIte]
    cases hvn : v.isNone
    · simp only [Bool.false_eq_true, ↓reduceIte]
      rcases split_Rep' env hH f o T hT hc h (k.commonPath T.sharedPath) with e | ⟨⟨s1, hs1⟩, os, pe, oe, hos, hs1r, hs1c⟩
      · left; simp only [e, bind, Except.bind]
      rw [pe, oe]
      simp only [except_bind_ok]
      rcases IH.put os s1 k v d hs1r hs1c hos with e | ⟨e, pe2, oe2⟩ | ⟨R, rr, o', pe2, oe2, hRR, ho'⟩
      · left; simp only [e, bind, Except.bind]
      · rw [pe2, oe2]; exact GoodP.err e
      · rw [pe2, oe2]
        simp only [except_bind_ok]
        cases rr <;> cases R <;> simp only [RepRes] at hRR
        · exact GoodP.ok (show RepRes env (.new o') (.new s1) from ⟨ho', hs1r, hs1c⟩) h
        · exact GoodP.ok trivial h
        · exact GoodP.ok hRR h
    · exact GoodP.ok trivial h
  · simp only [hsplit, ↓reduceIte, ↓reduceDIte]
    by_cases hB : T.sharedPath.length ≥ k.length
    · simp only [hB, ↓reduceIte]
      cases hdl : getDataLength v with
      | error e => exact GoodP.err e
      | ok dl =>
        simp only [except_bind_ok]
        have hvok := getDataLength_ok hn hdl
        by_cases hd : T.valueLength = dl
        · obtain ⟨o1, e1, h1⟩ := getValue_Rep env o T hT h
          simp only [hvl, hd, ↓reduceIte, e1, except_bind_ok, except_map_ok, except_pure,
            Trie.getValue_resident env T (Trie.Resident.valueOK hT)]
          exact tailB env hT hc h1 hvok d _
        · simp only [hvl, hd, ↓reduceIte, except_bind_ok, except_pure]
          exact tailB env hT hc h hvok d _
    · simp only [hB, ↓reduceIte, OTrie.Rep_isEmptyTrie h]
      by_cases hE : T.isEmptyTrie = true
      · simp only [hE, ↓reduceIte]
        unfold leaf
        cases hdl : getDataLength v with
        | error e => exact GoodP.err e
        | ok dl =>
          simp only [except_bind_ok, except_pure, except_map_ok]
          refine GoodP.ok ⟨Rep_mk' rfl rfl (Or.inl rfl) (fun _ => Or.inl rfl) (Or.inr ?_) trivial trivial,
            ⟨getDataLength_ok hn hdl, trivial, trivial⟩, ⟨Or.inr ?_, fun _ _ => Or.inl rfl, trivial, trivial⟩⟩ h
          all_goals simp [Trie.encS, NodeRef.isEmpty]
      · simp only [Bool.not_eq_true] at hE
        simp only [hE, Bool.false_eq_true, ↓reduceIte]
        generalize hpos : k.get T.sharedPath.length = pos
        rcases rne_Rep env hH f o T hT hc h pos with e | ⟨n, fresh, o1, N, pe, oe, hn1, hNr, hNc, ho1, hfr, hnfr⟩
        · left; simp only [e, bind, Except.bind]
        rw [pe, oe]
        simp only [except_bind_ok]
        have c3 : o1.sharedPath.length = T.sharedPath.length := by rw [ho1.sp]
        simp only [c3]
        rcases IH.put n N (k.slice (T.sharedPath.length + 1) k.length) v d hNr hNc hn1 with
          e | ⟨e, pe2, oe2⟩ | ⟨R, nn, n', pe2, oe2, hRR, hn'⟩
        · left; simp only [e, bind, Except.bind]
        · rw [pe2, oe2]; exact GoodP.err e
        rw [pe2, oe2]
        simp only [except_bind_ok]
        have ht2 : OTrie.Rep env (if fresh = true then o1 else o1.writeBack pos n') T := by
          cases fresh
          · exact (hnfr rfl).2 n' hn'
          · exact ho1
        generalize (if fresh = true then o1 else o1.writeBack pos n') = t2 at ht2 ⊢
        have RK := readOK env hH f
        cases nn <;> cases R <;> simp only [RepRes] at hRR
        · exact GoodP.ok trivial ht2
        all_goals simp only [OPutRes.isSame, PutRes.isSame, Bool.false_eq_true, ↓reduceIte]
        · -- `null` result: the child disappears
          have hNR : ORef.Rep env (ORef.ofNode (OPutRes.null.toOpt)) (NodeRef.ofNode (PutRes.null.toOpt)) := trivial
          have hRp : (NodeRef.ofNode (PutRes.null.toOpt)).Resident ∧ (NodeRef.ofNode (PutRes.null.toOpt)).CacheOK env.H :=
            ⟨trivial, trivial⟩
          exact finishD env hH f hT hc ht2 hNR hRp.1 hRp.2 pos
        · rename_i n2 N2
          have hNR : ORef.Rep env (ORef.ofNode (OPutRes.new n2).toOpt) (NodeRef.ofNode (PutRes.new N2).toOpt) :=
            ORef.Rep_ofNode hRR.1
          have hRp := NodeRef.ofNode_ok env.H N2 hRR.2.1 hRR.2.2
          exact finishD env hH f hT hc ht2 hNR hRp.1 hRp.2 pos

/-- A node coalesced with its only child (`put`'s delete path, Trie.java:807-820) is represented. -/
theorem coalesced_Rep (env : Env) {c' : OTrie} {c : Trie} (h : OTrie.Rep env c' c) (hr : c.Resident)
    (hcc : c.CacheOK env.H) (sp : TrieKeySlice) (b : Bool) :
    OTrie.Rep env (OTrie.mk' (sp.rebuildSharedPath b c'.sharedPath) c'.value c'.left c'.right c'.valueLength
      c'.valueHash c'.childrenSize) ⟨sp.rebuildSharedPath b c.sharedPath, c.value, c.left, c.right, c.valueLength,
        c.valueHash, c.childrenSize⟩ ∧
    (⟨sp.rebuildSharedPath b c.sharedPath, c.value, c.left, c.right, c.valueLength, c.valueHash,
      c.childrenSize⟩ : Trie).Resident ∧
    (⟨sp.rebuildSharedPath b c.sharedPath, c.value, c.left, c.right, c.valueLength, c.valueHash,
      c.childrenSize⟩ : Trie).CacheOK env.H := by
  have h' := (OTrie.Rep_iff env c' c).1 h
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := c
  refine ⟨Rep_mk' (by rw [h'.1]) h'.2.1 h'.2.2.1 h'.2.2.2.1 ?_ h'.2.2.2.2.2.2.2.1 h'.2.2.2.2.2.2.2.2, hr, ?_⟩
  · rcases h'.2.2.2.2.1 with e | e
    · exact Or.inl e
    · right; rw [e, encS_snd, encS_snd]
  · obtain ⟨hcs, hvh, hcl, hcr⟩ := hcc
    refine ⟨?_, hvh, hcl, hcr⟩
    rcases hcs with e | e
    · exact Or.inl e
    · right; rw [e, encS_snd, encS_snd]

theorem coal (env : Env) (hH : ∀ x, (env.H x).length = 32) (f : Nat) {T TR : Trie} {o1 tr : OTrie}
    {r : OPutRes} {R : PutRes} (ho1 : OTrie.Rep env o1 T) (htr : OTrie.Rep env tr TR) (hTR : TR.Resident)
    (hTRc : TR.CacheOK env.H) (hRR : RepRes env r R) :
    GoodP env T (TR.coalesce env R)
      (if tr.isEmptyTrie = true then pure (OPutRes.null, o1)
       else if tr.valueLength > 0 then pure (r, o1)
       else if (tr.left.isEmpty == tr.right.isEmpty) = true then pure (r, o1)
       else do
        let __x ← if (!tr.left.isEmpty) = true then do
            let __x ← ORef.getNode env f tr.left
            pure (__x.fst, false)
          else do
            let __x ← ORef.getNode env f tr.right
            pure (__x.fst, true)
        match __x.fst with
        | none => throw "System.exit(1): Broken database, execution can't continue"
        | some child =>
          pure (OPutRes.new (OTrie.mk' (tr.sharedPath.rebuildSharedPath __x.snd child.sharedPath) child.value
            child.left child.right child.valueLength child.valueHash child.childrenSize), o1)) := by
  have RK := readOK env hH f
  unfold Trie.coalesce
  simp only [OTrie.Rep_isEmptyTrie htr, htr.vl, ORef.Rep_isEmpty htr.left, ORef.Rep_isEmpty htr.right, htr.sp]
  by_cases h1 : TR.isEmptyTrie = true
  · simp only [h1, ↓reduceIte]; exact GoodP.ok (show RepRes env .null .null from trivial) ho1
  simp only [h1, Bool.false_eq_true, ↓reduceIte]
  by_cases h2 : TR.valueLength > 0
  · simp only [h2, ↓reduceIte]; exact GoodP.ok hRR ho1
  simp only [h2, ↓reduceIte]
  by_cases h3 : (TR.left.isEmpty == TR.right.isEmpty) = true
  · simp only [h3, ↓reduceIte]; exact GoodP.ok hRR ho1
  simp only [h3, Bool.false_eq_true, ↓reduceIte]
  by_cases h4 : (!TR.left.isEmpty) = true
  · simp only [h4, ↓reduceIte]
    rcases RK.node tr.left TR.left hTR.left htr.left with e | hn
    · left; simp only [e, bind, Except.bind]
    obtain ⟨p, v, l, rr, vl, vh, cs⟩ := TR
    cases l with
    | empty => simp [NodeRef.isEmpty] at h4
    | hash => exact absurd hTR.2.1 (by simp [NodeRef.Resident])
    | node c =>
      obtain ⟨c', lh, e, hr'⟩ := hn
      have h' := hr'; unfold ORef.Rep at h'
      rw [e]
      simp only [NodeRef.getNode, except_bind_ok, except_pure]
      obtain ⟨a1, a2, a3⟩ := coalesced_Rep env h'.1 hTR.2.1.1 hTRc.2.2.1 p false
      exact GoodP.ok (RepRes.new a1 a2 a3) ho1
  · simp only [h4, Bool.false_eq_true, ↓reduceIte]
    rcases RK.node tr.right TR.right hTR.right htr.right with e | hn
    · left; simp only [e, bind, Except.bind]
    obtain ⟨p, v, l, rr, vl, vh, cs⟩ := TR
    cases rr with
    | empty => exfalso; revert h3 h4; cases l <;> simp [NodeRef.isEmpty]
    | hash => exact absurd hTR.2.2 (by simp [NodeRef.Resident])
    | node c =>
      obtain ⟨c', lh, e, hr'⟩ := hn
      have h' := hr'; unfold ORef.Rep at h'
      rw [e]
      simp only [NodeRef.getNode, except_bind_ok, except_pure]
      obtain ⟨a1, a2, a3⟩ := coalesced_Rep env h'.1 hTR.2.2.1 hTRc.2.2.2 p true
      exact GoodP.ok (RepRes.new a1 a2 a3) ho1

theorem step_put (env : Env) (hH : ∀ x, (env.H x).length = 32) (f : Nat) (IH : PutOK env f) (o : OTrie)
    (T : Trie) (k : TrieKeySlice) (v : Option Bytes) (d : Bool) (hT : T.Resident) (hc : T.CacheOK env.H)
    (h : OTrie.Rep env o T) : GoodP env T (T.putSlice env k v d) (OTrie.putSlice env (f + 1) o k v d) := by
  simp only [OTrie.putSlice]
  rw [Trie.putSlice]
  rcases IH.ip o T k (normValue v) d (normValue_idem v) hT hc h with
    e | ⟨e, pe, oe⟩ | ⟨R, r, o1, pe, oe, hRR, ho1⟩
  · left; simp only [e, bind, Except.bind]
  · rw [pe, oe]; exact GoodP.err e
  rw [pe, oe]
  simp only [except_bind_ok]
  cases r <;> cases R <;> simp only [RepRes] at hRR
  · simp only [except_pure, except_bind_ok]
    by_cases hs : (normValue v).isSome = true
    · simp only [hs, ↓reduceIte]; exact GoodP.ok trivial ho1
    · simp only [hs, Bool.false_eq_true, ↓reduceIte]
      exact coal env hH f ho1 ho1 hT hc (show RepRes env .same .same from trivial)
  · exact GoodP.ok trivial ho1
  · rename_i n N
    simp only [except_pure, except_bind_ok]
    by_cases hs : (normValue v).isSome = true
    · simp only [hs, ↓reduceIte]; exact GoodP.ok hRR ho1
    · simp only [hs, Bool.false_eq_true, ↓reduceIte]
      exact coal env hH f ho1 hRR.1 hRR.2.1 hRR.2.2 hRR

/-- **Put bridge**: at every fuel, the operational `putSlice`/`internalPut` on a represented
object of a resident, cache-consistent trie simulate the pure ones. -/
theorem putOK (env : Env) (hH : ∀ x, (env.H x).length = 32) : ∀ f, PutOK env f
  | 0 => putOK_zero env
  | f + 1 =>
    have IH := putOK env hH f
    ⟨step_put env hH f IH, step_ip env hH f IH⟩

/-! ## Top-level bridge theorems -/

/-- The outcome of an operational update against the pure one. -/
def Agree (env : Env) (pr : Except Err Trie) (res : Except Err OTrie) : Prop :=
  res = .error "fuel" ∨ (∃ e, pr = .error e ∧ res = .error e) ∨
  ∃ o T, pr = .ok T ∧ res = .ok o ∧ OTrie.Rep env o T ∧ T.Resident ∧ T.CacheOK env.H

theorem finish_put (env : Env) {T : Trie} (hT : T.Resident) (hc : T.CacheOK env.H)
    {pr : Except Err PutRes} {res : Except Err (OPutRes × OTrie)} (hg : GoodP env T pr res) :
    Agree env (do match ← pr with | .same => pure T | .null => pure Trie.empty | .new n => pure n)
      (do let (r, t) ← res; match r with | .same => pure t | .null => pure OTrie.empty | .new n => pure n) := by
  rcases hg with e | ⟨e, pe, oe⟩ | ⟨R, r, o1, pe, oe, hRR, ho1⟩
  · left; simp only [e, bind, Except.bind]
  · rw [pe, oe]; exact Or.inr (Or.inl ⟨e, rfl, rfl⟩)
  · rw [pe, oe]
    right; right
    cases r <;> cases R <;> simp only [RepRes] at hRR
    · exact ⟨o1, T, rfl, rfl, ho1, hT, hc⟩
    · exact ⟨OTrie.empty, Trie.empty, rfl, rfl, empty_Rep env, (empty_ok env.H).1, (empty_ok env.H).2⟩
    · exact ⟨_, _, rfl, rfl, hRR⟩

/-- **put / delete / deleteRecursive bridge** on one operation. -/
theorem put_bridge (env : Env) (hH : ∀ x, (env.H x).length = 32) (o : OTrie) (T : Trie) (hT : T.Resident)
    (hc : T.CacheOK env.H) (h : OTrie.Rep env o T) (key : Bytes) (v : Option Bytes) :
    Agree env (T.put env key v) (o.put env key v) ∧ Agree env (T.delete env key) (o.delete env key) ∧
    Agree env (T.deleteRecursive env key) (o.deleteRecursive env key) := by
  refine ⟨?_, ?_, ?_⟩
  · unfold OTrie.put Trie.put
    exact finish_put env hT hc ((putOK env hH OFUEL).put o T _ v false hT hc h)
  · unfold OTrie.delete Trie.delete OTrie.put Trie.put
    exact finish_put env hT hc ((putOK env hH OFUEL).put o T _ none false hT hc h)
  · unfold OTrie.deleteRecursive Trie.deleteRecursive
    exact finish_put env hT hc ((putOK env hH OFUEL).put o T _ none true hT hc h)

/-- One `put`/`delete` operation on the operational layer. -/
def orun (env : Env) (t : OTrie) : RskjTrie.Op → Except Err OTrie
  | .put k v => t.put env k v
  | .delete k => t.delete env k

def orunOps (env : Env) : OTrie → List RskjTrie.Op → Except Err OTrie
  | t, [] => .ok t
  | t, op :: ops => do orunOps env (← orun env t op) ops

theorem orunOps_bridge (env : Env) (hH : ∀ x, (env.H x).length = 32) :
    ∀ (ops : List RskjTrie.Op) (o : OTrie) (T : Trie), T.Resident → T.CacheOK env.H → OTrie.Rep env o T →
      ∀ o', orunOps env o ops = .ok o' →
        ∃ T', runOps env T ops = .ok T' ∧ OTrie.Rep env o' T' ∧ T'.Resident ∧ T'.CacheOK env.H
  | [], o, T, hT, hc, h, o', e => by cases e; exact ⟨T, rfl, h, hT, hc⟩
  | op :: ops, o, T, hT, hc, h, o', e => by
    have hag : Agree env (op.run env T) (orun env o op) := by
      cases op with
      | put k v => exact (put_bridge env hH o T hT hc h k v).1
      | delete k => exact (put_bridge env hH o T hT hc h k none).2.1
    simp only [orunOps, bind, Except.bind] at e
    rcases hag with e1 | ⟨e2, _, oe⟩ | ⟨o1, T1, pe, oe, h1, hT1, hc1⟩
    · rw [e1] at e; cases e
    · rw [oe] at e; cases e
    · rw [oe] at e
      obtain ⟨T', e', h'⟩ := orunOps_bridge env hH ops o1 T1 hT1 hc1 h1 o' e
      refine ⟨T', ?_, h'⟩
      simp only [runOps, pe, bind, Except.bind, e']

/-- **Reads agree** on a represented object: `getHash()`, `toMessage()` and `get(k)` of the
operational layer return what the pure encoder / contents give (unless out of fuel). -/
theorem reads_agree (env : Env) (hH : ∀ x, (env.H x).length = 32) (o : OTrie) (t : Trie) (ht : t.Resident)
    (h : OTrie.Rep env o t) :
    (∀ hsh o', o.hashOf env = .ok (hsh, o') → hsh = t.hashS env.H ∧ OTrie.Rep env o' t) ∧
    (∀ m o', o.messageOf env = .ok (m, o') → m = (t.encS env.H).1 ∧ OTrie.Rep env o' t) ∧
    (∀ key v o', o.get env key = .ok (v, o') → v = t.contents (TrieKeySlice.fromKey key) ∧ OTrie.Rep env o' t) := by
  have RK := readOK env hH OFUEL
  refine ⟨fun hsh o' e => ?_, fun m o' e => ?_, fun key v o' e => ?_⟩
  · rcases RK.hash o t ht h with e' | ⟨o2, e', h2⟩ <;> rw [OTrie.hashOf, e'] at e <;> cases e
    exact ⟨rfl, h2⟩
  · rcases RK.msg o t ht h with e' | ⟨o2, e', h2⟩ <;> rw [OTrie.messageOf, e'] at e <;> cases e
    exact ⟨rfl, h2⟩
  · rcases getRec_Rep env hH OFUEL o t (TrieKeySlice.fromKey key) ht h with e' | ⟨o2, e', h2⟩ <;>
      rw [OTrie.get, e'] at e <;> cases e
    exact ⟨rfl, h2⟩

/-- **Bridge for tries built by put/delete**: running a sequence of `put`/`delete` operations
from `new Trie()` on the operational layer, if it succeeds, gives an object representing the pure
result, and its `getHash()`, `toMessage()` and `get(k)` equal the pure layer's. -/
theorem ops_bridge (env : Env) (hH : ∀ x, (env.H x).length = 32) (ops : List RskjTrie.Op) (o : OTrie)
    (e : orunOps env OTrie.empty ops = .ok o) :
    ∃ t, runOps env Trie.empty ops = .ok t ∧ OTrie.Rep env o t ∧
      (∀ hsh o', o.hashOf env = .ok (hsh, o') → t.getHash env = .ok hsh) ∧
      (∀ m o', o.messageOf env = .ok (m, o') → t.toMessage env = .ok m) ∧
      (∀ key v o', o.get env key = .ok (v, o') → t.get env key = .ok v) := by
  obtain ⟨t, e1, h, hres, hc⟩ := orunOps_bridge env hH ops OTrie.empty Trie.empty (empty_ok env.H).1
    (empty_ok env.H).2 (empty_Rep env) o e
  obtain ⟨r1, r2, r3⟩ := reads_agree env hH o t hres h
  refine ⟨t, e1, h, fun hsh o' e => ?_, fun m o' e => ?_, fun key v o' e => ?_⟩
  · rw [(r1 hsh o' e).1]; exact (Trie.encOK env t hres hc FUEL).2.2.2.1
  · rw [(r2 m o' e).1, Trie.toMessage]; exact (Trie.encOK env t hres hc FUEL).2.1
  · rw [(r3 key v o' e).1]; exact Trie.get_eq_contents env t hres key

/-- **Bridge for tries loaded from a store written by `save`**: after the pure `save` of a
well-formed non-empty trie `t`, the operational `retrieve(hash)` yields an object representing `t`;
so its reads equal the pure reads of the retrieved node (`Trie.save_retrieve`), and operational
`put`/`delete` on it simulate the pure ones on `t` (`put_bridge`). -/
theorem retrieve_bridge (H : Bytes → Bytes) (hH : ∀ x, (H x).length = 32) (db : DB) (t : Trie)
    (hwf : t.WF H) (hp : t.PathsOK) (hne : t.isEmptyTrie = false) (hinj : InjOn H (t.vals H)) :
    ∃ db' o, TrieStoreImpl.save H db t = .ok db' ∧ Op.retrieve ⟨H, db'⟩ (t.hashS H) = .ok (some o) ∧
      OTrie.Rep ⟨H, db'⟩ o t ∧
      (∀ hsh o', o.hashOf ⟨H, db'⟩ = .ok (hsh, o') → (t.reparse H).getHash ⟨H, db'⟩ = .ok hsh) ∧
      (∀ m o', o.messageOf ⟨H, db'⟩ = .ok (m, o') → (t.reparse H).toMessage ⟨H, db'⟩ = .ok m) ∧
      (∀ key v o', o.get ⟨H, db'⟩ key = .ok (v, o') → (t.reparse H).get ⟨H, db'⟩ key = .ok v) := by
  obtain ⟨hres, hc, _⟩ := hwf
  obtain ⟨db', h1, _, hs, hw⟩ := Trie.saveRec_spec H (t.vals H) hinj t db true hres hc hne (fun x hx => hx)
  have hroot : db' (t.hashS H) = some (t.encS H).1 := by rw [Trie.hashS_nonempty H t hne]; exact hw (Or.inl rfl)
  have hparse := fromMessage_encS ⟨H, db'⟩ hH t hres hp
  have hrep : OTrie.Rep ⟨H, db'⟩ { ofPure (t.reparse H) with saved := true } t :=
    Rep_saved (ofPure_reparse_Rep ⟨H, db'⟩ t hres hs hp) true
  have hg : ∀ key, (t.reparse H).get ⟨H, db'⟩ key = .ok (t.contents (TrieKeySlice.fromKey key)) :=
    fun key => Trie.get_reparse ⟨H, db'⟩ hH t hres hc hp hs _
  have hm : (t.reparse H).toMessage ⟨H, db'⟩ = .ok (t.encS H).1 := ((Trie.reEnc ⟨H, db'⟩ t hres) FUEL).2.1
  have hh : (t.reparse H).getHash ⟨H, db'⟩ = .ok (t.hashS H) := Trie.getHash_reparse ⟨H, db'⟩ t hres
  obtain ⟨r1, r2, r3⟩ := reads_agree ⟨H, db'⟩ hH _ t hres hrep
  refine ⟨db', _, h1, ?_, hrep, fun hsh o' e => ?_, fun m o' e => ?_, fun key v o' e => ?_⟩
  · simp only [Op.retrieve, hroot, hparse, bind, Except.bind, pure, Except.pure]
  · rw [hh, (r1 hsh o' e).1]
  · rw [hm, (r2 m o' e).1]
  · rw [hg, (r3 key v o' e).1]

end RskjTrie.Op
