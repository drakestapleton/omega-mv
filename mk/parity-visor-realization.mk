# Omega Visor V1 lane 5 (realization lab): differential qualification of the OM-2 module the omega
# binary runs (src/visor/visor_realization.om, with the program realizer of visor_program.om)
# against the C it replaced (src/visor/visor_realization.c, retired by wave 33). Host only, CPU
# only (the OM side interprets the realized code; the goldens hold the C's native runs), no
# physics checkout, no C compiler.
#
# test-visor-realization-parity
#   1. tests/visor/real_parity.sh: the hand corpus (tests/visor/real_corpus.txt) and the generated
#      matrix, operation, executable-code, disassembly, entry-edit and alternatives corpora through
#      tests/visor/real_dump.om, byte for byte against the committed goldens of the C at main
#      3f2c70dc5 (tests/visor/real_golden, MANIFEST with commit, generator and sha256);
#   2. tests/visor/real_mutants.sh: every mutant of the OM lane must differ from the goldens.
.PHONY: test-visor-realization-parity
test-visor-realization-parity: $(VISOR_OMC)
	REAL_PARITY_WORK=$(abspath $(OUT_DIR))/real-parity sh tests/visor/real_parity.sh $(abspath $(VISOR_OMC))
	REAL_PARITY_WORK=$(abspath $(OUT_DIR))/real-parity sh tests/visor/real_mutants.sh $(abspath $(VISOR_OMC))
