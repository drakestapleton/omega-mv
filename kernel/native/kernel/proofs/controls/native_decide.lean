
/- Negative control for proofs/check.sh (appended to a copy of TicketLock.lean; never part of the proof):
   a theorem closed by native_decide (trusts the compiler: axiom Lean.ofReduceBool; no warning). -/
-- expect: source syntax
-- expect-unrestricted: source constants pins
theorem ck_control_native : (2 : Nat) + 2 = 4 := by native_decide
