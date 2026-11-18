
/- Negative control for proofs/check.sh (appended to a copy of TicketLock.lean; never part of the proof):
   an axiom of False and a theorem proved from it. -/
-- expect: source syntax
-- expect-unrestricted: source constants pins
axiom ck_control_bad : False
theorem ck_control_from_bad : (1 : Nat) = 2 := ck_control_bad.elim
