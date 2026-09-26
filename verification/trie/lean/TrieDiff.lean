import RskjTrie
/-!
# `trie-diff`: differential runner for the executable model

Implements `verification/trie/differential/FORMAT.md`: reads a `.cases` file on stdin and prints
one block per case. Uses the real Keccak-256 (`RskjTrie.Keccak.keccak256`).
Empty byte strings are printed as `-`, input tokens are echoed verbatim and a null value in
an orchid line is printed `null` (as `differential/java/DiffRunner.java` does).
-/
open RskjTrie

def H : Bytes → Bytes := Keccak.keccak256

def hexOut (b : Bytes) : String := if b.isEmpty then "-" else toHex b

def pathOut (p : List Bool) : String :=
  if p.isEmpty then "-" else String.ofList (p.map fun b => if b then '1' else '0')

structure St where
  trie : Trie := Trie.empty
  db : DB := DB.empty
  step : Nat := 0
  keys : Array String := #[]
  out : Array String := #[]

def St.env (s : St) : Env := ⟨H, s.db⟩
def St.emit (s : St) (l : String) : St := { s with out := s.out.push l }
def St.useKey (s : St) (k : String) : St :=
  if s.keys.contains k then s else { s with keys := s.keys.push k }

def hashOut (s : St) : String :=
  match s.trie.getHash s.env with
  | .ok h => toHex h
  | .error _ => "error"

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
  match ws with
  | ["put", kw, v] => do
    let k ← hx kw; let v ← hx v
    let s := (s.useKey kw)
    let s := { s with step := s.step + 1 }
    match s.trie.put s.env k (some v) with
    | .ok t => let s := { s with trie := t }; pure (s.emit s!"step {s.step} {hashOut s}")
    | .error _ => pure (s.emit s!"step {s.step} error")
  | ["delete", kw] => do
    let k ← hx kw
    let s := (s.useKey kw)
    let s := { s with step := s.step + 1 }
    match s.trie.delete s.env k with
    | .ok t => let s := { s with trie := t }; pure (s.emit s!"step {s.step} {hashOut s}")
    | .error _ => pure (s.emit s!"step {s.step} error")
  | ["save"] =>
    match TrieStoreImpl.save H s.db s.trie with
    | .ok db => pure { s with db := db }
    | .error _ => pure (s.emit "save error")
  | ["reload"] =>
    match s.trie.getHash s.env >>= TrieStoreImpl.retrieve s.env with
    | .ok (some t) => pure { s with trie := t }
    | _ => pure (s.emit "reload error")
  | ["raw", kw, vw] => do
    let k ← hx kw; let v ← hx vw
    pure { s with db := s.db.put k v }
  | ["load", hw] => do
    let h ← hx hw
    match TrieStoreImpl.retrieve s.env h with
    | .ok (some t) => pure { s with trie := t }
    | _ => pure (s.emit "load error")
  | ["hash"] => pure (s.emit s!"hash {hashOut s}")
  | ["getk", kw] => do
    let k ← hx kw
    let v := match s.trie.get s.env k with
      | .ok (some v) => hexOut v
      | .ok none => "null"
      | .error _ => "error"
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
  let mut s := s.emit s!"root {hashOut s}"
  s := s.emit s!"msg {match s.trie.toMessage s.env with | .ok m => hexOut m | .error _ => "error"}"
  for kw in s.keys do
    let v := match fromHex kw with
      | none => "error"
      | some k => match s.trie.get s.env k with
        | .ok (some v) => hexOut v
        | .ok none => "null"
        | .error _ => "error"
    s := s.emit s!"get {kw} {v}"
  s.emit "end"

partial def readLines (h : IO.FS.Stream) (acc : Array String) : IO (Array String) := do
  let l ← h.getLine
  if l.isEmpty then pure acc else readLines h (acc.push l)

def main : IO UInt32 := do
  let lines ← readLines (← IO.getStdin) #[]
  let stdout ← IO.getStdout
  let mut cur : Option St := none
  for raw in lines do
    let l := raw.trimAscii.toString
    if l.isEmpty || l.startsWith "#" then continue
    let ws := (l.splitOn " ").filter (· ≠ "")
    match ws, cur with
    | ["case", name], none => cur := some (({} : St).emit s!"case {name}")
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
