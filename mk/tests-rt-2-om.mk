# Pure seeded OM-2 runtime test wave 2 (8 CPU-only host suites).
# Host-only, no GPU, no physics checkout. Picked up automatically by `-include mk/*.mk`.
TRT2_OM_OMC ?= seed/out/omc

TRT2_I11_SRCS  = seed/ng/sha256.om src/runtime/rx_world.om tests/runtime/rx_i11_wake_merge.om
TRT2_R15I_SRCS = seed/ng/sha256.om src/runtime/rx_world.om src/runtime/rx_generation.om tests/runtime/rx_r15_instr.om
TRT2_CG_SRCS   = seed/ng/sha256.om om/runtime/rx_mid.om om/runtime/rx_capq_core.om om/runtime/rx_skillroute_core.om src/runtime/rx_graph.om src/runtime/rx_capq.om src/runtime/rx_skillroute.om tests/runtime/rx_capability_graph.om
TRT2_R7_SRCS   = seed/ng/sha256.om src/omega_evidence.om src/runtime/aien_machine_id.om tests/runtime/rx_argus_env.om seed/authority/cap_table_om2.om src/runtime/rx_caproot.om tests/runtime/rx_r7_native.om
TRT2_R8_SRCS   = seed/ng/sha256.om src/omega_evidence.om src/runtime/aien_machine_id.om tests/runtime/rx_argus_env.om src/runtime/rx_world.om src/runtime/rx_aegis.om tests/runtime/rx_r8_aegis.om
TRT2_R9_SRCS   = seed/ng/sha256.om src/omega_evidence.om src/runtime/aien_machine_id.om tests/runtime/rx_argus_env.om seed/authority/cap_table_om2.om src/runtime/rx_caproot.om src/runtime/rx_generation.om tests/runtime/rx_r9_barrier.om
TRT2_R10_SRCS  = seed/ng/sha256.om src/runtime/rx_world.om src/runtime/rx_omega.om tests/runtime/rx_r10_omega.om
TRT2_EM_SRCS   = seed/ng/sha256.om src/runtime/rx_world.om src/runtime/rx_generation.om tests/runtime/rx_emergency.om

TRT2_I11_BIN  = $(OUT_DIR)/rx_i11_wake_merge_om
TRT2_R15I_BIN = $(OUT_DIR)/rx_r15_instr_om
TRT2_CG_BIN   = $(OUT_DIR)/rx_capability_graph_om
TRT2_R7_BIN   = $(OUT_DIR)/rx_r7_native_om
TRT2_R8_BIN   = $(OUT_DIR)/rx_r8_aegis_om
TRT2_R9_BIN   = $(OUT_DIR)/rx_r9_barrier_om
TRT2_R10_BIN  = $(OUT_DIR)/rx_r10_omega_om
TRT2_EM_BIN   = $(OUT_DIR)/rx_emergency_om

$(TRT2_I11_BIN): $(TRT2_I11_SRCS) $(TRT2_OM_OMC) | $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT2_I11_SRCS) ) | $(TRT2_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT2_R15I_BIN): $(TRT2_R15I_SRCS) $(TRT2_OM_OMC) | $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT2_R15I_SRCS) ) | $(TRT2_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT2_CG_BIN): $(TRT2_CG_SRCS) $(TRT2_OM_OMC) | $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT2_CG_SRCS) ) | $(TRT2_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT2_R7_BIN): $(TRT2_R7_SRCS) $(TRT2_OM_OMC) | $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT2_R7_SRCS) ) | $(TRT2_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT2_R8_BIN): $(TRT2_R8_SRCS) $(TRT2_OM_OMC) | $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT2_R8_SRCS) ) | $(TRT2_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT2_R9_BIN): $(TRT2_R9_SRCS) $(TRT2_OM_OMC) | $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT2_R9_SRCS) ) | $(TRT2_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT2_R10_BIN): $(TRT2_R10_SRCS) $(TRT2_OM_OMC) | $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT2_R10_SRCS) ) | $(TRT2_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT2_EM_BIN): $(TRT2_EM_SRCS) $(TRT2_OM_OMC) | $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT2_EM_SRCS) ) | $(TRT2_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-rx-i11-wake-merge-om test-rx-r15-instr-om test-rx-capability-graph-om \
	test-rx-r7-native-om test-rx-r8-aegis-om test-rx-r9-barrier-om \
	test-rx-r10-omega-om test-rx-emergency-om test-tests-rt-2-om

test-rx-i11-wake-merge-om: $(TRT2_I11_BIN)
	./$(TRT2_I11_BIN)

test-rx-r15-instr-om: $(TRT2_R15I_BIN)
	./$(TRT2_R15I_BIN)

test-rx-capability-graph-om: $(TRT2_CG_BIN)
	./$(TRT2_CG_BIN)

test-rx-r7-native-om: $(TRT2_R7_BIN)
	./$(TRT2_R7_BIN)

test-rx-r8-aegis-om: $(TRT2_R8_BIN)
	./$(TRT2_R8_BIN)

test-rx-r9-barrier-om: $(TRT2_R9_BIN)
	./$(TRT2_R9_BIN)

test-rx-r10-omega-om: $(TRT2_R10_BIN)
	./$(TRT2_R10_BIN)

test-rx-emergency-om: $(TRT2_EM_BIN)
	./$(TRT2_EM_BIN)

test-tests-rt-2-om: test-rx-i11-wake-merge-om test-rx-r15-instr-om test-rx-capability-graph-om \
	test-rx-r7-native-om test-rx-r8-aegis-om test-rx-r9-barrier-om \
	test-rx-r10-omega-om test-rx-emergency-om
