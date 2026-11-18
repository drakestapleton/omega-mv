# Negative control for proofs/check.sh (a sed script run on a copy of TicketLock.lean; never part of the
# proof): only slot_pair_safe's statement replaced by `True := trivial`; each statement is pinned on its own.
# expect: pins
s/^theorem slot_pair_safe : .*/theorem slot_pair_safe : True := trivial/
