# Accelerator World persistent substrate (src/omega_accelerator_world.om, twin of src/omega_accelerator_world.c).
# Pure seeded OM-2, physics-free, CPU-only host test (zero /dev/nvidia* access).
OMEGA_ACCEL_WORLD_OM_OMC ?= seed/out/omc
OMEGA_ACCEL_WORLD_OM_SRCS := seed/ng/sha256.om src/omega_accelerator_world.om tests/test_omega_accelerator_world.om
OMEGA_ACCEL_WORLD_OM_TEST = $(OUT_DIR)/test_omega_accelerator_world_om

$(OMEGA_ACCEL_WORLD_OM_TEST): $(OMEGA_ACCEL_WORLD_OM_SRCS) $(OMEGA_ACCEL_WORLD_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(OMEGA_ACCEL_WORLD_OM_SRCS)) | $(OMEGA_ACCEL_WORLD_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-omega-accelerator-world-om
test-omega-accelerator-world-om: $(OMEGA_ACCEL_WORLD_OM_TEST)
	$(abspath $(OMEGA_ACCEL_WORLD_OM_TEST))
