# Omega Visor V1 - lane 4 (verification + evidence explorer) test targets.
# test_visor_verify: pure seeded OM-2 (tests/visor/test_visor_verify.om), built by
# $(VISOR_OMC) from the verify module, the machine module, the OM-2 verify/validate/aarch64
# units it calls (their `export fn` becomes `fn` in a whole program) and the shared Visor core.
# test_visor_evidence: pure seeded OM-2 (tests/visor/test_visor_evidence.om), built by
# $(VISOR_OMC) from the evidence module and the shared Visor core; run from the repo root.
VISOR_VERIFY_OM_SRCS = src/visor/visor.om src/visor/visor_machine.om \
	om/aarch64/aarch64_om2.om om/visor/verify_om2.om om/visor/validate_om2.om \
	src/visor/visor_verify.om src/visor/visor_effect_request.om
VISOR_EVIDENCE_OM_SRCS = src/visor/visor.om src/visor/visor_evidence.om

$(OUT_DIR)/tests-visor/test_visor_verify: tests/visor/test_visor_verify.om $(VISOR_VERIFY_OM_SRCS) $(VISOR_OMC) | $(OUT_DIR)/tests-visor
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(VISOR_VERIFY_OM_SRCS) tests/visor/test_visor_verify.om) | $(VISOR_OMC) > $@ && chmod +x $@

$(OUT_DIR)/tests-visor/test_visor_evidence: tests/visor/test_visor_evidence.om $(VISOR_EVIDENCE_OM_SRCS) $(VISOR_OMC) | $(OUT_DIR)/tests-visor
	(printf 'om2\n'; sed '/^om2$$/d' $(VISOR_EVIDENCE_OM_SRCS) tests/visor/test_visor_evidence.om) | $(VISOR_OMC) > $@ && chmod +x $@

.PHONY: test-visor-verify test-visor-evidence

test-visor-verify: $(OUT_DIR)/tests-visor/test_visor_verify
	./$(OUT_DIR)/tests-visor/test_visor_verify

test-visor-evidence: $(OUT_DIR)/tests-visor/test_visor_evidence
	./$(OUT_DIR)/tests-visor/test_visor_evidence
