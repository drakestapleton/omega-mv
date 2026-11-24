# AArch64 instruction decoder & code validator (src/aarch64_decoder.om, twin of src/aarch64_decoder.c).
# Pure seeded OM-2, physics-free, host-only.
A64_DEC_OM_OMC ?= seed/out/omc
A64_DEC_OM_SRCS := om/aarch64/aarch64_om2.om src/aarch64_decoder.om tests/test_aarch64_decoder.om
A64_DEC_OM_TEST = $(OUT_DIR)/test_aarch64_decoder_om

$(A64_DEC_OM_TEST): $(A64_DEC_OM_SRCS) $(A64_DEC_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(A64_DEC_OM_SRCS)) | $(A64_DEC_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-aarch64-decoder-om
test-aarch64-decoder-om: $(A64_DEC_OM_TEST)
	$(abspath $(A64_DEC_OM_TEST))
