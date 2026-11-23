# C-to-OM differential of the EST-2/EST-3 fit and evaluation tools (docs/migration/PARITY.tsv rows
# tools/estimation/est_fit.c and tools/estimation/est_eval.c, retired at main commit 3f2c70dc5).
# Host only, CPU only, no C compiler: the reference is committed goldens.
#
# test-est-tools-parity
#   1. tests/estimation/est_tools_parity.sh: the cases of tests/estimation/est_tools_cases.txt
#      (fit, eval, v2 groups) in a fixture tree written by tests/estimation/est_tools_fixtures.sh,
#      through est_fit, est_eval (production identity "parity-commit", clean) and est_eval_t (the
#      test build), each composed from $(ESTT_OM_LIB) as mk/estimation_tools.mk composes it; exit
#      code, stdout, stderr and every output file byte for byte against the goldens of the C at
#      main 3f2c70dc5 (tests/estimation/est_tools_golden, MANIFEST with commit, generator and
#      sha256), which the cases cover to 100% of the lines of est_fit.c and est_eval.c (gcov);
#   2. tests/estimation/est_tools_mutants.sh: every mutant of the OM tools must differ from the goldens.
ifndef PARITY_EST_TOOLS_MK
PARITY_EST_TOOLS_MK := 1
include mk/estimation_tools.mk
.PHONY: test-est-tools-parity
test-est-tools-parity: $(ESTT_OMC)
	EST_OM_LIB="$(ESTT_OM_LIB)" EST_PARITY_WORK=$(abspath $(ESTT_DIR))/est-tools-parity sh tests/estimation/est_tools_parity.sh $(abspath $(ESTT_OMC))
	EST_OM_LIB="$(ESTT_OM_LIB)" EST_PARITY_WORK=$(abspath $(ESTT_DIR))/est-tools-parity sh tests/estimation/est_tools_mutants.sh $(abspath $(ESTT_OMC))
endif
