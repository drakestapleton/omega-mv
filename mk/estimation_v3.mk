# ESTIMATION-2 protocol v3: discrete predictive layer (src/estimation/est_pred.om).
# Picked up by `-include mk/*.mk`; not part of `all` or `test`.
#
# test-est-pred       hostile suite (pure OM-2)
# est-v3-purity       OM-2 purity scan on est_pred.om against EST_OM_FORBIDDEN
# test-estimation-v3  both
ifndef ESTIMATION_V3_MK
ESTIMATION_V3_MK := 1
include mk/estimation.mk
.PHONY: test-est-pred est-v3-purity test-estimation-v3
ESTV3_DIR = $(OUT_DIR)/tests-estimation-v3

est-v3-purity: src/estimation/est_pred.om
	@awk -v re='$(EST_OM_FORBIDDEN)' '$$1 != "note" && $$1 != "text" && $$0 ~ re { print FILENAME ":" FNR ": " $$0; bad = 1 } END { exit bad }' \
		src/estimation/est_pred.om || { echo "est_pred.om references an operation an estimator must not have"; exit 1; }
	@echo "est-v3-purity: est_pred.om references no forbidden symbol (pure OM-2)"

EST_OM_PRED = $(EST_OM_TYPES) src/estimation/est_mix.om src/estimation/est_pred.om

$(ESTV3_DIR)/test_est_pred: $(EST_OM_PRED) tests/estimation/test_est_pred.om $(EST_OMC)
	@mkdir -p $(ESTV3_DIR)
	cat $(EST_OM_PRED) tests/estimation/test_est_pred.om | $(EST_OMC) > $@ && chmod +x $@

test-est-pred: $(ESTV3_DIR)/test_est_pred
	./$(ESTV3_DIR)/test_est_pred
	@echo "test-est-pred: est_pred contract, numerics and calibration scenarios pass (pure OM-2)"

test-estimation-v3: est-v3-purity test-est-pred
	@echo "test-estimation-v3: ESTIMATION-2 v3 predictive layer passes"
endif
