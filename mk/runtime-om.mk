# Pure seeded OM-2 runtime wave 1 (rx_costmodel, rx_cortex, rx_projection, rx_regulate).
# Host-only, no GPU, no physics checkout. Picked up automatically by `-include mk/*.mk`.
RT_OM_OMC ?= seed/out/omc

RT_OM_CM_SRCS = seed/ng/sha256.om src/runtime/rx_costmodel.om tests/runtime/rx_costmodel_unit.om
RT_OM_CXJ_SRCS = seed/ng/sha256.om src/runtime/rx_cortex.om tests/runtime/rx_cortex_journal.om
RT_OM_PJ_SRCS = seed/ng/sha256.om src/runtime/rx_cortex.om src/runtime/rx_projection.om tests/runtime/rx_projection_unit.om
RT_OM_REG_SRCS = src/runtime/rx_regulate.om tests/runtime/rx_regulate_unit.om

RT_OM_CXJ_TEST = $(OUT_DIR)/rx_cortex_journal_test
RT_OM_PJ_UNIT = $(OUT_DIR)/rx_projection_unit_om
RT_OM_REG_UNIT = $(OUT_DIR)/rx_regulate_unit_om

$(RT_OM_PJ_UNIT): $(RT_OM_PJ_SRCS) $(RT_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT_OM_PJ_SRCS) ) | $(RT_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(RT_OM_REG_UNIT): $(RT_OM_REG_SRCS) $(RT_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT_OM_REG_SRCS) ) | $(RT_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-projection-om test-regulate-om test-cortex-journal-om test-runtime-om
test-projection-om: $(RT_OM_PJ_UNIT)
	./$(RT_OM_PJ_UNIT)

test-regulate-om: $(RT_OM_REG_UNIT)
	./$(RT_OM_REG_UNIT)

test-cortex-journal-om: $(RT_OM_CXJ_TEST)
	./$(RT_OM_CXJ_TEST)

test-runtime-om: test-costmodel test-projection-om test-regulate-om test-cortex-journal-om
