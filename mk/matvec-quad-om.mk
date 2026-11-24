# MatVec quad4 AArch64 synthesizer (src/omega_matvec_quad.om, twin of src/omega_matvec_quad.c).
# Pure seeded OM-2, physics-free, host-only.
MATVEC_QUAD_OM_OMC ?= seed/out/omc
MATVEC_QUAD_OM_SRCS := seed/ng/sha256.om om/aarch64/aarch64_om2.om src/omega_machine.om src/omega_matvec_quad.om tests/test_omega_matvec_quad.om
MATVEC_QUAD_OM_TEST = $(OUT_DIR)/test_omega_matvec_quad_om

$(MATVEC_QUAD_OM_TEST): $(MATVEC_QUAD_OM_SRCS) $(MATVEC_QUAD_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(MATVEC_QUAD_OM_SRCS)) | $(MATVEC_QUAD_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-matvec-quad-om
test-matvec-quad-om: $(MATVEC_QUAD_OM_TEST)
	$(abspath $(MATVEC_QUAD_OM_TEST))
