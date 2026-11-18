
/- Negative control for proofs/check.sh (appended to a copy of TicketLock.lean; never part of the proof):
   a theorem closed by admit (Lean warns "declaration uses 'sorry'" and still exits 0). -/
-- expect: source lean theorems constants
theorem ck_control_admit : (1 : Nat) = 2 := by admit
