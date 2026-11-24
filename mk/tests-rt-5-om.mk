# Pure seeded OM-2 runtime test wave 5 (10 final CPU-only host suites).
# Host-only, no GPU, no physics checkout. Picked up automatically by `-include mk/*.mk`.
TRT5_OM_OMC ?= seed/out/omc
OUT_DIR ?= build

TRT5_CG_SRCS   = seed/ng/sha256.om src/runtime/rx_compose.om tests/runtime/rx_composition_gate.om
TRT5_HB_SRCS   = seed/ng/sha256.om src/runtime/rx_world.om tests/runtime/rx_heartbeat_test.om
TRT5_PR_SRCS   = seed/ng/sha256.om src/runtime/rx_graph.om src/runtime/rx_plan.om src/runtime/rx_plan_arrange.om tests/runtime/rx_plan_reuse.om
TRT5_R12_SRCS  = src/runtime/rx_coherent.om tests/runtime/rx_r12_resident.om
TRT5_R13E_SRCS = seed/ng/sha256.om src/runtime/rx_cortex.om src/runtime/rx_cortex_record.om tests/runtime/rx_r13_cortex_episode.om
TRT5_R13L_SRCS = seed/ng/sha256.om src/runtime/rx_living.om src/runtime/rx_argus.om tests/runtime/rx_r13_living.om
TRT5_R14_SRCS  = seed/ng/sha256.om src/runtime/rx_generation.om tests/runtime/rx_r14_recovery.om
TRT5_R15G_SRCS = seed/ng/sha256.om src/runtime/rx_generation.om tests/runtime/rx_r15_g7.om
TRT5_R15P_SRCS = src/runtime/rx_seq_reference.om tests/runtime/rx_r15_perf.om
TRT5_R16_SRCS  = seed/authority/cap_table_om2.om src/runtime/rx_caproot.om src/runtime/rx_operator.om src/runtime/rx_aegis.om tests/runtime/rx_r16_negative.om

TRT5_CG_BIN   = $(OUT_DIR)/rx_composition_gate_om
TRT5_HB_BIN   = $(OUT_DIR)/rx_heartbeat_test_om
TRT5_PR_BIN   = $(OUT_DIR)/rx_plan_reuse_om
TRT5_R12_BIN  = $(OUT_DIR)/rx_r12_resident_om
TRT5_R13E_BIN = $(OUT_DIR)/rx_r13_cortex_episode_om
TRT5_R13L_BIN = $(OUT_DIR)/rx_r13_living_om
TRT5_R14_BIN  = $(OUT_DIR)/rx_r14_recovery_om
TRT5_R15G_BIN = $(OUT_DIR)/rx_r15_g7_om
TRT5_R15P_BIN = $(OUT_DIR)/rx_r15_perf_om
TRT5_R16_BIN  = $(OUT_DIR)/rx_r16_negative_om

$(TRT5_CG_BIN): $(TRT5_CG_SRCS) $(TRT5_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT5_CG_SRCS) ) | $(TRT5_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT5_HB_BIN): $(TRT5_HB_SRCS) $(TRT5_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT5_HB_SRCS) ) | $(TRT5_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT5_PR_BIN): $(TRT5_PR_SRCS) $(TRT5_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT5_PR_SRCS) ) | $(TRT5_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT5_R12_BIN): $(TRT5_R12_SRCS) $(TRT5_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT5_R12_SRCS) ) | $(TRT5_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT5_R13E_BIN): $(TRT5_R13E_SRCS) $(TRT5_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT5_R13E_SRCS) ) | $(TRT5_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT5_R13L_BIN): $(TRT5_R13L_SRCS) $(TRT5_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT5_R13L_SRCS) ) | $(TRT5_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT5_R14_BIN): $(TRT5_R14_SRCS) $(TRT5_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT5_R14_SRCS) ) | $(TRT5_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT5_R15G_BIN): $(TRT5_R15G_SRCS) $(TRT5_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT5_R15G_SRCS) ) | $(TRT5_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT5_R15P_BIN): $(TRT5_R15P_SRCS) $(TRT5_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT5_R15P_SRCS) ) | $(TRT5_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT5_R16_BIN): $(TRT5_R16_SRCS) $(TRT5_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT5_R16_SRCS) ) | $(TRT5_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-rx-composition-gate-om test-rx-heartbeat-test-om \
	test-rx-plan-reuse-om test-rx-r12-resident-om \
	test-rx-r13-cortex-episode-om test-rx-r13-living-om \
	test-rx-r14-recovery-om test-rx-r15-g7-om \
	test-rx-r15-perf-om test-rx-r16-negative-om \
	test-tests-rt-5-om

test-rx-composition-gate-om: $(TRT5_CG_BIN)
	$(TRT5_CG_BIN)

test-rx-heartbeat-test-om: $(TRT5_HB_BIN)
	$(TRT5_HB_BIN)

test-rx-plan-reuse-om: $(TRT5_PR_BIN)
	$(TRT5_PR_BIN)

test-rx-r12-resident-om: $(TRT5_R12_BIN)
	$(TRT5_R12_BIN)

test-rx-r13-cortex-episode-om: $(TRT5_R13E_BIN)
	$(TRT5_R13E_BIN)

test-rx-r13-living-om: $(TRT5_R13L_BIN)
	$(TRT5_R13L_BIN)

test-rx-r14-recovery-om: $(TRT5_R14_BIN)
	$(TRT5_R14_BIN)

test-rx-r15-g7-om: $(TRT5_R15G_BIN)
	$(TRT5_R15G_BIN)

test-rx-r15-perf-om: $(TRT5_R15P_BIN)
	$(TRT5_R15P_BIN)

test-rx-r16-negative-om: $(TRT5_R16_BIN)
	$(TRT5_R16_BIN)

test-tests-rt-5-om: test-rx-composition-gate-om test-rx-heartbeat-test-om \
	test-rx-plan-reuse-om test-rx-r12-resident-om \
	test-rx-r13-cortex-episode-om test-rx-r13-living-om \
	test-rx-r14-recovery-om test-rx-r15-g7-om \
	test-rx-r15-perf-om test-rx-r16-negative-om
