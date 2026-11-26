# Compiler verification suite. Pure seeded OM-2 (zero C).
# The frozen C OSC-1 compiler (src/compiler/) was removed in commit bb7f2dd68 in favor of
# the pure seeded-Omega compiler (seed/out/omc, rebuilt from seed/rung0/seed0.hex).
# Picked up by `-include mk/*.mk`.
#
# test-compiler / test-compiler-full / test-compiler-quick:
#   - pure seeded OM-2 legacy AArch64 differential/refusal suite (test-legacy-a64-om)
#   - frozen legacy AArch64 caller allowlist check (tests/compiler/legacy_a64_callers.sh)
#   - seeded compiler fixpoint bootstrap (sh seed/omega-from-seed.sh)
ifndef COMPILER_MK
COMPILER_MK := 1
.PHONY: test-compiler test-compiler-full test-compiler-quick
OSC_DIR = $(OUT_DIR)/compiler
OSC_QDIR = $(OSC_DIR)/quick

test-compiler: test-legacy-a64-om
	@mkdir -p $(OSC_DIR)
	sh tests/compiler/legacy_a64_callers.sh --selftest > $(OSC_DIR)/legacy_callers.out
	@tail -1 $(OSC_DIR)/legacy_callers.out; grep -q '^OSC2_LEGACY_CALLERS_PASS ' $(OSC_DIR)/legacy_callers.out
	sh seed/omega-from-seed.sh
	@echo "test-compiler: PASS (seeded omc fixpoint + pure OM-2 legacy AArch64 checks)"

test-compiler-full: test-compiler

test-compiler-quick: test-legacy-a64-om
	@mkdir -p $(OSC_QDIR)
	sh tests/compiler/legacy_a64_callers.sh --selftest > $(OSC_QDIR)/legacy_callers.out
	@tail -1 $(OSC_QDIR)/legacy_callers.out; grep -q '^OSC2_LEGACY_CALLERS_PASS ' $(OSC_QDIR)/legacy_callers.out
	@echo "test-compiler-quick: PASS (pure OM-2 legacy AArch64 + caller allowlist; C compiler retired)"
endif
