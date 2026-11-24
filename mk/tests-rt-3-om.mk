# Pure seeded OM-2 runtime test wave 3 (9 CPU-only host suites).
# Host-only, no GPU, no physics checkout. Picked up automatically by `-include mk/*.mk`.
TRT3_OM_OMC ?= seed/out/omc
OUT_DIR ?= build

TRT3_DJT_SRCS  = seed/ng/sha256.om src/runtime/rx_jspace.om tests/runtime/rx_dual_jspace_tap.om
TRT3_DJTB_SRCS = seed/ng/sha256.om src/runtime/rx_jspace.om tests/runtime/rx_dual_jspace_tap_bench.om
TRT3_BRR_SRCS  = seed/ng/sha256.om src/runtime/rx_jspace.om tests/runtime/rx_branch_reuse.om
TRT3_JSP_SRCS  = seed/ng/sha256.om src/runtime/rx_jspace.om tests/runtime/rx_jspace_prod.om
TRT3_HABI_SRCS = seed/ng/sha256.om src/runtime/rx_compose.om tests/runtime/rxc_host_abi_test.om
TRT3_CMP_SRCS  = seed/ng/sha256.om src/runtime/rx_compose.om tests/runtime/rx_compose_test.om
TRT3_ATT_SRCS  = seed/ng/sha256.om src/runtime/rx_compose.om tests/runtime/rx_compose_attach_test.om
TRT3_C4R_SRCS  = seed/ng/sha256.om src/runtime/rx_compose.om tests/runtime/rx_c4_requal.om
TRT3_R11_SRCS  = src/runtime/rx_aien.om tests/runtime/rx_r11_aien.om

TRT3_DJT_BIN  = $(OUT_DIR)/rx_dual_jspace_tap_om
TRT3_DJTB_BIN = $(OUT_DIR)/rx_dual_jspace_tap_bench_om
TRT3_BRR_BIN  = $(OUT_DIR)/rx_branch_reuse_om
TRT3_JSP_BIN  = $(OUT_DIR)/rx_jspace_prod_om
TRT3_HABI_BIN = $(OUT_DIR)/rxc_host_abi_test_om
TRT3_CMP_BIN  = $(OUT_DIR)/rx_compose_test_om
TRT3_ATT_BIN  = $(OUT_DIR)/rx_compose_attach_test_om
TRT3_C4R_BIN  = $(OUT_DIR)/rx_c4_requal_om
TRT3_R11_BIN  = $(OUT_DIR)/rx_r11_aien_om

$(TRT3_DJT_BIN): $(TRT3_DJT_SRCS) $(TRT3_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT3_DJT_SRCS) ) | $(TRT3_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT3_DJTB_BIN): $(TRT3_DJTB_SRCS) $(TRT3_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT3_DJTB_SRCS) ) | $(TRT3_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT3_BRR_BIN): $(TRT3_BRR_SRCS) $(TRT3_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT3_BRR_SRCS) ) | $(TRT3_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT3_JSP_BIN): $(TRT3_JSP_SRCS) $(TRT3_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT3_JSP_SRCS) ) | $(TRT3_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT3_HABI_BIN): $(TRT3_HABI_SRCS) $(TRT3_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT3_HABI_SRCS) ) | $(TRT3_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT3_CMP_BIN): $(TRT3_CMP_SRCS) $(TRT3_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT3_CMP_SRCS) ) | $(TRT3_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT3_ATT_BIN): $(TRT3_ATT_SRCS) $(TRT3_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT3_ATT_SRCS) ) | $(TRT3_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT3_C4R_BIN): $(TRT3_C4R_SRCS) $(TRT3_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT3_C4R_SRCS) ) | $(TRT3_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT3_R11_BIN): $(TRT3_R11_SRCS) $(TRT3_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT3_R11_SRCS) ) | $(TRT3_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-rx-dual-jspace-tap-om test-rx-dual-jspace-tap-bench-om \
	test-rx-branch-reuse-om test-rx-jspace-prod-om \
	test-rxc-host-abi-om test-rx-compose-test-om \
	test-rx-compose-attach-om test-rx-c4-requal-om \
	test-rx-r11-aien-om test-tests-rt-3-om

test-rx-dual-jspace-tap-om: $(TRT3_DJT_BIN)
	$(TRT3_DJT_BIN)

test-rx-dual-jspace-tap-bench-om: $(TRT3_DJTB_BIN)
	$(TRT3_DJTB_BIN)

test-rx-branch-reuse-om: $(TRT3_BRR_BIN)
	$(TRT3_BRR_BIN)

test-rx-jspace-prod-om: $(TRT3_JSP_BIN)
	$(TRT3_JSP_BIN)

test-rxc-host-abi-om: $(TRT3_HABI_BIN)
	$(TRT3_HABI_BIN)

test-rx-compose-test-om: $(TRT3_CMP_BIN)
	$(TRT3_CMP_BIN)

test-rx-compose-attach-om: $(TRT3_ATT_BIN)
	$(TRT3_ATT_BIN)

test-rx-c4-requal-om: $(TRT3_C4R_BIN)
	$(TRT3_C4R_BIN)

test-rx-r11-aien-om: $(TRT3_R11_BIN)
	$(TRT3_R11_BIN)

test-tests-rt-3-om: test-rx-dual-jspace-tap-om test-rx-dual-jspace-tap-bench-om \
	test-rx-branch-reuse-om test-rx-jspace-prod-om \
	test-rxc-host-abi-om test-rx-compose-test-om \
	test-rx-compose-attach-om test-rx-c4-requal-om \
	test-rx-r11-aien-om
