# C3 unwritten-output detector (src/omega_unwritten_trap.om, twin of src/omega_unwritten_trap.c).
# Pure seeded OM-2, physics-free, host-only.
UNWRITTEN_TRAP_OMC ?= seed/out/omc
UNWRITTEN_TRAP_OM_SRCS := src/omega_unwritten_trap.om tests/test_omega_unwritten_trap.om
UNWRITTEN_TRAP_OM_TEST = $(OUT_DIR)/test_omega_unwritten_trap_om

$(UNWRITTEN_TRAP_OM_TEST): $(UNWRITTEN_TRAP_OM_SRCS) $(UNWRITTEN_TRAP_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed '/^om2$$/d' $(UNWRITTEN_TRAP_OM_SRCS)) | $(UNWRITTEN_TRAP_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-unwritten-trap-om
test-unwritten-trap-om: $(UNWRITTEN_TRAP_OM_TEST)
	$(abspath $(UNWRITTEN_TRAP_OM_TEST))
