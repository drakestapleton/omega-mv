# Structural, differential, and algebraic property verification (src/omega_verify.om,
# twin of src/omega_verify.c). Pure seeded OM-2, physics-free, host-only.
VERIFY_OM_OMC ?= seed/out/omc
VERIFY_OM_SRCS := seed/ng/sha256.om om/aarch64/aarch64_om2.om om/visor/verify_om2.om src/omega_verify.om tests/test_omega_verify.om
VERIFY_OM_TEST = $(OUT_DIR)/test_omega_verify_om

$(VERIFY_OM_TEST): $(VERIFY_OM_SRCS) $(VERIFY_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(VERIFY_OM_SRCS)) | $(VERIFY_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-verify-om
test-verify-om: $(VERIFY_OM_TEST)
	$(abspath $(VERIFY_OM_TEST))
