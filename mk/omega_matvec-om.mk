# MatVec living kernel (src/omega_matvec.om, twin of src/omega_matvec.c).
# Pure seeded OM-2, physics-free, host-only.
OMEGA_MATVEC_OM_OMC ?= seed/out/omc
OMEGA_MATVEC_OM_SRCS := seed/ng/sha256.om om/aarch64/aarch64_om2.om src/omega_machine.om src/omega_matvec.om tests/test_omega_matvec.om
OMEGA_MATVEC_OM_TEST = $(OUT_DIR)/test_omega_matvec_om

$(OMEGA_MATVEC_OM_TEST): $(OMEGA_MATVEC_OM_SRCS) $(OMEGA_MATVEC_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(OMEGA_MATVEC_OM_SRCS)) | $(OMEGA_MATVEC_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-omega-matvec-om
test-omega-matvec-om: $(OMEGA_MATVEC_OM_TEST)
	$(abspath $(OMEGA_MATVEC_OM_TEST))
