import RskjTrie.Operational
import RskjTrie.Proofs.Store
/-!
# Bridge: the operational (cache-faithful) layer against the pure layer

`OTrie.Rep env o t` says that the operational object `o` (with Java's caches) *represents* the
resident pure trie `t`:

* same shared path and value length; the value is `t`'s, or (long value only) not yet loaded, in
  which case the store holds it under `valueHash = H(value)`;
* every cache (`valueHash` of a node with a value, `childrenSize`, `hash`, `encoded`, `lazyHash`)
  is unset or holds the value the pure encoder computes for `t`;
* a child is either represented by an operational child, or is a hash reference to a child `c`
  that is *not embeddable* and whose message (and everything below it) is in the store
  (`Stored`) — the situation after `TrieStoreImpl.save` (TRIE-HASH-04 is exactly a hash reference
  to an embeddable child, which `Rep` excludes).

Tries built by `put`/`delete` from `new Trie()` are represented by their operational objects with no
hash references (`ofPure_Rep`); a trie retrieved from a store written by `save` is represented by
the pure trie that was saved (`retrieve_Rep`). On represented objects every operational read
returns the pure value (or runs out of fuel) and leaves the object represented (`readOK`).
-/
namespace RskjTrie.Op
open RskjTrie Trie

set_option linter.unusedSimpArgs false

/-- A child stored by hash: its message is in the store under its hash, everything below it is
saved (`Trie.Saved`), and it can be parsed back (`PathsOK`, non-empty). -/
def Stored (env : Env) (c : Trie) : Prop :=
  env.db (Trie.hashS env.H c) = some (Trie.encS env.H c).1 ∧ Trie.Saved env.H env.db c ∧ c.PathsOK ∧
    c.isEmptyTrie = false

mutual
def OTrie.Rep (env : Env) : OTrie → Trie → Prop
  | ⟨p, v, l, r, vl, vh, cs, hc, enc, _⟩, ⟨p', v', l', r', vl', vh', cs'⟩ =>
    p = p' ∧ vl = vl' ∧
    (v = v' ∨ (vl' > 32 ∧ v = none ∧ vh = some (env.H (v'.getD [])) ∧
      env.db (env.H (v'.getD [])) = some (v'.getD []))) ∧
    (vl' > 0 → vh = none ∨ vh = some (env.H (v'.getD []))) ∧
    (cs = none ∨ cs = some (Trie.encS env.H ⟨p', v', l', r', vl', vh', cs'⟩).2) ∧
    (hc = none ∨ hc = some (Trie.hashS env.H ⟨p', v', l', r', vl', vh', cs'⟩)) ∧
    (enc = none ∨ enc = some (Trie.encS env.H ⟨p', v', l', r', vl', vh', cs'⟩).1) ∧
    ORef.Rep env l l' ∧ ORef.Rep env r r'
def ORef.Rep (env : Env) : ORef OTrie → NodeRef Trie → Prop
  | .empty, .empty => True
  | .hash h, .node c => h = Trie.hashS env.H c ∧ (NodeRef.encS env.H (.node c)).2.2 = false ∧ Stored env c
  | .node o lh, .node c => OTrie.Rep env o c ∧ (lh = none ∨ lh = some (Trie.hashS env.H c))
  | _, _ => False
end

/-- `Rep` with projections (for updated objects `{ o with … }`). -/
theorem OTrie.Rep_iff (env : Env) (o : OTrie) (t : Trie) : OTrie.Rep env o t ↔
    o.sharedPath = t.sharedPath ∧ o.valueLength = t.valueLength ∧
    (o.value = t.value ∨ (t.valueLength > 32 ∧ o.value = none ∧ o.valueHash = some (env.H (t.value.getD [])) ∧
      env.db (env.H (t.value.getD [])) = some (t.value.getD []))) ∧
    (t.valueLength > 0 → o.valueHash = none ∨ o.valueHash = some (env.H (t.value.getD []))) ∧
    (o.childrenSize = none ∨ o.childrenSize = some (Trie.encS env.H t).2) ∧
    (o.hash = none ∨ o.hash = some (Trie.hashS env.H t)) ∧
    (o.encoded = none ∨ o.encoded = some (Trie.encS env.H t).1) ∧
    ORef.Rep env o.left t.left ∧ ORef.Rep env o.right t.right := by
  obtain ⟨p, v, l, r, vl, vh, cs, hc, enc, sv⟩ := o
  obtain ⟨p', v', l', r', vl', vh', cs'⟩ := t
  simp only [OTrie.Rep]

/-! ## Structural facts -/

theorem ORef.Rep_isEmpty {env : Env} {r : ORef OTrie} {R : NodeRef Trie} (h : ORef.Rep env r R) :
    r.isEmpty = R.isEmpty := by
  cases r <;> cases R <;> simp_all [ORef.Rep, ORef.isEmpty, NodeRef.isEmpty]

theorem OTrie.Rep_isTerminal {env : Env} {o : OTrie} {t : Trie} (h : OTrie.Rep env o t) :
    o.isTerminal = t.isTerminal := by
  rw [OTrie.Rep_iff] at h
  simp [OTrie.isTerminal, Trie.isTerminal, ORef.Rep_isEmpty h.2.2.2.2.2.2.2.1, ORef.Rep_isEmpty h.2.2.2.2.2.2.2.2]

theorem OTrie.Rep_isEmptyTrie {env : Env} {o : OTrie} {t : Trie} (h : OTrie.Rep env o t) :
    o.isEmptyTrie = t.isEmptyTrie := by
  rw [OTrie.Rep_iff] at h
  simp [OTrie.isEmptyTrie, OTrie.isEmptyTrieOf, Trie.isEmptyTrie, Trie.isEmptyTrieOf, h.2.1,
    ORef.Rep_isEmpty h.2.2.2.2.2.2.2.1, ORef.Rep_isEmpty h.2.2.2.2.2.2.2.2]

/-! ## Updating a represented object -/

section update
variable {env : Env} {o : OTrie} {t : Trie}

theorem Rep_left (h : OTrie.Rep env o t) {l : ORef OTrie} (hl : ORef.Rep env l t.left) :
    OTrie.Rep env { o with left := l } t := by
  rw [OTrie.Rep_iff] at h ⊢; exact ⟨h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2.1, hl,
    h.2.2.2.2.2.2.2.2⟩

theorem Rep_right (h : OTrie.Rep env o t) {r : ORef OTrie} (hr : ORef.Rep env r t.right) :
    OTrie.Rep env { o with right := r } t := by
  rw [OTrie.Rep_iff] at h ⊢; exact ⟨h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, h.2.2.2.2.2.2.1,
    h.2.2.2.2.2.2.2.1, hr⟩

theorem Rep_cs (h : OTrie.Rep env o t) : OTrie.Rep env { o with childrenSize := some (Trie.encS env.H t).2 } t := by
  rw [OTrie.Rep_iff] at h ⊢; exact ⟨h.1, h.2.1, h.2.2.1, h.2.2.2.1, Or.inr rfl, h.2.2.2.2.2⟩

theorem Rep_hash (h : OTrie.Rep env o t) : OTrie.Rep env { o with hash := some (Trie.hashS env.H t) } t := by
  rw [OTrie.Rep_iff] at h ⊢; exact ⟨h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, Or.inr rfl, h.2.2.2.2.2.2⟩

theorem Rep_enc (h : OTrie.Rep env o t) : OTrie.Rep env { o with encoded := some (Trie.encS env.H t).1 } t := by
  rw [OTrie.Rep_iff] at h ⊢; exact ⟨h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1, h.2.2.2.2.2.1, Or.inr rfl,
    h.2.2.2.2.2.2.2⟩

end update

theorem OTrie.Rep.left {env : Env} {o : OTrie} {t : Trie} (h : OTrie.Rep env o t) : ORef.Rep env o.left t.left :=
  ((OTrie.Rep_iff env o t).1 h).2.2.2.2.2.2.2.1
theorem OTrie.Rep.right {env : Env} {o : OTrie} {t : Trie} (h : OTrie.Rep env o t) : ORef.Rep env o.right t.right :=
  ((OTrie.Rep_iff env o t).1 h).2.2.2.2.2.2.2.2
theorem OTrie.Rep.sp {env : Env} {o : OTrie} {t : Trie} (h : OTrie.Rep env o t) : o.sharedPath = t.sharedPath :=
  ((OTrie.Rep_iff env o t).1 h).1
theorem OTrie.Rep.vl {env : Env} {o : OTrie} {t : Trie} (h : OTrie.Rep env o t) : o.valueLength = t.valueLength :=
  ((OTrie.Rep_iff env o t).1 h).2.1

/-! ## Result predicates -/

/-- The operational call returned the pure value `x` and a still-represented receiver, or ran out
of fuel. -/
def Good {α} (env : Env) (t : Trie) (x : α) (res : Except Err (α × OTrie)) : Prop :=
  res = .error "fuel" ∨ ∃ o, res = .ok (x, o) ∧ OTrie.Rep env o t

def GoodR {α} (env : Env) (R : NodeRef Trie) (x : α) (res : Except Err (α × ORef OTrie)) : Prop :=
  res = .error "fuel" ∨ ∃ r, res = .ok (x, r) ∧ ORef.Rep env r R

/-- `getNode`: the node of a represented reference (`none` for the empty reference). -/
def GoodN (env : Env) (R : NodeRef Trie) (res : Except Err (Option OTrie × ORef OTrie)) : Prop :=
  res = .error "fuel" ∨
    match R with
    | .node c => ∃ o lh, res = .ok (some o, .node o lh) ∧ ORef.Rep env (.node o lh) (.node c)
    | _ => res = .ok (none, .empty)

theorem Good.bind {α β} {env : Env} {t : Trie} {x : α} {res : Except Err (α × OTrie)} (h : Good env t x res)
    {k : α × OTrie → Except Err β} {Q : Except Err β → Prop} (hq : Q (.error "fuel"))
    (hk : ∀ o, OTrie.Rep env o t → Q (k (x, o))) : Q (res >>= k) := by
  rcases h with h | ⟨o, h, ho⟩
  · rw [h]; exact hq
  · rw [h]; exact hk o ho

theorem GoodR.bind {α β} {env : Env} {R : NodeRef Trie} {x : α} {res : Except Err (α × ORef OTrie)}
    (h : GoodR env R x res) {k : α × ORef OTrie → Except Err β} {Q : Except Err β → Prop}
    (hq : Q (.error "fuel")) (hk : ∀ r, ORef.Rep env r R → Q (k (x, r))) : Q (res >>= k) := by
  rcases h with h | ⟨r, h, hr⟩
  · rw [h]; exact hq
  · rw [h]; exact hk r hr

theorem Good.fuel {α} {env : Env} {t : Trie} {x : α} : Good env t x (.error "fuel") := Or.inl rfl
theorem GoodR.fuel {α} {env : Env} {R : NodeRef Trie} {x : α} : GoodR env R x (.error "fuel") := Or.inl rfl

theorem Rep_saved {env : Env} {o : OTrie} {t : Trie} (h : OTrie.Rep env o t) (s : Bool) :
    OTrie.Rep env { o with saved := s } t := by
  rw [OTrie.Rep_iff] at h ⊢; exact h

/-! ## Objects built from pure tries -/

mutual
/-- A node re-parsed from a saved message is represented by the node that was saved. -/
theorem ofPure_reparse_Rep (env : Env) : ∀ c : Trie, c.Resident → Trie.Saved env.H env.db c → c.PathsOK →
    OTrie.Rep env (ofPure (c.reparse env.H)) c
  | ⟨p, v, l, r, vl, vh, cs⟩, ⟨hv, hl, hr⟩, ⟨hsv, hsl, hsr⟩, ⟨_, hpl, hpr⟩ => by
    simp only [Trie.reparse, ofPure]; unfold OTrie.Rep
    refine ⟨rfl, rfl, ?_, ?_, Or.inr (by rw [Trie.encS_eq env.H p v l r vl vh cs]), Or.inl rfl, Or.inl rfl,
      ofPureRef_reparse_Rep env l hl hsl hpl, ofPureRef_reparse_Rep env r hr hsr hpr⟩
    · by_cases h : vl > 32
      · rw [show (if vl > 32 then none else v) = none by simp [h],
          show (if vl > 0 then some (env.H (v.getD [])) else none) = some (env.H (v.getD [])) by
            simp [show vl > 0 by omega]]
        exact Or.inr ⟨h, rfl, rfl, hsv h⟩
      · rw [show (if vl > 32 then none else v) = v by simp [h]]; exact Or.inl rfl
    · intro h
      rw [show (if vl > 0 then some (env.H (v.getD [])) else none) = some (env.H (v.getD [])) by simp [h]]
      exact Or.inr rfl
theorem ofPureRef_reparse_Rep (env : Env) : ∀ R : NodeRef Trie, R.Resident → NodeRef.Saved env.H env.db R →
    NodeRef.PathsOK R → ORef.Rep env (ofPureRef (R.reparse env.H)) R
  | .empty, _, _, _ => by simp [NodeRef.reparse, ofPureRef, ORef.Rep]
  | .hash _, h, _, _ => absurd h (by simp [NodeRef.Resident])
  | .node c, ⟨hres, hne⟩, ⟨hs1, hs2⟩, hp => by
    simp only [NodeRef.reparse]
    split
    · next hemb =>
      simp only [ofPureRef]; unfold ORef.Rep
      exact ⟨ofPure_reparse_Rep env c hres hs2 hp, Or.inl rfl⟩
    · next hemb =>
      have he : (NodeRef.encS env.H (.node c)).2.2 = false := by simpa [NodeRef.encS] using hemb
      simp only [ofPureRef]; unfold ORef.Rep
      refine ⟨rfl, he, ?_, hs2, hp, hne⟩
      rw [Trie.hashS_nonempty _ _ hne]; exact hs1 he
end

mutual
/-- The operational object of a resident trie with consistent caches (e.g. one built by
`put`/`delete`) represents it. -/
theorem ofPure_Rep (env : Env) : ∀ t : Trie, t.Resident → t.CacheOK env.H → OTrie.Rep env (ofPure t) t
  | ⟨p, v, l, r, vl, vh, cs⟩, ⟨hv, hl, hr⟩, ⟨hcs, hvh, hcl, hcr⟩ => by
    simp only [ofPure]; unfold OTrie.Rep
    refine ⟨rfl, rfl, Or.inl rfl, ?_, ?_, Or.inl rfl, Or.inl rfl, ofPureRef_Rep env l hl hcl,
      ofPureRef_Rep env r hr hcr⟩
    · intro hpos
      rcases hv with ⟨rfl, rfl⟩ | ⟨x, rfl, _, _, _⟩
      · omega
      · exact hvh x rfl
    · rcases hcs with e | e
      · exact Or.inl e
      · right; rw [e, Trie.encS_eq env.H p v l r vl vh _]
theorem ofPureRef_Rep (env : Env) : ∀ R : NodeRef Trie, R.Resident → NodeRef.CacheOK env.H R →
    ORef.Rep env (ofPureRef R) R
  | .empty, _, _ => by simp [ofPureRef, ORef.Rep]
  | .hash _, h, _ => absurd h (by simp [NodeRef.Resident])
  | .node c, ⟨hres, _⟩, hc => by
    simp only [ofPureRef]; unfold ORef.Rep
    exact ⟨ofPure_Rep env c hres hc, Or.inl rfl⟩
end

/-! ## Values (no fuel) -/

theorem getValue_Rep (env : Env) (o : OTrie) (t : Trie) (ht : t.Resident) (h : OTrie.Rep env o t) :
    ∃ o', o.getValue env = .ok (t.value, o') ∧ OTrie.Rep env o' t := by
  have h' := (OTrie.Rep_iff env o t).1 h
  obtain ⟨p', v', l', r', vl', vh', cs'⟩ := t
  obtain ⟨hv, _, _⟩ := ht
  simp only at h' ⊢
  obtain ⟨_, hvl, hval, _⟩ := h'
  unfold OTrie.getValue
  rcases hval with e | ⟨hl, e, hvh, hdb⟩
  · rw [e]
    rcases hv with ⟨rfl, rfl⟩ | ⟨x, rfl, _, _, _⟩
    · simp only [hvl, gt_iff_lt, Nat.lt_irrefl, ↓reduceIte]; exact ⟨o, rfl, h⟩
    · exact ⟨o, rfl, h⟩
  · rcases hv with ⟨rfl, rfl⟩ | ⟨x, rfl, hx, _, _⟩
    · omega
    · simp only [Option.getD_some] at hvh hdb
      refine ⟨{ o with value := some x }, ?_, ?_⟩
      · simp only [e, hvl, show vl' > 0 by omega, ↓reduceIte, hvh, hdb, hx, ne_eq, not_true_eq_false]
      · rw [OTrie.Rep_iff] at h ⊢; exact ⟨h.1, h.2.1, Or.inl rfl, h.2.2.2⟩

theorem getValueHash_Rep (env : Env) (o : OTrie) (t : Trie) (ht : t.Resident) (h : OTrie.Rep env o t)
    (hpos : t.valueLength > 0) :
    ∃ o', o.getValueHash env = .ok (some (env.H (t.value.getD [])), o') ∧ OTrie.Rep env o' t := by
  have h' := (OTrie.Rep_iff env o t).1 h
  unfold OTrie.getValueHash
  rcases h'.2.2.2.1 hpos with e | e
  · rw [e]; simp only [h'.2.1, hpos, ↓reduceIte]
    obtain ⟨o', e1, h1⟩ := getValue_Rep env o t ht h
    rw [e1]
    refine ⟨{ o' with valueHash := some (env.H (t.value.getD [])) }, rfl, ?_⟩
    rw [OTrie.Rep_iff] at h1 ⊢
    refine ⟨h1.1, h1.2.1, ?_, fun _ => Or.inr rfl, h1.2.2.2.2⟩
    rcases h1.2.2.1 with e2 | ⟨a, b, _, d⟩
    · exact Or.inl e2
    · exact Or.inr ⟨a, b, rfl, d⟩
  · rw [e]; exact ⟨o, rfl, h⟩

/-! ## The read methods -/

/-- The pure `NodeReference.getHash()` of a resident reference. -/
def hashOptS (H : Bytes → Bytes) : NodeRef Trie → Option Bytes
  | .node c => some (Trie.hashS H c)
  | _ => none

/-- Every operational read method at fuel `f`, on a represented object, returns the pure value
(or runs out of fuel) and leaves the object represented. -/
structure ReadOK (env : Env) (f : Nat) : Prop where
  cs : ∀ o t, t.Resident → OTrie.Rep env o t → Good env t (Trie.encS env.H t).2 (OTrie.getChildrenSize env f o)
  itm : ∀ o t, t.Resident → OTrie.Rep env o t → Good env t (Trie.encS env.H t).1 (OTrie.internalToMessage env f o)
  msg : ∀ o t, t.Resident → OTrie.Rep env o t → Good env t (Trie.encS env.H t).1 (OTrie.toMessage env f o)
  len : ∀ o t, t.Resident → OTrie.Rep env o t →
    Good env t (Trie.encS env.H t).1.length (OTrie.getMessageLength env f o)
  emb : ∀ o t, t.Resident → OTrie.Rep env o t →
    Good env t (t.isTerminal && decide ((Trie.encS env.H t).1.length ≤ 44)) (OTrie.isEmbeddable env f o)
  hash : ∀ o t, t.Resident → OTrie.Rep env o t → Good env t (Trie.hashS env.H t) (OTrie.getHash env f o)
  size : ∀ o t, t.Resident → OTrie.Rep env o t →
    Good env t (wrap64 (((Trie.encS env.H t).2 : Int) + (if t.valueLength > 32 then t.valueLength else 0) +
      (Trie.encS env.H t).1.length)) (OTrie.nodeSize env f o)
  node : ∀ r R, R.Resident → ORef.Rep env r R → GoodN env R (ORef.getNode env f r)
  rhash : ∀ r R, R.Resident → ORef.Rep env r R → GoodR env R (hashOptS env.H R) (ORef.getHash env f r)
  remb : ∀ r R, R.Resident → ORef.Rep env r R → GoodR env R (NodeRef.encS env.H R).2.2 (ORef.isEmbeddable env f r)
  rlen : ∀ r R, R.Resident → ORef.Rep env r R →
    GoodR env R (NodeRef.encS env.H R).1.length (ORef.serializedLength env f r)
  rser : ∀ r R, R.Resident → ORef.Rep env r R → GoodR env R (NodeRef.encS env.H R).1 (ORef.serializeInto env f r)
  rsize : ∀ r R, R.Resident → ORef.Rep env r R → GoodR env R (NodeRef.encS env.H R).2.1 (ORef.referenceSize env f r)

theorem readOK_zero (env : Env) : ReadOK env 0 where
  cs _ _ _ _ := Good.fuel
  itm _ _ _ _ := Good.fuel
  msg _ _ _ _ := Good.fuel
  len _ _ _ _ := Good.fuel
  emb _ _ _ _ := Good.fuel
  hash _ _ _ _ := Good.fuel
  size _ _ _ _ := Good.fuel
  node _ _ _ _ := Or.inl rfl
  rhash _ _ _ _ := GoodR.fuel
  remb _ _ _ _ := GoodR.fuel
  rlen _ _ _ _ := GoodR.fuel
  rser _ _ _ _ := GoodR.fuel
  rsize _ _ _ _ := GoodR.fuel

theorem fromMessage_encS (env : Env) (hH : ∀ x, (env.H x).length = 32) (t : Trie) (hres : t.Resident)
    (hp : t.PathsOK) : Trie.fromMessage env (Trie.encS env.H t).1 = .ok (t.reparse env.H) := by
  obtain ⟨p, v, l, r, vl, vh, cs⟩ := t
  unfold Trie.fromMessage
  rw [Trie.encS_head]
  simp only [idx, List.getElem?_cons_zero, except_bind_ok]
  simp only [ARITY, mkFlags_ne_arity, ↓reduceIte]
  rw [← Trie.encS_head]
  exact Trie.parse_encS env hH _ hres hp _ (by omega)

section step
variable {env : Env} {f : Nat}

theorem step_node (hH : ∀ x, (env.H x).length = 32) (r : ORef OTrie) (R : NodeRef Trie) (hR : R.Resident) (h : ORef.Rep env r R) :
    GoodN env R (ORef.getNode env (f + 1) r) := by
  right
  cases r with
  | empty => cases R <;> simp_all [ORef.Rep, ORef.getNode]
  | node o lh =>
    cases R with
    | node c => exact ⟨o, lh, rfl, h⟩
    | _ => simp [ORef.Rep] at h
  | hash hh =>
    cases R with
    | node c =>
      unfold ORef.Rep at h
      obtain ⟨rfl, _, hdb, hs, hp, _⟩ := h
      refine ⟨{ ofPure (c.reparse env.H) with saved := true }, some (Trie.hashS env.H c), ?_, ?_⟩
      · simp [ORef.getNode, retrieve, hdb, fromMessage_encS env hH c hR.1 hp, bind, Except.bind, pure,
          Except.pure]
      · unfold ORef.Rep; exact ⟨Rep_saved (ofPure_reparse_Rep env c hR.1 hs hp) true, Or.inr rfl⟩
    | _ => simp [ORef.Rep] at h

theorem step_rhash (IH : ReadOK env f) (r : ORef OTrie) (R : NodeRef Trie) (hR : R.Resident) (h : ORef.Rep env r R) :
    GoodR env R (hashOptS env.H R) (ORef.getHash env (f + 1) r) := by
  cases r with
  | empty => cases R <;> simp_all [ORef.Rep]; exact Or.inr ⟨_, rfl, trivial⟩
  | hash hh =>
    cases R with
    | node c =>
      have h' := h; unfold ORef.Rep at h'
      obtain ⟨rfl, _⟩ := h'
      exact Or.inr ⟨_, rfl, h⟩
    | _ => simp [ORef.Rep] at h
  | node o lh =>
    cases R with
    | node c =>
      have h' := h; unfold ORef.Rep at h'
      obtain ⟨ho, hlh⟩ := h'
      rcases hlh with rfl | rfl
      · simp only [ORef.getHash]
        refine Good.bind (IH.hash o c hR.1 ho) GoodR.fuel (fun o' ho' => ?_)
        exact Or.inr ⟨_, rfl, by unfold ORef.Rep; exact ⟨ho', Or.inr rfl⟩⟩
      · exact Or.inr ⟨_, rfl, h⟩
    | _ => simp [ORef.Rep] at h

theorem step_remb (IH : ReadOK env f) (r : ORef OTrie) (R : NodeRef Trie) (hR : R.Resident) (h : ORef.Rep env r R) :
    GoodR env R (NodeRef.encS env.H R).2.2 (ORef.isEmbeddable env (f + 1) r) := by
  cases r with
  | empty => cases R <;> simp_all [ORef.Rep]; exact Or.inr ⟨_, rfl, trivial⟩
  | hash hh =>
    cases R with
    | node c =>
      have h' := h; unfold ORef.Rep at h'
      obtain ⟨_, he, _⟩ := h'
      rw [he]; exact Or.inr ⟨_, rfl, h⟩
    | _ => simp [ORef.Rep] at h
  | node o lh =>
    cases R with
    | node c =>
      have h' := h; unfold ORef.Rep at h'
      obtain ⟨ho, hlh⟩ := h'
      simp only [ORef.isEmbeddable]
      refine Good.bind (IH.emb o c hR.1 ho) GoodR.fuel (fun o' ho' => ?_)
      exact Or.inr ⟨_, rfl, by unfold ORef.Rep; exact ⟨ho', hlh⟩⟩
    | _ => simp [ORef.Rep] at h

theorem hashS_len (hH : ∀ x, (env.H x).length = 32) (c : Trie) : (Trie.hashS env.H c).length = 32 := by
  unfold Trie.hashS; split <;> exact hH _

theorem step_rlen (hH : ∀ x, (env.H x).length = 32) (IH : ReadOK env f) (r : ORef OTrie) (R : NodeRef Trie)
    (hR : R.Resident) (h : ORef.Rep env r R) :
    GoodR env R (NodeRef.encS env.H R).1.length (ORef.serializedLength env (f + 1) r) := by
  cases R with
  | hash => exact absurd hR (by simp [NodeRef.Resident])
  | empty =>
    cases r <;> simp [ORef.Rep] at h
    exact Or.inr ⟨_, rfl, trivial⟩
  | node c =>
    have hne : r.isEmpty = false := by rw [ORef.Rep_isEmpty h]; rfl
    simp only [ORef.serializedLength, hne, Bool.false_eq_true, ↓reduceIte]
    refine GoodR.bind (IH.remb r (.node c) hR h) GoodR.fuel (fun r' hr' => ?_)
    dsimp only
    by_cases he : (NodeRef.encS env.H (.node c)).2.2 = true
    · rw [he]
      cases r' with
      | node o lh =>
        have h' := hr'; unfold ORef.Rep at h'
        simp only [↓reduceIte]
        refine Good.bind (IH.len o c hR.1 h'.1) GoodR.fuel (fun o' ho' => ?_)
        refine Or.inr ⟨.node o' lh, ?_, by unfold ORef.Rep; exact ⟨ho', h'.2⟩⟩
        simp only [NodeRef.encS] at he ⊢
        simp [he, Uint8.encode, Nat.add_comm]
      | hash hh => unfold ORef.Rep at hr'; rw [hr'.2.1] at he; cases he
      | empty => simp [ORef.Rep] at hr'
    · simp only [Bool.not_eq_true] at he
      rw [he]
      simp only [Bool.false_eq_true, ↓reduceIte]
      refine Or.inr ⟨_, ?_, hr'⟩
      simp only [NodeRef.encS] at he ⊢
      simp only [he, Bool.false_eq_true, ↓reduceIte]
      split <;> simp [hH]

theorem step_rser (IH : ReadOK env f) (r : ORef OTrie) (R : NodeRef Trie)
    (hR : R.Resident) (h : ORef.Rep env r R) :
    GoodR env R (NodeRef.encS env.H R).1 (ORef.serializeInto env (f + 1) r) := by
  cases R with
  | hash => exact absurd hR (by simp [NodeRef.Resident])
  | empty =>
    cases r <;> simp [ORef.Rep] at h
    exact Or.inr ⟨_, rfl, trivial⟩
  | node c =>
    have hne : r.isEmpty = false := by rw [ORef.Rep_isEmpty h]; rfl
    simp only [ORef.serializeInto, hne, Bool.false_eq_true, ↓reduceIte]
    refine GoodR.bind (IH.remb r (.node c) hR h) GoodR.fuel (fun r' hr' => ?_)
    dsimp only
    by_cases he : (NodeRef.encS env.H (.node c)).2.2 = true
    · rw [he]
      cases r' with
      | node o lh =>
        have h' := hr'; unfold ORef.Rep at h'
        simp only [↓reduceIte]
        refine Good.bind (IH.msg o c hR.1 h'.1) GoodR.fuel (fun o' ho' => ?_)
        dsimp only
        have hle : (Trie.encS env.H c).1.length ≤ 44 := by
          simp only [NodeRef.encS, Bool.and_eq_true, decide_eq_true_eq] at he; exact he.2
        have : ¬ ((Trie.encS env.H c).1.length > 0xff) := by omega
        simp only [Uint8.mk, this, ↓reduceIte, except_bind_ok]
        refine Or.inr ⟨.node o' lh, ?_, by unfold ORef.Rep; exact ⟨ho', h'.2⟩⟩
        simp only [NodeRef.encS] at he ⊢
        simp [he]
      | hash hh => unfold ORef.Rep at hr'; rw [hr'.2.1] at he; cases he
      | empty => simp [ORef.Rep] at hr'
    · simp only [Bool.not_eq_true] at he
      rw [he]
      simp only [Bool.false_eq_true, ↓reduceIte]
      refine GoodR.bind (IH.rhash r' (.node c) hR hr') GoodR.fuel (fun r'' hr'' => ?_)
      refine Or.inr ⟨_, ?_, hr''⟩
      simp only [hashOptS]
      simp only [NodeRef.encS] at he ⊢
      simp only [he, Bool.false_eq_true, ↓reduceIte, hR.2, Trie.hashS_nonempty _ _ hR.2]
      rfl

theorem step_rsize (IH : ReadOK env f) (r : ORef OTrie) (R : NodeRef Trie)
    (hR : R.Resident) (h : ORef.Rep env r R) :
    GoodR env R (NodeRef.encS env.H R).2.1 (ORef.referenceSize env (f + 1) r) := by
  simp only [ORef.referenceSize]
  rcases IH.node r R hR h with e | hn
  · rw [e]; exact GoodR.fuel
  · cases R with
    | hash => exact absurd hR (by simp [NodeRef.Resident])
    | empty =>
      simp only at hn; rw [hn]; exact Or.inr ⟨_, rfl, trivial⟩
    | node c =>
      simp only at hn
      obtain ⟨o, lh, e, hr⟩ := hn
      rw [e]
      have h' := hr; unfold ORef.Rep at h'
      simp only [bind, Except.bind]
      refine Good.bind (IH.size o c hR.1 h'.1) GoodR.fuel (fun o' ho' => ?_)
      exact Or.inr ⟨_, rfl, by unfold ORef.Rep; exact ⟨ho', h'.2⟩⟩

theorem step_cs (IH : ReadOK env f) (o : OTrie) (t : Trie) (ht : t.Resident) (h : OTrie.Rep env o t) :
    Good env t (Trie.encS env.H t).2 (OTrie.getChildrenSize env (f + 1) o) := by
  have h' := (OTrie.Rep_iff env o t).1 h
  have hterm := OTrie.Rep_isTerminal h
  obtain ⟨p', v', l', r', vl', vh', cs'⟩ := t
  obtain ⟨_, hl, hr⟩ := ht
  simp only at h'
  simp only [OTrie.getChildrenSize]
  rcases h'.2.2.2.2.1 with e | e
  · rw [e]; dsimp only
    rw [hterm, encS_snd]
    by_cases hT : Trie.isTerminal ⟨p', v', l', r', vl', vh', cs'⟩ = true
    · have h0 : kidsSize env.H l' r' = 0 := by
        simp only [Trie.isTerminal] at hT; simp [kidsSize, hT]
      simp only [hT, ↓reduceIte, h0]
      exact Or.inr ⟨_, rfl, by have := Rep_cs h; rwa [encS_snd, h0] at this⟩
    · simp only [Bool.not_eq_true] at hT
      simp only [hT, Bool.false_eq_true, ↓reduceIte]
      refine GoodR.bind (IH.rsize o.left l' hl h'.2.2.2.2.2.2.2.1) Good.fuel (fun l1 hl1 => ?_)
      refine GoodR.bind (IH.rsize o.right r' hr h'.2.2.2.2.2.2.2.2) Good.fuel (fun r1 hr1 => ?_)
      have hk : kidsSize env.H l' r' = wrap64 ((NodeRef.encS env.H l').2.1 + (NodeRef.encS env.H r').2.1) := by
        simp only [Trie.isTerminal] at hT; simp [kidsSize, hT]
      refine Or.inr ⟨_, by rw [hk]; rfl, ?_⟩
      have := Rep_cs (Rep_right (Rep_left h hl1) hr1)
      rwa [encS_snd, hk] at this
  · rw [e]; exact Or.inr ⟨o, rfl, h⟩

theorem step_msg (IH : ReadOK env f) (o : OTrie) (t : Trie) (ht : t.Resident) (h : OTrie.Rep env o t) :
    Good env t (Trie.encS env.H t).1 (OTrie.toMessage env (f + 1) o) := by
  have h' := (OTrie.Rep_iff env o t).1 h
  simp only [OTrie.toMessage]
  rcases h'.2.2.2.2.2.2.1 with e | e
  · rw [e]; exact IH.itm o t ht h
  · rw [e]; exact Or.inr ⟨o, rfl, h⟩

theorem step_len (IH : ReadOK env f) (o : OTrie) (t : Trie) (ht : t.Resident) (h : OTrie.Rep env o t) :
    Good env t (Trie.encS env.H t).1.length (OTrie.getMessageLength env (f + 1) o) := by
  simp only [OTrie.getMessageLength]
  exact Good.bind (IH.msg o t ht h) Good.fuel (fun o' ho' => Or.inr ⟨o', rfl, ho'⟩)

theorem step_emb (IH : ReadOK env f) (o : OTrie) (t : Trie) (ht : t.Resident) (h : OTrie.Rep env o t) :
    Good env t (t.isTerminal && decide ((Trie.encS env.H t).1.length ≤ 44)) (OTrie.isEmbeddable env (f + 1) o) := by
  simp only [OTrie.isEmbeddable, OTrie.Rep_isTerminal h]
  split
  · next hT =>
    rw [hT, Bool.true_and]
    exact Good.bind (IH.len o t ht h) Good.fuel (fun o' ho' => Or.inr ⟨o', rfl, ho'⟩)
  · next hT =>
    simp only [Bool.not_eq_true] at hT
    rw [hT, Bool.false_and]; exact Or.inr ⟨o, rfl, h⟩

theorem step_hash (IH : ReadOK env f) (o : OTrie) (t : Trie) (ht : t.Resident) (h : OTrie.Rep env o t) :
    Good env t (Trie.hashS env.H t) (OTrie.getHash env (f + 1) o) := by
  have h' := (OTrie.Rep_iff env o t).1 h
  simp only [OTrie.getHash]
  rcases h'.2.2.2.2.2.1 with e | e
  · rw [e]; dsimp only
    rw [OTrie.Rep_isEmptyTrie h]
    split
    · next hE => exact Or.inr ⟨o, by simp [Trie.hashS, hE, Trie.emptyHash], h⟩
    · next hE =>
      simp only [Bool.not_eq_true] at hE
      refine Good.bind (IH.msg o t ht h) Good.fuel (fun o' ho' => ?_)
      have e2 : Trie.hashS env.H t = env.H (Trie.encS env.H t).1 := Trie.hashS_nonempty _ _ hE
      exact Or.inr ⟨_, by rw [e2]; rfl, by have := Rep_hash ho'; rwa [e2] at this⟩
  · rw [e]; exact Or.inr ⟨o, rfl, h⟩

theorem step_size (IH : ReadOK env f) (o : OTrie) (t : Trie) (ht : t.Resident) (h : OTrie.Rep env o t) :
    Good env t (wrap64 (((Trie.encS env.H t).2 : Int) + (if t.valueLength > 32 then t.valueLength else 0) +
      (Trie.encS env.H t).1.length)) (OTrie.nodeSize env (f + 1) o) := by
  have h' := (OTrie.Rep_iff env o t).1 h
  simp only [OTrie.nodeSize, OTrie.hasLongValue, h'.2.1]
  refine Good.bind (IH.cs o t ht h) Good.fuel (fun o1 h1 => ?_)
  refine Good.bind (IH.len o1 t ht h1) Good.fuel (fun o2 h2 => ?_)
  exact Or.inr ⟨o2, by simp, h2⟩

theorem ok_enc (m m' : Bytes) (o : OTrie) (h : m = m') :
    (Except.ok (m, { o with encoded := some m }) : Except Err (Bytes × OTrie)) =
      .ok (m', { o with encoded := some m' }) := by subst h; rfl

theorem step_itm (IH : ReadOK env f) (o : OTrie) (t : Trie) (ht : t.Resident) (h : OTrie.Rep env o t) :
    Good env t (Trie.encS env.H t).1 (OTrie.internalToMessage env (f + 1) o) := by
  have hR := ht
  obtain ⟨p', v', l', r', vl', vh', cs'⟩ := t
  obtain ⟨hv, hl, hr⟩ := hR
  simp only [OTrie.internalToMessage]
  refine Good.bind (IH.cs o _ ht h) Good.fuel (fun o1 h1 => ?_)
  dsimp only
  refine GoodR.bind (IH.rlen o1.left l' hl h1.left) Good.fuel (fun l1 hl1 => ?_)
  have h2 := Rep_left h1 hl1
  dsimp only
  refine GoodR.bind (IH.rlen _ r' hr h2.right) Good.fuel (fun r1 hr1 => ?_)
  have h3 := Rep_right h2 hr1
  dsimp only
  refine GoodR.bind (IH.remb _ l' hl h3.left) Good.fuel (fun l2 hl2 => ?_)
  have h4 := Rep_left h3 hl2
  dsimp only
  refine GoodR.bind (IH.remb _ r' hr h4.right) Good.fuel (fun r2 hr2 => ?_)
  have h5 := Rep_right h4 hr2
  dsimp only
  refine GoodR.bind (IH.rser _ l' hl h5.left) Good.fuel (fun l3 hl3 => ?_)
  have h6 := Rep_left h5 hl3
  dsimp only
  refine GoodR.bind (IH.rser _ r' hr h6.right) Good.fuel (fun r3 hr3 => ?_)
  have h7 := Rep_right h6 hr3
  dsimp only at h7 ⊢
  have e4 := ORef.Rep_isEmpty hl3
  have e5 := ORef.Rep_isEmpty hr3
  have e_sp : o1.sharedPath = p' := h1.sp
  have e_t7 : ({ o1 with left := l3, right := r3 } : OTrie).isTerminal = (l'.isEmpty && r'.isEmpty) := by
    simp only [OTrie.isTerminal, e4, e5]
  have e_s7 : ({ o1 with left := l3, right := r3 } : OTrie).sharedPath = p' := e_sp
  generalize ({ o1 with left := l3, right := r3 } : OTrie) = o7 at h7 e_t7 e_s7 ⊢
  have e2 := ORef.Rep_isEmpty hl2
  have e3 := ORef.Rep_isEmpty hr2
  simp only [OTrie.hasLongValue, h.vl, e_t7]
  by_cases hlong : vl' > 32
  · simp only [hlong, decide_true, ↓reduceIte]
    obtain ⟨o8, e8, h8⟩ := getValueHash_Rep env _ _ ht h7 (by simp only; omega)
    rw [e8]
    simp only [bind, Except.bind, pure, Except.pure]
    refine Or.inr ⟨_, ok_enc _ _ _ ?_, Rep_enc h8⟩
    simp only [Trie.encS, Trie.isTerminal, e_sp, h8.sp, e2, e3, hlong, decide_true,
      ↓reduceIte]
  · simp only [hlong, decide_false, Bool.false_eq_true, ↓reduceIte]
    by_cases hpos : vl' > 0
    · simp only [hpos, ↓reduceIte]
      obtain ⟨o8, e8, h8⟩ := getValue_Rep env _ _ ht h7
      rw [e8]
      obtain ⟨x, rfl, _, _, _⟩ : ∃ x, v' = some x ∧ x.length = vl' ∧ 0 < vl' ∧ vl' ≤ Uint24.MAX := by
        rcases hv with ⟨_, h0⟩ | h0
        · omega
        · exact h0
      simp only [bind, Except.bind, pure, Except.pure]
      refine Or.inr ⟨_, ok_enc _ _ _ ?_, Rep_enc h8⟩
      simp only [Trie.encS, Trie.isTerminal, e_sp, h8.sp, e2, e3, hlong, hpos,
        decide_false, Bool.false_eq_true, ↓reduceIte, Option.getD_some]
    · simp only [hpos, ↓reduceIte]
      simp only [bind, Except.bind, pure, Except.pure]
      refine Or.inr ⟨_, ok_enc _ _ _ ?_, Rep_enc h7⟩
      simp only [Trie.encS, Trie.isTerminal, e_sp, e_s7, e2, e3, hlong, hpos, decide_false,
        Bool.false_eq_true, ↓reduceIte]

end step

/-- **Read bridge**: at every fuel, every operational read method on a represented object returns
the pure encoder's value (or runs out of fuel) and leaves the object represented. -/
theorem readOK (env : Env) (hH : ∀ x, (env.H x).length = 32) : ∀ f, ReadOK env f
  | 0 => readOK_zero env
  | f + 1 =>
    have IH := readOK env hH f
    { cs := step_cs IH, itm := step_itm IH, msg := step_msg IH, len := step_len IH, emb := step_emb IH,
      hash := step_hash IH, size := step_size IH, node := step_node hH, rhash := step_rhash IH,
      remb := step_remb IH, rlen := step_rlen hH IH, rser := step_rser IH, rsize := step_rsize IH }

open TrieKeySlice in
/-- **Lookup bridge**: operational `find` + `getValue` on a represented object returns the pure
contents (or runs out of fuel), loading and caching children on the way. -/
theorem getRec_Rep (env : Env) (hH : ∀ x, (env.H x).length = 32) : ∀ (f : Nat) (o : OTrie) (t : Trie)
    (key : TrieKeySlice), t.Resident → OTrie.Rep env o t → Good env t (t.contents key) (OTrie.getRec env f o key)
  | 0, _, _, _, _, _ => Good.fuel
  | f + 1, o, ⟨p, v, l, r, vl, vh, cs⟩, key, ⟨hv, hl, hr⟩, h => by
    have hsp : o.sharedPath = p := h.sp
    have c1 : o.sharedPath.length = p.length := by rw [hsp]
    have c2 : key.commonPath o.sharedPath = TrieKeySlice.lcp key p := by rw [hsp, TrieKeySlice.commonPath_eq_lcp]
    have RK := readOK env hH f
    simp only [OTrie.getRec, c1, c2]
    by_cases h1 : p.length > key.length
    · have : ¬ p <+: key := fun h => by have := h.length_le; omega
      simp only [h1, ↓reduceIte, Trie.contents, this]
      exact Or.inr ⟨o, rfl, h⟩
    · simp only [h1, ↓reduceIte]
      by_cases h2 : (lcp key p).length < p.length
      · have : ¬ p <+: key := fun h => by rw [lcp_of_prefix h] at h2; omega
        simp only [h2, ↓reduceIte, Trie.contents, this]
        exact Or.inr ⟨o, rfl, h⟩
      · have hlen := lcp_length_le_right key p
        have heq : (lcp key p).length = p.length := by omega
        have hpre : p <+: key := (lcp_eq_iff_prefix key p).mp heq
        simp only [heq, Nat.lt_irrefl, ↓reduceIte]
        by_cases h3 : p.length = key.length
        · have : key.drop p.length = [] := by simp; omega
          simp only [h3, ↓reduceIte]
          obtain ⟨o', e, ho'⟩ := getValue_Rep env o ⟨p, v, l, r, vl, vh, cs⟩ ⟨hv, hl, hr⟩ h
          rw [e]
          refine Or.inr ⟨o', ?_, ho'⟩
          simp only [Trie.contents, hpre, ↓reduceIte, this]
        · simp only [h3, ↓reduceIte]
          have hlt : p.length < key.length := by omega
          have hc : Trie.contents ⟨p, v, l, r, vl, vh, cs⟩ key =
              (if key.get p.length = false then NodeRef.contents l (key.slice (p.length + 1) key.length)
               else NodeRef.contents r (key.slice (p.length + 1) key.length)) := by
            rw [Trie.contents]
            simp only [hpre, ↓reduceIte, drop_eq_cons_get hlt, slice_eq_drop]
            cases key.get p.length <;> rfl
          rw [hc]
          cases hb : key.get p.length
          · simp only [↓reduceIte]
            rcases RK.node o.left l hl h.left with e | hn
            · simp only [e, bind, Except.bind]; exact Good.fuel
            · cases l with
              | hash => exact absurd hl (by simp [NodeRef.Resident])
              | empty =>
                simp only at hn; rw [hn]
                exact Or.inr ⟨_, rfl, Rep_left h (by simp [ORef.Rep])⟩
              | node c =>
                obtain ⟨o1, lh, e, hr1⟩ := hn
                rw [e]
                have h' := hr1; unfold ORef.Rep at h'
                simp only [bind, Except.bind, NodeRef.contents]
                refine Good.bind (getRec_Rep env hH f o1 c _ hl.1 h'.1) Good.fuel (fun o2 h2 => ?_)
                exact Or.inr ⟨_, rfl, Rep_left h (by unfold ORef.Rep; exact ⟨h2, h'.2⟩)⟩
          · simp only [Bool.true_eq_false, ↓reduceIte]
            rcases RK.node o.right r hr h.right with e | hn
            · simp only [e, bind, Except.bind]; exact Good.fuel
            · cases r with
              | hash => exact absurd hr (by simp [NodeRef.Resident])
              | empty =>
                simp only at hn; rw [hn]
                exact Or.inr ⟨_, rfl, Rep_right h (by simp [ORef.Rep])⟩
              | node c =>
                obtain ⟨o1, lh, e, hr1⟩ := hn
                rw [e]
                have h' := hr1; unfold ORef.Rep at h'
                simp only [bind, Except.bind, NodeRef.contents]
                refine Good.bind (getRec_Rep env hH f o1 c _ hr.1 h'.1) Good.fuel (fun o2 h2 => ?_)
                exact Or.inr ⟨_, rfl, Rep_right h (by unfold ORef.Rep; exact ⟨h2, h'.2⟩)⟩

end RskjTrie.Op
