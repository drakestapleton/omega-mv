# Pure seeded OM-2 runtime wave 6 (rx_world, rx_living, rx_omega).
# Host-only, no GPU, no physics checkout. Picked up automatically by `-include mk/*.mk`.
RT6_OM_OMC ?= seed/out/omc

RT6_WORLD_SRCS = seed/ng/sha256.om src/runtime/rx_world.om tests/runtime/rx_world_unit.om
RT6_LIVING_SRCS = seed/ng/sha256.om src/runtime/rx_living.om tests/runtime/rx_living_unit.om
RT6_OMEGA_SRCS = seed/ng/sha256.om src/runtime/rx_omega.om tests/runtime/rx_omega_unit.om

RT6_WORLD_BIN = $(OUT_DIR)/rx_world_unit_om
RT6_LIVING_BIN = $(OUT_DIR)/rx_living_unit_om
RT6_OMEGA_BIN = $(OUT_DIR)/rx_omega_unit_om

$(RT6_WORLD_BIN): $(RT6_WORLD_SRCS) $(RT6_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT6_WORLD_SRCS) ) | $(RT6_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(RT6_LIVING_BIN): $(RT6_LIVING_SRCS) $(RT6_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT6_LIVING_SRCS) ) | $(RT6_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(RT6_OMEGA_BIN): $(RT6_OMEGA_SRCS) $(RT6_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT6_OMEGA_SRCS) ) | $(RT6_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-world-om test-living-om test-omega-om test-runtime-om-6
test-world-om: $(RT6_WORLD_BIN)
	./$(RT6_WORLD_BIN)

test-living-om: $(RT6_LIVING_BIN)
	./$(RT6_LIVING_BIN)

test-omega-om: $(RT6_OMEGA_BIN)
	./$(RT6_OMEGA_BIN)

test-runtime-om-6: test-world-om test-living-om test-omega-om
