# POLYGLOT-0 lane B1: pure seeded OM-2 correctness gate (spec/polyglot-0.md).
# test-polyglot-asm: builds and runs tests/polyglot/test_asm.om via seed/out/omc
# (error contract, MA-3 shape grid, random unaligned+canary cases, large magnitudes
# up to OMA_RZ_MAX_N).
# Guarded because Makefile includes mk/*.mk and mk/polyglot.mk may be read alongside.
ifndef POLYGLOT_ASM_MK
POLYGLOT_ASM_MK := 1

PGA_OMC ?= seed/out/omc
PGA_DIR = $(OUT_DIR)/tests-polyglot
PGA_SRCS = src/polyglot/omx_common.om tests/polyglot/test_asm.om
PGA_TEST = $(PGA_DIR)/test_asm

$(PGA_TEST): $(PGA_SRCS)
	@mkdir -p $(dir $@)
	cat $(PGA_SRCS) | $(PGA_OMC) > $@ && chmod +x $@

.PHONY: test-polyglot-asm
test-polyglot-asm: $(PGA_TEST)
	./$(PGA_TEST)

endif
