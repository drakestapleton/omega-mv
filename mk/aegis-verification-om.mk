# Aegis realization verification boundary (src/aegis_verification.om,
# twin of src/aegis_verification.c). Pure seeded OM-2, physics-free, host-only.
AEGIS_VER_OM_OMC ?= seed/out/omc
AEGIS_VER_OM_SRCS := seed/ng/sha256.om src/aegis_verification.om tests/test_aegis_verification.om
AEGIS_VER_OM_TEST = $(OUT_DIR)/test_aegis_verification_om

$(AEGIS_VER_OM_TEST): $(AEGIS_VER_OM_SRCS) $(AEGIS_VER_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(AEGIS_VER_OM_SRCS)) | $(AEGIS_VER_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-aegis-verification-om
test-aegis-verification-om: $(AEGIS_VER_OM_TEST)
	$(abspath $(AEGIS_VER_OM_TEST))
