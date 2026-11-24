# Canonical encoding & SemanticId (src/omega_canonical.om, twin of src/omega_canonical.c).
# Pure seeded OM-2, physics-free, host-only.
CANONICAL_OM_OMC ?= seed/out/omc
CANONICAL_OM_SRCS := seed/ng/sha256.om om/visor/canonical_om2.om src/omega_canonical.om tests/test_omega_canonical.om
CANONICAL_OM_TEST = $(OUT_DIR)/test_omega_canonical_om

$(CANONICAL_OM_TEST): $(CANONICAL_OM_SRCS) $(CANONICAL_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(CANONICAL_OM_SRCS)) | $(CANONICAL_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-canonical-om
test-canonical-om: $(CANONICAL_OM_TEST)
	$(abspath $(CANONICAL_OM_TEST))
