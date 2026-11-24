# OSC import resolver hook adapter in pure seeded OM-2 (src/omega_resolve_osc.om, twin of src/omega_resolve_osc.c).
# Pure seeded OM-2, physics-free, host-only.
OMEGA_RESOLVE_OSC_OM_OMC ?= seed/out/omc
OMEGA_RESOLVE_OSC_OM_SRCS := seed/ng/sha256.om om/blake3/b3unit.om src/omega_blake3.om src/omega_receipt.om src/omega_resolve.om src/omega_resolve_osc.om tests/test_omega_resolve_osc.om
OMEGA_RESOLVE_OSC_OM_TEST = $(OUT_DIR)/test_omega_resolve_osc_om

$(OMEGA_RESOLVE_OSC_OM_TEST): $(OMEGA_RESOLVE_OSC_OM_SRCS) $(OMEGA_RESOLVE_OSC_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(OMEGA_RESOLVE_OSC_OM_SRCS)) | $(OMEGA_RESOLVE_OSC_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-omega-resolve-osc-om
test-omega-resolve-osc-om: $(OMEGA_RESOLVE_OSC_OM_TEST)
	$(abspath $(OMEGA_RESOLVE_OSC_OM_TEST))
