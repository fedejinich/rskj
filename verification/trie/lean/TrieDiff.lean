import RskjTrie
import RskjTrie.Operational
/-!
# `trie-diff`: differential runner for the executable model

Implements `verification/trie/differential/FORMAT.md`: reads a `.cases` file on stdin and prints
one block per case. Uses the real Keccak-256 (`RskjTrie.Keccak.keccak256`).
Empty byte strings are printed as `-`, input tokens are echoed verbatim and a null value in
an orchid line is printed `null` (as `differential/java/DiffRunner.java` does).

The trie is the operational, cache-faithful one (`RskjTrie.Operational`); `--pure` runs the pure
layer instead. Where the Java runner throws (a failed `load`/`reload`, `put` of a value longer than
`0xFFFFFF`) and aborts, this runner prints an `… error` line and continues.
-/
open RskjTrie

def H : Bytes → Bytes := Keccak.keccak256

def hexOut (b : Bytes) : String := if b.isEmpty then "-" else toHex b

def pathOut (p : List Bool) : String :=
  if p.isEmpty then "-" else String.ofList (p.map fun b => if b then '1' else '0')

/-- Runner state. `trie` is the operational (cache-faithful) trie; with `--pure` the runner uses
`ptrie` and the pure layer instead (for comparing the two layers). -/
structure St where
  trie : Op.OTrie := Op.OTrie.empty
  ptrie : Trie := Trie.empty
  pure : Bool := false
  db : DB := DB.empty
  step : Nat := 0
  keys : Array String := #[]
  out : Array String := #[]

def St.env (s : St) : Env := ⟨H, s.db⟩
def St.emit (s : St) (l : String) : St := { s with out := s.out.push l }
def St.useKey (s : St) (k : String) : St :=
  if s.keys.contains k then s else { s with keys := s.keys.push k }

/-- `trie.getHash()` (caches in the operational trie). -/
def St.hash (s : St) : String × St :=
  if s.pure then
    match s.ptrie.getHash s.env with
    | .ok h => (toHex h, s)
    | .error _ => ("error", s)
  else
    match s.trie.hashOf s.env with
    | .ok (h, t) => (toHex h, { s with trie := t })
    | .error _ => ("error", s)

/-- `trie.toMessage()`. -/
def St.message (s : St) : String × St :=
  if s.pure then
    match s.ptrie.toMessage s.env with
    | .ok m => (hexOut m, s)
    | .error _ => ("error", s)
  else
    match s.trie.messageOf s.env with
    | .ok (m, t) => (hexOut m, { s with trie := t })
    | .error _ => ("error", s)

/-- `trie.get(key)` printed as the Java runner does. -/
def St.get (s : St) (k : Bytes) : String × St :=
  let pr : Option Bytes → String := fun | some v => hexOut v | none => "null"
  if s.pure then
    match s.ptrie.get s.env k with
    | .ok v => (pr v, s)
    | .error _ => ("error", s)
  else
    match s.trie.get s.env k with
    | .ok (v, t) => (pr v, { s with trie := t })
    | .error _ => ("error", s)

def St.putOp (s : St) (k : Bytes) (v : Option Bytes) : Option St :=
  if s.pure then
    match s.ptrie.put s.env k v with
    | .ok t => some { s with ptrie := t }
    | .error _ => none
  else
    match s.trie.put s.env k v with
    | .ok t => some { s with trie := t }
    | .error _ => none

def St.saveOp (s : St) : Option St :=
  if s.pure then
    match TrieStoreImpl.save H s.db s.ptrie with
    | .ok db => some { s with db := db }
    | .error _ => none
  else
    match Op.save H s.db s.trie with
    | .ok (db, t) => some { s with db := db, trie := t }
    | .error _ => none

def St.loadOp (s : St) (h : Bytes) : Option St :=
  if s.pure then
    match TrieStoreImpl.retrieve s.env h with
    | .ok (some t) => some { s with ptrie := t }
    | _ => none
  else
    match Op.retrieve s.env h with
    | .ok (some t) => some { s with trie := t }
    | _ => none

def doDecode (s : St) (tok : String) (bs : Bytes) : String :=
  let pre := s!"decode {tok} "
  match idx bs 0 with
  | .error _ => pre ++ "error"
  | .ok b0 =>
    if b0.toNat = Trie.ARITY then
      match Trie.fromMessage s.env bs with
      | .error _ => pre ++ "error"
      | .ok t =>
        let refOut : NodeRef Trie → String := fun
          | .hash h => toHex h
          | _ => "-"
        let v := match t.getValue s.env with
          | .ok (some v) => hexOut v
          | .ok none => "null"
          | .error _ => "error"
        pre ++ s!"orchid {pathOut t.sharedPath} {refOut t.left} {refOut t.right} {v}"
    else
      match Trie.fromMessage s.env bs >>= fun t => t.toMessage s.env with
      | .ok m => pre ++ hexOut m
      | .error _ => pre ++ "error"

