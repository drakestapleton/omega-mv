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
   the committed proofs/TicketLock.pins.
   Names are printed from their components, not with Name.toString (which leaves a component holding
   U+271D, ending in _hyg or starting with # unescaped, so a name could carry a tab or a newline and
   forge a record: review of omega-mv 5cd0af98f, LeanSpin finding 1). A string component is printed
   only when it is made of ASCII letters, digits, _ ' ! ? and does not start with a digit, a numeric
   component is printed in decimal after the first component, and components are joined by a dot
   [ctl:OMEGA-KERNEL-SPINLOCK/ticketlock-a1-forged-pin]. So a printed name has no tab or newline, and a
   string component has no dot and does not read as a number. A module constant whose name is refused
   gets a CK_REFUSED line in place of its CK_DECL line, with the name escaped (each string component
   quoted, a character outside printable ASCII as \u{hex}) and the reason, and the exit status is 1
   [ctl:OMEGA-KERNEL-SPINLOCK/ticketlock-a1b-decoy-only]. Two constants that print as the same name
   also get a CK_REFUSED line. In the type, value and statement fields a backslash is written \\ and a
   character below U+0020 (or U+007F) as \u{hex}, so these fields hold no tab or newline; for the
   reviewed TicketLock.lean the output is the same as before this change (TicketLock.pins unchanged).
   Last line: CK_DECLS <number of CK_DECL lines>. -/
import Lean
open Lean

def hexOf (n : Nat) : String := String.ofList (Nat.toDigits 16 n)

/-- One line, no tab: `\` becomes `\\` and a control character (below U+0020, or U+007F) `\u{hex}`. -/
def oneLine (s : String) : String :=
  s.foldl (fun acc c =>
    if c == '\\' then acc ++ "\\\\"
    else if c.toNat < 0x20 || c.toNat == 0x7f then acc ++ "\\u{" ++ hexOf c.toNat ++ "}"
    else acc.push c) ""

/-- The escaped form of a refused name: printable ASCII as it is (`\` and `"` escaped), anything else `\u{hex}`. -/
def escapeText (s : String) : String :=
  s.foldl (fun acc c =>
    if c == '\\' || c == '"' then (acc.push '\\').push c
    else if c.toNat < 0x20 || c.toNat > 0x7e then acc ++ "\\u{" ++ hexOf c.toNat ++ "}"
    else acc.push c) ""

def display : Name → String
  | .anonymous => "[anonymous]"
  | .str .anonymous s => "\"" ++ escapeText s ++ "\""
  | .str p s => display p ++ ".\"" ++ escapeText s ++ "\""
  | .num p k => display p ++ "." ++ toString k

def plainPart (s : String) : Bool :=
  !s.isEmpty && !s.front.isDigit &&
    s.all (fun c => c.isAlphanum || c == '_' || c == '\'' || c == '!' || c == '?')

/-- The printed name, or why it is refused. -/
def render : Name → Except String String
  | .anonymous => .error "anonymous name"
  | .str p s =>
    if !plainPart s then
      .error "a component is empty, starts with a digit, or has a character other than ASCII letters, digits, _ ' ! ?"
    else match p with
      | .anonymous => .ok s
      | _ => do return (← render p) ++ "." ++ s
  | .num p k => match p with
      | .anonymous => .error "the first component is a number"
      | _ => do return (← render p) ++ "." ++ toString k

def exprRepr (e : Expr) : String := oneLine ((repr e).pretty 1000000000)

def ppType (env : Environment) (e : Expr) : IO String := do
  let ctx : Core.Context := { fileName := "<inspect>", fileMap := default }
  let (fmt, _) ← (Meta.ppExpr e |>.run' {} {}).toIO ctx { env }
  return oneLine (fmt.pretty 1000000000)

def axiomsOf (env : Environment) (n : Name) : IO (Array Name) := do
  let ctx : Core.Context := { fileName := "<inspect>", fileMap := default }
  let (axs, _) ← (collectAxioms n : CoreM (Array Name)).toIO ctx { env }
  return axs

unsafe def main (args : List String) : IO UInt32 := do
  let [mod] := args | IO.eprintln "usage: lean --run checker/Inspect.lean MODULE"; return 2
  initSearchPath (← findSysroot)
  enableInitializersExecution
  let modName := mod.toName
  let env ← importModules #[{ module := modName }] {} (trustLevel := 0) (loadExts := true)
  let some idx := env.getModuleIdx? modName
    | IO.eprintln s!"module {mod} not loaded"; return 2
  let mut rows : Array (String × Name) := #[]
  let mut refused : Array String := #[]
  for (n, _) in env.constants.map₁.toList do
    if env.getModuleIdxFor? n == some idx then
      match render n with
      | .ok s => rows := rows.push (s, n)
      | .error why => refused := refused.push s!"CK_REFUSED\t{display n}\t{why}"
  rows := rows.qsort (fun a b => a.1 < b.1)
  for i in [1:rows.size] do
    if rows[i]!.1 == rows[i-1]!.1 then
      refused := refused.push s!"CK_REFUSED\t{display rows[i]!.2}\ttwo constants print as {rows[i]!.1}"
  for l in refused.qsort (· < ·) do IO.println l
  for (s, n) in rows do
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
    let axs := (axs.map (fun a => match render a with | .ok r => r | .error _ => display a)).qsort (· < ·)
    let axs := if axs.isEmpty then "-" else ",".intercalate axs.toList
    IO.println s!"CK_DECL\t{kind}\t{s}\t{axs}\t{exprRepr ci.type}\t{value}\t{stmt}"
  IO.println s!"CK_DECLS {rows.size}"
  return if refused.isEmpty then 0 else 1
