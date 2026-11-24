# Binary & text graph codec in pure seeded OM-2 (src/omega_codec.om, twin of src/omega_codec.c).
# Pure seeded OM-2, physics-free, host-only.
OMEGA_CODEC_OM_OMC ?= seed/out/omc
OMEGA_CODEC_OM_SRCS := seed/ng/sha256.om om/visor/canonical_om2.om src/omega_canonical.om src/omega_core.om om/visor/codec_om2.om src/omega_codec.om tests/test_omega_codec.om
OMEGA_CODEC_OM_TEST = $(OUT_DIR)/test_omega_codec_om

$(OMEGA_CODEC_OM_TEST): $(OMEGA_CODEC_OM_SRCS) $(OMEGA_CODEC_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(OMEGA_CODEC_OM_SRCS)) | $(OMEGA_CODEC_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-omega-codec-om
test-omega-codec-om: $(OMEGA_CODEC_OM_TEST)
	$(abspath $(OMEGA_CODEC_OM_TEST))
