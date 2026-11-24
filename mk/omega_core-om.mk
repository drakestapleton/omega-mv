# Core graph, builders, effect v2, pure eval in pure seeded OM-2 (src/omega_core.om, twin of src/omega_core.c).
# Pure seeded OM-2, physics-free, host-only.
OMEGA_CORE_OM_OMC ?= seed/out/omc
OMEGA_CORE_OM_SRCS := seed/ng/sha256.om om/visor/canonical_om2.om src/omega_canonical.om src/omega_core.om tests/test_omega_core.om
OMEGA_CORE_OM_TEST = $(OUT_DIR)/test_omega_core_om

$(OMEGA_CORE_OM_TEST): $(OMEGA_CORE_OM_SRCS) $(OMEGA_CORE_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(OMEGA_CORE_OM_SRCS)) | $(OMEGA_CORE_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-omega-core-om
test-omega-core-om: $(OMEGA_CORE_OM_TEST)
	$(abspath $(OMEGA_CORE_OM_TEST))
