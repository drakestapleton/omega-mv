# POLYGLOT-0 lane B1: pure seeded OM-2 correctness gate (spec/polyglot-0.md).
# test-polyglot-asm: builds and runs tests/polyglot/test_asm.om via seed/out/omc
# (error contract, MA-3 shape grid, random unaligned+canary cases, large magnitudes
# up to OMA_RZ_MAX_N).
# Guarded because Makefile includes mk/*.mk and mk/polyglot.mk may be read alongside.
ifndef POLYGLOT_ASM_MK
POLYGLOT_ASM_MK := 1

PGA_OMC ?= seed/out/omc
PGA_ARCH = -march=armv8.6-a+dotprod+i8mm
OBJCOPY ?= objcopy
PGA_DIR = $(OUT_DIR)/tests-polyglot
PGA_SRCS = src/polyglot/omx_common.om src/polyglot/omx_encoder.om tests/polyglot/test_asm.om
PGA_BINS = $(PGA_DIR)/gnu_sdot.text.bin $(PGA_DIR)/gnu_crumb.text.bin
PGA_TEST = $(PGA_DIR)/test_asm

$(PGA_DIR)/gnu_%.o: src/polyglot/asm/omx_%.S
	@mkdir -p $(dir $@)
	$(CC) $(PGA_ARCH) -c -o $@ $<

$(PGA_DIR)/gnu_%.text.bin: $(PGA_DIR)/gnu_%.o
	$(OBJCOPY) -O binary --only-section=.text $< $@

$(PGA_TEST): $(PGA_SRCS) $(PGA_OMC)
	@mkdir -p $(dir $@)
	cat $(PGA_SRCS) | $(PGA_OMC) > $@.tmp && chmod +x $@.tmp && mv $@.tmp $@

.PHONY: test-polyglot-asm
test-polyglot-asm: $(PGA_TEST) $(PGA_BINS)
	./$(PGA_TEST) $(PGA_BINS)

endif
