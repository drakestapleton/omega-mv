# Pure seeded OM-2 runtime test wave 1 (7 CPU-only host suites).
# Host-only, no GPU, no physics checkout. Picked up automatically by `-include mk/*.mk`.
TRT1_OM_OMC ?= seed/out/omc

TRT1_GWA_SRCS  = seed/ng/sha256.om src/runtime/rx_generation.om tests/runtime/rx_gen_work_auth.om
TRT1_SD_SRCS   = tests/runtime/r15_seat_diag_test.om
TRT1_OAM_SRCS  = seed/authority/cap_table_om2.om src/runtime/rx_caproot.om src/runtime/rx_operator.om tests/runtime/rx_operator_authority_misuse.om
TRT1_REG_SRCS  = seed/ng/sha256.om src/runtime/rx_world.om src/runtime/rx_regulate.om tests/runtime/rx_regulate_test.om
TRT1_CXC_SRCS  = seed/ng/sha256.om src/runtime/rx_cortex.om src/runtime/rx_cortex_record.om tests/runtime/rx_cortex_canon.om
TRT1_DLC_SRCS  = seed/ng/sha256.om src/runtime/rx_world.om tests/runtime/rx_deadline_cancel.om
TRT1_SRC_SRCS  = seed/ng/sha256.om om/runtime/rx_mid.om om/runtime/rx_capq_core.om om/runtime/rx_skillroute_core.om src/runtime/rx_graph.om src/runtime/rx_capq.om src/runtime/rx_skillroute.om tests/runtime/rx_skillroute_compose_test.om

TRT1_GWA_BIN = $(OUT_DIR)/rx_gen_work_auth_om
TRT1_SD_BIN  = $(OUT_DIR)/r15_seat_diag_test_om
TRT1_OAM_BIN = $(OUT_DIR)/rx_operator_authority_misuse_om
TRT1_REG_BIN = $(OUT_DIR)/rx_regulate_test_om
TRT1_CXC_BIN = $(OUT_DIR)/rx_cortex_canon_om
TRT1_DLC_BIN = $(OUT_DIR)/rx_deadline_cancel_om
TRT1_SRC_BIN = $(OUT_DIR)/rx_skillroute_compose_test_om

$(TRT1_GWA_BIN): $(TRT1_GWA_SRCS) $(TRT1_OM_OMC) | $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT1_GWA_SRCS) ) | $(TRT1_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT1_SD_BIN): $(TRT1_SD_SRCS) $(TRT1_OM_OMC) | $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT1_SD_SRCS) ) | $(TRT1_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT1_OAM_BIN): $(TRT1_OAM_SRCS) $(TRT1_OM_OMC) | $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT1_OAM_SRCS) ) | $(TRT1_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT1_REG_BIN): $(TRT1_REG_SRCS) $(TRT1_OM_OMC) | $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT1_REG_SRCS) ) | $(TRT1_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT1_CXC_BIN): $(TRT1_CXC_SRCS) $(TRT1_OM_OMC) | $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT1_CXC_SRCS) ) | $(TRT1_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT1_DLC_BIN): $(TRT1_DLC_SRCS) $(TRT1_OM_OMC) | $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT1_DLC_SRCS) ) | $(TRT1_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT1_SRC_BIN): $(TRT1_SRC_SRCS) $(TRT1_OM_OMC) | $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT1_SRC_SRCS) ) | $(TRT1_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-rx-gen-work-auth-om test-r15-seat-diag-om test-rx-operator-misuse-om \
	test-rx-regulate-test-om test-rx-cortex-canon-om test-rx-deadline-cancel-om \
	test-rx-skillroute-compose-om test-tests-rt-1-om

test-rx-gen-work-auth-om: $(TRT1_GWA_BIN)
	./$(TRT1_GWA_BIN)

test-r15-seat-diag-om: $(TRT1_SD_BIN)
	./$(TRT1_SD_BIN)

test-rx-operator-misuse-om: $(TRT1_OAM_BIN)
	./$(TRT1_OAM_BIN)

test-rx-regulate-test-om: $(TRT1_REG_BIN)
	./$(TRT1_REG_BIN)

test-rx-cortex-canon-om: $(TRT1_CXC_BIN)
	./$(TRT1_CXC_BIN)

test-rx-deadline-cancel-om: $(TRT1_DLC_BIN)
	./$(TRT1_DLC_BIN)

test-rx-skillroute-compose-om: $(TRT1_SRC_BIN)
	./$(TRT1_SRC_BIN)

test-tests-rt-1-om: test-rx-gen-work-auth-om test-r15-seat-diag-om test-rx-operator-misuse-om \
	test-rx-regulate-test-om test-rx-cortex-canon-om test-rx-deadline-cancel-om \
	test-rx-skillroute-compose-om
