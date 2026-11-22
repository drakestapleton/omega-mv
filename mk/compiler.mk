# Compiler verification suite.
# The frozen C OSC-1 compiler (src/compiler/) was removed in commit bb7f2dd68 in favor of
# the pure seeded-Omega compiler (seed/out/omc, rebuilt from seed/rung0/seed0.hex).
# Picked up by `-include mk/*.mk`.
#
# test-compiler / test-compiler-full / test-compiler-quick:
#   - legacy AArch64 writer differential/refusal test (plain + ASan/UBSan) while C callers remain
#   - frozen legacy AArch64 caller allowlist check (tests/compiler/legacy_a64_callers.sh)
#   - seeded compiler fixpoint bootstrap (sh seed/omega-from-seed.sh)
ifndef COMPILER_MK
COMPILER_MK := 1
.PHONY: test-compiler test-compiler-full test-compiler-quick
OSC_DIR = $(OUT_DIR)/compiler
OSC_CFLAGS = -std=gnu11 -Wall -Wextra -Werror -D_GNU_SOURCE -O2 -Isrc
OSC_ASAN = -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=all

OSC_LEGACY_A64 = src/aarch64_encoder.c src/aarch64_decoder.c src/omega_om_units.c
OSC_LEGACY_A64_HDRS = src/aarch64_encoder.h src/aarch64_decoder.h src/aarch64_target.h src/omega_api_decl.h

$(OSC_DIR)/test_legacy_a64: tests/compiler/test_legacy_a64.c $(OSC_LEGACY_A64) $(OSC_LEGACY_A64_HDRS)
	@mkdir -p $(OSC_DIR)
	$(CC) $(OSC_CFLAGS) -o $@ tests/compiler/test_legacy_a64.c $(OSC_LEGACY_A64)

$(OSC_DIR)/test_legacy_a64_asan: tests/compiler/test_legacy_a64.c $(OSC_LEGACY_A64) $(OSC_LEGACY_A64_HDRS)
	@mkdir -p $(OSC_DIR)
	$(CC) $(OSC_CFLAGS) $(OSC_ASAN) -o $@ tests/compiler/test_legacy_a64.c $(OSC_LEGACY_A64)

test-compiler: $(OSC_DIR)/test_legacy_a64 $(OSC_DIR)/test_legacy_a64_asan
	@mkdir -p $(OSC_DIR)
	$(abspath $(OSC_DIR)/test_legacy_a64) > $(OSC_DIR)/legacy_a64.out
	@tail -1 $(OSC_DIR)/legacy_a64.out; grep -q '^OSC2_LEGACY_A64_PASS$$' $(OSC_DIR)/legacy_a64.out
	$(abspath $(OSC_DIR)/test_legacy_a64_asan) quick > $(OSC_DIR)/legacy_a64_asan.out
	@tail -1 $(OSC_DIR)/legacy_a64_asan.out; grep -q '^OSC2_LEGACY_A64_PASS$$' $(OSC_DIR)/legacy_a64_asan.out
	@grep "^legacy a64 differential: .* mismatches=0$$" $(OSC_DIR)/legacy_a64.out
	sh tests/compiler/legacy_a64_callers.sh --selftest > $(OSC_DIR)/legacy_callers.out
	@tail -1 $(OSC_DIR)/legacy_callers.out; grep -q '^OSC2_LEGACY_CALLERS_PASS ' $(OSC_DIR)/legacy_callers.out
	sh seed/omega-from-seed.sh
	@echo "test-compiler: PASS (seeded omc fixpoint + legacy AArch64 writer)"

OSC_QDIR = $(OSC_DIR)/quick
test-compiler-full: test-compiler

test-compiler-quick: $(OSC_DIR)/test_legacy_a64
	@mkdir -p $(OSC_QDIR)
	$(abspath $(OSC_DIR)/test_legacy_a64) quick > $(OSC_QDIR)/legacy_a64.out
	@tail -1 $(OSC_QDIR)/legacy_a64.out; grep -q '^OSC2_LEGACY_A64_PASS$$' $(OSC_QDIR)/legacy_a64.out
	sh tests/compiler/legacy_a64_callers.sh --selftest > $(OSC_QDIR)/legacy_callers.out
	@tail -1 $(OSC_QDIR)/legacy_callers.out; grep -q '^OSC2_LEGACY_CALLERS_PASS ' $(OSC_QDIR)/legacy_callers.out
	@echo "test-compiler-quick: PASS (legacy AArch64 writer + caller allowlist; C compiler retired)"
endif
