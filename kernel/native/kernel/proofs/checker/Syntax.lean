/- proofs/checker/Syntax.lean: run by proofs/check.sh as `lean --run checker/Syntax.lean FILE`.
   Parses FILE with Lean's own parser and prints every syntax node kind it contains, one
   `KIND <name>` line each, sorted and unique, so check.sh can refuse any kind outside the committed
   allowlist (proofs/TicketLock.syntax). Parsing only: nothing in FILE is elaborated or run here, and
   check.sh does not let lean elaborate FILE unless every kind is allowed. A parse error is printed as
   `PARSE_ERROR <message>` and exits 1. -/
import Lean
open Lean Parser

partial def kinds (s : Syntax) (acc : Std.HashSet Name) : Std.HashSet Name :=
  match s with
  | .node _ k args => args.foldl (fun a c => kinds c a) (acc.insert k)
  | _ => acc

unsafe def main (args : List String) : IO UInt32 := do
  let [file] := args | IO.eprintln "usage: lean --run checker/Syntax.lean FILE"; return 2
  let input ← IO.FS.readFile file
  initSearchPath (← findSysroot)
  let ictx := mkInputContext input file
  let (header, mps, msgs) ← parseHeader ictx
  -- The header's imports are not processed: the file is parsed against Init alone (the prelude every
  -- file gets), and an `import` shows up as a Lean.Parser.Module.import kind, which the allowlist
  -- refuses.
  let mut acc := kinds header {}
  enableInitializersExecution
  let env ← importModules #[{ module := `Init }] {} (trustLevel := 0) (loadExts := true)
  let mut mps := mps
  let mut msgs := msgs
  repeat
    let (cmd, mps', msgs') := parseCommand ictx { env, options := {} } mps msgs
    mps := mps'
    msgs := msgs'
    acc := kinds cmd acc
    if isTerminalCommand cmd then break
  let mut bad := false
  for m in msgs.toList do
    if m.severity == .error then
      bad := true
      IO.println s!"PARSE_ERROR {m.pos.line}:{m.pos.column}: {(← m.data.toString).replace "\n" " "}"
  for k in acc.toArray.qsort (fun a b => a.toString < b.toString) do
    IO.println s!"KIND {k}"
  return if bad then 1 else 0
