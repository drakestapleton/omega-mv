# POLYGLOT-0 lane B2: B1's kernels emitted by Omega's pure seeded OM-2 AArch64
# encoder (src/polyglot/omx_encoder.om; spec/polyglot-0.md section 4).
# test-polyglot-encoder:
#   1. assembles B1's .S with GNU as (via $(CC)) and extracts each .text with
#      objcopy -O binary (the reference bytes);
#   2. builds tests/polyglot/test_encoder.om via seed/out/omc;
#   3. runs byte comparison vs GNU as (356/356 identical), final-form relocation
#      check, Omega decoder round trip, fail-closed checks + all 5,334 logical
#      immediates, and the B1 correctness suite.
ifndef POLYGLOT_ENCODER_MK
POLYGLOT_ENCODER_MK := 1

PGE_OMC ?= seed/out/omc
PGE_ARCH = -march=armv8.6-a+dotprod+i8mm
OBJCOPY ?= objcopy
PGE_SRCS = src/polyglot/omx_common.om src/polyglot/omx_encoder.om tests/polyglot/test_encoder.om
PGE_DIR = $(OUT_DIR)/tests-polyglot-encoder
PGE_BINS = $(PGE_DIR)/gnu_sdot.text.bin $(PGE_DIR)/gnu_crumb.text.bin
PGE_TEST = $(PGE_DIR)/test_encoder

$(PGE_DIR)/gnu_%.o: src/polyglot/asm/omx_%.S
	@mkdir -p $(dir $@)
	$(CC) $(PGE_ARCH) -c -o $@ $<

$(PGE_DIR)/gnu_%.text.bin: $(PGE_DIR)/gnu_%.o
	$(OBJCOPY) -O binary --only-section=.text $< $@

$(PGE_TEST): $(PGE_SRCS)
	@mkdir -p $(dir $@)
	cat $(PGE_SRCS) | $(PGE_OMC) > $@ && chmod +x $@

.PHONY: test-polyglot-encoder
test-polyglot-encoder: $(PGE_TEST) $(PGE_BINS)
	./$(PGE_TEST) $(PGE_BINS)

endif
