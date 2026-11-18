# Negative control for proofs/check.sh (a sed script run on a copy of TicketLock.lean; never part of the
# proof): the reviewer's trick (review of omega-mv c9e503afd, finding 2). `import Lean` at the top and, at
# the end, an #eval that builds the option name debug.skipKernelTC from strings and adds a theorem of False
# without kernel checking, then a theorem of False from it. With the syntax rule on, lean never runs the
# file; with it off (expect-unrestricted), leanchecker's kernel replay and the pins catch it on their own.
# expect: source syntax
# expect-unrestricted: kernel pins
1i\
import Lean
$a\
open Lean Elab Command in\
#eval show CommandElabM Unit from do\
\  let o : Options := ({} : Options).setBool (Name.mkStr (Name.mkSimple ("de" ++ "bug")) ("skipKernel" ++ "TC")) true\
\  let decl := Declaration.thmDecl { name := `ticket_unchecked, levelParams := [], type := mkConst ``False, value := mkConst ``True.intro }\
\  liftCoreM <| withOptions (fun _ => o) <| addDecl decl\
\
theorem ticketlock_is_broken : False := ticket_unchecked
