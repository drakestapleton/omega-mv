# TURING quantized continuous scorer (qint.v1) and PRD1 reader.
# Pure seeded OM-2: src/turing/ty_qcont_lib.om, tests/turing/test_ty_qcont.om,
# tests/turing/qcont_kat_gen.om (the C src/turing/ty_qcont.*, ty_prd.* are retired).
# Picked up by `-include mk/*.mk`; no Makefile edit; redefines nothing that exists.
#
# test-turing-qcont: builds the known-answer generator and the test with the
# seed omc and runs both.
ifndef TURING_QCONT_MK
TURING_QCONT_MK := 1
.PHONY: test-turing-qcont
TYQC_OM_LIB = src/turing/ty_qcont_lib.om
TYQC_DIR = $(OUT_DIR)/tests-turing-qcont

$(TYQC_DIR)/qcont_kat_gen: $(TYQC_OM_LIB) tests/turing/qcont_kat_gen.om seed/out/omc
	@mkdir -p $(TYQC_DIR)
	cat $(TYQC_OM_LIB) tests/turing/qcont_kat_gen.om | seed/out/omc > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TYQC_DIR)/test_ty_qcont: $(TYQC_OM_LIB) tests/turing/test_ty_qcont.om seed/out/omc
	@mkdir -p $(TYQC_DIR)
	cat $(TYQC_OM_LIB) tests/turing/test_ty_qcont.om | seed/out/omc > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

test-turing-qcont: $(TYQC_DIR)/qcont_kat_gen $(TYQC_DIR)/test_ty_qcont
	./$(TYQC_DIR)/qcont_kat_gen > $(TYQC_DIR)/kat_table.txt
	! grep -q REFUSED $(TYQC_DIR)/kat_table.txt
	./$(TYQC_DIR)/test_ty_qcont
	@echo "test-turing-qcont: pure OM-2 qint.v1 KATs, refusals and PRD1 cases pass"
endif
