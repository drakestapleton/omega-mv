# Differential qualification of the pure OM-2 SAT solver src/checker2/untrusted/c2sat.om (built as
# $(C2_DIR)/c2sat by mk/checker2.mk) against the retired C solver src/checker2/untrusted/c2sat.c
# (main commit 3f2c70dc5). Host only, CPU only, needs no C compiler.
#
# test-c2sat-parity
#   1. tests/checker2/sat_parity.sh: the hand, I/O, random, large and deep corpora through the OM
#      solver, byte for byte against the committed goldens of the C at main 3f2c70dc5
#      (tests/checker2/sat_golden, MANIFEST with commit, generator and sha256): exit status,
#      stdout, stderr, and the LRAT proof's existence, size and sha256;
#   2. tests/checker2/sat_mutants.sh: every mutant of c2sat.om must differ from the goldens.
.PHONY: test-c2sat-parity
test-c2sat-parity: $(C2_DIR)/c2sat $(C2_OMC)
	SAT_PARITY_WORK=$(abspath $(OUT_DIR))/c2sat-parity sh tests/checker2/sat_parity.sh $(abspath $(C2_DIR)/c2sat)
	SAT_PARITY_WORK=$(abspath $(OUT_DIR))/c2sat-parity sh tests/checker2/sat_mutants.sh $(abspath $(C2_OMC))
