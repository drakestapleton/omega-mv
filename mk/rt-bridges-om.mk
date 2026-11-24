# Pure seeded OM-2 runtime bridges & argus_replay wave (rxc_host_abi, rx_resident_gpu, argus_replay).
# CPU-only host tests, zero /dev/nvidia* access, no physics checkout.
# Picked up automatically by `-include mk/*.mk` and runnable standalone via `make -f mk/rt-bridges-om.mk`.
RTBR_OMC ?= seed/out/omc
OUT_DIR ?= build

RTBR_HOST_ABI_SRCS = seed/ng/sha256.om src/runtime/rx_compose.om src/runtime/rxc_host_abi.om tests/runtime/rxc_host_abi_unit.om
RTBR_RESIDENT_SRCS = src/runtime/rx_coherent.om src/runtime/rx_resident_gpu.om tests/runtime/rx_resident_gpu_unit.om
RTBR_ARGUS_REPLAY_SRCS = seed/ng/sha256.om src/runtime/rx_argus.om tools/argus_replay.om

RTBR_HOST_ABI_BIN = $(OUT_DIR)/rxc_host_abi_unit_om
RTBR_RESIDENT_BIN = $(OUT_DIR)/rx_resident_gpu_unit_om
RTBR_ARGUS_REPLAY_BIN = $(OUT_DIR)/argus_replay_om

$(RTBR_HOST_ABI_BIN): $(RTBR_HOST_ABI_SRCS) $(RTBR_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; cat $(RTBR_HOST_ABI_SRCS) ) | $(RTBR_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(RTBR_RESIDENT_BIN): $(RTBR_RESIDENT_SRCS) $(RTBR_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; cat $(RTBR_RESIDENT_SRCS) ) | $(RTBR_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(RTBR_ARGUS_REPLAY_BIN): $(RTBR_ARGUS_REPLAY_SRCS) $(RTBR_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; cat $(RTBR_ARGUS_REPLAY_SRCS) ) | $(RTBR_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-rxc-host-abi-unit-om test-rx-resident-gpu-om test-argus-replay-om test-rt-bridges-om
test-rxc-host-abi-unit-om: $(RTBR_HOST_ABI_BIN)
	./$(RTBR_HOST_ABI_BIN)

test-rx-resident-gpu-om: $(RTBR_RESIDENT_BIN)
	./$(RTBR_RESIDENT_BIN)

test-argus-replay-om: $(RTBR_ARGUS_REPLAY_BIN)
	./$(RTBR_ARGUS_REPLAY_BIN) --self-test

test-rt-bridges-om: test-rxc-host-abi-unit-om test-rx-resident-gpu-om test-argus-replay-om
