/- proofs/checker/Inspect.lean: run by proofs/check.sh as `lean --run checker/Inspect.lean MODULE`
   with LEAN_PATH holding the MODULE.olean that check.sh built from the file under test. A separate
   process from the one that elaborated the file: it loads the compiled module and prints one line
   per constant the module declares, every constant Lean put there (generated ones included),
   sorted by name, tab-separated:
     CK_DECL  kind  name  axioms  type  value  statement
   kind is theorem, def, opaque, axiom, quot, inductive, ctor or rec, with ":unsafe" appended for an
   unsafe constant; axioms is the comma-separated set of axioms the constant depends on (`-` for
   none); type is the elaborated type and value the definition body of a def or opaque (`-`
   otherwise), both as Lean's `repr` of the expression on one line; statement is the pretty-printed
   type of a theorem (`-` otherwise). check.sh hashes type and value and compares every line with
   the committed proofs/TicketLock.pins. -/
import Lean
open Lean

def oneLine (s : String) : String := (s.replace "\n" " ").replace "\t" " "

def exprRepr (e : Expr) : String := oneLine ((repr e).pretty 1000000000)

def ppType (env : Environment) (e : Expr) : IO String := do
  let ctx : Core.Context := { fileName := "<inspect>", fileMap := default }
  let (fmt, _) ← (Meta.ppExpr e |>.run' {} {}).toIO ctx { env }
  return oneLine (fmt.pretty 1000000000)

def axiomsOf (env : Environment) (n : Name) : IO (Array Name) := do
  let ctx : Core.Context := { fileName := "<inspect>", fileMap := default }
  let (axs, _) ← (collectAxioms n : CoreM (Array Name)).toIO ctx { env }
  return axs.qsort (fun a b => a.toString < b.toString)

unsafe def main (args : List String) : IO UInt32 := do
  let [mod] := args | IO.eprintln "usage: lean --run checker/Inspect.lean MODULE"; return 2
  initSearchPath (← findSysroot)
  enableInitializersExecution
  let modName := mod.toName
  let env ← importModules #[{ module := modName }] {} (trustLevel := 0) (loadExts := true)
  let some idx := env.getModuleIdx? modName
    | IO.eprintln s!"module {mod} not loaded"; return 2
  let mut names : Array Name := #[]
  for (n, _) in env.constants.map₁.toList do
    if env.getModuleIdxFor? n == some idx then names := names.push n
  names := names.qsort (fun a b => a.toString < b.toString)
  for n in names do
    let some ci := env.find? n | continue
    let kind := match ci with
      | .thmInfo _ => "theorem" | .defnInfo _ => "def" | .opaqueInfo _ => "opaque"
      | .axiomInfo _ => "axiom" | .quotInfo _ => "quot" | .inductInfo _ => "inductive"
      | .ctorInfo _ => "ctor" | .recInfo _ => "rec"
    let kind := if ci.isUnsafe then kind ++ ":unsafe" else kind
    let value := match ci with
      | .defnInfo d => exprRepr d.value | .opaqueInfo d => exprRepr d.value | _ => "-"
    let stmt ← if ci.isTheorem then ppType env ci.type else pure "-"
    let axs ← axiomsOf env n
    let axs := if axs.isEmpty then "-" else ",".intercalate (axs.toList.map toString)
    IO.println s!"CK_DECL\t{kind}\t{n}\t{axs}\t{exprRepr ci.type}\t{value}\t{stmt}"
  IO.println s!"CK_DECLS {names.size}"
  return 0
