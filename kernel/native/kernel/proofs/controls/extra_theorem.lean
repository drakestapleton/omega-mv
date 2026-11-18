
/- Negative control for proofs/check.sh (appended to a copy of TicketLock.lean; never part of the proof):
   a true, harmless theorem with allowed syntax and a valid proof. It is still not in the reviewed
   proofs/TicketLock.pins, so the pins rule refuses it as a declaration that is not pinned. -/
-- expect: pins
theorem ck_control_extra : 1 + 1 = 2 := rfl
