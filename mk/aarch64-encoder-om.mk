# AArch64 legacy instruction encoder (src/aarch64_encoder.om, twin of src/aarch64_encoder.c).
# Pure seeded OM-2, physics-free, host-only.
A64_ENC_OM_OMC ?= seed/out/omc
A64_ENC_OM_SRCS := seed/ng/sha256.om om/aarch64/aarch64_om2.om src/aarch64_encoder.om tests/test_aarch64_encoder.om
A64_ENC_OM_TEST = $(OUT_DIR)/test_aarch64_encoder_om

$(A64_ENC_OM_TEST): $(A64_ENC_OM_SRCS) $(A64_ENC_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(A64_ENC_OM_SRCS)) | $(A64_ENC_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-aarch64-encoder-om
test-aarch64-encoder-om: $(A64_ENC_OM_TEST)
	$(abspath $(A64_ENC_OM_TEST))
