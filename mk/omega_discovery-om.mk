# Abstraction discovery & corpus compression (src/omega_discovery.om, twin of src/omega_discovery.c).
# Pure seeded OM-2, physics-free, host-only.
OMEGA_DISCOVERY_OM_OMC ?= seed/out/omc
OMEGA_DISCOVERY_OM_SRCS := seed/ng/sha256.om om/aarch64/aarch64_om2.om src/omega_discovery.om tests/test_omega_discovery.om
OMEGA_DISCOVERY_OM_TEST = $(OUT_DIR)/test_omega_discovery_om

$(OMEGA_DISCOVERY_OM_TEST): $(OMEGA_DISCOVERY_OM_SRCS) $(OMEGA_DISCOVERY_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(OMEGA_DISCOVERY_OM_SRCS)) | $(OMEGA_DISCOVERY_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-omega-discovery-om
test-omega-discovery-om: $(OMEGA_DISCOVERY_OM_TEST)
	$(abspath $(OMEGA_DISCOVERY_OM_TEST))
