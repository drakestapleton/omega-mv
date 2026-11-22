# TURING quantized continuous scorer (qint.v1) and PRD1 reader.
# New files only: src/turing/ty_qcont.*, src/turing/ty_prd.*,
# tests/turing/test_ty_qcont.c, tests/turing/qcont_kat_gen.c. Picked up by
# `-include mk/*.mk`; no Makefile edit; redefines nothing that exists.
#
# test-turing-qcont: builds the known-answer generator (long double Simpson,
# also linked in-process into the test) and the test, plain + ASan/UBSan.
ifndef TURING_QCONT_MK
TURING_QCONT_MK := 1
.PHONY: test-turing-qcont
TYQC_OM_LIB = src/turing/ty_qcont_lib.om
TYQC_DIR = $(OUT_DIR)/tests-turing-qcont

$(TYQC_DIR)/qcont_kat_gen: $(TYQC_OM_LIB) tests/turing/qcont_kat_gen.om seed/out/omc
	@mkdir -p $(TYQC_DIR)
	cat $(TYQC_OM_LIB) tests/turing/qcont_kat_gen.om | seed/out/omc > $@ && chmod +x $@

$(TYQC_DIR)/test_ty_qcont: $(TYQC_OM_LIB) tests/turing/test_ty_qcont.om seed/out/omc
	@mkdir -p $(TYQC_DIR)
	cat $(TYQC_OM_LIB) tests/turing/test_ty_qcont.om | seed/out/omc > $@ && chmod +x $@

test-turing-qcont: $(TYQC_DIR)/qcont_kat_gen $(TYQC_DIR)/test_ty_qcont
	./$(TYQC_DIR)/qcont_kat_gen > $(TYQC_DIR)/kat_table.txt
	! grep -q REFUSED $(TYQC_DIR)/kat_table.txt
	./$(TYQC_DIR)/test_ty_qcont
	@echo "test-turing-qcont: pure OM-2 qint.v1 KATs, refusals and PRD1 cases pass"
endif
