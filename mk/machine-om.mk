# Machine graph profiles, topology validation & latency model (src/omega_machine.om,
# twin of src/omega_machine.c). Pure seeded OM-2, physics-free, host-only.
MACHINE_OM_OMC ?= seed/out/omc
MACHINE_OM_SRCS := seed/ng/sha256.om om/aarch64/aarch64_om2.om src/omega_machine.om tests/test_omega_machine.om
MACHINE_OM_TEST = $(OUT_DIR)/test_omega_machine_om

$(MACHINE_OM_TEST): $(MACHINE_OM_SRCS) $(MACHINE_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(MACHINE_OM_SRCS)) | $(MACHINE_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-machine-om
test-machine-om: $(MACHINE_OM_TEST)
	$(abspath $(MACHINE_OM_TEST))
