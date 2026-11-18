
/- Negative control for proofs/check.sh (appended to a copy of TicketLock.lean; never part of the proof):
   a proof by a tactic that runs arbitrary code (run_tac), which the allowlist does not list. -/
-- expect: source syntax
theorem ck_control_run_tac : True := by run_tac pure ()
