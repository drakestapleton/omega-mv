# Omega Visor V1 lane 1 (semantic query API) test target.
# Pure seeded OM-2: tests/visor/test_visor_semantic.om over the OM core and semantic lane.
VISOR_SEMANTIC_OM_SRCS = src/visor/visor.om src/visor/visor_semantic.om
$(OUT_DIR)/tests-visor/test_visor_semantic: tests/visor/test_visor_semantic.om $(VISOR_SEMANTIC_OM_SRCS) $(VISOR_OMC) | $(OUT_DIR)/tests-visor
	(printf 'om2\n'; sed '/^om2$$/d' $(VISOR_SEMANTIC_OM_SRCS) tests/visor/test_visor_semantic.om) | $(VISOR_OMC) > $@ && chmod +x $@

.PHONY: test-visor-semantic
test-visor-semantic: $(OUT_DIR)/tests-visor/test_visor_semantic
	./$(OUT_DIR)/tests-visor/test_visor_semantic
