# TURING companion records for continuous-value evidence (qprofile, qworld,
# qfreeze, qgain) and their sidecar manifest formats, in pure seeded OM-2:
# src/turing/ty_qrecord.om (composed after src/turing/ty_core_lib.om, which
# supplies SHA-256 and the OMG0 canonical builder), tests/turing/test_ty_qrecord.om,
# docs/turing/TURING_QCONT_RECORDS_V0.md. Picked up by `-include mk/*.mk`; no
# Makefile edit; redefines nothing that exists.
#
# test-turing-qrecord: builds the test with the seeded omc and runs it (pinned
# record and sidecar KATs, refusals, bindings, write-once files and manifests).
# The ASan/UBSan build of the C test is gone. OM-2 traps at run time an out-of-range array get or
# put (3), signed overflow (1), div or rem by 0 (2), a shift amount outside 0..width-1 (7) and an
# out-of-range conversion (5) (docs/one_layer/OMEGESE.md 9.3); unsigned arithmetic wraps as in C.
# Sanitizer checks with no OM-2 counterpart (alignment, use after free, leaks) are not replaced.
ifndef TURING_QRECORD_MK
TURING_QRECORD_MK := 1
.PHONY: test-turing-qrecord
TYQR_OMC ?= seed/out/omc
TYQR_OM_SRCS = src/turing/ty_core_lib.om src/turing/ty_qrecord.om
TYQR_DIR = $(OUT_DIR)/tests-turing-qrecord

$(TYQR_DIR)/test_ty_qrecord: tests/turing/test_ty_qrecord.om $(TYQR_OM_SRCS) $(TYQR_OMC)
	@mkdir -p $(TYQR_DIR)
	(printf 'om2\n'; sed '/^om2$$/d' $(TYQR_OM_SRCS) tests/turing/test_ty_qrecord.om) | $(TYQR_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

test-turing-qrecord: $(TYQR_DIR)/test_ty_qrecord
	./$(TYQR_DIR)/test_ty_qrecord
	@echo "test-turing-qrecord: pure OM-2 record builders, verifiers, refusals and manifests pass"
endif
