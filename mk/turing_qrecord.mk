# TURING companion records for continuous-value evidence (qprofile, qworld,
# qfreeze, qgain) and their sidecar manifest formats, in pure seeded OM-2:
# src/turing/ty_qrecord.om (composed after src/turing/ty_core_lib.om, which
# supplies SHA-256 and the OMG0 canonical builder), tests/turing/test_ty_qrecord.om,
# docs/turing/TURING_QCONT_RECORDS_V0.md. Picked up by `-include mk/*.mk`; no
# Makefile edit; redefines nothing that exists.
#
# test-turing-qrecord: builds the test with the seeded omc and runs it (pinned
# record and sidecar KATs, refusals, bindings, write-once files and manifests).
ifndef TURING_QRECORD_MK
TURING_QRECORD_MK := 1
.PHONY: test-turing-qrecord
TYQR_OMC ?= seed/out/omc
TYQR_OM_SRCS = src/turing/ty_core_lib.om src/turing/ty_qrecord.om
TYQR_DIR = $(OUT_DIR)/tests-turing-qrecord

$(TYQR_DIR)/test_ty_qrecord: tests/turing/test_ty_qrecord.om $(TYQR_OM_SRCS) $(TYQR_OMC)
	@mkdir -p $(TYQR_DIR)
	(printf 'om2\n'; sed '/^om2$$/d' $(TYQR_OM_SRCS) tests/turing/test_ty_qrecord.om) | $(TYQR_OMC) > $@ && chmod +x $@

test-turing-qrecord: $(TYQR_DIR)/test_ty_qrecord
	./$(TYQR_DIR)/test_ty_qrecord
	@echo "test-turing-qrecord: pure OM-2 record builders, verifiers, refusals and manifests pass"
endif
