# Native realization exec cache & QEMU runner builder (src/omega_exec.om, twin of src/omega_exec.c).
# Pure seeded OM-2, physics-free, host-only.
OMEGA_EXEC_OM_OMC ?= seed/out/omc
OMEGA_EXEC_OM_SRCS := seed/ng/sha256.om om/aarch64/aarch64_om2.om src/omega_exec.om tests/test_omega_exec.om
OMEGA_EXEC_OM_TEST = $(OUT_DIR)/test_omega_exec_om

$(OMEGA_EXEC_OM_TEST): $(OMEGA_EXEC_OM_SRCS) $(OMEGA_EXEC_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(OMEGA_EXEC_OM_SRCS)) | $(OMEGA_EXEC_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-omega-exec-om
test-omega-exec-om: $(OMEGA_EXEC_OM_TEST)
	$(abspath $(OMEGA_EXEC_OM_TEST))
