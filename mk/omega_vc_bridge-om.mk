# Verified Crumb Bridge (VC1 stage 6) receipt/VC minting and store admission
# (src/omega_vc_bridge.om, twin of src/omega_vc_bridge.c). Pure seeded OM-2, physics-free, host-only.
OMEGA_VC_BRIDGE_OM_OMC ?= seed/out/omc
OMEGA_VC_BRIDGE_OM_SRCS := seed/ng/sha256.om src/omega_vcstore.om src/omega_vc_bridge.om tests/test_omega_vc_bridge.om
OMEGA_VC_BRIDGE_OM_TEST = $(OUT_DIR)/test_omega_vc_bridge_om

$(OMEGA_VC_BRIDGE_OM_TEST): $(OMEGA_VC_BRIDGE_OM_SRCS) $(OMEGA_VC_BRIDGE_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(OMEGA_VC_BRIDGE_OM_SRCS)) | $(OMEGA_VC_BRIDGE_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-omega-vc-bridge-om
test-omega-vc-bridge-om: $(OMEGA_VC_BRIDGE_OM_TEST)
	$(abspath $(OMEGA_VC_BRIDGE_OM_TEST))
