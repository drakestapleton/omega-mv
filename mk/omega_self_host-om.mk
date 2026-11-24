# Self-hosting AArch64 bootstrap compiler (src/omega_self_host.om, twin of src/omega_self_host.c).
# Pure seeded OM-2, physics-free, host-only.
OMEGA_SELF_HOST_OM_OMC ?= seed/out/omc
OMEGA_SELF_HOST_OM_SRCS := seed/ng/sha256.om om/visor/canonical_om2.om om/visor/codec_om2.om src/omega_canonical.om src/omega_core.om src/omega_codec.om om/aarch64/aarch64_om2.om src/omega_exec.om src/omega_self_host.om tests/test_omega_self_host.om
OMEGA_SELF_HOST_OM_TEST = $(OUT_DIR)/test_omega_self_host_om

$(OMEGA_SELF_HOST_OM_TEST): $(OMEGA_SELF_HOST_OM_SRCS) $(OMEGA_SELF_HOST_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(OMEGA_SELF_HOST_OM_SRCS)) | $(OMEGA_SELF_HOST_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-omega-self-host-om
test-omega-self-host-om: $(OMEGA_SELF_HOST_OM_TEST)
	$(abspath $(OMEGA_SELF_HOST_OM_TEST))
