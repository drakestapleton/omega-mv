# PRD2 mixture-capable prediction format + mixture scorer (EXP-002D Stage A).
# Pure seeded OM-2: src/turing/ty_qcont_lib.om, tests/turing/test_ty_prd2.om (the C
# src/turing/ty_prd2.* is retired). Picked up by `-include mk/*.mk`.
ifndef TURING_PRD2_MK
TURING_PRD2_MK := 1
.PHONY: test-turing-prd2
TYP2_OM_LIB = src/turing/ty_qcont_lib.om
TYP2_DIR = $(OUT_DIR)/tests-turing-prd2

$(TYP2_DIR)/test_ty_prd2: $(TYP2_OM_LIB) tests/turing/test_ty_prd2.om seed/out/omc
	@mkdir -p $(TYP2_DIR)
	cat $(TYP2_OM_LIB) tests/turing/test_ty_prd2.om | seed/out/omc > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

test-turing-prd2: $(TYP2_DIR)/test_ty_prd2
	./$(TYP2_DIR)/test_ty_prd2
	@echo "test-turing-prd2: pure OM-2 PRD2 wire, R28-v2 and controls N1-N4 pass"
endif
