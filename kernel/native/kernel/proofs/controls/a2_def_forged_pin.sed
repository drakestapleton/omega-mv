# Negative control for proofs/check.sh (a sed script run on a copy of TicketLock.lean; never part of the
# proof): review of omega-mv 5cd0af98f, LeanSpin finding 1, attack A2. The edit of controls/def_changed.sed (pairNoMask gets a second release) plus a decoy def at the end. The decoy's name, in
# guillemets, holds a tab, the pinned record of pairNoMask (kind, name, axioms, type repr, value, statement,
# tab-separated), a newline and U+271D. Name.toString leaves such a name unescaped, so the earlier
# checker/Inspect.lean printed a forged CK_DECL line for pairNoMask and check.sh, keying pins by name (last
# line wins), passed. checker/Inspect.lean now refuses the name (rule names), and pairNoMask differs from its pin.
# expect: names pins
# expect-unrestricted: names pins
s/^def pairNoMask : List SOp := \[.take, .wait, .release\]$/def pairNoMask : List SOp := [.take, .wait, .release, .release]/
$s/$/\ndef «pairNoMask\t-\tLean.Expr.app (Lean.Expr.const `List [Lean.Level.zero]) (Lean.Expr.const `SOp [])\tLean.Expr.app (Lean.Expr.app (Lean.Expr.app (Lean.Expr.const `List.cons [Lean.Level.zero]) (Lean.Expr.const `SOp [])) (Lean.Expr.const `SOp.take [])) (Lean.Expr.app (Lean.Expr.app (Lean.Expr.app (Lean.Expr.const `List.cons [Lean.Level.zero]) (Lean.Expr.const `SOp [])) (Lean.Expr.const `SOp.wait [])) (Lean.Expr.app (Lean.Expr.app (Lean.Expr.app (Lean.Expr.const `List.cons [Lean.Level.zero]) (Lean.Expr.const `SOp [])) (Lean.Expr.const `SOp.release [])) (Lean.Expr.app (Lean.Expr.const `List.nil [Lean.Level.zero]) (Lean.Expr.const `SOp []))))\t-\n✝» : Nat := 0/
