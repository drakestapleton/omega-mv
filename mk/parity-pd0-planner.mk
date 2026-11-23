# PD-0 experiment planner: differential qualification of the pure OM-2 planner
# (src/physics0/planner/pd0_planner.om) against the C planner it replaced (pd0_planner.c, retired in
# wave 36b). Host only, CPU only, no cc.
#
# test-pd0-planner-parity
#   1. tests/physics0/planner/pd0p_parity.sh: the hand corpus (tests/physics0/planner/pd0p_corpus.txt) and
#      the generated seed, domain, duplicate, prior-cap, plan-parse and passive corpora through
#      tests/physics0/planner/pd0p_dump.om (built from P0P_OM_LIB), byte for byte against the committed
#      goldens of the C at main 3f2c70dc5 (tests/physics0/planner/parity_golden, MANIFEST with commit,
#      generator and sha256): proposals, PD0EXP1, preregistration and PD0PLN1 bytes, plan parse,
#      validation, passive schedules, the outside fraction;
#   2. tests/physics0/planner/pd0p_mutants.sh: every mutant of the OM planner must differ from the goldens.
#   (This file sorts before mk/physics0-planner.mk; its compiler default is repeated here.)
P0P_OMC ?= seed/out/omc
.PHONY: test-pd0-planner-parity
test-pd0-planner-parity: $(P0P_OMC)
	PD0P_PARITY_WORK=$(abspath $(OUT_DIR))/pd0p-parity sh tests/physics0/planner/pd0p_parity.sh $(abspath $(P0P_OMC))
	PD0P_PARITY_WORK=$(abspath $(OUT_DIR))/pd0p-parity sh tests/physics0/planner/pd0p_mutants.sh $(abspath $(P0P_OMC))
