# Effect 64-bit capability generation hostile tests (tests/effect/test_effect_cap64.om).
# Pure seeded OM-2, physics-free, host-only.
EFFECT_CAP64_OMC ?= seed/out/omc
EFFECT_CAP64_OM_SRCS := seed/ng/sha256.om om/visor/canonical_om2.om src/omega_canonical.om \
	src/omega_core.om om/visor/codec_om2.om src/omega_codec.om om/visor/validate_om2.om \
	src/omega_validate.om seed/authority/cap_table_om2.om src/runtime/rx_caproot.om \
	tests/effect/test_effect_cap64.om
EFFECT_CAP64_OM_TEST = $(OUT_DIR)/test_effect_cap64_om

$(EFFECT_CAP64_OM_TEST): $(EFFECT_CAP64_OM_SRCS) $(EFFECT_CAP64_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(EFFECT_CAP64_OM_SRCS)) | $(EFFECT_CAP64_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-effect-cap64-om
test-effect-cap64-om: $(EFFECT_CAP64_OM_TEST)
	$(abspath $(EFFECT_CAP64_OM_TEST))
