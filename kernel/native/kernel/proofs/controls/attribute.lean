
/- Negative control for proofs/check.sh (appended to a copy of TicketLock.lean; never part of the proof):
   an attribute command, outside the allowlist (attributes can attach compiled code or rewrite rules);
   no banned word, so only the syntax rule sees it. -/
-- expect: syntax
attribute [simp] tk
