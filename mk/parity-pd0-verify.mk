# PD-0 verifier library: differential qualification of the OM-2 ports (src/physics0/ladder/pd0_fmt.om,
# pd0_codes.om, src/physics0/controls/pd0_controls.om, pd0_receipt.om) against the live C library the
# learners and planner link (pd0_fmt.c, pd0_codes.c, pd0_controls.c, pd0_receipt.c). Host only, CPU
# only, no cc.
#
# test-pd0-verify-parity
#   1. tests/physics0/verify/pd0v_parity.sh: the hand corpus (tests/physics0/verify/pd0v_corpus.txt) and
#      the generated record, relation, PD0EXP1, PDLAW1, ledger/payload and controls corpora through
#      tests/physics0/verify/pd0v_dump.om (built from P0V_OM_VERIFY), byte for byte against the committed
#      goldens of the C at main 3f2c70dc5 (tests/physics0/verify/parity_golden, MANIFEST with commit,
#      generator and sha256), except on the capacity lines tests/physics0/verify/parity_divergences.txt
#      lists, which must differ;
#   2. tests/physics0/verify/pd0v_mutants.sh: every mutant of the OM ports must change the output.
#   (This file sorts before mk/physics0-verify.mk; its compiler default is repeated here.)
P0V_OMC ?= seed/out/omc
.PHONY: test-pd0-verify-parity
test-pd0-verify-parity: $(P0V_OMC)
	PD0V_PARITY_WORK=$(abspath $(OUT_DIR))/pd0v-parity sh tests/physics0/verify/pd0v_parity.sh $(abspath $(P0V_OMC))
	PD0V_PARITY_WORK=$(abspath $(OUT_DIR))/pd0v-parity sh tests/physics0/verify/pd0v_mutants.sh $(abspath $(P0V_OMC))
