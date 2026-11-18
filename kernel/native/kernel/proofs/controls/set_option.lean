
/- Negative control for proofs/check.sh (appended to a copy of TicketLock.lean; never part of the proof):
   a set_option command (options can switch off checks; the allowlist has no set_option kind). -/
-- expect: source syntax
set_option maxRecDepth 4096 in
theorem ck_control_set_option : (2 : Nat) + 2 = 4 := rfl
