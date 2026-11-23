# PD-0 ladder checker and scorer: differential qualification of the OM-2 ports
# (src/physics0/ladder/pd0_ladder.om, src/physics0/score/pd0_score.om and its memoriser mode 1) against
# the live C the learners and planner link (pd0_ladder.c, pd0_score.c, the memoriser of pd0_controls.c).
# Host only, CPU only, no cc.
#
# test-pd0-ladder-parity
#   1. tests/physics0/verify/pd0l_parity.sh: the hand corpus (tests/physics0/verify/pd0l_corpus.txt) and
#      the generated bundle-option, ladder-parameter, ledger-damage, hand-made-ledger, crafted-entry,
#      statistics and scorer corpora through tests/physics0/verify/pd0l_dump.om (built from
#      P0V_OM_VERIFY and the test bundle builder pd0_bundle.om), byte for byte against the committed
#      goldens of the C at main 3f2c70dc5 (tests/physics0/verify/ladder_golden, gzip -9n, MANIFEST with
#      commit, generator and sha256);
#   2. tests/physics0/verify/pd0l_mutants.sh: every mutant of the OM ports must change the output.
#   (This file sorts before mk/physics0-verify.mk; its compiler default is repeated here.)
P0V_OMC ?= seed/out/omc
.PHONY: test-pd0-ladder-parity
test-pd0-ladder-parity: $(P0V_OMC)
	PD0L_PARITY_WORK=$(abspath $(OUT_DIR))/pd0l-parity sh tests/physics0/verify/pd0l_parity.sh $(abspath $(P0V_OMC))
	PD0L_PARITY_WORK=$(abspath $(OUT_DIR))/pd0l-parity sh tests/physics0/verify/pd0l_mutants.sh $(abspath $(P0V_OMC))

# test-pd0-parity: both PD-0 differentials. The pd0_controls.c row of docs/migration/PARITY.tsv
# names it: test-pd0-verify-parity compares the controls, test-pd0-ladder-parity the memoriser.
.PHONY: test-pd0-parity
test-pd0-parity: test-pd0-verify-parity test-pd0-ladder-parity
