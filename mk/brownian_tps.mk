# Lane T phases 1-2: TPS1 binariser with qint.v1 proof, hooked to the EXP-001 coders.
# Pure seeded OM-2: tools/brownian/brw_tps_adapter.om, tests/brownian/test_brw_tps.om.
# Picked up by `-include mk/*.mk`.
#
# test-brownian-tps: builds the pure OM-2 test via seed/out/omc and runs it.
ifndef BROWNIAN_TPS_MK
BROWNIAN_TPS_MK := 1
.PHONY: test-brownian-tps
SEED_OMC ?= seed/out/omc
BRWT_OM_DEPS = src/turing/ty_qcont_lib.om seed/ng/sha256.om tools/brownian/brw_tps_adapter.om
BRWT_DIR = $(OUT_DIR)/tests-brownian-tps

$(BRWT_DIR)/test_brw_tps: $(BRWT_OM_DEPS) tests/brownian/test_brw_tps.om $(SEED_OMC)
	@mkdir -p $(BRWT_DIR)
	cat $(BRWT_OM_DEPS) tests/brownian/test_brw_tps.om | $(SEED_OMC) > $@ && chmod +x $@

test-brownian-tps: $(BRWT_DIR)/test_brw_tps
	./$(BRWT_DIR)/test_brw_tps
	@echo "test-brownian-tps: pure OM-2 TPS1 binariser proofs, EXP-001 coders, and refusals pass"
endif
