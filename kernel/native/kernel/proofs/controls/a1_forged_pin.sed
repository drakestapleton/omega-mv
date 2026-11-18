# Negative control for proofs/check.sh (a sed script run on a copy of TicketLock.lean; never part of the
# proof): review of omega-mv 5cd0af98f, LeanSpin finding 1, attack A1. slot_safe weakened to `True := trivial`, plus a decoy theorem. The decoy's name, in
# guillemets, holds a tab, the pinned record of slot_safe (kind, name, axioms, type repr, value, statement,
# tab-separated), a newline and U+271D. Name.toString leaves such a name unescaped, so the earlier
# checker/Inspect.lean printed a forged CK_DECL line for slot_safe and check.sh, keying pins by name (last
# line wins), passed (constants 296, pinned 295). checker/Inspect.lean now refuses the name (rule names), and slot_safe differs from its pin.
# expect: names pins
# expect-unrestricted: names pins
s/^theorem slot_safe : safe2 slotLU slotLU = true := by decide$/theorem slot_safe : True := trivial\ntheorem «slot_safe\t-\tLean.Expr.app (Lean.Expr.app (Lean.Expr.app (Lean.Expr.const `Eq [Lean.Level.succ (Lean.Level.zero)]) (Lean.Expr.const `Bool [])) (Lean.Expr.app (Lean.Expr.app (Lean.Expr.const `safe2 []) (Lean.Expr.const `slotLU [])) (Lean.Expr.const `slotLU []))) (Lean.Expr.const `Bool.true [])\t-\tsafe2 slotLU slotLU = true\n✝» : True := trivial/
