# Accelerator World M19/M19R qualification gates (src/omega_world_gates.om, twin of src/omega_world_gates.c).
# Pure seeded OM-2, physics-free, CPU-only host test (zero /dev/nvidia* access).
OMEGA_WORLD_GATES_OM_OMC ?= seed/out/omc
OMEGA_WORLD_GATES_OM_SRCS := seed/ng/sha256.om src/omega_accelerator_world.om src/omega_world_gates.om tests/test_omega_world_gates.om
OMEGA_WORLD_GATES_OM_TEST = $(OUT_DIR)/test_omega_world_gates_om

$(OMEGA_WORLD_GATES_OM_TEST): $(OMEGA_WORLD_GATES_OM_SRCS) $(OMEGA_WORLD_GATES_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(OMEGA_WORLD_GATES_OM_SRCS)) | $(OMEGA_WORLD_GATES_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-omega-world-gates-om
test-omega-world-gates-om: $(OMEGA_WORLD_GATES_OM_TEST)
	$(abspath $(OMEGA_WORLD_GATES_OM_TEST))
