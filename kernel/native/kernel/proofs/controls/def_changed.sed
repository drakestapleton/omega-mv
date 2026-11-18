# Negative control for proofs/check.sh (a sed script run on a copy of TicketLock.lean; never part of the
# proof): the definition a statement names is changed while every statement keeps its text: pairNoMask
# gets a second release, so pairNoMask_unsafe says something else with the same words. The pinned
# definition body catches it.
# expect: pins
s/^def pairNoMask : List SOp := \[.take, .wait, .release\]$/def pairNoMask : List SOp := [.take, .wait, .release, .release]/
