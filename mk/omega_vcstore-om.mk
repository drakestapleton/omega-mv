# Verified Crumb Store (VC1 stage 3) canonical decoder, immutable store, closure,
# digests, name index, and binary persistence (src/omega_vcstore.om, twin of src/omega_vcstore.c).
# Pure seeded OM-2, physics-free, host-only.
OMEGA_VCSTORE_OM_OMC ?= seed/out/omc
OMEGA_VCSTORE_OM_SRCS := seed/ng/sha256.om src/omega_vcstore.om tests/test_omega_vcstore.om
OMEGA_VCSTORE_OM_TEST = $(OUT_DIR)/test_omega_vcstore_om

$(OMEGA_VCSTORE_OM_TEST): $(OMEGA_VCSTORE_OM_SRCS) $(OMEGA_VCSTORE_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(OMEGA_VCSTORE_OM_SRCS)) | $(OMEGA_VCSTORE_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-omega-vcstore-om
test-omega-vcstore-om: $(OMEGA_VCSTORE_OM_TEST)
	$(abspath $(OMEGA_VCSTORE_OM_TEST))