def runOp (s : St) (ws : List String) : Except String St := do
  let hx (w : String) : Except String Bytes :=
    match fromHex w with
    | some b => .ok b
    | none => .error s!"bad hex {w}"
  let step (s : St) (k : Bytes) (v : Option Bytes) : St :=
    let s := { s with step := s.step + 1 }
    match s.putOp k v with
    | some s => let (h, s) := s.hash; s.emit s!"step {s.step} {h}"
    | none => s.emit s!"step {s.step} error"
  match ws with
  | ["put", kw, v] => do
    let k ← hx kw; let v ← hx v
    pure (step (s.useKey kw) k (some v))
  | ["delete", kw] => do
    let k ← hx kw
    pure (step (s.useKey kw) k none)
  | ["save"] =>
    match s.saveOp with
    | some s => pure s
    | none => pure (s.emit "save error")
  | ["reload"] =>
    let (h, s) := s.hash
    match fromHex h >>= fun h => s.loadOp h with
    | some s => pure s
    | none => pure (s.emit "reload error")
  | ["raw", kw, vw] => do
    let k ← hx kw; let v ← hx vw
    pure { s with db := s.db.put k v }
  | ["load", hw] => do
    let h ← hx hw
    match s.loadOp h with
    | some s => pure s
    | none => pure (s.emit "load error")
  | ["hash"] =>
    let (h, s) := s.hash
    pure (s.emit s!"hash {h}")
  | ["getk", kw] => do
    let k ← hx kw
    let (v, s) := s.get k
    pure (s.emit s!"getk {kw} {v}")
  | ["decode", tok] => do
    let b ← hx tok
    pure (s.emit (doDecode s tok b))
  | ["keymap-account", aw] => do
    let a ← hx aw
    match TrieKeyMapper.rskAddress a with
    | .ok a => pure (s.emit s!"keymap account {aw} {hexOut (TrieKeyMapper.getAccountKey H a)}")
    | .error _ => pure (s.emit s!"keymap account {aw} error")
  | ["keymap-code", aw] => do
    let a ← hx aw
    match TrieKeyMapper.rskAddress a with
    | .ok a => pure (s.emit s!"keymap code {aw} {hexOut (TrieKeyMapper.getCodeKey H a)}")
    | .error _ => pure (s.emit s!"keymap code {aw} error")
  | ["keymap-storage", aw, sw] => do
    let a ← hx aw; let slot ← hx sw
    match TrieKeyMapper.rskAddress a, TrieKeyMapper.dataWordValueOf slot with
    | .ok a, .ok w =>
      pure (s.emit s!"keymap storage {aw} {sw} {hexOut (TrieKeyMapper.getAccountStorageKey H a w)}")
    | _, _ => pure (s.emit s!"keymap storage {aw} {sw} error")
  | _ => .error s!"unknown op: {" ".intercalate ws}"

def finish (s : St) : St := Id.run do
  let (h, s) := s.hash
  let mut s := s.emit s!"root {h}"
  let (m, s') := s.message
  s := s'.emit s!"msg {m}"
  for kw in s.keys do
    match fromHex kw with
    | none => s := s.emit s!"get {kw} error"
    | some k =>
      let (v, s') := s.get k
      s := s'.emit s!"get {kw} {v}"
  s.emit "end"

partial def readLines (h : IO.FS.Stream) (acc : Array String) : IO (Array String) := do
  let l ← h.getLine
  if l.isEmpty then pure acc else readLines h (acc.push l)

def main (args : List String) : IO UInt32 := do
  let pureMode := args.contains "--pure"
  let lines ← readLines (← IO.getStdin) #[]
  let stdout ← IO.getStdout
  let mut cur : Option St := none
  for raw in lines do
    let l := raw.trimAscii.toString
    if l.isEmpty || l.startsWith "#" then continue
    let ws := (l.splitOn " ").filter (· ≠ "")
    match ws, cur with
    | ["case", name], none => cur := some (({ pure := pureMode } : St).emit s!"case {name}")
    | ["end"], some s =>
      for o in (finish s).out do stdout.putStrLn o
      cur := none
    | _, some s =>
      match runOp s ws with
      | .ok s' => cur := some s'
      | .error e => IO.eprintln s!"trie-diff: {e}"; return 2
    | _, none => IO.eprintln s!"trie-diff: line outside a case: {l}"; return 2
  if cur.isSome then IO.eprintln "trie-diff: missing end"; return 2
  pure 0
