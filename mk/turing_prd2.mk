# PRD2 mixture-capable prediction format + mixture scorer (EXP-002D Stage A).
# New files only: src/turing/ty_prd2.*, tests/turing/test_ty_prd2.c. Reads
# ty_qcont/ty_prd/ty_math; changes none of them. Picked up by `-include mk/*.mk`.
ifndef TURING_PRD2_MK
TURING_PRD2_MK := 1
.PHONY: test-turing-prd2
TYP2_OM_LIB = src/turing/ty_qcont_lib.om
TYP2_DIR = $(OUT_DIR)/tests-turing-prd2

$(TYP2_DIR)/test_ty_prd2: $(TYP2_OM_LIB) tests/turing/test_ty_prd2.om seed/out/omc
	@mkdir -p $(TYP2_DIR)
	cat $(TYP2_OM_LIB) tests/turing/test_ty_prd2.om | seed/out/omc > $@ && chmod +x $@

test-turing-prd2: $(TYP2_DIR)/test_ty_prd2
	./$(TYP2_DIR)/test_ty_prd2
	@echo "test-turing-prd2: pure OM-2 PRD2 wire, R28-v2 and controls N1-N4 pass"
endif
