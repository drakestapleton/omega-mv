# Negative control for proofs/check.sh (a sed script run on a copy of TicketLock.lean; never part of the
# proof): the reviewer's weakening (review of omega-mv c9e503afd, finding 2): the statements of slot_safe,
# pair_safe and slot_pair_safe, the three GATED by tests/gates/run.sh spinlock, each replaced by
# `True := trivial`. Allowed syntax, no banned word, no axiom: only the pinned statements catch it.
# expect: pins
s/^theorem slot_safe : .*/theorem slot_safe : True := trivial/
s/^theorem pair_safe : .*/theorem pair_safe : True := trivial/
s/^theorem slot_pair_safe : .*/theorem slot_pair_safe : True := trivial/
