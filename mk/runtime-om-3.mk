# Pure seeded OM-2 runtime wave 3 (rx_aegis, rx_aien, rx_cortex_record, rx_plan, rx_semcomm).
# Host-only, no GPU, no physics checkout. Picked up automatically by `-include mk/*.mk`.
RT3_OM_OMC ?= seed/out/omc

RT3_AEGIS_SRCS = src/runtime/rx_aegis.om tests/runtime/rx_aegis_unit.om
RT3_AIEN_SRCS = src/runtime/rx_aien.om tests/runtime/rx_aien_unit.om
RT3_CXREC_SRCS = seed/ng/sha256.om src/runtime/rx_cortex.om src/runtime/rx_cortex_record.om tests/runtime/rx_cortex_record_unit.om
RT3_PLAN_SRCS = seed/ng/sha256.om src/runtime/rx_plan.om tests/runtime/rx_plan_unit.om
RT3_SEMCOMM_SRCS = seed/ng/sha256.om src/runtime/rx_semcomm.om tests/runtime/rx_semcomm_unit.om

RT3_AEGIS_BIN = $(OUT_DIR)/rx_aegis_unit_om
RT3_AIEN_BIN = $(OUT_DIR)/rx_aien_unit_om
RT3_CXREC_BIN = $(OUT_DIR)/rx_cortex_record_unit_om
RT3_PLAN_BIN = $(OUT_DIR)/rx_plan_unit_om
RT3_SEMCOMM_BIN = $(OUT_DIR)/rx_semcomm_unit_om

$(RT3_AEGIS_BIN): $(RT3_AEGIS_SRCS) $(RT3_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT3_AEGIS_SRCS) ) | $(RT3_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(RT3_AIEN_BIN): $(RT3_AIEN_SRCS) $(RT3_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT3_AIEN_SRCS) ) | $(RT3_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(RT3_CXREC_BIN): $(RT3_CXREC_SRCS) $(RT3_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT3_CXREC_SRCS) ) | $(RT3_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(RT3_PLAN_BIN): $(RT3_PLAN_SRCS) $(RT3_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT3_PLAN_SRCS) ) | $(RT3_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(RT3_SEMCOMM_BIN): $(RT3_SEMCOMM_SRCS) $(RT3_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT3_SEMCOMM_SRCS) ) | $(RT3_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-aegis-om test-aien-om test-cortex-record-om test-plan-om test-semcomm-om test-runtime-om-3
test-aegis-om: $(RT3_AEGIS_BIN)
	./$(RT3_AEGIS_BIN)

test-aien-om: $(RT3_AIEN_BIN)
	./$(RT3_AIEN_BIN)

test-cortex-record-om: $(RT3_CXREC_BIN)
	./$(RT3_CXREC_BIN)

test-plan-om: $(RT3_PLAN_BIN)
	./$(RT3_PLAN_BIN)

test-semcomm-om: $(RT3_SEMCOMM_BIN)
	./$(RT3_SEMCOMM_BIN)

test-runtime-om-3: test-aegis-om test-aien-om test-cortex-record-om test-plan-om test-semcomm-om
