# PD-0 experiment planner (Direction 5): contract tests, purity check, passive baseline
# and the information-efficiency comparison (development evidence, not EXP-003).
# Pure OM-2 (wave 36b): the planner, its contract tests, the test-only world bridge and both
# efficiency comparisons are built from .om by the seed omc. The ASan/UBSan run of the C build is
# gone. What OM-2 checks at run time instead (docs/one_layer/OMEGESE.md 9.3; exit 100 + trap): an
# out-of-range array get or put traps 3; signed add, sub, mul, neg, div and shl outside the type
# trap 1; div or rem by 0 traps 2; a shift amount outside 0..width-1 traps 7; an out-of-range
# conversion traps 5. Unsigned arithmetic wraps by definition, as in C. Sanitizer checks with no
# OM-2 run-time counterpart (alignment, use after free, leaks) are not replaced and not claimed.
ifndef PHYSICS0_PLANNER_MK
PHYSICS0_PLANNER_MK := 1
.PHONY: test-physics0-planner p0p-purity physics0-planner-eff physics0-planner-eff2

P0P_COMMIT := $(shell git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)
P0P_OMC ?= seed/out/omc
P0P_DIR = $(OUT_DIR)/tests-physics0-planner
# planner units: verifier formats only, no generator, no world. pd0_planner_types.om comes first
# (an OM-2 struct is declared before the program's first fn).
P0P_OM_LIB = src/physics0/planner/pd0_planner_types.om src/physics0/pd0_types.om src/physics0/pd0_rng.om src/physics0/pd0_wire.om \
  src/physics0/ladder/pd0_codes.om src/physics0/ladder/pd0_fmt.om src/physics0/planner/pd0_planner.om
# bridge side: substrate formats, links the generator on purpose (harness side, never a planner unit)
P0P_OM_WORLD = src/physics0/pd0_chan.om src/physics0/pd0_relation.om src/physics0/pd0_world.om tests/physics0/planner/pd0p_bridge.om
P0P_OM_TEST = $(P0P_OM_LIB) tests/physics0/planner/test_pd0_planner.om
P0P_OM_EFF = $(P0P_OM_LIB) $(P0P_OM_WORLD) tests/physics0/planner/pd0p_eff_lib.om tests/physics0/planner/pd0_plan_eff.om
P0P_OM_EFF2 = $(P0P_OM_LIB) $(P0P_OM_WORLD) tests/physics0/planner/pd0p_eff_lib.om tests/physics0/planner/pd0_plan_eff2.om
P0P_FORBIDDEN = 'pd0_gen|pd0_world|oracle|truth_|forge_|argus_|mmap|fork|exec|socket'
# OM host words a planner unit must not use (process, socket, map, device, file open/remove, environment)
P0P_OM_HOST = 'fork|execprog|execpure|socknew|connect|bind|listen|accept|mapnew|mapbind|fopen|unlink|devctl|devcall|pipefds|killpid|envread|getenv'

$(P0P_DIR)/test_pd0_planner: $(P0P_OM_TEST) $(P0P_OMC)
	@mkdir -p $(P0P_DIR)
	{ echo "om2"; cat $(P0P_OM_TEST); } | $(P0P_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@
$(P0P_DIR)/pd0_plan_eff: $(P0P_OM_EFF) $(P0P_OMC)
	@mkdir -p $(P0P_DIR)
	{ echo "om2"; cat $(P0P_OM_EFF); } | $(P0P_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@
$(P0P_DIR)/pd0_plan_eff2: $(P0P_OM_EFF2) $(P0P_OMC)
	@mkdir -p $(P0P_DIR)
	{ echo "om2"; cat $(P0P_OM_EFF2); } | $(P0P_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

# purity: the planner units (code lines; notes excluded) carry no generator, world or authority name and
# use no host process/socket/map/file word; both checks are shown to bite on the harness side
p0p-purity:
	@if grep -hv '^[[:space:]]*note' $(P0P_OM_LIB) | grep -E $(P0P_FORBIDDEN); then echo "planner OM sources reference generator, world or authority names"; exit 1; fi
	@if grep -hv '^[[:space:]]*note' $(P0P_OM_LIB) | grep -wE $(P0P_OM_HOST); then echo "planner OM sources use a process, socket, map or file host word"; exit 1; fi
	@grep -hv '^[[:space:]]*note' tests/physics0/planner/pd0p_bridge.om | grep -qE $(P0P_FORBIDDEN) || { echo "p0p-purity: the name check does not bite (the bridge carries no world name)"; exit 1; }
	@grep -hv '^[[:space:]]*note' tests/physics0/planner/pd0p_eff_lib.om | grep -qwE $(P0P_OM_HOST) || { echo "p0p-purity: the host-word check does not bite"; exit 1; }
	@echo "p0p-purity: planner OM units carry no generator, world, authority or host I/O name (both checks bite on the harness side)"

physics0-planner-eff: $(P0P_DIR)/pd0_plan_eff
	@rm -f $(P0P_DIR)/pd0-planner-eff.json
	./$(P0P_DIR)/pd0_plan_eff $(P0P_DIR)/pd0-planner-eff.json $(P0P_COMMIT) | tee $(P0P_DIR)/eff.out | tail -3
	@grep -q '^PD0_PLANNER_EFF: PASS$$' $(P0P_DIR)/eff.out

physics0-planner-eff2: $(P0P_DIR)/pd0_plan_eff2
	@rm -f $(P0P_DIR)/pd0-planner-eff2.json
	./$(P0P_DIR)/pd0_plan_eff2 $(P0P_DIR)/pd0-planner-eff2.json $(P0P_COMMIT) | tee $(P0P_DIR)/eff2.out | tail -6
	@grep -q '^PD0_PLANNER_EFF2: PASS' $(P0P_DIR)/eff2.out

test-physics0-planner: p0p-purity $(P0P_DIR)/test_pd0_planner physics0-planner-eff physics0-planner-eff2
	./$(P0P_DIR)/test_pd0_planner
	@echo "test-physics0-planner: PD-0 planner contract (behaviours 1-6), mutants, passive baseline and efficiency comparison pass (pure OM-2); receipt in $(P0P_DIR)/pd0-planner-eff.json"
endif
