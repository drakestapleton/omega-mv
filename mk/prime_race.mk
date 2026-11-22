# AIEN Prime Drag Race (bench/prime_race/): implementation-side protocol + conventional CPU baseline.
# Pure seeded OM-2 standalone module under bench/prime_race/. Picked up by `-include mk/*.mk`;
# not part of `all` or `test`. No C, no physics, no GPU, no libraries.
#
# prime-race-cpu        builds bench/prime_race/build/cpu_base via seed/out/omc
# prime-race-host-test  trial-division oracle test of cpu_base + protocol formatting/parsing
ifndef PRIME_RACE_MK
PRIME_RACE_MK := 1
.PHONY: prime-race-cpu prime-race-host-test
PR_DIR = bench/prime_race
PR_BUILD = $(PR_DIR)/build
PR_OMC ?= seed/out/omc
PR_CORE_OM = $(PR_DIR)/prime_race_impl.om $(PR_DIR)/cpu_base.om

$(PR_BUILD)/cpu_base: $(PR_CORE_OM) $(PR_DIR)/cpu_base_main.om $(PR_OMC)
	@mkdir -p $(PR_BUILD)
	cat $(PR_CORE_OM) $(PR_DIR)/cpu_base_main.om | $(PR_OMC) > $@
	chmod +x $@
prime-race-cpu: $(PR_BUILD)/cpu_base

$(PR_BUILD)/prime_race_host_test: $(PR_CORE_OM) $(PR_DIR)/tests/prime_race_host_test.om $(PR_OMC)
	@mkdir -p $(PR_BUILD)
	cat $(PR_CORE_OM) $(PR_DIR)/tests/prime_race_host_test.om | $(PR_OMC) > $@
	chmod +x $@
prime-race-host-test: $(PR_BUILD)/prime_race_host_test
	./$(PR_BUILD)/prime_race_host_test
endif
