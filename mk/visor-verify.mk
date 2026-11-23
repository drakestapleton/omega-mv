# Omega Visor V1 - lane 4 (verification + evidence explorer) test targets.
# test_visor_verify: the generic $(OUT_DIR)/tests-visor/% C rule in mk/00-visor-core.mk.
# test_visor_evidence: pure seeded OM-2 (tests/visor/test_visor_evidence.om), built by
# $(VISOR_OMC) from the evidence module and the shared Visor core; run from the repo root.
VISOR_EVIDENCE_OM_SRCS = src/visor/visor.om src/visor/visor_evidence.om

$(OUT_DIR)/tests-visor/test_visor_evidence: tests/visor/test_visor_evidence.om $(VISOR_EVIDENCE_OM_SRCS) $(VISOR_OMC) | $(OUT_DIR)/tests-visor
	(printf 'om2\n'; sed '/^om2$$/d' $(VISOR_EVIDENCE_OM_SRCS) tests/visor/test_visor_evidence.om) | $(VISOR_OMC) > $@ && chmod +x $@

.PHONY: test-visor-verify test-visor-evidence

test-visor-verify: $(OUT_DIR)/tests-visor/test_visor_verify
	./$(OUT_DIR)/tests-visor/test_visor_verify

test-visor-evidence: $(OUT_DIR)/tests-visor/test_visor_evidence
	./$(OUT_DIR)/tests-visor/test_visor_evidence
