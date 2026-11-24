# Accelerator port capability, EffectIntent, EffectReceipt seal chain, and machine graph binding
# (src/omega_accelerator.om, twin of src/omega_accelerator.c). Pure seeded OM-2, physics-free, host-only.
OMEGA_ACCELERATOR_OM_OMC ?= seed/out/omc
OMEGA_ACCELERATOR_OM_SRCS := seed/ng/sha256.om om/aarch64/aarch64_om2.om src/omega_machine.om src/omega_accelerator.om tests/test_omega_accelerator.om
OMEGA_ACCELERATOR_OM_TEST = $(OUT_DIR)/test_omega_accelerator_om

$(OMEGA_ACCELERATOR_OM_TEST): $(OMEGA_ACCELERATOR_OM_SRCS) $(OMEGA_ACCELERATOR_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(OMEGA_ACCELERATOR_OM_SRCS)) | $(OMEGA_ACCELERATOR_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-omega-accelerator-om
test-omega-accelerator-om: $(OMEGA_ACCELERATOR_OM_TEST)
	$(abspath $(OMEGA_ACCELERATOR_OM_TEST))
