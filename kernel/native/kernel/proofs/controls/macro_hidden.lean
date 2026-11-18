
/- Negative control for proofs/check.sh (appended to a copy of TicketLock.lean; never part of the proof):
   a theorem made by a macro, so no line of the file starts with "theorem" for it and it gets no
   `#print axioms` line; only Lean's own listing of the file's constants sees it. Its proof is sorryAx
   written out, which the source rule does not match as a word. -/
-- expect: lean constants
macro "ck_control_hide" : command => `(theorem ck_control_hidden : (1 : Nat) = 2 := sorryAx _ false)
ck_control_hide
