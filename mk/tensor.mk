# M20 OMEGA_TENSOR (docs/tensor/M20_OMEGA_TENSOR.md): semantic tensor layer +
# CPU realization + crash-safe storage lifetime. Pure seeded OM-2 under src/tensor/.
# Picked up by `-include mk/*.mk`. Not part of `all` or `test`. CPU only:
# opens no device, never touches the GB10.
#
# test-tensor            pure seeded OM-2 CPU tests, then test-tensor-no-hooks
# test-tensor-no-hooks   verifies pure OM-2 tensor sources carry no C test hooks
#                        and no process-exit call in omega_tensor/omega_tensor_cpu
# test-tensor-mutations  applies each MUT: source mutation in a scratch copy
#                        and proves the pure OM-2 test then fails
# test-m20-receipt       tests/test_m20_receipt.sh: content-addressed M20
#                        receipt writer tools/m20_receipt.sh (fixtures only)
# test-tensor-e1-reduce  alias of test-tensor
# test-tensor-store      pure seeded OM-2 crash-safe storage lifetime tests,
#                        then test-tensor-no-hooks
ifndef TENSOR_MK
TENSOR_MK := 1
.PHONY: test-tensor test-tensor-no-hooks test-tensor-mutations test-tensor-e1-reduce test-tensor-store
TENSOR_HOOK_SYMS = omega_tensor_test_set_storage_generation omega_tensor_store_test_set_crash_step

TENSOR_OMC ?= seed/out/omc
TENSOR_OM_CORE = src/tensor/tensor_shape.om src/tensor/tensor_ops.om src/train/tg_sha256.om \
	src/tensor/omega_tensor_cpu.om src/tensor/omega_tensor_gb10.om src/tensor/omega_tensor.om
TENSOR_STORE_OM_SRCS = src/tensor/tensor_shape.om src/tensor/tensor_ops.om src/train/tg_sha256.om \
	src/tensor/omega_tensor_cpu.om src/tensor/omega_tensor.om src/tensor/omega_tensor_store.om

$(OUT_DIR)/test_omega_tensor: src/tensor/test_tensor.om $(TENSOR_OM_CORE) $(TENSOR_OMC)
	@mkdir -p $(OUT_DIR)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TENSOR_OM_CORE) src/tensor/test_tensor.om) | $(TENSOR_OMC) > $@.tmp && chmod +x $@.tmp && mv $@.tmp $@

test-tensor: $(OUT_DIR)/test_omega_tensor
	$(abspath $(OUT_DIR)/test_omega_tensor)
	$(MAKE) --no-print-directory test-tensor-no-hooks

# Pure seeded OM-2 hook hygiene check: omega_tensor.om/omega_tensor_cpu.om carry
# no exit/fork calls and no legacy C test hook symbols exist in src/tensor/*.om.
test-tensor-no-hooks: $(TENSOR_OM_CORE) src/tensor/omega_tensor_store.om
	@grep -q '^fn ot_ctx_init ' src/tensor/omega_tensor.om \
		|| { echo "test-tensor-no-hooks: FAIL (sanity: fn ot_ctx_init not found)"; exit 1; }
	@if grep -hv '^[[:space:]]*note' src/tensor/omega_tensor.om src/tensor/omega_tensor_cpu.om | grep -qwE 'exit|fork'; then \
		echo "test-tensor-no-hooks: FAIL (exit/fork referenced by omega_tensor.om or omega_tensor_cpu.om)"; exit 1; fi
	@for s in $(TENSOR_HOOK_SYMS); do \
		if grep -q "\b$$s\b" $(TENSOR_OM_CORE) src/tensor/omega_tensor_store.om; then \
			echo "test-tensor-no-hooks: FAIL ($$s present in OM-2 tensor sources)"; exit 1; fi; \
	done; echo "test-tensor-no-hooks: PASS (pure OM-2 tensor sources clean; no C test hooks)"

test-tensor-mutations:
	tools/tensor_mutations.sh

# Kept as an alias: the seam now always calls omega_reduce_cpu (E1 WP-D, #134 merged).
test-tensor-e1-reduce: test-tensor

.PHONY: test-m20-receipt
test-m20-receipt:
	tests/test_m20_receipt.sh

# Crash-safe storage lifetime (src/tensor/omega_tensor_store.{c,h}): round
# trip, crash at every commit phase (fork + test-only hook), torn writes,
# crafted journals. Plain and ASan/UBSan, then test-tensor-no-hooks. Writes
# only under $TMPDIR (default /tmp). Its mutants run in test-tensor-mutations.

$(OUT_DIR)/test_omega_tensor_store: src/tensor/test_tensor_store.om $(TENSOR_STORE_OM_SRCS) $(TENSOR_OMC)
	@mkdir -p $(OUT_DIR)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TENSOR_STORE_OM_SRCS) src/tensor/test_tensor_store.om) | $(TENSOR_OMC) > $@.tmp && chmod +x $@.tmp && mv $@.tmp $@

test-tensor-store: $(OUT_DIR)/test_omega_tensor_store
	@rm -rf $(OUT_DIR)/tensor_store_scratch && mkdir -p $(OUT_DIR)/tensor_store_scratch
	$(abspath $(OUT_DIR)/test_omega_tensor_store) $(OUT_DIR)/tensor_store_scratch
	$(MAKE) --no-print-directory test-tensor-no-hooks

# ---- GB10 realization table (M20 cut gb10) ---------------------------------
# test-tensor-gb10-host  PHYSICS_DIR=<physics checkout at physics.lock>:
#                        builds the GB10 table + tests/test_omega_tensor_gb10.c
#                        against physics and runs host self checks only (no
#                        --chip, no device), the nm no-CPU-fallback check and
#                        the GB10 MUT: mutants (tools/tensor_mutations.sh --gb10)
# test-tensor-gb10-chip  the chip parity gate: tests/run_tensor_chip.sh (pins,
#                        clean trees, /tmp/aien-gb10.lock, receipt). Refuses
#                        unless GB10_CHIP_RUN=1 is set, so it never runs by
#                        accident. Never pass a quiet flag.
.PHONY: test-tensor-gb10-host test-tensor-gb10-chip
test-tensor-gb10-host:
	@test -n "$(PHYSICS_DIR)" && test -d "$(PHYSICS_DIR)" \
		|| { echo "test-tensor-gb10-host: set PHYSICS_DIR to the physics checkout"; exit 2; }
	tools/tensor_mutations.sh --gb10 "$(PHYSICS_DIR)"

test-tensor-gb10-chip:
	@test "$$GB10_CHIP_RUN" = 1 || { echo "test-tensor-gb10-chip: chip run refused (set GB10_CHIP_RUN=1; forge only)"; exit 2; }
	@test -n "$(PHYSICS_DIR)" || { echo "test-tensor-gb10-chip: set PHYSICS_DIR"; exit 2; }
	tests/run_tensor_chip.sh --physics-dir "$(PHYSICS_DIR)"
endif
