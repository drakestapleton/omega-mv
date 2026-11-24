# Semantic object & graph validator in pure seeded OM-2 (src/omega_validate.om, twin of src/omega_validate.c).
# Pure seeded OM-2, physics-free, host-only.
OMEGA_VALIDATE_OM_OMC ?= seed/out/omc
OMEGA_VALIDATE_OM_SRCS := seed/ng/sha256.om om/visor/canonical_om2.om src/omega_canonical.om src/omega_core.om om/visor/validate_om2.om src/omega_validate.om tests/test_omega_validate.om
OMEGA_VALIDATE_OM_TEST = $(OUT_DIR)/test_omega_validate_om

$(OMEGA_VALIDATE_OM_TEST): $(OMEGA_VALIDATE_OM_SRCS) $(OMEGA_VALIDATE_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(OMEGA_VALIDATE_OM_SRCS)) | $(OMEGA_VALIDATE_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-omega-validate-om
test-omega-validate-om: $(OMEGA_VALIDATE_OM_TEST)
	$(abspath $(OMEGA_VALIDATE_OM_TEST))
