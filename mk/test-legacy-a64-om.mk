# Pure seeded OM-2 twin of tests/compiler/test_legacy_a64.c (legacy AArch64 encoder/decoder
# differential + all 90 out-of-range refusal checks).
# test_legacy_a64.c stays live in mk/compiler.mk while C callers remain.
# Pure seeded OM-2, physics-free, host-only.
LEGACY_A64_OM_OMC ?= seed/out/omc
LEGACY_A64_OM_SRCS := om/aarch64/aarch64_om2.om src/aarch64_encoder.om src/aarch64_decoder.om tests/compiler/test_legacy_a64.om
LEGACY_A64_OM_BIN = $(OUT_DIR)/compiler/test_legacy_a64_om

$(LEGACY_A64_OM_BIN): $(LEGACY_A64_OM_SRCS) $(LEGACY_A64_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(LEGACY_A64_OM_SRCS)) | $(LEGACY_A64_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-legacy-a64-om
test-legacy-a64-om: $(LEGACY_A64_OM_BIN)
	@set -e; \
	$(abspath $(LEGACY_A64_OM_BIN)) quick | tee $(OUT_DIR)/compiler/legacy_a64_om.out; \
	grep -q '^OSC2_LEGACY_A64_PASS$$' $(OUT_DIR)/compiler/legacy_a64_om.out; \
	grep -q '^legacy a64 differential: .* mismatches=0$$' $(OUT_DIR)/compiler/legacy_a64_om.out; \
	grep -q '^legacy a64 refusal: cases=90 refused_and_no_write=90$$' $(OUT_DIR)/compiler/legacy_a64_om.out
