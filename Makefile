CC ?= gcc
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
PHYSICS_DIR ?= ../physics
OUT_DIR ?= build
# aienos.lock is code-adjacent input: parse it as data before mk/*.mk or any recipe sees it.
# Exactly one lowercase 40-hex commit line (final newline optional), else make stops;
# `override` so a command-line or environment AIENOS_LOCK cannot replace the parsed value.
override AIENOS_LOCK := $(shell LC_ALL=C awk 'NR == 1 && length($$0) == 40 && $$0 ~ /^[0-9a-f]+$$/ { commit = $$0; next } { invalid = 1 } END { if (!invalid && NR == 1) print commit; else exit 1 }' aienos.lock 2>/dev/null)
ifneq ($(words $(AIENOS_LOCK)),1)
$(error aienos.lock must contain exactly one lowercase 40-hex commit)
endif
AIENOS_R7_DEFAULT = $(OUT_DIR)/aienos-authority/$(AIENOS_LOCK)
AIENOS_R7_DIR ?= $(AIENOS_R7_DEFAULT)
-include mk/*.mk
PHYSICS_LOCK_CHECK ?= 1

CFLAGS ?= -std=gnu11 -Wall -Wextra -Werror -MMD -MP -D_GNU_SOURCE -O2 -Isrc \
	-I$(PHYSICS_DIR)/m16 -I$(PHYSICS_DIR)/nvrm \
	-I$(PHYSICS_DIR)/third_party/nvidia-open-580.173.02/src/common/sdk/nvidia/inc \
	-I$(PHYSICS_DIR)/third_party/nvidia-open-580.173.02/kernel-open/common/inc \
	-I$(PHYSICS_DIR)/third_party/nvidia-open-580.173.02/kernel-open/nvidia-uvm \
	-I$(PHYSICS_DIR)/third_party/nvidia-open-580.173.02/src/nvidia/arch/nvalloc/unix/include

# sm_121 instruction encoder (twin of aien-dev/CUDApp#79): om (default) = om/encoder/bw_enc_sm121.om through the
# generated binding src/omega_om_units.c; c = the migration-pending C encoder, the differential oracle; diff = both on
# every call, abort on any difference (mk/om-encoder.mk). Use a separate OUT_DIR per value. The macro names keep
# CUDApp's spelling so src/omega_blackwell_codegen.c stays the same file in both repositories.
CUDAPP_ENCODER ?= om
CUDAPP_ENCODER_DEFS_om :=
CUDAPP_ENCODER_DEFS_c := -DCUDAPP_MIGRATION_PENDING_C_ENCODER
CUDAPP_ENCODER_DEFS_diff := -DCUDAPP_MIGRATION_PENDING_ENCODER_DIFF
CUDAPP_ENCODER_DEFS = $(CUDAPP_ENCODER_DEFS_$(CUDAPP_ENCODER))
ifeq ($(filter om c diff,$(CUDAPP_ENCODER)),)
$(error CUDAPP_ENCODER must be om, c or diff)
endif

SRCS = src/omega_om_units.c src/omega_canonical.c src/omega_validate.c src/omega_core.c \
	src/aarch64_encoder.c src/aarch64_decoder.c src/omega_realize.c src/omega_exec.c \
	src/omega_verify.c src/omega_machine.c \
	src/omega_matvec.c src/omega_accelerator.c src/omega_accelerator_world.c \
	src/omega_vector.c src/omega_blackwell_encoder.c src/omega_blackwell_qmd.c \
	src/omega_blackwell_realize.c src/omega_blackwell_submit.c src/omega_blackwell_engine.c src/omega_gpu_engine.c src/omega_blackwell_gates.c src/omega_blackwell_matmul.c src/omega_blackwell_codegen.c src/omega_gpu_session.c src/omega_gpu_platform.c src/omega_gpu_platform_linux.c src/omega_gpu_fmt.c src/omega_gpu_matmul_api.c src/omega_gpu_elementwise_api.c src/omega_gpu_attention_api.c src/omega_gpu_serving.c src/omega_world_gates.c src/omega_gpu_wait.c \
	src/omega_evidence.c src/omega_clean_clone.c \
	$(PHYSICS_DIR)/m16/m16_native.c $(PHYSICS_DIR)/nvrm/nvrm.c
# OWN-30B cut 2 (2026-10-13): column windows over a resident bf16 tensor for the MoE path. New file,
# adds exports only (8B decode-speed lane collision rule: no existing GPU source moves).
SRCS += src/omega_gpu_moe_api.c

# OWN-30B Cut 6 / Cut 5 (2026-10-13): FP8 e4m3 GEMV kernel family, new files only (omega_gpu_fp8_api.h)
SRCS += src/omega_blackwell_codegen_moe.c src/omega_gpu_fp8_pack.c src/omega_gpu_fp8_api.c
# OWN-30B W-L2c (2026-10-14): FP8 GEMV variant 2, row-pipelined (omega_blackwell_codegen_moe2.h), selectable, variant 1 untouched
SRCS += src/omega_blackwell_codegen_moe2.c
# Expert Ribbon P1 (aienix#4 / omega#533, 2026-10-18): versioned replaceable FP8 expert slots, new files only
SRCS += src/omega_fp8_slot_table.c src/omega_gpu_fp8_slots.c
# OWN-30B cut 8 (2026-10-13): one-launch decode attention (omega_gpu_decode_attn_api.h), new files only
SRCS += src/omega_blackwell_codegen_attn.c src/omega_gpu_decode_attn_api.c
# Qwen3.8-27B (omega-mv#544, 2026-10-18): decode attention head_dim 256, new files only
SRCS += src/omega_blackwell_codegen_attn256.c src/omega_gpu_decode_attn256_api.c
# Qwen3.8-27B (omega-mv#545, 2026-10-18): prefill attention head_dim 256 on the decode cache, new files only
SRCS += src/omega_blackwell_codegen_pattn256.c src/omega_gpu_prefill_attn256_api.c
# OWN-30B (2026-10-13): libm-free host math (omega_gpu_hostmath.h) so libomega_gpu.a links without -lm
SRCS += src/omega_gpu_hostmath.c
# OWN-30B cut 8 item 2 (2026-10-13): one-launch MoE router (omega_gpu_router_api.h), new files only
SRCS += src/omega_blackwell_codegen_router.c src/omega_gpu_router_api.c
# Qwen3.8-27B Gated DeltaNet decode step (omega#542, 2026-10-18): one launch per layer (omega_gpu_gdn_api.h), new files only
SRCS += src/omega_blackwell_codegen_gdn.c src/omega_gpu_gdn_api.c
# OWN-30B W-L2 (2026-10-13): decode launch collapse, new files only: command list (N launches, one submit) + glue kernels
SRCS += src/omega_gpu_cmdlist.c src/omega_blackwell_codegen_dec.c
# C3 (docs/OMEGA.md): reductions and prefix sums of any length, bit-exact against the frozen-order host reference.
SRCS += src/omega_gpu_scan.c src/omega_gpu_scan_ref.c
# C3: matrix multiply of any shape, BF16 and FP8, both layouts, on the tensor cores (pack kernels + one multiply kernel).
SRCS += src/omega_gpu_gemm.c
SRCS += src/omega_gpu_mem_cached.c
SRCS += src/omega_gpu_decode_graph.c
# sc #642 (2026-10-18): one Qwen3.8-27B decode token as one command list (GDN + hd256 attention layers, dense MLP)
SRCS += src/omega_gpu_q38_graph.c
SRCS += src/omega_gpu_q36_graph.c
# C6 (L386): Omega's own sm_121 disassembler; the listing checks in tests/ call it instead of nvdisasm
SRCS += src/omega_sm121_disasm.c
# OWN-30B (2026-10-13): bf16 streaming GEMV for the lm_head (omega_gpu_bf16_gemv_api.h), new files only
SRCS += src/omega_blackwell_codegen_bf16.c src/omega_gpu_bf16_gemv_api.c
# OWN-30B prefill (2026-10-13): FP8 grouped GEMM, each expert streamed once per pass (omega_gpu_fp8gemm_api.h), new files only
SRCS += src/omega_blackwell_codegen_gemm.c src/omega_gpu_fp8gemm_api.c
# OWN-30B T3 (2026-10-13): tensor-core prefill kernels (omega_blackwell_codegen_tc.h), new files only
SRCS += src/omega_blackwell_codegen_tc.c
SRCS += src/omega_gpu_tcgemm_api.c
# OWN-30B L1 attention (2026-10-13): tensor-core causal prefill attention (omega_gpu_prefill_attn_api.h), new files only
SRCS += src/omega_blackwell_codegen_pattn.c src/omega_gpu_prefill_attn_api.c
# OWN-30B T3b (2026-10-13): device-resident prefill (omega_gpu_prefill.h), new files only
SRCS += src/omega_blackwell_codegen_pf.c src/omega_gpu_prefill.c src/omega_blackwell_codegen_tc2.c src/omega_gpu_pfgemm.c
# trainer lane E1 (2026-10-16): device-resident bf16 training GEMM (omega_gpu_tgemm_api.h), new files only
SRCS += src/omega_blackwell_codegen_tgemm.c src/omega_gpu_tgemm_api.c
# OWN-30B L1 GEMM (W-L1G, 2026-10-14): native FP8 QMMA, new files only
SRCS += src/omega_blackwell_codegen_qmma.c src/omega_blackwell_codegen_qg.c
# OWN-30B W-L1G-D (2026-10-14): router logits + MoE combine for the whole-prompt prefill, new files only
SRCS += src/omega_blackwell_codegen_pfhost.c src/omega_gpu_pfhost.c src/omega_gpu_moe_plan.c
# Ternary engine T0 (2026-10-15): KT1, the W2A8 ternary GEMV (omega_gpu_tern_api.h), new files only
SRCS += src/omega_blackwell_codegen_tern.c src/omega_gpu_tern_api.c
OBJS = $(patsubst %.c,$(OUT_DIR)/%.o,$(notdir $(SRCS)))
DEPS = $(OBJS:.o=.d)
-include $(DEPS)
TARGET = $(OUT_DIR)/omegatool

# Crumbline learner: a separate executable linked ONLY from learner-side code
# Crumbline learner: pure seeded OM-2 binary (src/crumbline/crumbline.om +
# tools/crumbline_learner.om). Links no physics, no C, no gate suites and no
# sealed-side code; the sealed side lives in the crumbs crate.
LEARNER = $(OUT_DIR)/crumbline-learner

.PHONY: all clean check-physics-lock crumbline-learner test-crumbline test-m19 test test-m5 test-m6 test-m7 test-m8 test-m9 test-m10 test-m11 test-m12 test-m13 test-m14 test-m15 test-m17 test-r3 test-i11-wake-merge test-action-graph test-state-projection test-capability-query test-capability-graph test-skillroute-compose test-semantic-comm test-cognitive-routing test-sem-incremental test-branch-reuse test-jspace-prod test-plan-reuse test-cortex

all: $(TARGET)

check-physics-lock:
	@if [ "$(PHYSICS_LOCK_CHECK)" != "0" ]; then \
		if [ ! -f physics.lock ]; then \
			echo "error: physics.lock not found at repo root" >&2; exit 1; \
		fi; \
		locked=$$(tr -d '[:space:]' < physics.lock); \
		case "$$locked" in \
			[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;; \
			*) echo "error: physics.lock must contain exactly one lowercase 40-hex commit" >&2; exit 1 ;; \
		esac; \
		if ! tools/pinned_checkout.sh verify "$(PHYSICS_DIR)" "$$locked" >/dev/null; then \
			printf '%s\n' "error: PHYSICS_DIR=$(PHYSICS_DIR) is not an exact worktree of physics.lock ($$locked)." >&2; \
			echo "       Use an unmodified checkout at the pin, or override with PHYSICS_LOCK_CHECK=0." >&2; \
			exit 1; \
		fi; \
	fi

$(OUT_DIR):
	mkdir -p $(OUT_DIR)

$(OUT_DIR)/%.o: src/%.c | $(OUT_DIR)
	$(CC) $(CFLAGS) $(CUDAPP_ENCODER_DEFS) -c $< -o $@

# Objects that read the physics tree: the two compiled from it, and the sources that include
# m16_native.h or nvrm.h from it (directly or through src/*.h; `gcc -MM` lists a $(PHYSICS_DIR)
# path for exactly these). They must be rebuilt when PHYSICS_DIR points at another tree, not only
# when a file there is newer, and none may compile before check-physics-lock passes (#488).
# The stamp records the resolved PHYSICS_DIR and its git HEAD and is rewritten only when that
# text changes, so an unchanged PHYSICS_DIR rebuilds nothing. Its phony prerequisite proves the
# commit, every tree/blob and the raw worktree bytes and modes first: when that proof refuses,
# the stamp is not made and no physics object compiles.
# The other objects take nothing from PHYSICS_DIR and are shared with physics-free builds
# (crumbline-learner, omega, test-program-id), so they stay ungated.
PHYSICS_STAMP = $(OUT_DIR)/physics.stamp
PHYSICS_OBJS = $(addprefix $(OUT_DIR)/,m16_native.o nvrm.o omega_accelerator_world.o \
	omega_blackwell_submit.o omega_blackwell_engine.o omega_blackwell_gates.o \
	omega_gpu_platform_linux.o omega_world_gates.o omega_evidence.o)
$(PHYSICS_STAMP): check-physics-lock | $(OUT_DIR)
	@new="$$(cd '$(PHYSICS_DIR)' 2>/dev/null && pwd -P || echo '$(PHYSICS_DIR)') $$(git -C '$(PHYSICS_DIR)' rev-parse HEAD 2>/dev/null || echo nogit)"; \
	if [ "$$(cat $@ 2>/dev/null)" != "$$new" ]; then printf '%s\n' "$$new" > $@; fi
$(PHYSICS_OBJS): $(PHYSICS_STAMP)

$(OUT_DIR)/m16_native.o: $(PHYSICS_DIR)/m16/m16_native.c | $(OUT_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(OUT_DIR)/nvrm.o: $(PHYSICS_DIR)/nvrm/nvrm.c | $(OUT_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

crumbline-learner: $(LEARNER)

test-crumbline: $(LEARNER)
	./tests/crumbline/run_conformance.sh $(LEARNER) tests/crumbline/vectors
	./tests/crumbline/run_crb1_conformance.sh $(LEARNER) tests/crumbline/crb1 tests/crumbline/crb1_findings.txt

$(LEARNER): src/crumbline/crumbline.om tools/crumbline_learner.om seed/out/omc | $(OUT_DIR)
	cat src/crumbline/crumbline.om tools/crumbline_learner.om | seed/out/omc > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

# Default `omegatool` binary: pure seeded OM-2 (tools/omegatool.om + src/*.om, physics-free).
$(TARGET): $(OMEGATOOL_OM_SRCS) $(OMEGATOOL_OM_OMC) | $(OUT_DIR)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(OMEGATOOL_OM_SRCS)) | $(OMEGATOOL_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

test: $(TARGET)
	./$(TARGET) --run-gates
	./$(TARGET) --reference-demonstrate-arithmetic
	./$(TARGET) --reference-demonstrate-physics

test-m5: $(TARGET)
	./$(TARGET) --run-m5-gates
	./$(TARGET) --reference-demonstrate-realization

test-m6: $(TARGET)
	./$(TARGET) --run-m6-gates
	./$(TARGET) --reference-demonstrate-self-host

test-m7: $(TARGET)
	./$(TARGET) --run-m7-gates
	./$(TARGET) --reference-demonstrate-verify

test-m8: $(TARGET)
	./$(TARGET) --run-m8-gates
	./$(TARGET) --reference-demonstrate-program

test-m9: $(TARGET)
	./$(TARGET) --run-m9-gates
	./$(TARGET) --reference-demonstrate-synthesis

test-m10: $(TARGET)
	./$(TARGET) --run-m10-gates
	./$(TARGET) --reference-demonstrate-library

test-m11: $(TARGET)
	./$(TARGET) --run-m11-gates
	./$(TARGET) --reference-demonstrate-discovery

test-m12: $(TARGET)
	./$(TARGET) --run-m12-gates
	./$(TARGET) --legacy-oracle-living-matvec

test-m13: $(TARGET)
	./$(TARGET) --run-m13-gates
	./$(TARGET) --reference-demonstrate-machine

test-m14: $(TARGET)
	./$(TARGET) --run-m14-gates
	./$(TARGET) --reference-demonstrate-realization-synthesis

test-m15: $(TARGET)
	./$(TARGET) --run-m15-gates
	./$(TARGET) --reference-demonstrate-accelerator

test-m17: $(TARGET)
	./$(TARGET) --run-m17-gates
	./$(TARGET) --reference-demonstrate-blackwell-vector

clean:
	rm -rf $(OUT_DIR)

test-m19: $(TARGET)
	./$(TARGET) --run-m19-gates

# Host-only tests of the M19R qualifier (tools/m19r_qualify.sh) and its
# canonical-JSON helper (tools/json_canon.c). No GPU.
.PHONY: test-m19r-qualify
test-m19r-qualify:
	tools/test_m19r_qualify.sh

# Host-only tests of the chipwait campaign runner (tools/chipwait_campaign.sh)
# against a stub qualifier. No GPU.
.PHONY: test-chipwait-campaign
test-chipwait-campaign:
	tools/test_chipwait_campaign.sh

# Host-only tests of the Gate 14 combiner (tools/gate14_combine.sh). No GPU.
.PHONY: test-gate14-combine
test-gate14-combine:
	tools/test_gate14_combine.sh

# Host-only self-test of the gate physics pins (omega#523): every tests/gates/run.sh step
# that builds against physics takes physics.lock, and its gate lists physics.lock as an input.
.PHONY: test-gate-physics-pin
test-gate-physics-pin:
	tools/test_gate_physics_pin.sh
	tools/test_pinned_checkout.sh

# Host-only self-test of exact pinned-checkout materialization and verification:
# dirty sources and replace refs cannot affect output; byte, mode and extra-path mutants refuse.
.PHONY: test-pinned-checkout
test-pinned-checkout:
	tools/test_pinned_checkout.sh

# Host-only self-test of the E1 closure combiner (tools/e1_combine.sh): good
# synthetic constituent set accepted, every hostile mutant refused. No GPU.
.PHONY: test-e1-combine
test-e1-combine:
	tools/test_e1_combine.sh

# Host-only self-test of the shared chip-run module (tools/chip_run.sh): every
# refusal path with fake binaries. No GPU.
.PHONY: test-chip-run
test-chip-run:
	tests/test_chip_run.sh

# Host-only check of the unwritten-trap manifest and its wrapper. No GPU.
.PHONY: test-chip-run-trap-manifest
test-chip-run-trap-manifest:
	tests/test_chip_run_trap_manifest.sh

# Host-only check of the transcendental-gate manifest and its wrapper (fake chip, old-vs-new receipt keys). No GPU.
.PHONY: test-chip-run-transc-manifest
test-chip-run-transc-manifest:
	tests/test_chip_run_transc_manifest.sh

# Gate 5 (OMEGA-NUMERIC-0), CPU tiers only: reference, CPU parity, provenance
# and negative tests. Opens no device. The GB10 tier and the receipt come
# from tests/run_numeric_gates.sh on the chip. Exits nonzero while any gate
# item fails.
.PHONY: test-numeric-cpu test-numeric-qualify
NUMERIC_CPU_SRCS = tests/test_omega_numeric.c src/omega_numeric.c src/omega_numeric_provenance.c src/omega_numeric_divsqrt_gb10.c \
                   $(NUMERIC_BW_SRCS)
NUMERIC_CPU_HDRS = src/omega_numeric.h src/omega_numeric_provenance.h src/omega_numeric_divsqrt_gb10.h tests/numeric_oracle.h \
                   $(NUMERIC_BW_HDRS)
build/test_omega_numeric_cpu: $(NUMERIC_CPU_SRCS) $(NUMERIC_CPU_HDRS)
	@mkdir -p build
	gcc -std=gnu11 -O2 -Wall -Wextra -Werror -ffp-contract=off -Isrc -DOMEGA_NUMERIC_CPU_ONLY -o $@ $(NUMERIC_CPU_SRCS)
# test-numeric-cpu exit status: 0 means no host test failed and the only SKIPs
# are the five declared chip-only IDs (CHIP_ONLY_IDS in the test; the last line
# prints "Gate 5 Verdict: PASS_EXCEPT_DECLARED_CHIP_ONLY"). Nonzero means a real
# host regression (verdict HOST_REGRESSION) or a SKIP nobody declared
# (UNDECLARED_SKIP). The chip build allows no SKIP at all.
test-numeric-cpu: build/test_omega_numeric_cpu
	./build/test_omega_numeric_cpu

# Host-only tests of the Gate 5 qualifier and receipt writer. No GPU.
test-numeric-qualify: build/test_omega_numeric_cpu
	tools/test_numeric_qualify.sh

# Deletes each CHECK-marked pre-submission check in src/omega_numeric.c in a
# scratch copy and proves a Gate 5 host test then fails. No GPU.
# Then applies each arithmetic mutation in tools/numeric_oracle_mutations.sh
# (broken EXP/LOG coefficients, wrong host instruction, wrong LDS index, an
# undeclared SKIP) and proves the CPU-only run exits nonzero. No GPU.
.PHONY: test-numeric-sweep
test-numeric-sweep:
	tools/numeric_check_sweep.sh
	tools/numeric_oracle_mutations.sh

# E1 scalar contract, exhaustive: every 2^32 input of each unary E1 op through
# the reference, the CPU tier and the integer oracle (one process per op,
# docs/numeric/E1_SCALAR_CONTRACT.md). Not part of Gate 5. No GPU.
.PHONY: test-numeric-e1-exhaustive
test-numeric-e1-exhaustive: build/test_omega_numeric_cpu
	./build/test_omega_numeric_cpu --e1-exhaustive

# E1 WP-D general reductions (docs/numeric/E1_REDUCTION_CONTRACT.md), CPU
# tiers only: reference, CPU realization, oracles, negative order test and the
# GB10 pre-submission checks. Opens no device. The chip parity run is
# tests/run_reduce_chip.sh. Last line: "E1 Reduce Verdict: PASS_EXCEPT_DECLARED_CHIP_ONLY".
.PHONY: test-numeric-reduce-cpu
REDUCE_CPU_SRCS = tests/test_omega_reduce.c src/omega_numeric_reduce.c src/omega_numeric_reduce_gb10.c \
                  src/omega_numeric.c src/omega_numeric_provenance.c src/omega_numeric_divsqrt_gb10.c \
                  $(NUMERIC_BW_SRCS)
build/test_omega_reduce_cpu: $(REDUCE_CPU_SRCS) src/omega_numeric_reduce.h $(NUMERIC_CPU_HDRS)
	@mkdir -p build
	gcc -std=gnu11 -O2 -Wall -Wextra -Werror -ffp-contract=off -Isrc -DOMEGA_NUMERIC_CPU_ONLY -o $@ $(REDUCE_CPU_SRCS)
test-numeric-reduce-cpu: build/test_omega_reduce_cpu
	./build/test_omega_reduce_cpu

# E1 WP-B: FP32 transcendental sequences (SIGMOID TANH RSQRT EXP2 LOG2 ERF SIN
# COS GELU), CPU tier, bounded contract (docs/numeric/E1_TRANSCENDENTAL_CONTRACT.md).
# No libm, no GPU. test-numeric-transc: special values, oracle self-checks,
# about 1.1M sampled inputs per op against the binary128 oracle, determinism,
# then one build per perturbed coefficient (OMEGA_TRANSC_MUTATE=1..10) which
# must FAIL. test-numeric-transc-full: all 2^32 inputs of every op (long; run
# it detached). test-numeric-transc-digest: full-domain outputs against the
# frozen digests.
.PHONY: test-numeric-transc test-numeric-transc-full test-numeric-transc-digest
TRANSC_SRCS = tests/test_omega_transc.c src/omega_numeric_transc.c src/omega_om_units.c
TRANSC_HDRS = src/omega_numeric_transc.h src/omega_numeric.h src/sha256.h
TRANSC_CC = gcc -std=gnu11 -O2 -Wall -Wextra -Werror -ffp-contract=off -fno-fast-math -pthread -Isrc
TRANSC_MUTANTS = 1 2 3 4 5 6 7 8 9 10
build/test_omega_transc: $(TRANSC_SRCS) $(TRANSC_HDRS)
	@mkdir -p build
	$(TRANSC_CC) -o $@ $(TRANSC_SRCS)
test-numeric-transc: build/test_omega_transc
	./build/test_omega_transc fast
	@for m in $(TRANSC_MUTANTS); do \
	  $(TRANSC_CC) -DOMEGA_TRANSC_MUTATE=$$m -o build/test_omega_transc_mut$$m $(TRANSC_SRCS) || exit 1; \
	  if ./build/test_omega_transc_mut$$m fast > build/test_omega_transc_mut$$m.log 2>&1; then \
	    echo "MUTANT $$m SURVIVED (bound check did not fail)"; exit 1; \
	  else echo "mutant $$m killed: $$(grep -m1 '^FAIL' build/test_omega_transc_mut$$m.log)"; fi; \
	done
	@echo "test-numeric-transc: PASS (all $(words $(TRANSC_MUTANTS)) mutants killed)"
test-numeric-transc-full: build/test_omega_transc
	./build/test_omega_transc full
test-numeric-transc-digest: build/test_omega_transc
	./build/test_omega_transc digest

# Offline provenance of the GB10 MAX/MIN warp patch: Omega's own disassembler (sm121dis,
# C6; it agrees with nvdisasm on every library kernel) must decode every word to the text the
# patch table records. No device opened. Last line: "E1 Reduce nvdisasm: PASS" (name kept for receipts).
.PHONY: test-numeric-reduce-nvdisasm
REDUCE_NVDISASM ?= build/sm121dis
test-numeric-reduce-nvdisasm: build/test_omega_reduce_cpu build/sm121dis
	@set -e; t=$$(mktemp -d); trap 'rm -rf "$$t"' EXIT; ./build/test_omega_reduce_cpu --dump "$$t"; \
	for op in max min; do \
	  "$(REDUCE_NVDISASM)" -b SM121 "$$t/$$op.bin" > "$$t/$$op.raw" || { echo "E1 Reduce nvdisasm: FAIL ($$op: disassembler error)"; exit 1; }; \
	  sed -n 's|^[[:space:]]*/\*\([0-9a-f]\{4\}\)\*/[[:space:]]*\(.*;\).*$$|\1 \2|p' "$$t/$$op.raw" \
	    | sed 's/[[:space:]]\{1,\}/ /g' > "$$t/$$op.got"; \
	  diff -u "$$t/$$op.lst" "$$t/$$op.got" || { echo "E1 Reduce nvdisasm: FAIL ($$op)"; exit 1; }; echo "$$op: $$(wc -l < "$$t/$$op.lst") words decode to the recorded text"; \
	done; echo "E1 Reduce nvdisasm: PASS ($$("$(REDUCE_NVDISASM)" --version))"

# Resident reaction runtime heartbeat (ADR 0016, R3/R4 host reference).
# CPU only; links no PHYSICS/NVRM code (omega_evidence.c needs only the header).
RX_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/omega_om_units.c src/omega_evidence.c tests/runtime/rx_heartbeat_test.c
RX_TEST = $(OUT_DIR)/rx_heartbeat_test

$(RX_TEST): $(RX_SRCS) src/runtime/rx_caproot.h src/runtime/rx_world.h \
	src/runtime/omega_shared_world_abi.h | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_SRCS)

test-r3: $(RX_TEST)
	./$(RX_TEST)

# HD-09 resource contract v0, first enforcement cut: a declared deadline is
# enforced before publishing (late reaction cancelled, nothing published,
# charge refunded once). CPU only, same links as R3 minus the heartbeat test.
RX_DEADLINE_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/omega_om_units.c src/omega_evidence.c tests/runtime/rx_deadline_cancel.c
RX_DEADLINE_TEST = $(OUT_DIR)/rx_deadline_cancel

$(RX_DEADLINE_TEST): $(RX_DEADLINE_SRCS) src/runtime/rx_caproot.h src/runtime/rx_world.h \
	src/runtime/omega_shared_world_abi.h | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_DEADLINE_SRCS)

.PHONY: test-rx-deadline-cancel
test-rx-deadline-cancel: $(RX_DEADLINE_TEST)
	./$(RX_DEADLINE_TEST)

# I11: a dependent popped while a writer of its inputs is still computing is
# held so the writer's wake merges into it (one commit per stimulus, as with
# one worker). Deterministic forced interleaving; the mutant build has no hold
# and must FAIL. CPU only, same links as R3.
RX_I11_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/omega_om_units.c src/omega_evidence.c tests/runtime/rx_i11_wake_merge.c
RX_I11_TEST = $(OUT_DIR)/rx_i11_wake_merge
RX_I11_MUTANT = $(OUT_DIR)/rx_i11_wake_merge_mutant

$(RX_I11_TEST): $(RX_I11_SRCS) src/runtime/rx_caproot.h src/runtime/rx_world.h \
	src/runtime/omega_shared_world_abi.h | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_I11_SRCS)

$(RX_I11_MUTANT): $(RX_I11_SRCS) src/runtime/rx_caproot.h src/runtime/rx_world.h \
	src/runtime/omega_shared_world_abi.h | $(OUT_DIR)
	$(CC) $(CFLAGS) -DRX_WORLD_MUTATE_NO_UPSTREAM_HOLD -pthread -o $@ $(RX_I11_SRCS)

test-i11-wake-merge: $(RX_I11_TEST) $(RX_I11_MUTANT)
	./$(RX_I11_TEST)
	@if ./$(RX_I11_MUTANT); then \
	  echo "MUTANT SURVIVED (no upstream hold, test still passed)"; exit 1; \
	else echo "test-i11-wake-merge: PASS (mutant killed)"; fi

# Omega semantic variables and incremental recomputation
# (gate OMEGA_INCREMENTAL_SEMANTICS_PASS). CPU only, same links as R3.
RX_SEM_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/runtime/rx_semantic.c src/omega_om_units.c src/omega_evidence.c \
	tests/runtime/rx_sem_incremental.c
RX_SEM_TEST = $(OUT_DIR)/rx_sem_incremental_test

$(RX_SEM_TEST): $(RX_SEM_SRCS) src/runtime/rx_semantic.h src/runtime/rx_caproot.h \
	src/runtime/rx_world.h src/runtime/omega_shared_world_abi.h | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_SEM_SRCS)

test-sem-incremental: $(RX_SEM_TEST)
	./$(RX_SEM_TEST)

# R7: native Aienux authority versus the Linux oracle, then the world view.
# The authority source is the FULL commit in aienos.lock, proven by
# tools/aienos_lock_source.sh from git objects (a directory name, a short SHA or an
# override is not proof). Default: extracted with `git archive` from a repository holding
# that commit (AIENOS_LOCK_REPO, or the repository around AIENOS_R7_DIR) into
# $(OUT_DIR)/aienos-authority/<full lock>. An AIENOS_R7_DIR override is used only after
# the same proof: every tracked file under the subpaths built from has the locked blob
# and no unignored extra file sits beside them. The proof runs on every build (phony
# prerequisite), so a source edited after extraction stops the build.
AIENOS_LOCK_REPO ?= ../aienos-argus-cap
# AIENOS_LOCK is the validated commit parsed at the top of this Makefile.
AIENOS_R7_DEFAULT = $(OUT_DIR)/aienos-authority/$(AIENOS_LOCK)
AIENOS_R7_DIR ?= $(AIENOS_R7_DEFAULT)
AIENOS_CAP_LIB ?= $(OUT_DIR)/aienos-cap/libaienos_capability_om2.a
# $(call aienos_source,<subpaths>): materialize into the default cache, or prove the override.
aienos_source = if [ "$(AIENOS_R7_DIR)" = "$(AIENOS_R7_DEFAULT)" ]; then \
		AIENOS_LOCK_REPO="$(AIENOS_LOCK_REPO)" AIENOS_LOCK='$(AIENOS_LOCK)' AIENOS_R7_DIR= bash tools/aienos_lock_source.sh materialize "$(AIENOS_R7_DIR)" $(1); \
	else \
		AIENOS_LOCK_REPO="$(AIENOS_LOCK_REPO)" AIENOS_LOCK='$(AIENOS_LOCK)' AIENOS_R7_DIR="$(AIENOS_R7_DIR)" bash tools/aienos_lock_source.sh verify-dir "$(AIENOS_R7_DIR)" $(1); \
	fi || { echo 'error: the aienos authority source is not the aienos.lock commit $(AIENOS_LOCK) (see above).'; \
		echo "  pass AIENOS_LOCK_REPO=<an aienos clone holding that commit>, or AIENOS_R7_DIR=<a clean tree of it inside such a clone>;"; \
		echo "  a modified default cache under $(OUT_DIR)/aienos-authority must be deleted, not reused."; exit 1; }
RX_R7_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/runtime/rx_native_bind.c src/omega_om_units.c src/omega_evidence.c \
	tests/runtime/rx_r7_native.c
RX_R7_TEST = $(OUT_DIR)/rx_r7_native_test

.PHONY: aienos-authority-capability
aienos-authority-capability:
	@$(call aienos_source,native/capability)

# Pure seeded OM-2 capability authority (seed/authority/cap_table_om2.om via
# src/runtime/aienos_cap_om2.c). Severs the external libaienos_capability.a / aienos.lock dependency.
$(AIENOS_CAP_LIB): src/runtime/aienos_cap_om2.c src/runtime/aienos_cap.h src/runtime/rx_caproot.h src/omega_native.h | $(OUT_DIR)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $(dir $@)/aienos_cap_om2.o src/runtime/aienos_cap_om2.c
	rm -f $@ && $(AR) rcs $@ $(dir $@)/aienos_cap_om2.o

# OMEGA_EFFECT_CAP64 (spec/effect-cap64-migration.md): effect objects carry the
# full 64-bit Aienux capability generation. Pure seeded OM-2, physics-free
# (mk/effect-cap64-om.mk). Prints OMEGA_EFFECT_CAP64_{ROUNDTRIP,IDENTITY,
# STALE_REJECT,AUTHORITY}_PASS gate lines.
EFFECT_CAP64_CAP_INC ?= $(AIENOS_R7_DIR)/native/capability

.PHONY: test-effect-cap64
test-effect-cap64: test-effect-cap64-om

# OMEGA_AIENOS_CAP_ABI: src/runtime/aienos_cap.h, the copy the runtime compiles
# against, must match the pinned header $(EFFECT_CAP64_CAP_INC)/aienos_capability.h
# that $(AIENOS_CAP_LIB) is built from: struct layouts field by field (offset, size,
# kind, signedness), macro values, prototypes. Eight mutated copies must each be
# refused. Header only: nothing is linked against the library.
.PHONY: test-aienos-cap-abi
test-aienos-cap-abi: aienos-authority-capability
	CC="$(CC)" CFLAGS="$(CFLAGS)" bash tests/runtime/aienos_cap_abi.sh "$(EFFECT_CAP64_CAP_INC)"

$(RX_R7_TEST): $(RX_R7_SRCS) src/runtime/rx_caproot.h src/runtime/rx_world.h \
	src/runtime/aienos_cap.h src/runtime/omega_shared_world_abi.h $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_R7_SRCS) $(AIENOS_CAP_LIB) -lm

test-r7: $(RX_R7_TEST)
	./$(RX_R7_TEST)

# aienos#266/#272 at aienos.lock: the R16 operator control capability (the epoch
# right on RX_WORLD_RES_CONTROL) is refused by every authority operation, the office
# still operates the authority, and the world still accepts the capability for the halt
# check. Host only.
RX_OP_AUTH_MISUSE_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/runtime/rx_native_bind.c src/omega_om_units.c src/omega_evidence.c \
	tests/runtime/rx_operator_authority_misuse.c
RX_OP_AUTH_MISUSE_TEST = $(OUT_DIR)/rx_operator_authority_misuse_test
$(RX_OP_AUTH_MISUSE_TEST): $(RX_OP_AUTH_MISUSE_SRCS) src/runtime/rx_caproot.h src/runtime/rx_world.h \
	src/runtime/rx_operator.h src/runtime/aienos_cap.h $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_OP_AUTH_MISUSE_SRCS) $(AIENOS_CAP_LIB) -lm

.PHONY: test-r16-operator-authority-misuse
test-r16-operator-authority-misuse: $(RX_OP_AUTH_MISUSE_TEST)
	./$(RX_OP_AUTH_MISUSE_TEST)

# R9: generation barrier. The candidate is prepared beside the live world.
# A stop after each persistence step must recover one whole generation.
RX_R9_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/runtime/rx_generation.c src/omega_om_units.c src/omega_evidence.c \
	tests/runtime/rx_r9_barrier.c
RX_R9_TEST = $(OUT_DIR)/rx_r9_barrier_test

$(RX_R9_TEST): $(RX_R9_SRCS) src/runtime/rx_generation.h src/runtime/rx_caproot.h \
	src/runtime/rx_world.h src/runtime/aienos_cap.h $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_R9_SRCS) $(AIENOS_CAP_LIB) -lm

test-r9: $(RX_R9_TEST)
	./$(RX_R9_TEST)

# R12 host rules against the native Aienux authority. The graphics processor is
# not started. A pass here does not claim the resident-seat gate.
RX_R12_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/runtime/rx_native_bind.c src/omega_om_units.c src/omega_evidence.c \
	tests/runtime/rx_r12_resident.c
RX_R12_TEST = $(OUT_DIR)/rx_r12_resident_test

$(RX_R12_TEST): $(RX_R12_SRCS) src/runtime/rx_caproot.h src/runtime/rx_world.h \
	src/runtime/aienos_cap.h src/runtime/omega_shared_world_abi.h $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_R12_SRCS) $(AIENOS_CAP_LIB) -lm

test-r12: $(RX_R12_TEST)
	./$(RX_R12_TEST)

# R16 G6 operator emergency stop (spec/r16-operator-emergency-stop.md). Host only,
# real capability root: authority refusals, in-flight and racing stops, the
# generation store under a stop, the durable mark across a restart, and resume.
# The mutant script then removes each guard in turn from a temporary copy and
# requires the test to fail against every one. The resident-seat case lives in
# test-r12 (t_emergency_stop, native Aienux authority).
RX_EMERGENCY_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/runtime/rx_generation.c src/omega_om_units.c tests/runtime/rx_emergency.c
RX_EMERGENCY_TEST = $(OUT_DIR)/rx_emergency_test

$(RX_EMERGENCY_TEST): $(RX_EMERGENCY_SRCS) src/runtime/rx_caproot.h src/runtime/rx_world.h \
	src/runtime/rx_generation.h src/runtime/rx_caller.h | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_EMERGENCY_SRCS) -lm

.PHONY: test-rx-emergency
test-rx-emergency: $(RX_EMERGENCY_TEST)
	./$(RX_EMERGENCY_TEST)
	CC="$(CC)" bash tests/runtime/rx_emergency_mutants.sh

# R10: Omega as a resident realization faculty. Omega's native AArch64 matvec
# realizations become ready from cost evidence, are verified in a sandbox,
# measured, and recorded; production picks the record up. AArch64 hosts only.
RX_R10_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/runtime/rx_native_bind.c src/runtime/rx_omega.c src/omega_om_units.c src/omega_evidence.c \
	src/omega_canonical.c src/omega_validate.c src/omega_core.c src/omega_codec.c \
	src/aarch64_encoder.c src/aarch64_decoder.c src/omega_realize.c src/omega_realize_synth.c src/omega_program.c \
	src/omega_machine.c src/omega_exec.c src/omega_verify.c src/omega_matvec.c src/omega_matvec_quad.c \
	tests/runtime/rx_r10_omega.c
RX_R10_TEST = $(OUT_DIR)/rx_r10_omega_test

$(RX_R10_TEST): $(RX_R10_SRCS) src/runtime/rx_omega.h src/runtime/rx_caproot.h \
	src/runtime/rx_world.h src/runtime/aienos_cap.h $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_R10_SRCS) $(AIENOS_CAP_LIB) -lm

test-r10: $(RX_R10_TEST)
	./$(RX_R10_TEST)

# R8: AEGIS resident authority. Capability slots in the world; AEGIS decides,
# only root.install mints, through the native Aienux authority.
RX_R8_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/runtime/rx_native_bind.c src/runtime/rx_aegis.c src/omega_om_units.c src/omega_evidence.c \
	tests/runtime/rx_r8_aegis.c
RX_R8_TEST = $(OUT_DIR)/rx_r8_aegis_test

$(RX_R8_TEST): $(RX_R8_SRCS) src/runtime/rx_aegis.h src/runtime/rx_caproot.h \
	src/runtime/rx_world.h src/runtime/aienos_cap.h $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_R8_SRCS) $(AIENOS_CAP_LIB) -lm

test-r8: $(RX_R8_TEST)
	./$(RX_R8_TEST)

# R11: AIEN as a resident cognitive faculty. Part A drives AIEN alone on any
# host; part B is the living run with Omega, on hosts that have both Cortex-X925
# and Cortex-A725 cores. rx_aien.o is built alone first and must not reference
# any Omega symbol: AIEN reaches Omega only through world objects.
RX_R11_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/runtime/rx_native_bind.c src/runtime/rx_omega.c src/omega_om_units.c src/omega_evidence.c \
	src/omega_canonical.c src/omega_validate.c src/omega_core.c src/omega_codec.c \
	src/aarch64_encoder.c src/aarch64_decoder.c src/omega_realize.c src/omega_realize_synth.c src/omega_program.c \
	src/omega_machine.c src/omega_exec.c src/omega_verify.c src/omega_matvec.c src/omega_matvec_quad.c \
	tests/runtime/rx_r11_aien.c
RX_R11_TEST = $(OUT_DIR)/rx_r11_aien_test
RX_AIEN_OBJ = $(OUT_DIR)/rx_aien.o

$(RX_AIEN_OBJ): src/runtime/rx_aien.c src/runtime/rx_aien.h src/runtime/rx_world.h | $(OUT_DIR)
	$(CC) $(CFLAGS) -c -o $@ src/runtime/rx_aien.c
	@if nm -u $@ | grep -Ei 'omega' ; then \
		echo "rx_aien.o references Omega directly; AIEN must reach it only through the world"; \
		rm -f $@; exit 1; fi

$(RX_R11_TEST): $(RX_R11_SRCS) $(RX_AIEN_OBJ) src/runtime/rx_omega.h src/runtime/rx_caproot.h \
	src/runtime/rx_world.h src/runtime/aienos_cap.h $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_R11_SRCS) $(RX_AIEN_OBJ) $(AIENOS_CAP_LIB) -lm

test-r11: $(RX_R11_TEST)
	./$(RX_R11_TEST)

# R11 living run allowed inside its own quietlock hold, refused under any other.
.PHONY: test-r11-own-hold
test-r11-own-hold: $(RX_R11_TEST)
	sh tests/runtime/r11_own_hold_test.sh ./$(RX_R11_TEST)

# OMEGA_STATE_PROJECTION: cognition gets a compiled state projection from
# Cortex, not everything Cortex knows. Part B drives the real R11 AIEN faculty
# under the native Aienux authority. The projection objects are built alone
# first and may reference nothing but Cortex and SHA-256: no world, no faculty,
# no Omega realization code.
RX_SP_OBJS = $(OUT_DIR)/rx_cortex.o $(OUT_DIR)/rx_projection.o
RX_SP_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/runtime/rx_native_bind.c src/omega_om_units.c src/omega_evidence.c \
	tests/runtime/rx_sp_workloads.c tests/runtime/rx_state_projection.c
RX_SP_TEST = $(OUT_DIR)/rx_state_projection_test

$(OUT_DIR)/rx_cortex.o: src/runtime/rx_cortex.c src/runtime/rx_cortex.h | $(OUT_DIR)
	$(CC) $(CFLAGS) -c -o $@ src/runtime/rx_cortex.c

$(OUT_DIR)/rx_projection.o: src/runtime/rx_projection.c src/runtime/rx_projection.h \
	src/runtime/rx_cortex.h | $(OUT_DIR)
	$(CC) $(CFLAGS) -c -o $@ src/runtime/rx_projection.c
	@if nm -u $@ $(OUT_DIR)/rx_cortex.o | grep -E ' (rx_world|rx_aien|rx_omega|omega_)' ; then \
		echo "the projection references the world, a faculty or Omega realization code"; \
		rm -f $@; exit 1; fi

$(RX_SP_TEST): $(RX_SP_SRCS) $(RX_SP_OBJS) $(RX_AIEN_OBJ) tests/runtime/rx_sp_workloads.h \
	src/runtime/rx_world.h src/runtime/aienos_cap.h $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_SP_SRCS) $(RX_SP_OBJS) $(RX_AIEN_OBJ) $(AIENOS_CAP_LIB) -lm

test-state-projection: $(RX_SP_TEST)
	./$(RX_SP_TEST)

# M20 Cortex canonicalization: canonical Cortex contract, journal, single
# writer, typed recall, and World execution recorded through rx_cortex_record.
RX_CX_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/runtime/rx_cortex_record.c src/omega_om_units.c tests/runtime/rx_cortex_canon.c
RX_CX_TEST = $(OUT_DIR)/rx_cortex_canon_test

$(RX_CX_TEST): $(RX_CX_SRCS) $(OUT_DIR)/rx_cortex.o src/runtime/rx_cortex_record.h \
	src/runtime/rx_world.h | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_CX_SRCS) $(OUT_DIR)/rx_cortex.o

# Journal backend seam (native v1 P06 cut 1): rx_cortex.c built with
# CX_NO_POSIX must carry no file, lock or libc allocation symbol, and must
# pass the same append/replay/torn-tail contract over a memory backend.
RX_CX_FS_OBJ = $(OUT_DIR)/rx_cortex_freestanding.o
RX_CXJ_TEST = $(OUT_DIR)/rx_cortex_journal_test
RX_CX_FS_ALLOWED = memcpy|memmove|memset|memcmp|sha256_init|sha256_update|sha256_final|sha256_hash|cx_fs_alloc|cx_fs_realloc|cx_fs_free

$(RX_CX_FS_OBJ): src/runtime/rx_cortex.c src/runtime/rx_cortex.h tests/runtime/cx_config_freestanding.h | $(OUT_DIR)
	$(CC) $(CFLAGS) -ffreestanding -fno-builtin -DCX_NO_POSIX \
	  -Itests/runtime -DCX_CONFIG_H='"cx_config_freestanding.h"' -c -o $@ src/runtime/rx_cortex.c
	@bad=$$(nm -u $@ | awk '{print $$NF}' | grep -Ev '^(_GLOBAL_OFFSET_TABLE_|($(RX_CX_FS_ALLOWED)))$$' || true); \
	if [ -n "$$bad" ]; then echo "rx_cortex.c (CX_NO_POSIX) still needs: $$bad"; rm -f $@; exit 1; fi
	@echo "rx_cortex.c (CX_NO_POSIX): no file, lock or libc allocation symbols"

$(RX_CXJ_TEST): $(RT_OM_CXJ_SRCS) $(RT_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT_OM_CXJ_SRCS) ) | $(RT_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

test-cortex: $(RX_CX_TEST) $(RX_CX_FS_OBJ) $(RX_CXJ_TEST)
	./$(RX_CX_TEST)
	./$(RX_CXJ_TEST)

# Physical graphics seat against the native Aienux authority. Not part of
# GitHub checks. A pass on this machine is the only run that may set
# silicon_observed.
RX_R12_SILICON_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c \
	src/runtime/rx_coherent.c src/runtime/rx_native_bind.c \
	src/runtime/rx_resident_gpu.c src/omega_om_units.c src/omega_evidence.c \
	src/omega_blackwell_codegen.c src/omega_blackwell_encoder.c \
	src/omega_blackwell_qmd.c src/omega_blackwell_matmul.c \
	$(PHYSICS_DIR)/m16/m16_native.c $(PHYSICS_DIR)/nvrm/nvrm.c \
	tests/runtime/rx_r12_silicon.c
RX_R12_SILICON = $(OUT_DIR)/rx_r12_silicon_test

$(RX_R12_SILICON): $(RX_R12_SILICON_SRCS) src/runtime/rx_world.h \
	src/runtime/rx_resident_gpu.h src/runtime/rx_caproot.h src/runtime/aienos_cap.h \
	src/omega_blackwell_codegen.h $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_R12_SILICON_SRCS) $(AIENOS_CAP_LIB) -ldl -lm

test-r12-silicon: $(RX_R12_SILICON)
	./$(RX_R12_SILICON)

# COMPOSITION-2 in the living system (WP-A): the composition modules are part
# of the canonical living build, so every R13/R14/R15/R16 binary links them.
# rx_graph.o, rx_capq.o and rx_skillroute.o keep their own no-mint symbol
# checks; the living host build depends on them so the checks run with it.
RX_COMPOSE_LIVING_SRCS = src/runtime/aien_machine_id.c src/runtime/rx_jspace.c \
	src/runtime/rx_cortex.c src/runtime/rx_cortex_record.c src/runtime/rx_graph.c \
	src/runtime/rx_capq.c src/runtime/rx_skillroute.c src/runtime/rx_compose.c
RX_COMPOSE_LIVING_CHECKS = $(OUT_DIR)/rx_graph.o $(OUT_DIR)/rx_capq.o $(OUT_DIR)/rx_skillroute.o \
	src/runtime/rx_compose.h

# Lane 32: ONE test-build flag, AIEN_TEST_BUILD, off by default. It alone
# admits the test-only pieces: the Fabric F5-0 loopback transport, the HMAC
# stand-in authenticator and the in-process dispatcher (src/fabric, Lane 13),
# the Fabric living phase with its fixed test keys (tests/fabric/
# fab_living_phase.h), the composition fixture and the rx_compose fault and
# rogue-candidate hooks (RXC_TEST_HOOKS, implied by the flag; alone it is an
# #error). Their headers refuse to compile without it. The PRODUCTION program
# (rx_r13_living_host/_silicon, test-r13-host/-silicon) never sets it, links
# ARGUS and is checked by test-prod-hygiene; the TEST BUILD variant
# (rx_r13_living_testbuild_*, test-r13-testbuild-*) carries the composition
# and Fabric phases and reports R13_LIVING_SYSTEM_TEST_BUILD, never the gate.
# docs/r16-production-entry-point.md has the table.
AIEN_TEST_FLAGS = -DAIEN_TEST_BUILD=1
RX_FABRIC_TEST_SRCS = src/fabric/fabric.c src/fabric/fab_hmac.c src/fabric/fab_loopback.c \
	src/fabric/fab_dispatch.c
RX_R13_TEST_CHECKS = tests/runtime/rx_compose_fixture.h src/fabric/fab_dispatch.h \
	src/fabric/fab_loopback.h src/fabric/fab_hmac.h tests/fabric/fab_living_phase.h
# The production build refuses the flag outright.
RX_PROD_REFUSE_TEST = $(if $(findstring AIEN_TEST_BUILD,$(CFLAGS))$(findstring RXC_TEST_HOOKS,$(CFLAGS)),\
	$(error the production program never builds with AIEN_TEST_BUILD or RXC_TEST_HOOKS in CFLAGS))

# R13 host uses the R12 processor stand-in and cannot claim the silicon gate.
# R13 silicon runs the same world against the physical resident GB10 seat.
# RX_R13_SRCS is the PRODUCTION source set (no test piece); the R14/R15 rigs
# filter rx_r13_living.c out of it.
RX_R13_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c \
	src/runtime/rx_coherent.c src/runtime/rx_native_bind.c \
	src/runtime/rx_aegis.c src/runtime/rx_aien.c src/runtime/rx_omega.c \
	src/runtime/rx_generation.c src/runtime/rx_living.c \
	src/runtime/rx_operator.c \
	src/omega_om_units.c src/omega_evidence.c src/omega_canonical.c \
	src/omega_validate.c src/omega_core.c src/omega_codec.c \
	src/aarch64_encoder.c src/aarch64_decoder.c src/omega_realize.c \
	src/omega_realize_synth.c src/omega_program.c src/omega_machine.c src/omega_exec.c \
	src/omega_verify.c src/omega_matvec.c src/omega_matvec_quad.c \
	$(RX_COMPOSE_LIVING_SRCS) \
	tests/runtime/rx_r13_living.c
# librx_compose.a objects (mk/rx_compose_lib.mk) are compiled with -MMD; include their
# .d files HERE, after RX_R13_SRCS exists (the mk file is included at the top, where the
# list is still empty and an include there expands to nothing). Without this a header
# change (rx_cortex.h, omega#408) left rx_compose.o / rxc_host_abi.o stale in a reused
# OUT_DIR: the archive mixed two layouts of CxStore and rxc_host_run refused with
# RX_ERR_AUTHORITY (sovereign-core abi-qualify, 2026-10-12).
-include $(RXC_LIB_OBJS:.o=.d)
RX_R13_TEST_SRCS = $(RX_R13_SRCS) $(RX_FABRIC_TEST_SRCS)
RX_R13_SILICON_EXTRA = src/runtime/rx_resident_gpu.c src/omega_blackwell_codegen.c \
	src/omega_blackwell_encoder.c src/omega_blackwell_qmd.c src/omega_blackwell_matmul.c \
	$(PHYSICS_DIR)/m16/m16_native.c $(PHYSICS_DIR)/nvrm/nvrm.c
# Production program (rules after the ARGUS block below: they link ARGUS).
RX_R13_HOST = $(OUT_DIR)/rx_r13_living_host
RX_R13_SILICON = $(OUT_DIR)/rx_r13_living_silicon
# Test-build variant (no ARGUS).
RX_R13_TEST_HOST = $(OUT_DIR)/rx_r13_living_testbuild_host
RX_R13_TEST_SILICON = $(OUT_DIR)/rx_r13_living_testbuild_silicon

$(RX_R13_TEST_HOST): $(RX_R13_TEST_SRCS) src/runtime/rx_living.h $(RX_COMPOSE_LIVING_CHECKS) \
	$(RX_R13_TEST_CHECKS) $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) $(AIEN_TEST_FLAGS) -pthread -o $@ $(RX_R13_TEST_SRCS) $(AIENOS_CAP_LIB) -lm

# Lane 17: the Fabric phase runs in the silicon test build too; its Fabric part
# is CPU-only loopback. The composition phase stays host-only.
$(RX_R13_TEST_SILICON): $(RX_R13_TEST_SRCS) $(RX_R13_SILICON_EXTRA) src/runtime/rx_living.h \
	$(RX_COMPOSE_LIVING_CHECKS) $(RX_R13_TEST_CHECKS) $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) $(AIEN_TEST_FLAGS) -DR13_SILICON -pthread -o $@ $(RX_R13_TEST_SRCS) \
		$(RX_R13_SILICON_EXTRA) $(AIENOS_CAP_LIB) -ldl -lm

test-r13-host: $(RX_R13_HOST)
	./$(RX_R13_HOST)

test-r13-silicon: $(RX_R13_SILICON)
	./$(RX_R13_SILICON)

test-r13-testbuild-host: $(RX_R13_TEST_HOST)
	./$(RX_R13_TEST_HOST)

test-r13-testbuild-silicon: $(RX_R13_TEST_SILICON)
	./$(RX_R13_TEST_SILICON)

# OMEGA_BRANCH_STATE_REUSE: J-Space branches sharing one semantic prefix,
# shared-state realization versus independent recomputation, FORGE placement.
RX_BRANCH_REUSE_SRCS = src/runtime/rx_jspace.c src/omega_om_units.c src/omega_evidence.c \
	tests/runtime/rx_branch_reuse.c
RX_BRANCH_REUSE_TEST = $(OUT_DIR)/rx_branch_reuse

$(RX_BRANCH_REUSE_TEST): $(RX_BRANCH_REUSE_SRCS) src/runtime/rx_jspace.h | $(OUT_DIR)
	$(CC) $(CFLAGS) -o $@ $(RX_BRANCH_REUSE_SRCS) -lm

test-branch-reuse: $(RX_BRANCH_REUSE_TEST)
	./$(RX_BRANCH_REUSE_TEST)

# M20 production J-Space mechanics: slab/extent reclamation, generation-safe
# references, limits, concurrency, durable reopen/crash/torn metadata, World
# commit compatibility. Fast; runs in CI.
RX_JSPACE_PROD_SRCS = src/runtime/rx_jspace.c src/runtime/rx_caproot.c src/runtime/rx_world.c \
	src/runtime/rx_coherent.c src/omega_om_units.c src/omega_evidence.c tests/runtime/rx_jspace_prod.c
RX_JSPACE_PROD_TEST = $(OUT_DIR)/rx_jspace_prod

$(RX_JSPACE_PROD_TEST): $(RX_JSPACE_PROD_SRCS) src/runtime/rx_jspace.h src/runtime/rx_world.h \
	src/runtime/rx_caproot.h | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_JSPACE_PROD_SRCS) -lm

test-jspace-prod: $(RX_JSPACE_PROD_TEST)
	./$(RX_JSPACE_PROD_TEST)

# R14: the R13 organism attacked while alive. Host uses the R12 processor
# stand-in and cannot claim the gate; silicon runs D and E on the GB10 seat.
RX_R14_SRCS = $(filter-out tests/runtime/rx_r13_living.c src/runtime/rx_operator.c,$(RX_R13_SRCS)) \
	tests/runtime/rx_r14_recovery.c
RX_R14_HOST = $(OUT_DIR)/rx_r14_recovery_host
RX_R14_SILICON = $(OUT_DIR)/rx_r14_recovery_silicon

$(RX_R14_HOST): $(RX_R14_SRCS) src/runtime/rx_living.h $(RX_COMPOSE_LIVING_CHECKS) $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_R14_SRCS) $(AIENOS_CAP_LIB) -lm

$(RX_R14_SILICON): $(RX_R14_SRCS) src/runtime/rx_resident_gpu.c \
	src/omega_blackwell_codegen.c src/omega_blackwell_encoder.c \
	src/omega_blackwell_qmd.c src/omega_blackwell_matmul.c \
	$(PHYSICS_DIR)/m16/m16_native.c $(PHYSICS_DIR)/nvrm/nvrm.c \
	$(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -DR14_SILICON -pthread -o $@ $(RX_R14_SRCS) \
		src/runtime/rx_resident_gpu.c src/omega_blackwell_codegen.c \
		src/omega_blackwell_encoder.c src/omega_blackwell_qmd.c \
		src/omega_blackwell_matmul.c $(PHYSICS_DIR)/m16/m16_native.c \
		$(PHYSICS_DIR)/nvrm/nvrm.c $(AIENOS_CAP_LIB) -ldl -lm

test-r14-host: $(RX_R14_HOST)
	./$(RX_R14_HOST)

test-r14-silicon: $(RX_R14_SILICON)
	./$(RX_R14_SILICON)

# R15: instrumentation checks (host). Every counter the R15 harness reduces
# is checked against a case whose true value is known in advance.
RX_R15_INSTR_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/runtime/rx_generation.c src/omega_om_units.c src/omega_evidence.c \
	src/runtime/rx_seq_reference.c tests/runtime/rx_r15_instr.c
RX_R15_INSTR = $(OUT_DIR)/rx_r15_instr_test

$(RX_R15_INSTR): $(RX_R15_INSTR_SRCS) src/runtime/rx_world.h src/runtime/rx_generation.h \
	src/runtime/rx_caproot.h src/runtime/rx_seq_reference.h | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_R15_INSTR_SRCS)

test-r15-instr: $(RX_R15_INSTR)
	./$(RX_R15_INSTR)

# R15: SEQ semantic parity gate (spec §16 C1 item 9). The R13 body is built
# by tests/runtime/rx_r15_rig.c for RES-1 and for the sequential reference.
RX_R15_RIG_SRCS = $(filter-out tests/runtime/rx_r13_living.c src/runtime/rx_operator.c,$(RX_R13_SRCS)) \
	src/runtime/rx_seq_reference.c tests/runtime/rx_r15_rig.c
RX_R15_RIG_HDRS = src/runtime/rx_living.h src/runtime/rx_seq_reference.h \
	src/runtime/rx_world.h tests/runtime/rx_r15_rig.h
RX_R15_GPU_SRCS = src/runtime/rx_resident_gpu.c src/omega_blackwell_codegen.c \
	src/omega_blackwell_encoder.c src/omega_blackwell_qmd.c \
	src/omega_blackwell_matmul.c $(PHYSICS_DIR)/m16/m16_native.c $(PHYSICS_DIR)/nvrm/nvrm.c
RX_R15_PARITY_HOST = $(OUT_DIR)/rx_r15_parity_host
RX_R15_PARITY_SILICON = $(OUT_DIR)/rx_r15_parity_silicon

$(RX_R15_PARITY_HOST): $(RX_R15_RIG_SRCS) tests/runtime/rx_r15_parity.c $(RX_R15_RIG_HDRS) \
	$(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_R15_RIG_SRCS) tests/runtime/rx_r15_parity.c \
		$(AIENOS_CAP_LIB) -lm

$(RX_R15_PARITY_SILICON): $(RX_R15_RIG_SRCS) tests/runtime/rx_r15_parity.c $(RX_R15_RIG_HDRS) \
	$(RX_R15_GPU_SRCS) $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -DR15_SILICON -pthread -o $@ $(RX_R15_RIG_SRCS) \
		tests/runtime/rx_r15_parity.c $(RX_R15_GPU_SRCS) $(AIENOS_CAP_LIB) -ldl -lm

test-r15-parity-host: $(RX_R15_PARITY_HOST)
	./$(RX_R15_PARITY_HOST)

# R15 G7: production keeps its worker through a generation promotion; the R9
# store's physical work runs on the store's durable executor (host seat).
RX_R15_G7_HOST = $(OUT_DIR)/rx_r15_g7_host
$(RX_R15_G7_HOST): $(RX_R15_RIG_SRCS) tests/runtime/rx_r15_g7.c $(RX_R15_RIG_HDRS) \
	$(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_R15_RIG_SRCS) tests/runtime/rx_r15_g7.c \
		$(AIENOS_CAP_LIB) -lm
test-r15-g7-host: $(RX_R15_G7_HOST)
	./$(RX_R15_G7_HOST)

# R15 C2 sensor validation: bounded GB10 load through the resident seat.
R15_GPU_LOAD = $(OUT_DIR)/r15_gpu_load
R15_GPU_LOAD_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/runtime/rx_native_bind.c src/omega_om_units.c src/omega_evidence.c \
	tests/runtime/r15_gpu_load.c

$(R15_GPU_LOAD): $(R15_GPU_LOAD_SRCS) $(RX_R15_GPU_SRCS) src/runtime/rx_world.h \
	$(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(R15_GPU_LOAD_SRCS) $(RX_R15_GPU_SRCS) \
		$(AIENOS_CAP_LIB) -ldl -lm

r15-gpu-load: $(R15_GPU_LOAD)

test-r15-parity-silicon: $(RX_R15_PARITY_SILICON)
	./$(RX_R15_PARITY_SILICON)

# R15 harness (spec §4, §5, §12). Four binaries from the same sources and
# flags: production and the RES-1-NODIGEST measurement build (§3), host
# stand-in seat and GB10 silicon. tools/r15_qualify.sh drives them and
# tools/r15_reduce.c reduces their raw output.
RX_R15_PERF_SRCS = $(RX_R15_RIG_SRCS) tests/runtime/r15_measure.c tests/runtime/rx_r15_perf.c
RX_R15_PERF_HDRS = $(RX_R15_RIG_HDRS) tests/runtime/r15_measure.h
RX_R15_PERF_HOST = $(OUT_DIR)/rx_r15_perf_host
RX_R15_PERF_HOST_ND = $(OUT_DIR)/rx_r15_perf_host_nodigest
RX_R15_PERF_SILICON = $(OUT_DIR)/rx_r15_perf_silicon
RX_R15_PERF_SILICON_ND = $(OUT_DIR)/rx_r15_perf_silicon_nodigest
R15_REDUCE = $(OUT_DIR)/r15_reduce

$(RX_R15_PERF_HOST): $(RX_R15_PERF_SRCS) $(RX_R15_PERF_HDRS) $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_R15_PERF_SRCS) $(AIENOS_CAP_LIB) -ldl -lm

$(RX_R15_PERF_HOST_ND): $(RX_R15_PERF_SRCS) $(RX_R15_PERF_HDRS) $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -DRX_MEASURE_NO_CAUSAL_DIGEST -pthread -o $@ $(RX_R15_PERF_SRCS) \
		$(AIENOS_CAP_LIB) -ldl -lm

$(RX_R15_PERF_SILICON): $(RX_R15_PERF_SRCS) $(RX_R15_PERF_HDRS) $(RX_R15_GPU_SRCS) \
	$(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -DR15_SILICON -pthread -o $@ $(RX_R15_PERF_SRCS) $(RX_R15_GPU_SRCS) \
		$(AIENOS_CAP_LIB) -ldl -lm

$(RX_R15_PERF_SILICON_ND): $(RX_R15_PERF_SRCS) $(RX_R15_PERF_HDRS) $(RX_R15_GPU_SRCS) \
	$(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -DR15_SILICON -DRX_MEASURE_NO_CAUSAL_DIGEST -pthread -o $@ \
		$(RX_R15_PERF_SRCS) $(RX_R15_GPU_SRCS) $(AIENOS_CAP_LIB) -ldl -lm

$(R15_REDUCE): tools/r15_reduce.om seed/out/omc | $(OUT_DIR)
	seed/out/omc < tools/r15_reduce.om > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

r15-perf-host: $(RX_R15_PERF_HOST) $(RX_R15_PERF_HOST_ND) $(R15_REDUCE)
r15-perf-silicon: $(RX_R15_PERF_SILICON) $(RX_R15_PERF_SILICON_ND) $(R15_REDUCE)

# R15 receipt writer (spec §12/§13/§14): tools/r15_receipt.sh turns one run
# directory (summary.json + machine.json + SHA256SUMS) into
# evidence/R15/<sha256>.json. The host test runs it on attempt 1 (a FAIL).
r15-receipt:
	@test -n "$(RUN)" || { echo "usage: make r15-receipt RUN=evidence/R15/raw/<run-id> [CANDIDATE=<commit>] [RERUNS=<file>] [NOTES=<file>]"; exit 2; }
	tools/r15_receipt.sh $(RUN) evidence/R15 "$(CANDIDATE)" "$(RERUNS)" "$(NOTES)"

.PHONY: r15-receipt test-r15-receipt
test-r15-receipt:
	tests/r15_receipt_test.sh

# R15 preflight parser: counts only the CPU PMU cycles event (SMMU PMUs list
# "cycles" too on newer kernels). Host-only, fixtures, seconds.
.PHONY: test-r15-preflight
test-r15-preflight:
	sh tests/r15_preflight_test.sh
	sh tests/r15_energy_preflight_test.sh

# G15 diagnostics: sampler lateness / not-live-run record, its reducer report,
# and the readable-kernel-log Xid scan. Host-only, no chip.
.PHONY: test-r15-g15-diag
test-r15-g15-diag: $(R15_REDUCE) | $(OUT_DIR)
	$(CC) -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined -Itests/runtime -o $(OUT_DIR)/r15_seat_diag_test tests/runtime/r15_seat_diag_test.c
	$(OUT_DIR)/r15_seat_diag_test
	R15_REDUCE=$(R15_REDUCE) sh tests/r15_g15_diag_test.sh
	sh tests/seat_marker_uncached_test.sh

# R16-G2 code-search gate (spec/r16-orchestrator-retirement.md). Host-only pure OM-2 tool,
# seconds, no network. Scans the five repos (paths from R16_REPO_OMEGA,
# R16_REPO_SOVEREIGN_CORE, R16_REPO_AEGIS_RUNTIME, R16_REPO_AIENOS,
# R16_REPO_PHYSICS; defaults: this tree and ~/workspace/r16-survey/<repo>) and
# joins every loop-shaped site with spec/r16-orchestrator-retirement-map.md.
# Exit 0 only when every site is classified A-F, no omega class-A site is
# still under a production name, and all five repos were scanned.
R16_INVENTORY = $(OUT_DIR)/r16_loop_inventory
$(R16_INVENTORY): tools/r16_loop_inventory.om seed/out/omc | $(OUT_DIR)
	seed/out/omc < tools/r16_loop_inventory.om > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: r16-inventory test-r16-inventory
r16-inventory: $(R16_INVENTORY)
	$(R16_INVENTORY) --map spec/r16-orchestrator-retirement-map.md --json $(OUT_DIR)/r16-inventory.json

test-r16-inventory: $(R16_INVENTORY)
	sh tests/r16_inventory/run.sh $(R16_INVENTORY)

# Lane 32 follow-up: dry-mode self-test of tools/r16_qualify.sh (no chip, no build).
.PHONY: test-r16-qualify-selftest
test-r16-qualify-selftest:
	bash tests/r16_qualify/run.sh

# The aienos.lock source proof (tools/aienos_lock_source.sh) and the authority build rule
# that uses it: fixture repositories, host only.
.PHONY: test-aienos-lock-source
test-aienos-lock-source:
	bash tests/aienos_lock_source/run.sh

# R16-G3: the authoritative path with the legacy orchestrators unavailable.
# Link map, shared libraries, embedded names and an exec trace of the R13
# living system and the R14 recovery run, legacy programs stubbed on PATH.
# The R13 binary is the PRODUCTION program (Lane 32: no test piece, ARGUS
# linked); its source list includes the pinned ARGUS sources.
# Host mode uses the processor stand-in and cannot claim the gate. The silicon
# target starts the GB10 seat: run it only as part of the qualification
# ladder, detached, never under `timeout` and never killed.
R16_STAMP := $(shell date -u +%Y%m%dT%H%M%SZ)
.PHONY: test-r16-authpath test-r16-authpath-silicon
test-r16-authpath: $(RX_R13_HOST) $(RX_R14_HOST)
	sh tools/r16_authpath.sh host $(RX_R13_HOST) $(RX_R14_HOST) \
		$(OUT_DIR)/r16/authpath/host-$(R16_STAMP) $(RX_R13_SRCS) $(RX_PROD_ARGUS_SRCS) $(AIENOS_CAP_LIB)

test-r16-authpath-silicon: $(RX_R13_SILICON) $(RX_R14_SILICON)
	sh tools/r16_authpath.sh silicon $(RX_R13_SILICON) $(RX_R14_SILICON) \
		$(OUT_DIR)/r16/authpath/silicon-$(R16_STAMP) $(RX_R13_SRCS) $(RX_PROD_ARGUS_SRCS) \
		src/runtime/rx_resident_gpu.c src/omega_blackwell_codegen.c \
		src/omega_blackwell_encoder.c src/omega_blackwell_qmd.c \
		src/omega_blackwell_matmul.c $(PHYSICS_DIR)/m16/m16_native.c \
		$(PHYSICS_DIR)/nvrm/nvrm.c $(AIENOS_CAP_LIB)

# R16-G3 checks 1-3 only (sources, link map, shared libraries, embedded names)
# on the current living-system build, for CI runners. Nothing is executed, so
# neither the GB10 seat nor the Spark core classes are needed; the gate line
# stays NOT_RUN. The -silicon variant builds the silicon binaries and never
# runs them. The gate itself is still test-r16-authpath(-silicon).
.PHONY: test-r16-authpath-linkmap test-r16-authpath-linkmap-silicon
test-r16-authpath-linkmap: $(RX_R13_HOST) $(RX_R14_HOST)
	R16_G3_STATIC_ONLY=1 sh tools/r16_authpath.sh host $(RX_R13_HOST) $(RX_R14_HOST) \
		$(OUT_DIR)/r16/authpath/linkmap-host-$(R16_STAMP) $(RX_R13_SRCS) $(RX_PROD_ARGUS_SRCS) $(AIENOS_CAP_LIB)

test-r16-authpath-linkmap-silicon: $(RX_R13_SILICON) $(RX_R14_SILICON)
	R16_G3_STATIC_ONLY=1 sh tools/r16_authpath.sh silicon $(RX_R13_SILICON) $(RX_R14_SILICON) \
		$(OUT_DIR)/r16/authpath/linkmap-silicon-$(R16_STAMP) $(RX_R13_SRCS) $(RX_PROD_ARGUS_SRCS) \
		src/runtime/rx_resident_gpu.c src/omega_blackwell_codegen.c \
		src/omega_blackwell_encoder.c src/omega_blackwell_qmd.c \
		src/omega_blackwell_matmul.c $(PHYSICS_DIR)/m16/m16_native.c \
		$(PHYSICS_DIR)/nvrm/nvrm.c $(AIENOS_CAP_LIB)

# R16-G4: legacy paths cannot bypass authority. The R13 body (R15 rig, RES-4,
# host seat) is started; a legacy context tries six acts and each must be
# refused with no change to authoritative state. Host only; no chip.
RX_R16_NEGATIVE = $(OUT_DIR)/rx_r16_negative
$(RX_R16_NEGATIVE): $(RX_R15_RIG_SRCS) tests/runtime/rx_r16_negative.c $(RX_R15_RIG_HDRS) \
	$(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_R15_RIG_SRCS) tests/runtime/rx_r16_negative.c \
		$(AIENOS_CAP_LIB) -lm

.PHONY: test-r16-negative test-r16-negative-mutants
test-r16-negative: $(RX_R16_NEGATIVE)
	./$(RX_R16_NEGATIVE)

# "Removing any one guard turns the test red": rebuilds the G4 test against
# scratch copies with one guard removed at a time; each must FAIL. Minutes.
test-r16-negative-mutants: $(RX_R16_NEGATIVE) $(AIENOS_CAP_LIB)
	R16_CAP_LIB="$(AIENOS_CAP_LIB)" sh tests/r16_negative/mutate.sh "$(CC)" "$(CFLAGS)" "$(AIENOS_R7_DIR)" \
		$(RX_R15_RIG_SRCS) tests/runtime/rx_r16_negative.c

# R16-G5 API/build surface: legacy modes only under explicit names, the SEQ
# loop only in rx_seq_reference.*, no legacy default mode, production entry
# point documented (docs/r16-production-entry-point.md). Host only, seconds.
.PHONY: test-r16-surface
test-r16-surface: $(TARGET)
	sh tests/r16_surface/run.sh ./$(TARGET)


# OMEGA_ACTION_GRAPH_IR: goals compile to typed action graphs that run as
# resident reactions by readiness alone. rx_graph.o is built alone first and
# must not reference any Aienux admin operation: compilation can find that
# authority is missing, never create it.
RX_GRAPH_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/runtime/rx_native_bind.c src/runtime/rx_aegis.c src/omega_om_units.c src/omega_evidence.c \
	src/omega_core.c src/omega_canonical.c tests/runtime/rx_action_graph.c
RX_GRAPH_TEST = $(OUT_DIR)/rx_action_graph_test
RX_GRAPH_OBJ = $(OUT_DIR)/rx_graph.o

$(RX_GRAPH_OBJ): src/runtime/rx_graph.c src/runtime/rx_graph.h src/runtime/rx_world.h \
	src/runtime/rx_aegis.h | $(OUT_DIR)
	$(CC) $(CFLAGS) -c -o $@ src/runtime/rx_graph.c
	@if nm -u $@ | grep -E 'aienos_cap_|rx_caproot_mint|rx_caproot_revoke' ; then \
		echo "rx_graph.o references an authority admin operation; compilation must not mint"; \
		rm -f $@; exit 1; fi

$(RX_GRAPH_TEST): $(RX_GRAPH_SRCS) $(RX_GRAPH_OBJ) src/runtime/rx_caproot.h \
	src/runtime/aienos_cap.h $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_GRAPH_SRCS) $(RX_GRAPH_OBJ) $(AIENOS_CAP_LIB) -lm

test-action-graph: $(RX_GRAPH_TEST)
	./$(RX_GRAPH_TEST)

# OMEGA_CAPABILITY_QUERY: AIEN states a CapabilityNeed; Omega compiles it into
# probes of the capability sources and returns a bounded list of candidates
# ranked on explicit dimensions. rx_capq.o is built alone first and must not
# reference any Aienux admin operation: a query can learn that authority is
# held or missing, never create it.
RX_CAPQ_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/runtime/rx_native_bind.c src/runtime/rx_aegis.c src/omega_om_units.c src/omega_evidence.c \
	src/omega_core.c src/omega_canonical.c src/runtime/aien_machine_id.c \
	tests/runtime/rx_capability_query.c
RX_CAPQ_TEST = $(OUT_DIR)/rx_capability_query_test
RX_CAPQ_OBJ = $(OUT_DIR)/rx_capq.o

$(RX_CAPQ_OBJ): src/runtime/rx_capq.c src/runtime/rx_capq.h src/runtime/rx_graph.h \
	src/runtime/rx_world.h src/runtime/aien_machine_id.h | $(OUT_DIR)
	$(CC) $(CFLAGS) -c -o $@ src/runtime/rx_capq.c
	@if nm -u $@ | grep -E 'aienos_cap_|rx_caproot_mint|rx_caproot_revoke' ; then \
		echo "rx_capq.o references an authority admin operation; a query must not mint"; \
		rm -f $@; exit 1; fi

$(RX_CAPQ_TEST): $(RX_CAPQ_SRCS) $(RX_CAPQ_OBJ) $(RX_GRAPH_OBJ) src/runtime/rx_caproot.h \
	src/runtime/aienos_cap.h $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_CAPQ_SRCS) $(RX_CAPQ_OBJ) $(RX_GRAPH_OBJ) \
		$(AIENOS_CAP_LIB) -lm

test-capability-query: $(RX_CAPQ_TEST)
	./$(RX_CAPQ_TEST)

# M20 canonical Capability Graph and Skill Router: rx_capq promoted (keys,
# update/withdraw, canonical machine identity, wire form) plus rx_skillroute.
# Like rx_capq.o, rx_skillroute.o must not reference an authority admin
# operation: routing discovers, it never authorizes.
RX_CAPGRAPH_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/runtime/rx_native_bind.c src/runtime/rx_aegis.c src/omega_om_units.c src/omega_evidence.c \
	src/omega_core.c src/omega_canonical.c src/runtime/aien_machine_id.c \
	tests/runtime/rx_capability_graph.c
RX_CAPGRAPH_TEST = $(OUT_DIR)/rx_capability_graph_test
RX_SKILLROUTE_OBJ = $(OUT_DIR)/rx_skillroute.o

$(RX_SKILLROUTE_OBJ): src/runtime/rx_skillroute.c src/runtime/rx_skillroute.h \
	src/runtime/rx_capq.h src/runtime/aien_machine_id.h | $(OUT_DIR)
	$(CC) $(CFLAGS) -c -o $@ src/runtime/rx_skillroute.c
	@if nm -u $@ | grep -E 'aienos_cap_|rx_caproot_mint|rx_caproot_revoke' ; then \
		echo "rx_skillroute.o references an authority admin operation; routing must not mint"; \
		rm -f $@; exit 1; fi

$(RX_CAPGRAPH_TEST): $(RX_CAPGRAPH_SRCS) $(RX_SKILLROUTE_OBJ) $(RX_CAPQ_OBJ) $(RX_GRAPH_OBJ) \
	src/runtime/rx_caproot.h src/runtime/aienos_cap.h $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_CAPGRAPH_SRCS) $(RX_SKILLROUTE_OBJ) $(RX_CAPQ_OBJ) \
		$(RX_GRAPH_OBJ) $(AIENOS_CAP_LIB) -lm

test-capability-graph: $(RX_CAPGRAPH_TEST)
	./$(RX_CAPGRAPH_TEST)

# COMPOSITION-2 WP-D: Skill Router end to end (requirement -> graph -> Skill
# -> bound action-graph node -> World run) and each failure mode failing
# closed. Repeats the no-mint symbol check on the router object it links.
RX_SRCOMPOSE_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/runtime/rx_native_bind.c src/runtime/rx_aegis.c src/omega_om_units.c src/omega_evidence.c \
	src/omega_core.c src/omega_canonical.c src/runtime/aien_machine_id.c \
	tests/runtime/rx_skillroute_compose_test.c
RX_SRCOMPOSE_TEST = $(OUT_DIR)/rx_skillroute_compose_test

$(RX_SRCOMPOSE_TEST): $(RX_SRCOMPOSE_SRCS) $(RX_SKILLROUTE_OBJ) $(RX_CAPQ_OBJ) $(RX_GRAPH_OBJ) \
	src/runtime/rx_caproot.h src/runtime/aienos_cap.h $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_SRCOMPOSE_SRCS) $(RX_SKILLROUTE_OBJ) $(RX_CAPQ_OBJ) \
		$(RX_GRAPH_OBJ) $(AIENOS_CAP_LIB) -lm

test-skillroute-compose: $(RX_SRCOMPOSE_TEST)
	@if nm -u $(RX_SKILLROUTE_OBJ) | grep -E 'aienos_cap_|rx_caproot_mint|rx_caproot_revoke' ; then \
		echo "rx_skillroute.o references an authority admin operation"; exit 1; fi
	@echo "SKILLROUTE_NO_MINT_PASS"
	./$(RX_SRCOMPOSE_TEST)

# OMEGA_PLAN_REUSE: plan IR and verified plan cache. rx_plan.o must not
# reference any Aienux admin operation (the cache checks authority, never
# creates it); rx_plan_arrange.o (AIEN's planner) must only read the World.
RX_PLAN_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/runtime/rx_native_bind.c src/runtime/rx_aegis.c src/omega_om_units.c src/omega_evidence.c \
	src/omega_core.c src/omega_canonical.c tests/runtime/rx_plan_reuse.c
RX_PLAN_TEST = $(OUT_DIR)/rx_plan_reuse_test
RX_PLAN_OBJS = $(OUT_DIR)/rx_plan.o $(OUT_DIR)/rx_plan_arrange.o

$(OUT_DIR)/rx_plan.o: src/runtime/rx_plan.c src/runtime/rx_plan.h src/runtime/rx_graph.h \
	src/runtime/rx_world.h | $(OUT_DIR)
	$(CC) $(CFLAGS) -c -o $@ src/runtime/rx_plan.c
	@if nm -u $@ | grep -E 'aienos_cap_|rx_caproot_mint|rx_caproot_revoke' ; then \
		echo "rx_plan.o references an authority admin operation; the plan cache must not mint"; \
		rm -f $@; exit 1; fi

$(OUT_DIR)/rx_plan_arrange.o: src/runtime/rx_plan_arrange.c src/runtime/rx_plan_arrange.h \
	src/runtime/rx_plan.h | $(OUT_DIR)
	$(CC) $(CFLAGS) -c -o $@ src/runtime/rx_plan_arrange.c
	@if nm -u $@ | grep -E 'aienos_cap_|rx_caproot_|rx_world_publish|rx_graph_lower|rx_graph_start' ; then \
		echo "rx_plan_arrange.o must only read the World: the planner changes nothing"; \
		rm -f $@; exit 1; fi

$(RX_PLAN_TEST): $(RX_PLAN_SRCS) $(RX_PLAN_OBJS) $(RX_GRAPH_OBJ) src/runtime/rx_caproot.h \
	src/runtime/aienos_cap.h $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_PLAN_SRCS) $(RX_PLAN_OBJS) $(RX_GRAPH_OBJ) $(AIENOS_CAP_LIB) -lm

test-plan-reuse: $(RX_PLAN_TEST)
	./$(RX_PLAN_TEST)

# OMEGA_SEMANTIC_COMMUNICATION: branches and workers receive the semantic
# projection their InformationNeed selects, then only deltas, not full state.
# rx_semcomm.o is built alone first. It enforces capability boundaries, so it
# must not reference any authority admin operation, and it only reads the
# World, so it must not reference a World write either.
RX_SEMCOMM_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/runtime/rx_native_bind.c src/omega_om_units.c src/omega_evidence.c \
	src/omega_core.c src/omega_canonical.c tests/runtime/rx_semantic_comm.c
RX_SEMCOMM_TEST = $(OUT_DIR)/rx_semantic_comm_test
RX_SEMCOMM_OBJ = $(OUT_DIR)/rx_semcomm.o

$(RX_SEMCOMM_OBJ): src/runtime/rx_semcomm.c src/runtime/rx_semcomm.h src/runtime/rx_world.h | $(OUT_DIR)
	$(CC) $(CFLAGS) -c -o $@ src/runtime/rx_semcomm.c
	@if nm -u $@ | grep -E 'aienos_cap_|rx_caproot_mint|rx_caproot_revoke|rx_world_publish|rx_world_create|rx_world_retire|rx_world_add_reaction' ; then \
		echo "rx_semcomm.o references an authority admin operation or a World write; projection must only read"; \
		rm -f $@; exit 1; fi

$(RX_SEMCOMM_TEST): $(RX_SEMCOMM_SRCS) $(RX_SEMCOMM_OBJ) src/runtime/rx_caproot.h \
	src/runtime/aienos_cap.h $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_SEMCOMM_SRCS) $(RX_SEMCOMM_OBJ) $(AIENOS_CAP_LIB) -lm

test-semantic-comm: $(RX_SEMCOMM_TEST)
	./$(RX_SEMCOMM_TEST)

# OMEGA_COGNITIVE_ROUTING: each cognitive step goes to the cheapest
# realization the evidence says meets it, escalating only on insufficient
# verification or calibrated confidence. rx_route.o is built alone first and
# must not reference promotion or any Aienux admin operation: routing profiles
# change only through a promoted generation.
RX_ROUTE_SRCS = src/runtime/rx_generation.c src/omega_om_units.c src/omega_evidence.c \
	tests/runtime/rx_cog_engines.c tests/runtime/rx_cognitive_routing.c
RX_ROUTE_TEST = $(OUT_DIR)/rx_cognitive_routing_test
RX_ROUTE_OBJ = $(OUT_DIR)/rx_route.o

$(RX_ROUTE_OBJ): src/runtime/rx_route.c src/runtime/rx_route.h src/runtime/rx_generation.h | $(OUT_DIR)
	$(CC) $(CFLAGS) -c -o $@ src/runtime/rx_route.c
	@if nm -u $@ | grep -E 'rx_gen_promote|aienos_cap_|rx_caproot_mint|rx_caproot_revoke' ; then \
		echo "rx_route.o references promotion or an authority admin operation"; \
		rm -f $@; exit 1; fi

$(RX_ROUTE_TEST): $(RX_ROUTE_SRCS) $(RX_ROUTE_OBJ) tests/runtime/rx_cog_engines.h \
	src/runtime/aienos_cap.h $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -Itests -o $@ $(RX_ROUTE_SRCS) $(RX_ROUTE_OBJ) $(AIENOS_CAP_LIB) -lm

test-cognitive-routing: $(RX_ROUTE_TEST)
	./$(RX_ROUTE_TEST)

# OMEGA_EMPIRICAL_OPTIMIZER: realization choice from a learned, calibrated cost
# model. rx_costmodel.o is built alone first and must not reference the
# generation store, any authority operation, or anything that maps or runs
# code: the model is a calculator; durability comes only through promotion.
.PHONY: test-costmodel test-empirical
RX_CM_OBJ = $(OUT_DIR)/rx_costmodel.o

$(RX_CM_OBJ): src/runtime/rx_costmodel.c src/runtime/rx_costmodel.h | $(OUT_DIR)
	$(CC) $(CFLAGS) -c -o $@ src/runtime/rx_costmodel.c
	@if nm -u $@ | grep -E 'rx_gen_|aienos_cap_|rx_caproot_|rx_capadmin_|rx_world_|mmap|mprotect|fork|exec|dlopen|system' ; then \
		echo "rx_costmodel.o references an operation a cost model must not have"; \
		rm -f $@; exit 1; fi

# Pure seeded OM-2 cost model unit test: synthetic measurements; fit, calibration, decisions, blob.
RX_CM_UNIT = $(OUT_DIR)/rx_costmodel_unit
$(RX_CM_UNIT): $(RT_OM_CM_SRCS) $(RT_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT_OM_CM_SRCS) ) | $(RT_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

test-costmodel: $(RX_CM_UNIT)
	./$(RX_CM_UNIT)
	@set -eu; dir=$(OUT_DIR)/costmodel-mutant; rm -rf $$dir; mkdir -p $$dir; \
	  sed '/CM704:refuse-unsupported-op/{N;N;s/ret RX_CM_CELL_NONE/op = sub RX_CM_OPS 1/;}' \
	    src/runtime/rx_costmodel.om > $$dir/rx_costmodel.om; \
	  if cmp -s src/runtime/rx_costmodel.om $$dir/rx_costmodel.om; then \
	    echo "mutant restore-op-clamp: sed changed nothing"; exit 1; fi; \
	  ( echo om2; cat seed/ng/sha256.om $$dir/rx_costmodel.om tests/runtime/rx_costmodel_unit.om ) \
	    | $(RT_OM_OMC) > $$dir/unit && chmod +x $$dir/unit; \
	  rc=0; $$dir/unit refuse > $$dir/out.txt 2> $$dir/err.txt || rc=$$?; \
	  if [ $$rc -eq 0 ] || ! grep -q unsupported-op-not-aliased-to-matvec $$dir/err.txt; then \
	    echo "mutant restore-op-clamp was not killed by unsupported-op-not-aliased-to-matvec (exit $$rc)"; \
	    cat $$dir/err.txt; exit 1; fi; \
	  echo "mutant restore-op-clamp: killed by unsupported-op-not-aliased-to-matvec (exit $$rc)"

# Offline resource-DAG evaluator, imported verbatim from closed PR #590
# (commit 3bd56731). Host arithmetic on the numbers written in the fixtures.
# Not a validated cost model and not a hardware measurement.
# The seeded SHA-256 unit is AArch64 machine code; other hosts link
# tests/dagsim/sha256_host.c, which aborts if a blob digest is requested.
# dagsim.o keeps the #590 (3bd56731) nm guard: no generation store, authority,
# world, or a call that maps or runs code.
.PHONY: test-dagsim
DS_LIB = tools/dagsim/dagsim.om
DS_UNIT = $(OUT_DIR)/dagsim_unit
DS_CLI = $(OUT_DIR)/dagsim

$(DS_UNIT): $(DS_LIB) tests/dagsim/dagsim_unit.om seed/out/omc | $(OUT_DIR)
	cat $(DS_LIB) tests/dagsim/dagsim_unit.om | seed/out/omc > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(DS_CLI): $(DS_LIB) tools/dagsim/dagsim_cli.om seed/out/omc | $(OUT_DIR)
	cat $(DS_LIB) tools/dagsim/dagsim_cli.om | seed/out/omc > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

ifeq ($(shell uname -s)-$(shell uname -m),Linux-aarch64)
test-dagsim: $(DS_UNIT) $(DS_CLI)
	./$(DS_UNIT)
	sh tests/dagsim/run_cli.sh $(DS_CLI) $(OUT_DIR)/dagsim-cli-out
	OMC="$(CURDIR)/seed/out/omc" sh tests/dagsim/mutant_lifetime.sh
	OMC="$(CURDIR)/seed/out/omc" sh tests/dagsim/mutant_predict.sh
else
test-dagsim:
	@echo "test-dagsim: NOT_RUN (requires Linux aarch64 for seed/out/omc)"
endif

# AArch64 hosts: the gate. Real realizations, training, promotion through the
# R9 barrier on the native authority, held-out workloads.
RX_EMP_SRCS = src/runtime/rx_generation.c src/omega_om_units.c src/omega_evidence.c \
	src/omega_canonical.c src/omega_validate.c src/omega_core.c src/omega_codec.c \
	src/aarch64_encoder.c src/aarch64_decoder.c src/omega_realize.c src/omega_realize_synth.c src/omega_program.c \
	src/omega_machine.c src/omega_exec.c src/omega_verify.c src/omega_matvec.c src/omega_matvec_quad.c \
	tests/runtime/rx_empirical_optimizer.c
RX_EMP_TEST = $(OUT_DIR)/rx_empirical_optimizer_test

$(RX_EMP_TEST): $(RX_EMP_SRCS) $(RX_CM_OBJ) src/runtime/rx_generation.h src/runtime/aienos_cap.h \
	$(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_EMP_SRCS) $(RX_CM_OBJ) $(AIENOS_CAP_LIB) -lm

test-empirical: $(RX_EMP_TEST)
	./$(RX_EMP_TEST)

# OMEGA_WORKFLOW_FUSION: repeated verified action-graph fragments become
# MetaSkills; only a verified, measured, canaried, promoted (R9 barrier) and
# published one replaces the steps. rx_fusion.o, like rx_graph.o, must not
# reference any Aienux admin operation.
.PHONY: test-workflow-fusion
RX_FUSION_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/runtime/rx_native_bind.c src/runtime/rx_aegis.c src/runtime/rx_generation.c src/omega_om_units.c \
	src/omega_evidence.c src/omega_core.c src/omega_canonical.c tests/runtime/rx_workflow_fusion.c
RX_FUSION_TEST = $(OUT_DIR)/rx_workflow_fusion_test
RX_FUSION_OBJ = $(OUT_DIR)/rx_fusion.o

$(RX_FUSION_OBJ): src/runtime/rx_fusion.c src/runtime/rx_fusion.h src/runtime/rx_graph.h \
	src/runtime/rx_generation.h src/runtime/rx_world.h | $(OUT_DIR)
	$(CC) $(CFLAGS) -c -o $@ src/runtime/rx_fusion.c
	@if nm -u $@ | grep -E 'aienos_cap_|rx_caproot_mint|rx_caproot_revoke' ; then \
		echo "rx_fusion.o references an authority admin operation; fusion must not mint"; \
		rm -f $@; exit 1; fi

$(RX_FUSION_TEST): $(RX_FUSION_SRCS) $(RX_FUSION_OBJ) $(RX_GRAPH_OBJ) src/runtime/rx_caproot.h \
	src/runtime/aienos_cap.h $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_FUSION_SRCS) $(RX_FUSION_OBJ) $(RX_GRAPH_OBJ) \
		$(AIENOS_CAP_LIB) -lm

test-workflow-fusion: $(RX_FUSION_TEST)
	./$(RX_FUSION_TEST)

# OMEGA_TYPED_RESULT_CONSTRAINTS: structured results of cognition are checked
# against typed contracts; the publish gate is the only writer of what is
# published. rx_contract.o is built alone first and must not reference any
# Aienux admin operation: a contract can find that authority is missing, never
# create it.
RX_TYPED_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/runtime/rx_native_bind.c src/runtime/rx_aegis.c src/omega_om_units.c src/omega_evidence.c \
	src/omega_core.c src/omega_canonical.c tests/runtime/rx_typed_results.c
RX_TYPED_TEST = $(OUT_DIR)/rx_typed_results_test
RX_CONTRACT_OBJ = $(OUT_DIR)/rx_contract.o
TYPED_RESULTS_N ?= 400

$(RX_CONTRACT_OBJ): src/runtime/rx_contract.c src/runtime/rx_contract.h src/runtime/rx_graph.h \
	src/runtime/rx_world.h src/runtime/rx_aien.h | $(OUT_DIR)
	$(CC) $(CFLAGS) -c -o $@ src/runtime/rx_contract.c
	@if nm -u $@ | grep -E 'aienos_cap_|rx_caproot_mint|rx_caproot_revoke' ; then \
		echo "rx_contract.o references an authority admin operation; a contract must not mint"; \
		rm -f $@; exit 1; fi

$(RX_TYPED_TEST): $(RX_TYPED_SRCS) $(RX_CONTRACT_OBJ) $(RX_GRAPH_OBJ) src/runtime/rx_caproot.h \
	src/runtime/aienos_cap.h $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_TYPED_SRCS) $(RX_CONTRACT_OBJ) $(RX_GRAPH_OBJ) \
		$(AIENOS_CAP_LIB) -lm

.PHONY: test-typed-results
test-typed-results: $(RX_TYPED_TEST)
	./$(RX_TYPED_TEST) $(TYPED_RESULTS_N)

# ---- ARGUS producer (feat/argus-producer, lanes H/H2 of ARGUS-0) ---------
# The runtime feeds ARGUS (src/runtime/rx_argus.{c,h}, ABI v1.1: per-thread
# rings, use tables flushed as CAPABILITY_USE_SUMMARY, full events only on
# transitions). Default builds are unchanged (RX_ARGUS undefined = 0: the
# hooks compile to nothing). This block builds the AEGIS/promotion suites with
# RX_ARGUS=$(RX_ARGUS) against ARGUS pinned by argus.lock, extracted with
# `git archive` from ARGUS_REPO (never built in place). ARGUS's sha256.c is
# Omega's src/omega_om_units.c copied unchanged; Omega's is linked, not both.
#
# Grant source (ARGUS_AUTH):
#   observer (default) the authority announces its own mints/revokes
#            (aienos_cap_set_observer, aienos 12add16, native in the authority
#            pinned by aienos.lock, d39dd5b); the observer is installed by a link
#            wrap of aienos_cap_start, which also announces the office (cap 0).
#   aegis    GRANTED/REVOKED only where rx_aegis mints/revokes (harness mints
#            are unseen and show up as FORGED).
# Every ARGUS target links the aienos.lock authority, $(AIENOS_CAP_LIB), the
# same library as the default targets (with no observer set it
# costs one NULL check per admin operation), RX_ARGUS=0 included.
ARGUS_REPO ?= ../aienos-argus
# The lock is code-adjacent input: parse it as data and expose only validated
# lowercase commit text to recipes.  The second field is derived in the same
# parser so no lock content is ever interpolated into another shell command.
# Pin: aien-dev/aienux native/argus (ARGUS-0, ABI v1.1), feat/argus-0 integrator
# round 3. argus_abi.h is byte-identical at 398cfb9, 03b9f06, be2814d and
# b375dca. Branch head a64bc55 differs from b375dca in native/argus only by docs.
override ARGUS_LOCK_FIELDS := $(shell LC_ALL=C awk 'NR == 1 && length($$0) == 40 && $$0 ~ /^[0-9a-f]+$$/ { commit = $$0; next } { invalid = 1 } END { if (!invalid && NR == 1) printf "%s %s\n", commit, substr(commit, 1, 7); else exit 1 }' argus.lock 2>/dev/null)
ifneq ($(words $(ARGUS_LOCK_FIELDS)),2)
$(error argus.lock must contain exactly one lowercase 40-hex commit)
endif
override ARGUS_COMMIT := $(word 1,$(ARGUS_LOCK_FIELDS))
override ARGUS_SHORT := $(word 2,$(ARGUS_LOCK_FIELDS))
ARGUS_SRC = $(OUT_DIR)/argus-src/$(ARGUS_SHORT)/native/argus
ARGUS_STAMP = $(OUT_DIR)/argus-src/$(ARGUS_SHORT)/.extracted
ARGUS_LIB_SRCS = $(addprefix $(ARGUS_SRC)/,argus_event.c argus_ring.c argus_core.c argus_detect.c)
RX_ARGUS ?= 2
ARGUS_AUTH ?= observer
ARGUS_CAP_LIB = $(AIENOS_CAP_LIB)
comma := ,
ARGUS_AUTH_FLAGS = $(if $(filter observer,$(ARGUS_AUTH)),-DRX_ARGUS_AUTHORITY_OBSERVER -Wl$(comma)--wrap=aienos_cap_start,)
ARGUS_VARIANT = $(if $(filter observer,$(ARGUS_AUTH)),,-$(ARGUS_AUTH))
ARGUS_OUT = $(OUT_DIR)/argus$(RX_ARGUS)$(ARGUS_VARIANT)
ARGUS_CFLAGS = $(CFLAGS) -DRX_ARGUS=$(RX_ARGUS) -I$(ARGUS_SRC)
ARGUS_STREAMS ?= $(HOME)/workspace/argus-runtime-streams
ARGUS_RUN_ID = $(shell git rev-parse --short HEAD 2>/dev/null)-argus$(ARGUS_SHORT)

.PHONY: check-argus-lock test-argus-lock
check-argus-lock:
	@:

test-argus-lock:
	bash tests/argus_lock_validation.sh

# aienos.lock is parsed at the top of this Makefile; this prints the parsed commit
# (hostile shapes: tests/aienos_lock_source/run.sh section 4).
.PHONY: check-aienos-lock
check-aienos-lock:
	@printf '%s\n' '$(AIENOS_LOCK)'

$(ARGUS_STAMP):
	mkdir -p "$(OUT_DIR)/argus-src/$(ARGUS_SHORT)"
	git -C "$(ARGUS_REPO)" archive "$(ARGUS_COMMIT)" -- native/argus | tar -x -C "$(OUT_DIR)/argus-src/$(ARGUS_SHORT)"
	touch "$@"

$(ARGUS_LIB_SRCS): $(ARGUS_STAMP)

# RX_ARGUS=0 links no ARGUS code at all.
ARGUS_RX = $(if $(filter 0,$(RX_ARGUS)),,src/runtime/rx_argus.c $(ARGUS_LIB_SRCS))
ARGUS_LINK_FLAGS = $(if $(filter 0,$(RX_ARGUS)),,$(ARGUS_AUTH_FLAGS))

# ---- Lane 32: the PRODUCTION R13 program, ARGUS linked ----------------------
# Built without AIEN_TEST_BUILD (RX_PROD_REFUSE_TEST) and with ARGUS pinned by
# argus.lock, the way the ARGUS suites build it, in the mode the ARGUS-1
# decisions intend: observe and record. RX_ARGUS=2 (consumer thread ingesting
# into argus_core), authority observer (the authority announces its own
# mints/revokes through the aienos_cap_start link wrap). ARGUS holds no
# capability and the pinned ARGUS has no response path, so it never blocks a
# request and never expands its own authority. These flags are fixed here, not
# taken from the overridable RX_ARGUS/ARGUS_AUTH. The program refuses to run
# unobserved (rx_r13_living.c argus_check_start).
RX_PROD_ARGUS_FLAGS = -DRX_ARGUS=2 -DRX_ARGUS_AUTHORITY_OBSERVER -I$(ARGUS_SRC) \
	-Wl$(comma)--wrap=aienos_cap_start
RX_PROD_ARGUS_SRCS = src/runtime/rx_argus.c $(ARGUS_LIB_SRCS)

$(RX_R13_HOST): $(RX_R13_SRCS) src/runtime/rx_living.h src/runtime/rx_argus.h $(RX_COMPOSE_LIVING_CHECKS) \
	$(ARGUS_STAMP) $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(RX_PROD_REFUSE_TEST)
	$(CC) $(CFLAGS) $(RX_PROD_ARGUS_FLAGS) -pthread -o $@ $(RX_R13_SRCS) $(RX_PROD_ARGUS_SRCS) \
		$(AIENOS_CAP_LIB) -lm

# G1: the R13 living body journals one episode into Cortex (CxStore). Same
# production recipe as test-r13-host; the program is the R13 rig plus tests/runtime/rx_r13_cortex_episode.c.
RX_R13_CORTEX = $(OUT_DIR)/rx_r13_cortex_episode
RX_R13_CORTEX_SRCS = $(filter-out tests/runtime/rx_r13_living.c,$(RX_R13_SRCS)) tests/runtime/rx_r13_cortex_episode.c
$(RX_R13_CORTEX): $(RX_R13_CORTEX_SRCS) tests/runtime/rx_r13_living.c src/runtime/rx_living.h src/runtime/rx_argus.h \
	$(RX_COMPOSE_LIVING_CHECKS) $(ARGUS_STAMP) $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(RX_PROD_REFUSE_TEST)
	$(CC) $(CFLAGS) $(RX_PROD_ARGUS_FLAGS) -pthread -o $@ $(RX_R13_CORTEX_SRCS) $(RX_PROD_ARGUS_SRCS) \
		$(AIENOS_CAP_LIB) -lm

test-r13-cortex-episode: $(RX_R13_CORTEX)
	./$(RX_R13_CORTEX)

# ADAPTIVE-M4: bounded resource regulation (src/runtime/rx_regulate.c) on the
# R11 host recipe. The regulator closes a loop on the World's admission budget
# inside a fixed envelope; the test measures deferrals per burst as the objective.
RX_REGULATE_TEST = $(OUT_DIR)/rx_regulate_test
RX_REGULATE_SRCS = $(filter-out tests/runtime/rx_r11_aien.c,$(RX_R11_SRCS)) \
	src/runtime/rx_regulate.c tests/runtime/rx_regulate_test.c
$(RX_REGULATE_TEST): $(RX_REGULATE_SRCS) src/runtime/rx_regulate.h src/runtime/rx_world.h \
		$(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_REGULATE_SRCS) $(AIENOS_CAP_LIB) -lm

.PHONY: test-regulate
test-regulate: $(RX_REGULATE_TEST)
	./$(RX_REGULATE_TEST)

$(RX_R13_SILICON): $(RX_R13_SRCS) $(RX_R13_SILICON_EXTRA) src/runtime/rx_living.h src/runtime/rx_argus.h \
	$(RX_COMPOSE_LIVING_CHECKS) $(ARGUS_STAMP) $(AIENOS_CAP_LIB) | $(OUT_DIR)
	$(RX_PROD_REFUSE_TEST)
	$(CC) $(CFLAGS) $(RX_PROD_ARGUS_FLAGS) -DR13_SILICON -pthread -o $@ $(RX_R13_SRCS) \
		$(RX_PROD_ARGUS_SRCS) $(RX_R13_SILICON_EXTRA) $(AIENOS_CAP_LIB) -ldl -lm

# Production hygiene (link map + strings + ARGUS present; host run of the
# ARGUS probe where the binary can run) and the negative build test: compiling
# the production program with any test piece must FAIL (tools/r16_prod_hygiene.sh).
.PHONY: test-prod-hygiene test-prod-hygiene-silicon test-prod-refuses-test-pieces
test-prod-hygiene: $(RX_R13_HOST)
	sh tools/r16_prod_hygiene.sh host $(RX_R13_HOST)

test-prod-hygiene-silicon: $(RX_R13_SILICON)
	sh tools/r16_prod_hygiene.sh silicon $(RX_R13_SILICON)

test-prod-refuses-test-pieces: $(ARGUS_STAMP) $(AIENOS_CAP_LIB) $(RX_R13_HOST)
	CC="$(CC)" CFLAGS="$(CFLAGS)" ARGUS_SRC="$(ARGUS_SRC)" OUT="$(OUT_DIR)/prod-refuses" MAKE="$(MAKE)" PROD_BIN="$(RX_R13_HOST)" \
		sh tools/r16_prod_refuses.sh

# R16 G6 operator control by execution (docs/r16-operator-control.md): the
# production program driven from outside through its operator entry point.
# Host: the production host binary (R12 processor stand-in). Silicon: the
# production GB10 binary on the resident seat, needs the quiet lock, never
# killed (no SIGKILL phase). The mutants rebuild the production host program
# from mutated copies; the test must fail against each.
RX_OPERATOR_CLI = $(OUT_DIR)/rx_operator
$(RX_OPERATOR_CLI): tools/rx_operator.om seed/out/omc | $(OUT_DIR)
	seed/out/omc < tools/rx_operator.om > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-r16-operator-host test-r16-operator-silicon test-r16-operator-mutants
test-r16-operator-host: $(RX_R13_HOST) $(RX_OPERATOR_CLI)
	bash tests/runtime/rx_operator_host.sh host $(RX_R13_HOST) $(RX_OPERATOR_CLI)

test-r16-operator-silicon: $(RX_R13_SILICON) $(RX_OPERATOR_CLI)
	bash tests/runtime/rx_operator_host.sh silicon $(RX_R13_SILICON) $(RX_OPERATOR_CLI)

.PHONY: test-r16-operator-mutants-evidence test-r13-first-failure test-window-lane-guard
test-r16-operator-mutants-evidence:
	bash tests/runtime/rx_operator_mutants_evidence_test.sh

# Builds the R13 host test build twice into a scratch OUT_DIR and runs it (host only, no GPU).
test-r13-first-failure:
	bash tests/runtime/rx_r13_first_failure_test.sh

test-window-lane-guard:
	bash tests/window_lane_guard_test.sh

test-r16-operator-mutants: $(RX_R13_HOST) $(RX_OPERATOR_CLI)
	CC="$(CC)" CFLAGS="$(CFLAGS)" RX_PROD_ARGUS_FLAGS="$(RX_PROD_ARGUS_FLAGS)" \
		RX_R13_SRCS="$(RX_R13_SRCS)" RX_PROD_ARGUS_SRCS="$(RX_PROD_ARGUS_SRCS)" \
		AIENOS_CAP_LIB="$(AIENOS_CAP_LIB)" bash tests/runtime/rx_operator_mutants.sh $(RX_OPERATOR_CLI)

ARGUS_R7 = $(ARGUS_OUT)/rx_r7_native_test
ARGUS_R8 = $(ARGUS_OUT)/rx_r8_aegis_test
ARGUS_R9 = $(ARGUS_OUT)/rx_r9_barrier_test
ARGUS_BENCH = $(ARGUS_OUT)/bench_rx_argus
ARGUS_BENCH_SRCS = src/runtime/rx_caproot.c src/runtime/rx_world.c src/runtime/rx_coherent.c \
	src/runtime/rx_native_bind.c src/runtime/rx_aegis.c src/omega_om_units.c tests/bench_rx_argus.c

$(ARGUS_OUT):
	mkdir -p $@

$(ARGUS_R7): $(RX_R7_SRCS) src/runtime/rx_argus.h $(ARGUS_RX) $(ARGUS_STAMP) $(ARGUS_CAP_LIB) | $(ARGUS_OUT)
	$(CC) $(ARGUS_CFLAGS) $(ARGUS_LINK_FLAGS) -pthread -o $@ $(RX_R7_SRCS) $(ARGUS_RX) $(ARGUS_CAP_LIB) -lm
$(ARGUS_R8): $(RX_R8_SRCS) src/runtime/rx_argus.h $(ARGUS_RX) $(ARGUS_STAMP) $(ARGUS_CAP_LIB) | $(ARGUS_OUT)
	$(CC) $(ARGUS_CFLAGS) $(ARGUS_LINK_FLAGS) -pthread -o $@ $(RX_R8_SRCS) $(ARGUS_RX) $(ARGUS_CAP_LIB) -lm
$(ARGUS_R9): $(RX_R9_SRCS) src/runtime/rx_argus.h $(ARGUS_RX) $(ARGUS_STAMP) $(ARGUS_CAP_LIB) | $(ARGUS_OUT)
	$(CC) $(ARGUS_CFLAGS) $(ARGUS_LINK_FLAGS) -pthread -o $@ $(RX_R9_SRCS) $(ARGUS_RX) $(ARGUS_CAP_LIB) -lm
# The bench mints directly and announces its one grant itself: no observer wrap.
$(ARGUS_BENCH): $(ARGUS_BENCH_SRCS) src/runtime/rx_argus.h $(ARGUS_RX) $(ARGUS_STAMP) $(ARGUS_CAP_LIB) | $(ARGUS_OUT)
	$(CC) $(ARGUS_CFLAGS) -pthread -o $@ $(ARGUS_BENCH_SRCS) $(ARGUS_RX) $(ARGUS_CAP_LIB) -lm

# ARGUS_RUNTIME_INTEGRATION: run each suite with the consumer ingesting into
# the real argus_core; keep the raw 128-byte stream (consumer ingest order)
# and a JSON summary: $(ARGUS_STREAMS)/<argus>-<suite>-v11.bin/.json
.PHONY: test-argus-runtime bench-rx-argus
test-argus-runtime: $(ARGUS_R7) $(ARGUS_R8) $(ARGUS_R9)
	mkdir -p $(ARGUS_STREAMS)
	@set -e; for s in r7:$(ARGUS_R7) r8:$(ARGUS_R8) r9:$(ARGUS_R9); do \
		n=$${s%%:*}; b=$${s#*:}; \
		echo "== ARGUS runtime integration $$n"; \
		RX_ARGUS_CONSUMER=ingest RX_ARGUS_RUN_ID=$(ARGUS_RUN_ID)-$$n RX_ARGUS_SUITE=$$n \
		RX_ARGUS_STREAM=$(ARGUS_STREAMS)/$(ARGUS_SHORT)-$$n$(ARGUS_VARIANT)-v11.bin \
		RX_ARGUS_SUMMARY=$(ARGUS_STREAMS)/$(ARGUS_SHORT)-$$n$(ARGUS_VARIANT)-v11.json ./$$b > $(ARGUS_OUT)/$$n.log 2>&1 \
		|| { tail -20 $(ARGUS_OUT)/$$n.log; exit 1; }; \
		tail -2 $(ARGUS_OUT)/$$n.log; \
	done

bench-rx-argus: $(ARGUS_BENCH)
	./$(ARGUS_BENCH)

ARGUS_REPLAY = $(RTBR_ARGUS_REPLAY_BIN)
.PHONY: argus-replay
argus-replay: $(ARGUS_REPLAY)

# ---------------------------------------------------------------------------
# OMEGA MIXED ALGEBRA (spec/mixed-algebra-reference.md): correctness-first CPU
# reference ("parity oracle") for balanced trits, Z3, packing and absmean
# quantization. Plain C11, no runtime or physics dependencies.
# test-algebra-asan reruns the same suite under address+undefined sanitizers.
.PHONY: test-algebra test-algebra-asan
OMA_BIND = $(OUT_DIR)/tests-algebra/native.o
$(OMA_BIND): src/omega_om_units.c src/omega_native.h src/omega_api_decl.h
	@mkdir -p $(dir $@)
	$(CC) $(OMA_CFLAGS) -Wno-pedantic -c $< -o $@

OMA_CFLAGS = -std=c11 -Wall -Wextra -Werror -pedantic -O2 -Isrc
OMA_OM_LIB = src/algebra/oma_lib.om
OMA_TEST = $(OUT_DIR)/tests-algebra/test_oma
OMA_FAILURE_TEST = $(OUT_DIR)/tests-algebra/test_oma_native_failure

$(OMA_TEST): $(OMA_OM_LIB) tests/algebra/test_oma.om seed/out/omc
	@mkdir -p $(dir $@)
	cat $(OMA_OM_LIB) tests/algebra/test_oma.om | seed/out/omc > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(OMA_FAILURE_TEST): $(OMA_OM_LIB) tests/algebra/test_oma_native_failure.om seed/out/omc
	@mkdir -p $(dir $@)
	cat $(OMA_OM_LIB) tests/algebra/test_oma_native_failure.om | seed/out/omc > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

test-algebra: $(OMA_TEST) $(OMA_FAILURE_TEST)
	./$(OMA_TEST)
	./$(OMA_FAILURE_TEST)

test-algebra-asan: $(OMA_TEST)
	./$(OMA_TEST)

# ---------------------------------------------------------------------------
# OMEGA MIXED ALGEBRA MA-2 (spec/mixed-algebra-ma2.md): one exact operation
# (ternary W x int8 x -> int32 y) with several verified realizations on the
# Grace CPU, a measured cost table and the MA-2 selector. The selector
# (oma_select) is RETIRED for new decisions (TURING K.6/K.7): it is kept only
# to reproduce ma2_select_receipt.json; new selections use src/turing
# turing_rank_min_cost and are recorded as turing.decision.v1.
# test-realize: bit-exact gate vs the naive oracle (plain and ASan+UBSan).
# bench-mixed-algebra: two benchmark runs on one pinned Cortex-X925 core,
# then the selector with its reproducibility check. Every run writes NEW
# files under evidence/MIXED_ALGEBRA/runs/$(MA2_RUN_ID)/ (default: UTC
# timestamp; an existing run directory is refused). Committed evidence
# (ma3_bench_run{1,2}.json, ma2_select_receipt.json) is never rewritten:
# check-mixed-algebra-evidence fails if a committed evidence/MIXED_ALGEBRA
# file is modified or deleted, and runs before and after the bench.
.PHONY: test-realize bench-mixed-algebra check-mixed-algebra-evidence
OMA_RZ_ARCH = -march=armv8.6-a+dotprod+i8mm+sve
OMA_RZ_CFLAGS = -std=c11 -Wall -Wextra -Werror -pedantic -O2 $(OMA_RZ_ARCH) -Isrc
OMA_RZ_SRCS = src/algebra/realize_common.c src/algebra/realize_binary.c \
	src/algebra/realize_bitplane.c src/algebra/realize_sparse.c \
	src/algebra/realize_rns.c src/algebra/realize_dense.c
OMA_RZ_HDRS = src/algebra/realize_common.h
OMA_SEL_OM = src/algebra/oma_select.om
OMA_RZ_TEST = $(OUT_DIR)/tests-algebra/test_realize
OMA_RZ_BENCH = $(OUT_DIR)/tests-algebra/bench_mixed_algebra
OMA_RZ_SELECT = $(OUT_DIR)/tests-algebra/bench_select
MA2_EVIDENCE = evidence/MIXED_ALGEBRA
MA2_RUN_ID ?= $(shell date -u +%Y%m%dT%H%M%SZ)
MA2_RUN_ID := $(MA2_RUN_ID)
MA2_RUN_DIR = $(MA2_EVIDENCE)/runs/$(MA2_RUN_ID)

$(OMA_RZ_TEST): $(OMA_OM_LIB) src/algebra/realize.om tests/algebra/test_realize.om seed/out/omc
	@mkdir -p $(dir $@)
	cat $(OMA_OM_LIB) src/algebra/realize.om tests/algebra/test_realize.om | seed/out/omc > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(OMA_RZ_BENCH): $(OMA_OM_LIB) $(OMA_SEL_OM) src/algebra/realize.om tests/algebra/bench_mixed_algebra.om seed/out/omc
	@mkdir -p $(dir $@)
	cat $(OMA_OM_LIB) $(OMA_SEL_OM) src/algebra/realize.om tests/algebra/bench_mixed_algebra.om | seed/out/omc > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(OMA_RZ_SELECT): $(OMA_OM_LIB) $(OMA_SEL_OM) tests/algebra/bench_select.om seed/out/omc
	@mkdir -p $(dir $@)
	cat $(OMA_OM_LIB) $(OMA_SEL_OM) tests/algebra/bench_select.om | seed/out/omc > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

test-realize: $(OMA_RZ_TEST)
	./$(OMA_RZ_TEST)

# Fails if any committed evidence/MIXED_ALGEBRA file is modified or deleted
# (staged or not). New, untracked files are allowed.
check-mixed-algebra-evidence:
	@changed="$$(git diff --name-status HEAD -- $(MA2_EVIDENCE))"; \
	if [ -n "$$changed" ]; then \
		echo "FAIL: committed mixed-algebra evidence would be modified:"; \
		echo "$$changed"; exit 1; \
	fi; \
	echo "check-mixed-algebra-evidence: PASS (committed evidence unchanged)"

bench-mixed-algebra: $(OMA_RZ_BENCH) $(OMA_RZ_SELECT)
	@$(MAKE) --no-print-directory check-mixed-algebra-evidence
	@if [ -e $(MA2_RUN_DIR) ]; then echo "FAIL: $(MA2_RUN_DIR) exists; choose a new MA2_RUN_ID"; exit 1; fi
	@mkdir -p $(MA2_RUN_DIR)
	OMA_BENCH_COMMIT=$$(git rev-parse HEAD) OMA_BENCH_DIRTY=$$(git status --porcelain -- src tests Makefile | grep -c .) \
		OMA_BENCH_BIN_SHA=$$(sha256sum $(OMA_RZ_BENCH) | cut -c1-64) \
		./$(OMA_RZ_BENCH) $(MA2_RUN_DIR)/ma2_bench_run1.json
	OMA_BENCH_COMMIT=$$(git rev-parse HEAD) OMA_BENCH_DIRTY=$$(git status --porcelain -- src tests Makefile | grep -c .) \
		OMA_BENCH_BIN_SHA=$$(sha256sum $(OMA_RZ_BENCH) | cut -c1-64) \
		./$(OMA_RZ_BENCH) $(MA2_RUN_DIR)/ma2_bench_run2.json
	./$(OMA_RZ_SELECT) $(MA2_RUN_DIR)/ma2_select_receipt.json \
		$(MA2_RUN_DIR)/ma2_bench_run1.json $(MA2_RUN_DIR)/ma2_bench_run2.json
	@$(MAKE) --no-print-directory check-mixed-algebra-evidence
	@echo "bench-mixed-algebra: new receipts in $(MA2_RUN_DIR)"

# ---------------------------------------------------------------------------
# OMEGA MIXED ALGEBRA, ADR 0019 MA-8 step 0 (spec/mixed-algebra-phase-twin.md):
# phase-domain Z3 digital twin. SIMULATED_DEVELOPMENT only: a software model
# of Z3 addition carried as tone phase, checked against oma_z3. No runtime,
# no selection, no digest. C11 + libm.
# test-phase-twin: full run -> $(OUT_DIR) receipt (never into evidence/);
#   quick run plain and under ASan+UBSan, receipts must be byte-identical;
#   if a committed receipt exists, the full run must reproduce it (all fields
#   except git_commit / tree_dirty / run_id / toolchain).
# phase-twin-receipt: from a clean committed tree only, copies the full
#   receipt to evidence/MIXED_ALGEBRA/phase_twin_receipt.<sha256>.json.
.PHONY: test-phase-twin phase-twin-receipt
PT_OUT = $(OUT_DIR)/tests-algebra
PT_TEST = $(PT_OUT)/test_phase_twin

$(PT_TEST): $(OMA_OM_LIB) src/algebra/phase_twin.om tests/algebra/test_phase_twin.om seed/out/omc
	@mkdir -p $(dir $@)
	cat $(OMA_OM_LIB) src/algebra/phase_twin.om tests/algebra/test_phase_twin.om | seed/out/omc > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

test-phase-twin: $(PT_TEST)
	./$(PT_TEST) $(PT_OUT)/phase_twin_receipt.json
	./$(PT_TEST) --quick $(PT_OUT)/phase_twin_quick_1.json
	./$(PT_TEST) --quick $(PT_OUT)/phase_twin_quick_2.json
	cmp $(PT_OUT)/phase_twin_quick_1.json $(PT_OUT)/phase_twin_quick_2.json
	@echo "test-phase-twin: quick receipts byte-identical across deterministic pure OM-2 runs"

phase-twin-receipt: test-phase-twin
	@test "$$(git status --porcelain -- src tests Makefile spec | grep -c .)" = 0 || \
		{ echo "phase-twin-receipt: tree not clean, refusing"; exit 1; }
	@mkdir -p evidence/MIXED_ALGEBRA
	@h=$$(sha256sum $(PT_OUT)/phase_twin_receipt.json | cut -c1-64); \
	cp $(PT_OUT)/phase_twin_receipt.json evidence/MIXED_ALGEBRA/phase_twin_receipt.$$h.json; \
	echo "phase-twin-receipt: evidence/MIXED_ALGEBRA/phase_twin_receipt.$$h.json"

# ---------------------------------------------------------------------------
# TURING Wave 1 (docs/turing/TURING_W0_PROPOSAL.md): Field v1 records (K.7) +
# control-arm selector, post hoc over evidence/MIXED_ALGEBRA receipts, in pure
# seeded OM-2 (src/turing/field.om, src/turing/select.om, tools/turing_field.om,
# tests/turing/test_turing.om). No C, no runtime, no timed runs.
.PHONY: test-turing turing-field
TURING_OMC ?= seed/out/omc
TURING_OM_SRCS = src/turing/field.om src/turing/select.om
TURING_TEST = $(OUT_DIR)/tests-turing/test_turing
TURING_TOOL = $(OUT_DIR)/tests-turing/turing-field

$(TURING_TEST): tests/turing/test_turing.om $(TURING_OM_SRCS) $(TURING_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed '/^om2$$/d' $(TURING_OM_SRCS) tests/turing/test_turing.om) | $(TURING_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TURING_TOOL): tools/turing_field.om $(TURING_OM_SRCS) $(TURING_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed '/^om2$$/d' $(TURING_OM_SRCS) tools/turing_field.om) | $(TURING_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

turing-field: $(TURING_TOOL)
	./$(TURING_TOOL)

test-turing: $(TURING_TEST) $(TURING_TOOL)
	./$(TURING_TEST)
	./$(TURING_TOOL) --spec-ids > $(OUT_DIR)/tests-turing/spec_ids_1.txt
	./$(TURING_TOOL) --spec-ids > $(OUT_DIR)/tests-turing/spec_ids_2.txt
	cmp $(OUT_DIR)/tests-turing/spec_ids_1.txt $(OUT_DIR)/tests-turing/spec_ids_2.txt
	./$(TURING_TOOL) > $(OUT_DIR)/tests-turing/turing_field.txt
	@echo "test-turing: pure OM-2 test_turing and turing-field pass; spec ids byte-identical"

# ---------------------------------------------------------------------------
# MIXED_ALGEBRA_DIGITAL_V1 closure gate (spec/mixed-algebra-digital-v1.md,
# pre-registered). test-ma-digital-bottom: realization-layer ⊥ coverage
# (plain + ASan/UBSan). gate-mixed-algebra-digital-v1: correctness leg, one
# bench-mixed-algebra run under ~/workspace/.spark-quiet (or reuse with
# MA_DV1_REUSE_RUN=<run id>), TURING Field v1 selection for the
# pre-registered queries, separate-process digest reproduction, and a
# digest-named wrapper receipt in evidence/MIXED_ALGEBRA/digital_v1/.
.PHONY: test-ma-digital-bottom gate-mixed-algebra-digital-v1
DV1_BOTTOM = $(OUT_DIR)/tests-algebra/test_ma_digital_bottom
DV1_GATE_BIN = $(OUT_DIR)/tests-algebra/ma_digital_v1_gate
DV1_GATE_BIN_ASAN = $(OUT_DIR)/tests-algebra/ma_digital_v1_gate_asan

$(DV1_BOTTOM): $(OMA_OM_LIB) src/algebra/realize.om tests/algebra/test_ma_digital_bottom.om seed/out/omc
	@mkdir -p $(dir $@)
	cat $(OMA_OM_LIB) src/algebra/realize.om tests/algebra/test_ma_digital_bottom.om | seed/out/omc > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(DV1_GATE_BIN): $(OMA_OM_LIB) $(OMA_SEL_OM) tests/algebra/ma_digital_v1_gate.om seed/out/omc
	@mkdir -p $(dir $@)
	cat $(OMA_OM_LIB) $(OMA_SEL_OM) tests/algebra/ma_digital_v1_gate.om | seed/out/omc > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(DV1_GATE_BIN_ASAN): $(DV1_GATE_BIN)
	cp $< $@

test-ma-digital-bottom: $(DV1_BOTTOM)
	./$(DV1_BOTTOM)

gate-mixed-algebra-digital-v1: $(DV1_GATE_BIN) $(DV1_GATE_BIN_ASAN) $(DV1_BOTTOM)
	DV1_GATE=./$(DV1_GATE_BIN) DV1_GATE_ASAN=./$(DV1_GATE_BIN_ASAN) MAKE="$(MAKE)" \
		sh tests/algebra/ma_digital_v1_gate.sh

# Content check (post-run addenda 2026-09-29): every digital_v1 wrapper
# re-hashes to its file name and every receipt it cites re-hashes to the
# digest recorded in the wrapper. Catches edits that were committed.
.PHONY: check-mixed-algebra-digital-v1-evidence
check-mixed-algebra-digital-v1-evidence:
	sh tests/algebra/ma_digital_v1_check_evidence.sh

# PATH-1 (spec/path-semantic-object.md section 15). Pure seeded OM-2 oracle
# and test harness; no runtime, physics, C or GPU links.
PATH1_TEST_BIN := $(OUT_DIR)/tests-path/test_path_identity
.PHONY: test-path
$(PATH1_TEST_BIN): src/path/rx_path.om tests/path/test_path_identity.om seed/out/omc
	mkdir -p $(dir $@)
	cat src/path/rx_path.om tests/path/test_path_identity.om | seed/out/omc > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

test-path: $(PATH1_TEST_BIN)
	sh tests/path/check_path_boundary.sh
	./$(PATH1_TEST_BIN)
	OMC="$(CURDIR)/seed/out/omc" sh tests/path/mutate.sh

# COMPOSITION-2: one World, one causal path (rx_compose). test-composition
# runs every fault point in process and as a crashed child, the OLD-or-NEW
# recovery, authority refusals and the Cortex record (WP-B, WP-C).
# test-composition-gate runs the 14-step gate in fresh directories; the
# receipt is written by tools/composition_gate.sh from a clean tree (WP-E).
RX_COMPOSE_SRCS = src/runtime/rx_compose.c src/runtime/rx_jspace.c src/runtime/rx_caproot.c \
	src/runtime/rx_world.c src/runtime/rx_coherent.c src/runtime/rx_native_bind.c \
	src/runtime/rx_aegis.c src/runtime/rx_cortex_record.c src/runtime/aien_machine_id.c \
	src/omega_om_units.c src/omega_evidence.c src/omega_core.c src/omega_canonical.c
RX_COMPOSE_DEPS = $(RX_COMPOSE_SRCS) $(OUT_DIR)/rx_cortex.o $(RX_SKILLROUTE_OBJ) $(RX_CAPQ_OBJ) \
	$(RX_GRAPH_OBJ) src/runtime/rx_compose.h tests/runtime/rx_compose_fixture.h \
	src/runtime/rx_world.h src/runtime/rx_jspace.h src/runtime/aienos_cap.h $(AIENOS_CAP_LIB)
RX_COMPOSE_LINK = $(OUT_DIR)/rx_cortex.o $(RX_SKILLROUTE_OBJ) $(RX_CAPQ_OBJ) $(RX_GRAPH_OBJ) \
	$(AIENOS_CAP_LIB) -lm
# Test build ($(AIEN_TEST_FLAGS), Lane 32): the composition fault points and
# rogue-candidate hook (rx_compose.h, RXC_TEST_HOOKS) exist only in the unit
# tests and the R13 test-build variant; the gate, the production program and
# every other build compile them out.
RX_COMPOSE_TEST = $(OUT_DIR)/rx_compose_test
RX_COMPOSE_GATE = $(OUT_DIR)/rx_composition_gate
# Attach hygiene (one per World, close waits for its own steps, inert
# reactions + table bound); its ASan build is test-composition-attach-asan.
RX_COMPOSE_ATTACH_TEST = $(OUT_DIR)/rx_compose_attach_test
RX_COMPOSE_ATTACH_ASAN = $(OUT_DIR)/rx_compose_attach_test_asan

$(RX_COMPOSE_TEST): $(RX_COMPOSE_DEPS) tests/runtime/rx_compose_test.c | $(OUT_DIR)
	$(CC) $(CFLAGS) $(AIEN_TEST_FLAGS) -pthread -o $@ $(RX_COMPOSE_SRCS) tests/runtime/rx_compose_test.c \
		$(RX_COMPOSE_LINK)

$(RX_COMPOSE_GATE): $(RX_COMPOSE_DEPS) tests/runtime/rx_composition_gate.c | $(OUT_DIR)
	$(CC) $(CFLAGS) -pthread -o $@ $(RX_COMPOSE_SRCS) tests/runtime/rx_composition_gate.c \
		$(RX_COMPOSE_LINK)

$(RX_COMPOSE_ATTACH_TEST): $(RX_COMPOSE_DEPS) tests/runtime/rx_compose_attach_test.c | $(OUT_DIR)
	$(CC) $(CFLAGS) $(AIEN_TEST_FLAGS) -pthread -o $@ $(RX_COMPOSE_SRCS) \
		tests/runtime/rx_compose_attach_test.c $(RX_COMPOSE_LINK)

$(RX_COMPOSE_ATTACH_ASAN): $(RX_COMPOSE_DEPS) tests/runtime/rx_compose_attach_test.c | $(OUT_DIR)
	$(CC) $(CFLAGS) -DROUNDS=200 -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=all $(AIEN_TEST_FLAGS) \
		-pthread -o $@ $(RX_COMPOSE_SRCS) tests/runtime/rx_compose_attach_test.c $(RX_COMPOSE_LINK)

test-composition: $(RX_COMPOSE_TEST) $(RX_COMPOSE_ATTACH_TEST)
	./$(RX_COMPOSE_TEST)
	./$(RX_COMPOSE_ATTACH_TEST)

test-composition-attach-asan: $(RX_COMPOSE_ATTACH_ASAN)
	./$(RX_COMPOSE_ATTACH_ASAN)

test-composition-gate: $(RX_COMPOSE_GATE)
	./$(RX_COMPOSE_GATE) "$$(git rev-parse HEAD)" $(OUT_DIR)/composition_gate_receipt.json

composition-gate-bin: $(RX_COMPOSE_GATE)

print-composition-gate-bin:
	@echo $(RX_COMPOSE_GATE)

.PHONY: test-composition test-composition-gate test-composition-attach-asan composition-gate-bin print-composition-gate-bin

# C4 (Convergence plan item 4): requalification of the local runtime with
# interruption and recovery (crash at every stage boundary, SIGKILL sweep, on-disk
# corruption). Test build only (crash points). Receipt: tools/c4_requal.sh.
RX_C4_REQUAL = $(OUT_DIR)/rx_c4_requal

$(RX_C4_REQUAL): $(RX_COMPOSE_DEPS) tests/runtime/rx_c4_requal.c | $(OUT_DIR)
	$(CC) $(CFLAGS) $(AIEN_TEST_FLAGS) -pthread -o $@ $(RX_COMPOSE_SRCS) tests/runtime/rx_c4_requal.c \
		$(RX_COMPOSE_LINK)

test-c4-requal: $(RX_C4_REQUAL)
	./$(RX_C4_REQUAL) $(OUT_DIR)/c4_requal_receipt.json

c4-requal-bin: $(RX_C4_REQUAL)

print-c4-requal-bin:
	@echo $(RX_C4_REQUAL)

.PHONY: test-c4-requal c4-requal-bin print-c4-requal-bin

# COMPOSITION-2 GPU tier: the same 14-step gate with both Skills executed on
# the GB10 through the sovereign M16 native path (no CUDA); see
# tests/runtime/rx_compose_gpu_skill.h. A chip run: take the quiet flag and
# use tools/composition_gate.sh --gpu (clean tree, content-addressed receipt).
RX_COMPOSE_GATE_GPU = $(OUT_DIR)/rx_composition_gate_gpu
RX_COMPOSE_GPU_SRCS = src/omega_blackwell_submit.c src/omega_blackwell_engine.c src/omega_gpu_engine.c src/omega_blackwell_matmul.c \
	src/omega_blackwell_codegen.c src/omega_blackwell_encoder.c src/omega_blackwell_qmd.c \
	src/omega_blackwell_realize.c src/omega_vector.c src/omega_validate.c src/omega_gpu_wait.c \
	$(PHYSICS_DIR)/m16/m16_native.c $(PHYSICS_DIR)/nvrm/nvrm.c

$(RX_COMPOSE_GATE_GPU): $(RX_COMPOSE_DEPS) $(RX_COMPOSE_GPU_SRCS) tests/runtime/rx_composition_gate.c \
	tests/runtime/rx_compose_gpu_skill.h | check-physics-lock $(OUT_DIR)
	$(CC) $(CFLAGS) -DRXC_GATE_GPU -Itests/runtime -pthread -o $@ $(RX_COMPOSE_SRCS) \
		$(RX_COMPOSE_GPU_SRCS) tests/runtime/rx_composition_gate.c $(RX_COMPOSE_LINK) -ldl

test-composition-gate-gpu: $(RX_COMPOSE_GATE_GPU)
	./$(RX_COMPOSE_GATE_GPU) "$$(git rev-parse HEAD)" $(OUT_DIR)/composition_gate_gpu_receipt.json

composition-gate-gpu-bin: $(RX_COMPOSE_GATE_GPU)

print-composition-gate-gpu-bin:
	@echo $(RX_COMPOSE_GATE_GPU)

.PHONY: test-composition-gate-gpu composition-gate-gpu-bin print-composition-gate-gpu-bin

# E1 row 7: correctly rounded FP32 DIV and SQRT on the GB10
# (docs/numeric/E1_DIVSQRT_GB10.md). Host tier, offline nvdisasm provenance
# and the CHECK mutation sweep need no device; the chip run is
# tools/run_divsqrt_gate.sh only (quiet flag, detached, receipt).
DIVSQRT_SRCS = tests/test_omega_divsqrt_gb10.c src/omega_numeric_divsqrt_gb10.c src/omega_numeric.c \
               src/omega_numeric_provenance.c $(NUMERIC_BW_SRCS)
DIVSQRT_HDRS = src/omega_numeric_divsqrt_gb10.h src/omega_numeric.h src/omega_blackwell_encoder.h \
               src/omega_blackwell_qmd.h src/sha256.h
.PHONY: test-divsqrt-host test-divsqrt-nvdisasm test-divsqrt-sweep
build/test_omega_divsqrt_gb10_cpu: $(DIVSQRT_SRCS) $(DIVSQRT_HDRS)
	@mkdir -p build
	gcc -std=gnu11 -O2 -Wall -Wextra -Werror -ffp-contract=off -Isrc -DOMEGA_NUMERIC_CPU_ONLY -pthread -o $@ $(DIVSQRT_SRCS)
test-divsqrt-host: build/test_omega_divsqrt_gb10_cpu
	./build/test_omega_divsqrt_gb10_cpu
test-divsqrt-nvdisasm:
	tools/divsqrt_nvdisasm_check.sh
test-divsqrt-sweep:
	tools/divsqrt_check_sweep.sh

# E1 row 10: GB10 realizations of the frozen transcendental sequences (EXP2
# LOG2 SIGMOID TANH SIN COS ERF GELU RSQRT, bit-identical to
# src/omega_numeric_transc.c; natural EXP and LOG, bit-identical to
# omega_math_exp / omega_math_log of src/omega_numeric.c). Kernels live in
# src/omega_numeric_divsqrt_gb10.c (same frame as DIV/SQRT; nvdisasm
# provenance via test-divsqrt-nvdisasm). Host tier needs no device; the chip
# run (all 2^32 inputs per op) is tools/run_numeric_transc_gate.sh only.
# test-numeric-transc-gb10-mutants: OMEGA_DS_MUTATE=1 (EXP c2 +1 ulp) and 2
# (LOG c1 +1 ulp) must each fail a host-model check, not only the digest one.
TRANSC_GB10_SRCS = tests/test_omega_numeric_transc_gb10.c src/omega_numeric_divsqrt_gb10.c \
                   src/omega_numeric_transc.c src/omega_numeric.c src/omega_numeric_provenance.c \
                   $(NUMERIC_BW_SRCS)
TRANSC_GB10_CC = gcc -std=gnu11 -O2 -Wall -Wextra -Werror -ffp-contract=off -fno-fast-math -Isrc -DOMEGA_NUMERIC_CPU_ONLY -pthread
TRANSC_GB10_MUTANTS = 1:EXP 2:LOG
.PHONY: test-numeric-transc-gb10-host test-numeric-transc-gb10-mutants
build/test_omega_numeric_transc_gb10_cpu: $(TRANSC_GB10_SRCS) $(DIVSQRT_HDRS) src/omega_numeric_transc.h
	@mkdir -p build
	$(TRANSC_GB10_CC) -o $@ $(TRANSC_GB10_SRCS)
test-numeric-transc-gb10-host: build/test_omega_numeric_transc_gb10_cpu
	./build/test_omega_numeric_transc_gb10_cpu
test-numeric-transc-gb10-mutants: $(TRANSC_GB10_SRCS) $(DIVSQRT_HDRS) src/omega_numeric_transc.h
	@mkdir -p build
	@for mo in $(TRANSC_GB10_MUTANTS); do m=$${mo%%:*}; op=$${mo#*:}; \
	  $(TRANSC_GB10_CC) -DOMEGA_DS_MUTATE=$$m -o build/test_omega_numeric_transc_gb10_mut$$m $(TRANSC_GB10_SRCS) || exit 1; \
	  ./build/test_omega_numeric_transc_gb10_mut$$m > build/test_omega_numeric_transc_gb10_mut$$m.log 2>&1; \
	  if grep -q "^\[FAIL\] TG_$${op}_HOST_MODEL_" build/test_omega_numeric_transc_gb10_mut$$m.log; then \
	    echo "mutant $$m ($$op) killed: $$(grep -m1 "^\[FAIL\] TG_$${op}_HOST_MODEL_" build/test_omega_numeric_transc_gb10_mut$$m.log)"; \
	  else echo "MUTANT $$m ($$op) SURVIVED (no host-model check failed)"; exit 1; fi; \
	done
	@echo "test-numeric-transc-gb10-mutants: PASS (all $(words $(TRANSC_GB10_MUTANTS)) mutants killed)"

# C3: host-only detector for the intermittent unwritten-output event. Pure seeded
# OM-2 (mk/unwritten-trap.mk). The GB10 harness is tests/test_omega_unwritten_trap_gb10.c.
.PHONY: test-unwritten-trap-host
test-unwritten-trap-host: test-unwritten-trap-om

# E1 row 2: general global load/store on the GB10 (src/omega_numeric_ldst_gb10.h,
# docs/numeric/E1_LDST_GB10.md). test-ldst-host needs no device; test-ldst-nvdisasm
# decodes every table kernel offline; the chip run is tools/run_numeric_ldst_chip.sh.
LDST_SRCS = tests/test_omega_ldst_gb10.c src/omega_numeric_ldst_gb10.c src/omega_numeric_divsqrt_gb10.c src/omega_numeric.c \
            src/omega_numeric_provenance.c src/omega_blackwell_encoder.c src/omega_blackwell_codegen.c \
            src/omega_blackwell_matmul.c src/omega_blackwell_qmd.c src/omega_om_units.c
LDST_HDRS = src/omega_numeric_ldst_gb10.h src/omega_numeric_divsqrt_gb10.h src/omega_numeric.h src/omega_blackwell_encoder.h \
            src/omega_blackwell_qmd.h src/sha256.h
.PHONY: test-ldst-host test-ldst-nvdisasm
build/test_omega_ldst_gb10_cpu: $(LDST_SRCS) $(LDST_HDRS)
	@mkdir -p build
	gcc -std=gnu11 -O2 -Wall -Wextra -Werror -ffp-contract=off -Isrc -DOMEGA_NUMERIC_CPU_ONLY -pthread -o $@ $(LDST_SRCS)
test-ldst-host: build/test_omega_ldst_gb10_cpu
	./build/test_omega_ldst_gb10_cpu
test-ldst-nvdisasm:
	tools/ldst_nvdisasm_check.sh

# VC1 / Library / Exec-Cache / VCStore / Resolve / Genesis / Program-IR / VC-Bridge:
# All cut over to pure seeded OM-2 (physics-free, CPU-only, zero C).
.PHONY: test-library test-exec-native-cache test-vcstore test-resolve oscv \
	test-genesis test-program-ir test-resolve-genesis test-vcstore-genesis \
	test-genesis-real test-vc-bridge

test-library: test-omega-library-om
	@echo "test-library: PASS (pure seeded OM-2)"

test-exec-native-cache: test-exec-native-cache-om
	@echo "test-exec-native-cache: PASS (pure seeded OM-2)"

test-vcstore: test-omega-vcstore-om
	@echo "test-vcstore: PASS (pure seeded OM-2)"

oscv: test-oscv-main-om
test-resolve: test-oscv-main-om test-omega-resolve-om test-omega-resolve-osc-om test-omega-receipt-om test-blake3-om
	@echo "test-resolve: PASS (pure seeded OM-2 resolver, oscv, receipt, and BLAKE3 suites)"

test-genesis: test-tests-root-2-om
	@echo "test-genesis: PASS (pure seeded OM-2 genesis set checks)"

test-program-ir: test-program-ir-om test-tests-root-1-om
	@echo "test-program-ir: PASS (pure seeded OM-2 program IR checks)"

test-resolve-genesis: test-resolve test-tests-root-2-om
	@echo "test-resolve-genesis: PASS (pure seeded OM-2 resolver + genesis checks)"

test-vcstore-genesis: test-omega-vcstore-om
	@echo "test-vcstore-genesis: PASS (pure seeded OM-2 vcstore genesis checks)"

test-genesis-real: test-tests-root-1-om
	@echo "test-genesis-real: PASS (pure seeded OM-2 pinned genesis checks)"

test-vc-bridge: test-omega-vc-bridge-om
	@echo "test-vc-bridge: PASS (pure seeded OM-2 vc bridge checks)"

# FB-1 cut 1: native (no CUDA) matmul entry point for the inference stack.
# libomega_gpu.a = everything the tool links except its main; the Rust FFI crate
# (cut 2) links it. test-gpu-matmul-api runs the host-only refusals; the chip
# sweep is `./build/gpu_matmul_api_test --out receipt.json` through the heavy queue.
.PHONY: libomega_gpu test-gpu-matmul-api
# The two gate-runner objects (omegatool's M17/M18/M19 and World gates) are NOT part of the
# library: nothing in the library or in the Rust FFI crate calls them (checked with nm), and
# they compile the physics checkout path into the object (-DOMEGA_PHYSICS_DIR), which made the
# archive digest depend on where physics was checked out. Without them libomega_gpu.a is
# byte-identical for any PHYSICS_DIR and any omega checkout directory.
GPU_API_OBJS = $(filter-out $(OUT_DIR)/omega_blackwell_gates.o $(OUT_DIR)/omega_world_gates.o $(OUT_DIR)/omega_clean_clone.o,$(OBJS))
GPU_API_TEST = $(OUT_DIR)/gpu_matmul_api_test
GPU_R4_RECEIPT = $(OUT_DIR)/gpu_matmul_r4_receipt
$(OUT_DIR)/libomega_gpu.a: $(GPU_API_OBJS) | check-physics-lock
	ar rcs $@ $(GPU_API_OBJS)
libomega_gpu: $(OUT_DIR)/libomega_gpu.a
# omega-mv#471: the archive must link without -lm (omegatool, the Rust FFI crate and Aienux link it bare). Fails if any symbol
# the archive leaves undefined is one libm exports (the export list is read from this toolchain's libm.so.6).
.PHONY: test-gpu-libm-free
test-gpu-libm-free: $(OUT_DIR)/libomega_gpu.a
	@export LC_ALL=C; libm="$$($(CC) -print-file-name=libm.so.6)"; test -f "$$libm" || { echo "libm-free: no libm.so.6 from $(CC)"; exit 1; }; \
	nm -D --defined-only "$$libm" | awk '{print $$3}' | sed 's/@.*//' | sort -u > $(OUT_DIR)/libm.syms; \
	nm -u $(OUT_DIR)/libomega_gpu.a | awk '{print $$2}' | sort -u | comm -12 - $(OUT_DIR)/libm.syms > $(OUT_DIR)/libm-refs.txt; \
	n=$$(wc -l < $(OUT_DIR)/libm-refs.txt); echo "libm-free: $$n libm symbols referenced by libomega_gpu.a ($$(wc -l < $(OUT_DIR)/libm.syms) libm exports checked)"; \
	if [ "$$n" -ne 0 ]; then sed 's/^/  /' $(OUT_DIR)/libm-refs.txt; echo "FAIL: libomega_gpu.a is not libm-free"; exit 1; fi; echo "PASS: libomega_gpu.a is libm-free"
$(GPU_API_TEST): tests/gpu_matmul_api_test.c src/omega_gpu_matmul_api.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -o $@ tests/gpu_matmul_api_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-gpu-matmul-api: $(GPU_API_TEST) $(GPU_R4_RECEIPT)
	./$(GPU_API_TEST) --host-only
	./$(GPU_R4_RECEIPT) --host-only

# omega #473 R4: the sealed CTA-budget receipt (full-output comparison at the training shapes,
# every budget, repeats, I42 stale-output check, negative controls). Host-only self-test above; the
# chip receipt is `quietlock run -- ./build/gpu_matmul_r4_receipt --out receipt.json`.
$(GPU_R4_RECEIPT): tests/gpu_matmul_r4_receipt.c src/omega_gpu_matmul_api.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -o $@ tests/gpu_matmul_r4_receipt.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm

# FB-1 cut 4: native rmsnorm / rope / swiglu (+ EX2 and shared-exchange probes).
# test-gpu-elementwise is host-only (refusals, codegen, word fixtures, nvdisasm
# listing); the chip gate is `./build/gpu_elementwise_test --out receipt.json`
# through the heavy queue. -ffp-contract=off keeps the f32 oracle free of FMA.
.PHONY: test-gpu-elementwise
GPU_EW_TEST = $(OUT_DIR)/gpu_elementwise_test
$(GPU_EW_TEST): tests/gpu_elementwise_test.c tests/bw_mufu_ftz.h src/omega_gpu_elementwise_api.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -o $@ tests/gpu_elementwise_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-gpu-elementwise: $(GPU_EW_TEST)
	./$(GPU_EW_TEST) --host-only

# omega-mv#545: every opcode the encoder accepts carries the emitter's control word (stall, scoreboards, wait mask)
# into instruction word 3. Host only; the golden-word checks compare words 0..2, so this is the check for word 3.
.PHONY: test-bw-encode-control
BW_ENCODE_CONTROL_TEST = $(OUT_DIR)/bw_encode_control_test
$(BW_ENCODE_CONTROL_TEST): tests/bw_encode_control_test.c src/omega_blackwell_codegen.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -o $@ tests/bw_encode_control_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-bw-encode-control: $(BW_ENCODE_CONTROL_TEST)
	./$(BW_ENCODE_CONTROL_TEST)

# omega #308: structured warp reconvergence (BSSY/BSYNC regions). test-gpu-reconv is
# host-only (encoder goldens, region bookkeeping, refusals, nvdisasm listing, every probe
# kernel through the SIMT warp simulator tests/bw_warp_sim.h against the oracle, mutation
# controls); the chip gate is tools/run_gpu_reconv_chip.sh.
.PHONY: test-gpu-reconv
GPU_RECONV_TEST = $(OUT_DIR)/gpu_reconv_test
$(GPU_RECONV_TEST): tests/gpu_reconv_test.c tests/bw_warp_sim.h src/omega_gpu_elementwise_api.h src/omega_bw_reconv.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -Itests -o $@ tests/gpu_reconv_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-gpu-reconv: $(GPU_RECONV_TEST)
	./$(GPU_RECONV_TEST) --host-only

# omega #492: IMAD.HI.U32 with a register Rc. The chip reads Rc as a 64-bit register pair (nvcc 13.0
# sm_121 oracle, evidence/IMADHI-RC-ORACLE-nvcc13.0-20261016; chip probe pending), so the four warp
# simulators model an even Rc as the pair Rc+1:Rc and refuse an odd Rc, and replay the PR #487
# odd-column pack (it must come out wrong, as on the chip). One binary per simulator header.
.PHONY: test-gpu-imadhi-rc
GPU_IMADHI_SIMS = bw_warp_sim bw_warp_sim_tc bw_warp_sim_k bw_warp_sim_pa
GPU_IMADHI_TESTS = $(GPU_IMADHI_SIMS:%=$(OUT_DIR)/gpu_imadhi_rc_test_%)
$(OUT_DIR)/gpu_imadhi_rc_test_%: tests/gpu_imadhi_rc_test.c tests/%.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -Itests -DSIM_HEADER='"$*.h"' -o $@ tests/gpu_imadhi_rc_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-gpu-imadhi-rc: $(GPU_IMADHI_TESTS)
	@for t in $(GPU_IMADHI_TESTS); do ./$$t || exit 1; done

# FB-1 cut 5: native gqa_attention (f32 KV) and paged_attention (bf16 KV, + batch).
# head_dim 128 (Qwen3-4B): the same battery with --hd 128 through both host simulators; GB10 parity PASS 126/0
# at 7dd92dc (evidence/FB1-CUT5-HD128-7dd92dc).
# test-gpu-attention runs host-only (refusals, codegen, nvdisasm listing) and then the
# whole parity battery through the host IR simulator (--sim, no chip); the chip
# gate is `./build/gpu_attention_test --out receipt.json` through the heavy queue
# (tools/run_gpu_attention_chip.sh). -ffp-contract=off keeps the oracle free of FMA.
.PHONY: test-gpu-attention
GPU_ATTN_TEST = $(OUT_DIR)/gpu_attention_test
$(GPU_ATTN_TEST): tests/gpu_attention_test.c tests/bw_warp_sim.h src/omega_gpu_attention_api.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -Itests -o $@ tests/gpu_attention_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-gpu-attention: $(GPU_ATTN_TEST)
	./$(GPU_ATTN_TEST) --host-only
	./$(GPU_ATTN_TEST) --sim
	./$(GPU_ATTN_TEST) --sweep --sim --out $(OUT_DIR)/gpu_attention_sweep_sim.json
	./$(GPU_ATTN_TEST) --hd 128 --host-only
	./$(GPU_ATTN_TEST) --hd 128 --sim
	./$(GPU_ATTN_TEST) --hd 128 --divergent --sim

# FB-1 cut 4b: fresh-process device-open probe (flake investigation, tools/probe_gpu_open.sh)
$(OUT_DIR)/gpu_session_probe: tests/gpu_session_probe.c src/omega_gpu_session.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -o $@ tests/gpu_session_probe.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm

# OWN-30B cut 2: window matmul gate (tests/gpu_moe_window_test.c). test-gpu-moe-window runs the host-only
# refusals and the packed-window byte rule; the chip gate is `./build/gpu_moe_window_test --out r.json`
# under /tmp/aien-gb10.lock (equivalence to the whole-tensor columns, mutants, window timing).
GPU_MOE_TEST = $(OUT_DIR)/gpu_moe_window_test
$(GPU_MOE_TEST): tests/gpu_moe_window_test.c src/omega_gpu_moe_api.h src/omega_gpu_matmul_api.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -o $@ tests/gpu_moe_window_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
.PHONY: test-gpu-moe-window
test-gpu-moe-window: $(GPU_MOE_TEST)
	./$(GPU_MOE_TEST) --host-only

# OWN-30B Cut 6 / Cut 5 (2026-10-13): FP8 e4m3 block-scaled GEMV (omega_gpu_fp8_api.h). test-gpu-fp8 is host-only
# (exhaustive conversion, pack refusals, codegen budgets, nvdisasm listing) then the warp-simulator battery
# (parity, grouped experts, mutants, both fragment orders); the chip gate is tools/run_gpu_fp8_chip.sh.
# -ffp-contract=off keeps the double oracle free of FMA.
.PHONY: test-gpu-fp8
GPU_FP8_TEST = $(OUT_DIR)/gpu_fp8_api_test
$(GPU_FP8_TEST): tests/gpu_fp8_api_test.c tests/bw_warp_sim.h src/omega_gpu_fp8_api.h src/omega_blackwell_codegen_moe.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -Itests -o $@ tests/gpu_fp8_api_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-gpu-fp8: $(GPU_FP8_TEST)
	./$(GPU_FP8_TEST) --host-only
	AIEN_OMEGA_FP8_COAL=0 ./$(GPU_FP8_TEST) --coal-default
	AIEN_OMEGA_FP8_DEEP=0 ./$(GPU_FP8_TEST) --deep-default
	./$(GPU_FP8_TEST) --sim

# omega #457 (2026-10-15): host rewrite of a GPU-cached buffer must be visible to the next launch. Chip only; the gate
# is tools/run_gpu_l2_stale_chip.sh.
GPU_L2_STALE_TEST = $(OUT_DIR)/gpu_l2_stale_test
$(GPU_L2_STALE_TEST): tests/gpu_l2_stale_test.c src/omega_gpu_fp8_api.h src/omega_gpu_session.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -o $@ tests/gpu_l2_stale_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm

# OWN-30B cut 8 (2026-10-13): one-launch decode attention (omega_gpu_decode_attn_api.h). test-gpu-decode-attn is
# host-only + simulator; the chip gate is tools/run_gpu_decode_attn_chip.sh.
.PHONY: test-gpu-decode-attn
GPU_DATTN_TEST = $(OUT_DIR)/gpu_decode_attn_test
$(GPU_DATTN_TEST): tests/gpu_decode_attn_test.c tests/bw_warp_sim_k.h src/omega_gpu_decode_attn_api.h src/omega_blackwell_codegen_attn.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -Itests -o $@ tests/gpu_decode_attn_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-gpu-decode-attn: $(GPU_DATTN_TEST) test-gpu-decode-attn-maxpos
	$(GPU_DATTN_TEST) --host-only
	$(GPU_DATTN_TEST) --sim

# omega #535: the 128k position bound (OMEGA_GPU_DATTN_MAX_POS 131072) on a fake platform, no device. A sanitized copy
# of src/omega_gpu_decode_attn_api.c is linked ahead of the library, so cache writes, the RoPE fill and launch staging
# are ASan/UBSan checked against the fake's exact-size buffers. Each mutant breaks one bound in a copy of that file;
# the test must FAIL on it.
.PHONY: test-gpu-decode-attn-maxpos
GPU_DATTN_MAXPOS_TEST = $(OUT_DIR)/test_omega_gpu_decode_attn_maxpos
GPU_DATTN_MAXPOS_MUT = $(OUT_DIR)/dattn_maxpos_mut
GPU_DATTN_MAXPOS_SAN = -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=all
$(GPU_DATTN_MAXPOS_TEST): tests/test_omega_gpu_decode_attn_maxpos.c src/omega_gpu_decode_attn_api.c src/omega_gpu_decode_attn_api.h src/omega_blackwell_codegen_attn.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(filter-out -MMD -MP -O2,$(CFLAGS)) $(GPU_DATTN_MAXPOS_SAN) -o $@ tests/test_omega_gpu_decode_attn_maxpos.c \
	  src/omega_gpu_decode_attn_api.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-gpu-decode-attn-maxpos: $(GPU_DATTN_MAXPOS_TEST)
	$(GPU_DATTN_MAXPOS_TEST)
	@mkdir -p $(GPU_DATTN_MAXPOS_MUT)
	@set -e; \
	tmut() { name=$$1; script=$$2; \
	  sed -e "$$script" src/omega_gpu_decode_attn_api.c > $(GPU_DATTN_MAXPOS_MUT)/$$name.c; \
	  if cmp -s src/omega_gpu_decode_attn_api.c $(GPU_DATTN_MAXPOS_MUT)/$$name.c; then echo "mutant $$name: pattern not found"; exit 1; fi; \
	  $(CC) $(filter-out -MMD -MP -O2,$(CFLAGS)) $(GPU_DATTN_MAXPOS_SAN) -o $(GPU_DATTN_MAXPOS_MUT)/$$name \
	    tests/test_omega_gpu_decode_attn_maxpos.c $(GPU_DATTN_MAXPOS_MUT)/$$name.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm; \
	  if $(GPU_DATTN_MAXPOS_MUT)/$$name > $(GPU_DATTN_MAXPOS_MUT)/$$name.log 2>&1; then echo "mutant $$name SURVIVED"; exit 1; fi; \
	  if ! grep -q '^FAIL ' $(GPU_DATTN_MAXPOS_MUT)/$$name.log; then \
	    echo "mutant $$name: no FAIL case (did not run?)"; cat $(GPU_DATTN_MAXPOS_MUT)/$$name.log; exit 1; fi; \
	  echo "mutant $$name killed"; }; \
	tmut cap-off-by-one 's/max_pos > OMEGA_GPU_DATTN_MAX_POS ||/max_pos >= OMEGA_GPU_DATTN_MAX_POS ||/'; \
	tmut cap-one-chunk-over 's/max_pos > OMEGA_GPU_DATTN_MAX_POS ||/max_pos > OMEGA_GPU_DATTN_MAX_POS + 256u ||/'; \
	tmut write-pos-bound 's/kv_head >= 4 || pos >= c->max_pos || count == 0/kv_head >= 4 || count == 0/'; \
	tmut write-count-bound 's/count > c->max_pos - pos ||/count > c->max_pos - pos + 1u ||/'; \
	tmut read-pos-bound 's/kv_head >= 4 || pos >= c->max_pos || !k/kv_head >= 4 || pos > c->max_pos || !k/'; \
	tmut step-pos-bound 's/layer >= c->layers || pos >= c->max_pos || (rec/layer >= c->layers || pos > c->max_pos || (rec/'; \
	tmut rope-table-short 's/(size_t)max_pos \* OMEGA_DATTN_ROPE_ROW_BYTES/(size_t)(max_pos - 8u) * OMEGA_DATTN_ROPE_ROW_BYTES/'; \
	echo "test-gpu-decode-attn-maxpos: 7 of 7 mutants killed"

# Qwen3.8-27B (omega-mv#544, 2026-10-18): decode attention head_dim 256, 24 q / 4 kv heads, partial RoPE by permutation
# (omega_gpu_decode_attn256_api.h). test-gpu-decode-attn256 is host-only + simulator; the chip gate is
# tools/run_gpu_decode_attn256_chip.sh.
.PHONY: test-gpu-decode-attn256
GPU_DATTN256_TEST = $(OUT_DIR)/gpu_decode_attn256_test
$(GPU_DATTN256_TEST): tests/gpu_decode_attn256_test.c tests/bw_warp_sim_k.h src/omega_gpu_decode_attn256_api.h src/omega_blackwell_codegen_attn256.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -Itests -o $@ tests/gpu_decode_attn256_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-gpu-decode-attn256: $(GPU_DATTN256_TEST)
	$(GPU_DATTN256_TEST) --host-only
	$(GPU_DATTN256_TEST) --sim

# OWN-30B cut 8 item 2 (2026-10-13): one-launch MoE router (omega_gpu_router_api.h). test-gpu-router is host-only
# (oracle, budgets) plus the warp simulator; the chip gate is tools/run_gpu_router_chip.sh under the GB10 lock.
.PHONY: test-gpu-router
GPU_ROUTER_TEST = $(OUT_DIR)/gpu_router_test
$(GPU_ROUTER_TEST): tests/gpu_router_test.c tests/bw_warp_sim_k.h src/omega_gpu_router_api.h src/omega_blackwell_codegen_router.h src/omega_gpu_fp8_api.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -Itests -o $@ tests/gpu_router_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-gpu-router: $(GPU_ROUTER_TEST)
	./$(GPU_ROUTER_TEST) --host-only
	./$(GPU_ROUTER_TEST) --sim

# Qwen3.8-27B Gated DeltaNet decode step (omega#542, 2026-10-18): one launch per layer (omega_gpu_gdn_api.h).
# test-gpu-gdn is host-only plus the warp simulator over the whole grid; the chip run is ./build/gpu_gdn_test under the GB10 lock.
.PHONY: test-gpu-gdn
GPU_GDN_TEST = $(OUT_DIR)/gpu_gdn_test
$(GPU_GDN_TEST): tests/gpu_gdn_test.c tests/bw_warp_sim_k.h src/omega_gpu_gdn_api.h src/omega_blackwell_codegen_gdn.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -Itests -o $@ tests/gpu_gdn_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
# L369: the multi-token GDN decode == T decode steps bit for bit (--sim: simulator; default: the chip, under the GB10 lock)
GPU_GDN_MULTI_TEST = $(OUT_DIR)/gpu_gdn_multi_test
$(GPU_GDN_MULTI_TEST): tests/gpu_gdn_multi_test.c tests/bw_warp_sim_k.h src/omega_gpu_gdn_api.h src/omega_blackwell_codegen_gdn.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -Itests -o $@ tests/gpu_gdn_multi_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
GPU_DATTN256_MULTI_TEST = $(OUT_DIR)/gpu_dattn256_multi_test
$(GPU_DATTN256_MULTI_TEST): tests/gpu_dattn256_multi_test.c src/omega_gpu_decode_attn256_api.h src/omega_blackwell_codegen_attn256.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -Itests -o $@ tests/gpu_dattn256_multi_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-gpu-gdn: $(GPU_GDN_TEST)
	./$(GPU_GDN_TEST) --host-only
	./$(GPU_GDN_TEST) --sim

# OWN-30B (2026-10-13): bf16 streaming GEMV, the lm_head (omega_gpu_bf16_gemv_api.h). test-gpu-bf16-gemv is host-only
# (emulation, budgets) plus the warp simulator (bit-identical to the host f32 emulation, mutants 1-3 caught); the chip
# gate is tools/run_gpu_bf16_gemv_chip.sh under the GB10 lock.
.PHONY: test-gpu-bf16-gemv
GPU_BF16_TEST = $(OUT_DIR)/gpu_bf16_gemv_test
$(GPU_BF16_TEST): tests/gpu_bf16_gemv_test.c tests/bw_warp_sim_k.h src/omega_gpu_bf16_gemv_api.h src/omega_blackwell_codegen_bf16.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -Itests -o $@ tests/gpu_bf16_gemv_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-gpu-bf16-gemv: $(GPU_BF16_TEST)
	$(GPU_BF16_TEST) --host-only
	$(GPU_BF16_TEST) --sim

# Ternary engine T0 (2026-10-15): KT1 W2A8 ternary GEMV (omega_gpu_tern_api.h). test-gpu-tern is host-only (word
# arithmetic, packing, segments, budgets, refusals) plus the warp simulator (bit-equal to oma_rz_oracle, f32 segment
# epilogue, three warp orders, mutants 1 to 5 caught); the chip gate is tools/run_gpu_tern_chip.sh with the quiet flag held.
.PHONY: test-gpu-tern
GPU_TERN_TEST = $(OUT_DIR)/gpu_tern_test
$(GPU_TERN_TEST): tests/gpu_tern_test.c tests/bw_warp_sim_k.h src/omega_gpu_tern_api.h src/omega_blackwell_codegen_tern.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -Itests -o $@ tests/gpu_tern_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-gpu-tern: $(GPU_TERN_TEST)
	$(GPU_TERN_TEST) --host-only
	$(GPU_TERN_TEST) --sim

# OWN-30B (2026-10-13): report-only lm_head study, fp8 vs bf16 argmax agreement on the real checkpoint (chip, GB10 lock).
$(OUT_DIR)/gpu_lmhead_fp8_study: tests/gpu_lmhead_fp8_study.c src/omega_gpu_bf16_gemv_api.h src/omega_gpu_fp8_api.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -O2 -o $@ tests/gpu_lmhead_fp8_study.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm

# OWN-30B prefill (2026-10-13): FP8 grouped GEMM (omega_gpu_fp8gemm_api.h). test-gpu-fp8gemm is host-only (emulation,
# permutation, budgets) plus the warp simulator (512 threads); the chip gate is tools/run_gpu_fp8gemm_chip.sh under the GB10 lock.
.PHONY: test-gpu-fp8gemm
GPU_FP8GEMM_TEST = $(OUT_DIR)/gpu_fp8gemm_test
$(GPU_FP8GEMM_TEST): tests/gpu_fp8gemm_test.c tests/bw_warp_sim_k.h src/omega_gpu_fp8gemm_api.h src/omega_blackwell_codegen_gemm.h src/omega_gpu_fp8_api.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -DWS_MAX_THREADS=512 -Itests -o $@ tests/gpu_fp8gemm_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm

# Qwen3.6-35B (sc L306 / L312) host-only simulator checks of the decode glue kernels, and the codegen hash pin
Q36_DEC_SIM_TEST = $(OUT_DIR)/q36_dec_sim_test
$(Q36_DEC_SIM_TEST): tests/q36_dec_sim_test.c tests/bw_warp_sim_k.h src/omega_blackwell_codegen_dec.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -DWS_MAX_THREADS=512 -Itests -o $@ tests/q36_dec_sim_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
Q36_CODEGEN_HASH = $(OUT_DIR)/q36_codegen_hash
$(Q36_CODEGEN_HASH): tests/q36_codegen_hash.c $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -Itests -o $@ tests/q36_codegen_hash.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-gpu-fp8gemm: $(GPU_FP8GEMM_TEST)
	$(GPU_FP8GEMM_TEST) --host-only
	$(GPU_FP8GEMM_TEST) --sim

# OWN-30B (2026-10-13): host-only audit that every launcher declares peak + 2 registers (the chip hung at peak + 1).
.PHONY: test-gpu-gpr-boundary
GPU_GPR_BOUNDARY_TEST = $(OUT_DIR)/gpu_gpr_boundary_test
$(GPU_GPR_BOUNDARY_TEST): tests/gpu_gpr_boundary_test.c src/omega_blackwell_codegen.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -o $@ tests/gpu_gpr_boundary_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-gpu-gpr-boundary: $(GPU_GPR_BOUNDARY_TEST)
	$(GPU_GPR_BOUNDARY_TEST)

# omega-mv#554: static scoreboard hazard checker (RAW / WAR / WAW) over the encoded bytes of every kernel the generators
# build, after the launchers' patch steps. Host only: decoder vs encoder, the pre-#553 attend red receipt
# (tests/fixtures/bw_hazard), negative controls, then the sweep. test-bw-hazard-nvdisasm (the name it had when it
# called nvdisasm) adds the decoder cross-check against Omega's own sm_121 disassembler, in process, on every distinct
# kernel (bar C6: every check that called nvdisasm calls ours; test-sm121dis checks that disassembler against the oracle).
.PHONY: test-bw-hazard test-bw-hazard-nvdisasm
BW_HAZARD_TEST = $(OUT_DIR)/bw_hazard_test
$(BW_HAZARD_TEST): tests/bw_hazard_test.c src/omega_bw_hazard.c src/omega_bw_hazard.h src/omega_sm121_disasm.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -o $@ tests/bw_hazard_test.c src/omega_bw_hazard.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-bw-hazard: $(BW_HAZARD_TEST)
	$(BW_HAZARD_TEST)
test-bw-hazard-nvdisasm: $(BW_HAZARD_TEST)
	$(BW_HAZARD_TEST) --disasm

# OWN-30B T3 (2026-10-13): HMMA arithmetic probe (host model self-checks; chip run under the GB10 lock).
GPU_TC_PROBE_TEST = $(OUT_DIR)/gpu_tc_probe_test
$(GPU_TC_PROBE_TEST): tests/gpu_tc_probe_test.c tests/bw_hmma_model.h src/omega_blackwell_codegen_tc.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -Itests -o $@ tests/gpu_tc_probe_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm

GPU_TCGEMM_TEST = $(OUT_DIR)/gpu_tcgemm_test
$(GPU_TCGEMM_TEST): tests/gpu_tcgemm_test.c tests/bw_hmma_model.h tests/bw_warp_sim_tc.h src/omega_blackwell_codegen_tc.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -DWS_MAX_THREADS=512 -Itests -o $@ tests/gpu_tcgemm_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm

GPU_TC_PEAK_TEST = $(OUT_DIR)/gpu_tc_peak_test
$(GPU_TC_PEAK_TEST): tests/gpu_tc_peak_test.c tests/bw_hmma_model.h tests/bw_warp_sim_tc.h src/omega_blackwell_codegen_tc.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -DWS_MAX_THREADS=512 -Itests -o $@ tests/gpu_tc_peak_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm

# Training R5 part 2 (2026-10-15): f32 global atomic add probe. --host-only is the simulator; the chip run is one short window.
GPU_ATOMF32_PROBE_TEST = $(OUT_DIR)/gpu_atomf32_probe_test
$(GPU_ATOMF32_PROBE_TEST): tests/gpu_atomf32_probe_test.c tests/bw_warp_sim_tc.h src/omega_bw_em.h src/omega_blackwell_codegen.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -DWS_MAX_THREADS=256 -Itests -o $@ tests/gpu_atomf32_probe_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
.PHONY: test-atomf32-probe-host
test-atomf32-probe-host: $(GPU_ATOMF32_PROBE_TEST)
	$(GPU_ATOMF32_PROBE_TEST) --host-only

# OWN-30B L1 attention (2026-10-13): tensor-core causal prefill attention. --host-only and --sim are host proofs;
# the chip gate is tools/run_gpu_prefill_attn_chip.sh.
GPU_PATTN_TEST = $(OUT_DIR)/gpu_prefill_attn_test
$(GPU_PATTN_TEST): tests/gpu_prefill_attn_test.c tests/bw_hmma_model.h tests/bw_warp_sim_pa.h src/omega_gpu_prefill_attn_api.h src/omega_blackwell_codegen_pattn.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -DWS_MAX_THREADS=256 -Itests -o $@ tests/gpu_prefill_attn_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
# Qwen3.8-27B (omega-mv#545, 2026-10-18): head_dim 256 prefill attention on the decode cache. --host-only and --sim
# are host proofs; the chip run is the default mode (under the GB10 lock).
GPU_PATTN256_TEST = $(OUT_DIR)/gpu_prefill_attn256_test
$(GPU_PATTN256_TEST): tests/gpu_prefill_attn256_test.c tests/bw_hmma_model.h tests/bw_warp_sim_pa.h src/omega_gpu_prefill_attn256_api.h src/omega_blackwell_codegen_pattn256.h src/omega_blackwell_codegen_attn256.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -DWS_MAX_THREADS=256 -Itests -o $@ tests/gpu_prefill_attn256_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
# OWN-30B T3b (2026-10-13): device-resident prefill module tests (host sim first; chip parts under the GB10 lock)
GPU_PF_MEM_TEST = $(OUT_DIR)/gpu_pf_mem_test
$(GPU_PF_MEM_TEST): tests/gpu_pf_mem_test.c tests/bw_warp_sim_tc.h src/omega_gpu_prefill.h src/omega_blackwell_codegen_pf.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -DWS_MAX_THREADS=512 -Itests -o $@ tests/gpu_pf_mem_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
GPU_PFGEMM_TEST = $(OUT_DIR)/gpu_pfgemm_test
$(GPU_PFGEMM_TEST): tests/gpu_pfgemm_test.c tests/bw_hmma_model.h tests/bw_warp_sim_tc.h src/omega_gpu_prefill.h src/omega_blackwell_codegen_tc2.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -DWS_MAX_THREADS=512 -Itests -o $@ tests/gpu_pfgemm_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
# trainer lane E1 (2026-10-16): bf16 training GEMM. --host-only and --sim are host proofs; the chip gate is tools/run_gpu_tgemm_chip.sh
GPU_TGEMM_TEST = $(OUT_DIR)/gpu_tgemm_test
$(GPU_TGEMM_TEST): tests/gpu_tgemm_test.c tests/bw_hmma_model.h tests/bw_warp_sim_tc.h src/omega_gpu_tgemm_api.h src/omega_blackwell_codegen_tgemm.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -DWS_MAX_THREADS=512 -Itests -o $@ tests/gpu_tgemm_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-gpu-tgemm: $(GPU_TGEMM_TEST)
	$(GPU_TGEMM_TEST) --host-only && $(GPU_TGEMM_TEST) --sim
GPU_QMMA_PROBE_TEST = $(OUT_DIR)/gpu_qmma_probe_test
$(GPU_QMMA_PROBE_TEST): tests/gpu_qmma_probe_test.c tests/bw_qmma_model.h src/omega_blackwell_codegen_qmma.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -Itests -o $@ tests/gpu_qmma_probe_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
GPU_QGEMM_TEST = $(OUT_DIR)/gpu_qgemm_test
$(GPU_QGEMM_TEST): tests/gpu_qgemm_test.c tests/bw_qmma_model.h tests/bw_warp_sim_tc.h src/omega_gpu_prefill.h src/omega_blackwell_codegen_qg.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -DWS_MAX_THREADS=1024 -Itests -o $@ tests/gpu_qgemm_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
GPU_PFHOST_TEST = $(OUT_DIR)/gpu_pfhost_test
$(GPU_PFHOST_TEST): tests/gpu_pfhost_test.c tests/bw_warp_sim_tc.h src/omega_gpu_pfhost.h src/omega_blackwell_codegen_pfhost.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -DWS_MAX_THREADS=1024 -Itests -o $@ tests/gpu_pfhost_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm

GPU_MOE_PLAN_TEST = $(OUT_DIR)/gpu_moe_plan_test
$(GPU_MOE_PLAN_TEST): tests/gpu_moe_plan_test.c src/omega_gpu_moe_plan.h src/omega_gpu_pfhost.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -o $@ tests/gpu_moe_plan_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
# omega#456: the prefill tests above, host model and warp simulator only. Every run names --host-only or --sim, the two
# modes that never open the device (each test's main returns before its chip part); chip runs stay under the GB10 lock.
.PHONY: test-gpu-prefill-host
test-gpu-prefill-host: $(GPU_TC_PROBE_TEST) $(GPU_TCGEMM_TEST) $(GPU_PATTN_TEST) $(GPU_PF_MEM_TEST) $(GPU_PFGEMM_TEST) \
                       $(GPU_QMMA_PROBE_TEST) $(GPU_QGEMM_TEST) $(GPU_PFHOST_TEST)
	./$(GPU_TC_PROBE_TEST) --host-only
	./$(GPU_QMMA_PROBE_TEST) --host-only
	./$(GPU_PF_MEM_TEST) --host-only
	./$(GPU_TCGEMM_TEST) --host-only
	./$(GPU_TCGEMM_TEST) --sim
	./$(GPU_PATTN_TEST) --host-only
	./$(GPU_PATTN_TEST) --sim
	./$(GPU_PFGEMM_TEST) --host-only
	./$(GPU_PFGEMM_TEST) --sim
	./$(GPU_QGEMM_TEST) --host-only
	./$(GPU_QGEMM_TEST) --sim
	./$(GPU_PFHOST_TEST) --host-only
	./$(GPU_PFHOST_TEST) --sim
	@echo "test-gpu-prefill-host: PASS (8 prefill tests, host model + warp simulator, no device)"
# omega-mv#1032 (review REJECT 2026-11-06, Linear DRA-127): the REQUIRED prefill gate runs first-party cases only.
# gpu_tcgemm_test and gpu_qgemm_test (Qwen3.8-27B widths), pattn/pfgemm/pfhost (Qwen3-30B-A3B shapes, Reviewer 2026-11-15),
# and tools/own30b_decode_profile.c (the OWN-30B build) all stay out of it: six items, all in the
# optional model-shape lane below (OMEGA-GPU-PREFILL-MODELSHAPES, requires: operator). The required lane is host-only.
# Refuse a non-empty inherited MAKEFILES when these gates are the goal. A MAKEFILES file containing
# `.IGNORE:` would otherwise turn a failing recipe into PASS (Reviewer 2026-11-15 v2). Parse-time
# $(error) is not subject to `.IGNORE`. run.sh also unsets MAKEFILES before it invokes make.
ifneq ($(filter test-gpu-prefill-host-fp test-gpu-prefill-modelshapes check-own30b-decode-profile,$(MAKECMDGOALS)),)
  ifneq ($(strip $(MAKEFILES)),)
    $(error MAKEFILES must be empty for the prefill gates; inherited $(MAKEFILES) can ignore recipe failures)
  endif
endif
.PHONY: test-gpu-prefill-host-fp
test-gpu-prefill-host-fp: $(GPU_TC_PROBE_TEST) $(GPU_QMMA_PROBE_TEST) $(GPU_PF_MEM_TEST)
	./$(GPU_TC_PROBE_TEST) --host-only
	./$(GPU_QMMA_PROBE_TEST) --host-only
	./$(GPU_PF_MEM_TEST) --host-only
	@echo "test-gpu-prefill-host-fp: PASS (3 first-party prefill tests, host model, no device)"
# omega-mv#1032: the optional model-shape lane (not required): the five prefill tests with outside model-family shapes.
.PHONY: test-gpu-prefill-modelshapes
test-gpu-prefill-modelshapes: $(GPU_TCGEMM_TEST) $(GPU_QGEMM_TEST) $(GPU_PATTN_TEST) $(GPU_PFGEMM_TEST) $(GPU_PFHOST_TEST)
	./$(GPU_TCGEMM_TEST) --host-only
	./$(GPU_TCGEMM_TEST) --sim
	./$(GPU_QGEMM_TEST) --host-only
	./$(GPU_QGEMM_TEST) --sim
	./$(GPU_PATTN_TEST) --host-only
	./$(GPU_PATTN_TEST) --sim
	./$(GPU_PFGEMM_TEST) --host-only
	./$(GPU_PFGEMM_TEST) --sim
	./$(GPU_PFHOST_TEST) --host-only
	./$(GPU_PFHOST_TEST) --sim
	@echo "test-gpu-prefill-modelshapes: PASS (5 model-shape prefill tests, host model + warp simulator, no device)"
# omega#456: pure seeded OM-2 OWN-30B decode stage profiler (tools/own30b_decode_profile.om).
.PHONY: check-own30b-decode-profile
check-own30b-decode-profile: tools/own30b_decode_profile.om seed/out/omc
	@mkdir -p $(OUT_DIR)
	seed/out/omc < tools/own30b_decode_profile.om > $(OUT_DIR)/own30b_decode_profile.tmp.$$$$ && chmod +x $(OUT_DIR)/own30b_decode_profile.tmp.$$$$ && mv -f $(OUT_DIR)/own30b_decode_profile.tmp.$$$$ $(OUT_DIR)/own30b_decode_profile
	./$(OUT_DIR)/own30b_decode_profile --test
	@echo "check-own30b-decode-profile: PASS (pure OM-2)"
# OWN-30B W-L2 (2026-10-13): command list (many launches, one submission) + decode glue kernels. test-gpu-cmdlist is
# host-only + warp simulator; the chip gate is tools/run_gpu_cmdlist_chip.sh under the GB10 lock.
.PHONY: test-gpu-cmdlist
GPU_CMDLIST_TEST = $(OUT_DIR)/gpu_cmdlist_test
$(GPU_CMDLIST_TEST): tests/gpu_cmdlist_test.c tests/bw_warp_sim_k.h src/omega_gpu_cmdlist.h src/omega_blackwell_codegen_dec.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -Itests -o $@ tests/gpu_cmdlist_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-gpu-cmdlist: $(GPU_CMDLIST_TEST)
	./$(GPU_CMDLIST_TEST) --host-only
	./$(GPU_CMDLIST_TEST) --sim

# C4 streams (docs/OMEGA.md row C4): two queues of the same half-chip work side by side, an event (cmdlist wait_for)
# between them, both with red checks. test-gpu-streams is host + warp simulator; the chip tier is "$(GPU_STREAMS_TEST)"
# with no flag, under the GB10 lock (timings need an exclusive window).
.PHONY: test-gpu-streams
GPU_STREAMS_TEST = $(OUT_DIR)/gpu_streams_test
$(GPU_STREAMS_TEST): tests/gpu_streams_test.c tests/bw_warp_sim.h src/omega_gpu_cmdlist.h src/omega_bw_em.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -Itests -o $@ tests/gpu_streams_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-gpu-streams: $(GPU_STREAMS_TEST)
	./$(GPU_STREAMS_TEST) --sim

# C5 isolation (docs/OMEGA.md row C5): a never-ending kernel times out, omega_gpu_session_recover, a correct launch in the
# same process; two processes on one GPU; a hang beside a working process. test-gpu-isolation is host + simulator;
# the chip tier is "$(GPU_ISOLATION_TEST)" with no flag, under the GB10 lock.
.PHONY: test-gpu-isolation
GPU_ISOLATION_TEST = $(OUT_DIR)/gpu_isolation_test
$(GPU_ISOLATION_TEST): tests/gpu_isolation_test.c tests/bw_warp_sim.h src/omega_gpu_session.h src/omega_bw_em.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -Itests -o $@ tests/gpu_isolation_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-gpu-isolation: $(GPU_ISOLATION_TEST)
	./$(GPU_ISOLATION_TEST) --host-only

# OWN-30B W-L2a (2026-10-13): one decode token as one command list (omega_gpu_decode_graph). test-gpu-decode-graph is
# host-only; the chip gate is tools/run_gpu_decode_graph_chip.sh under the GB10 lock.
.PHONY: test-gpu-decode-graph
GPU_DECODE_GRAPH_TEST = $(OUT_DIR)/gpu_decode_graph_test
GPU_DGRAPH_ABORT_TEST = $(OUT_DIR)/test_omega_gpu_decode_graph_abort
$(GPU_DECODE_GRAPH_TEST): tests/gpu_decode_graph_test.c src/omega_gpu_decode_graph.h src/omega_gpu_cmdlist.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -o $@ tests/gpu_decode_graph_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-gpu-decode-graph: $(GPU_DECODE_GRAPH_TEST) $(GPU_DGRAPH_ABORT_TEST) test-gpu-decode-graph-abort-mutants test-gpu-decode-graph-timeline
	./$(GPU_DECODE_GRAPH_TEST) --host-only
	./$(GPU_DGRAPH_ABORT_TEST)

# omega #518: lock and token-state recovery of the split API (failed begin_token, abort_token, end_token after a failed
# record, latched session) on a fake platform whose lock refuses a second acquisition. Host only, opens no device.
# Each mutant breaks one rule in a copy of omega_gpu_decode_graph.c linked ahead of the library; the test must FAIL on it.
.PHONY: test-gpu-decode-graph-abort-mutants
GPU_DGRAPH_MUT_DIR = $(OUT_DIR)/dgraph_mut
$(GPU_DGRAPH_ABORT_TEST): tests/test_omega_gpu_decode_graph_abort.c src/omega_gpu_decode_graph.h src/omega_gpu_platform.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -o $@ tests/test_omega_gpu_decode_graph_abort.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-gpu-decode-graph-abort-mutants: $(OUT_DIR)/libomega_gpu.a
	@mkdir -p $(GPU_DGRAPH_MUT_DIR)
	@set -e; killed=0; \
	dmut() { name=$$1; script=$$2; \
	  sed -e "$$script" src/omega_gpu_decode_graph.c > $(GPU_DGRAPH_MUT_DIR)/$$name.c; \
	  if cmp -s src/omega_gpu_decode_graph.c $(GPU_DGRAPH_MUT_DIR)/$$name.c; then echo "mutant $$name: pattern not found"; exit 1; fi; \
	  $(CC) $(filter-out -MMD -MP,$(CFLAGS)) -c -o $(GPU_DGRAPH_MUT_DIR)/$$name.o $(GPU_DGRAPH_MUT_DIR)/$$name.c; \
	  $(CC) $(filter-out -MMD -MP,$(CFLAGS)) -o $(GPU_DGRAPH_MUT_DIR)/$$name tests/test_omega_gpu_decode_graph_abort.c \
	    $(GPU_DGRAPH_MUT_DIR)/$$name.o $(OUT_DIR)/libomega_gpu.a -lpthread -lm; \
	  if ./$(GPU_DGRAPH_MUT_DIR)/$$name > $(GPU_DGRAPH_MUT_DIR)/$$name.log 2>&1; then echo "mutant $$name SURVIVED"; exit 1; fi; \
	  nfail=$$(grep -c '^FAIL' $(GPU_DGRAPH_MUT_DIR)/$$name.log || true); \
	  if [ "$$nfail" -eq 0 ]; then echo "mutant $$name: nonzero exit but no FAIL case (did not run?)"; cat $(GPU_DGRAPH_MUT_DIR)/$$name.log; exit 1; fi; \
	  echo "mutant $$name killed: $$nfail case(s) failed"; killed=$$((killed+1)); }; \
	dmut begin-fail-keeps-lock 's|    omega_gpu_session_unlock(); /\* begin_fail releases \*/|    ;|'; \
	dmut begin-fail-stays-in-token 's|    g->in_token = 0; g->failed = 1;|    g->failed = 1;|'; \
	dmut oneshot-old-bad-args-only 's|if (brc != OMEGA_GPU_DGRAPH_OK) {|if (brc == OMEGA_GPU_DGRAPH_BAD_ARGS) {|'; \
	dmut abort-keeps-lock 's|g->n_stamp = 0; /\* no timeline for an abandoned token \*/|&\n    return OMEGA_GPU_DGRAPH_OK;|'; \
	dmut abort-submits 's|^int omega_gpu_decode_graph_abort_token(OmegaGpuDecodeGraph \*g) {$$|&\n    if (g \&\& g->in_token) return omega_gpu_decode_graph_end_token(g, NULL, NULL);|'; \
	echo "test-gpu-decode-graph-abort-mutants: $$killed of 5 mutants killed"

# omega #456: the per-token timeline (set_stamps) never writes past stamp[]: 4096 stamped launches fill it, the 4097th
# (flush_each, one submission per launch) fails the token and leaves no timeline. Fake platform that completes every
# submission; no device. Each mutant breaks one rule in a copy of omega_gpu_decode_graph.c linked ahead of the library;
# the overflow case must FAIL on it.
.PHONY: test-gpu-decode-graph-timeline
GPU_DGRAPH_TL_TEST = $(OUT_DIR)/test_omega_gpu_decode_graph_timeline
GPU_DGRAPH_TL_MUT = $(OUT_DIR)/dgraph_tl_mut
$(GPU_DGRAPH_TL_TEST): tests/test_omega_gpu_decode_graph_timeline.c src/omega_gpu_decode_graph.h src/omega_gpu_platform.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -o $@ tests/test_omega_gpu_decode_graph_timeline.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-gpu-decode-graph-timeline: $(GPU_DGRAPH_TL_TEST)
	./$(GPU_DGRAPH_TL_TEST)
	@mkdir -p $(GPU_DGRAPH_TL_MUT)
	@set -e; \
	tmut() { name=$$1; script=$$2; \
	  sed -e "$$script" src/omega_gpu_decode_graph.c > $(GPU_DGRAPH_TL_MUT)/$$name.c; \
	  if cmp -s src/omega_gpu_decode_graph.c $(GPU_DGRAPH_TL_MUT)/$$name.c; then echo "mutant $$name: pattern not found"; exit 1; fi; \
	  $(CC) $(filter-out -MMD -MP,$(CFLAGS)) -o $(GPU_DGRAPH_TL_MUT)/$$name tests/test_omega_gpu_decode_graph_timeline.c \
	    $(GPU_DGRAPH_TL_MUT)/$$name.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm; \
	  if ./$(GPU_DGRAPH_TL_MUT)/$$name > $(GPU_DGRAPH_TL_MUT)/$$name.log 2>&1; then echo "mutant $$name SURVIVED"; exit 1; fi; \
	  if ! grep -q '^FAIL one launch past the timeline' $(GPU_DGRAPH_TL_MUT)/$$name.log; then \
	    echo "mutant $$name: no FAIL case (did not run?)"; cat $(GPU_DGRAPH_TL_MUT)/$$name.log; exit 1; fi; \
	  echo "mutant $$name killed"; }; \
	tmut room-off-by-one 's|(uint32_t)(cnt - from) > room) {|(uint32_t)(cnt - from) > room + 1u) {|'; \
	tmut timeline-after-failure 's#if (!g->stamps || g->failed || #if (!g->stamps || #'; \
	echo "test-gpu-decode-graph-timeline: 2 of 2 mutants killed"

# OWN-30B W-L2c (2026-10-14): per-launch fixed cost inside a command list (tests/gpu_launch_cost_test.c, chip only, GB10 lock).
GPU_LAUNCH_COST_TEST = $(OUT_DIR)/gpu_launch_cost_test
$(GPU_LAUNCH_COST_TEST): tests/gpu_launch_cost_test.c src/omega_gpu_fp8_api.h src/omega_gpu_cmdlist.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -o $@ tests/gpu_launch_cost_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm

# OWN-30B W-L2d (2026-10-14): L2 reuse of FP8 GEMV weights between two launches of one list (tests/gpu_l2_reuse_test.c, chip only, GB10 lock).
GPU_L2_REUSE_TEST = $(OUT_DIR)/gpu_l2_reuse_test
$(GPU_L2_REUSE_TEST): tests/gpu_l2_reuse_test.c src/omega_gpu_fp8_api.h src/omega_gpu_cmdlist.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -o $@ tests/gpu_l2_reuse_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm

# sc #642 (2026-10-18): Qwen3.8-27B decode graph (one token = one command list), chip test vs the APIs one call at a time
.PHONY: test-gpu-q38-graph-host
GPU_Q38_GRAPH_TEST = $(OUT_DIR)/gpu_q38_graph_test
GPU_Q38_GRAPH_HOST_TEST = $(OUT_DIR)/test_omega_gpu_q38_graph_host
GPU_Q38_STROKE_EXACT_TEST = $(OUT_DIR)/gpu_q38_stroke_exact_test
$(GPU_Q38_GRAPH_TEST): tests/gpu_q38_graph_test.c src/omega_gpu_q38_graph.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -o $@ tests/gpu_q38_graph_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
$(GPU_Q38_GRAPH_HOST_TEST): tests/test_omega_gpu_q38_graph_host.c src/omega_gpu_q38_graph.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -o $@ tests/test_omega_gpu_q38_graph_host.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
$(GPU_Q38_STROKE_EXACT_TEST): tests/gpu_q38_stroke_exact_test.c src/omega_gpu_q38_graph.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -o $@ tests/gpu_q38_stroke_exact_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-gpu-q38-graph-host: $(GPU_Q38_GRAPH_TEST) $(GPU_Q38_GRAPH_HOST_TEST)
	./$(GPU_Q38_GRAPH_TEST) --host-only
	./$(GPU_Q38_GRAPH_HOST_TEST)

# HUM L314 exact two-pass lm_head (XBOUND simulator proofs; the chip run comes with the export)
GPU_EXACT_HEAD_TEST = $(OUT_DIR)/gpu_exact_head_test
$(GPU_EXACT_HEAD_TEST): tests/gpu_exact_head_test.c tests/bw_warp_sim_k.h src/omega_blackwell_codegen_dec.h src/omega_gpu_bf16_gemv_api.h src/omega_gpu_fp8_api.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -Itests -o $@ tests/gpu_exact_head_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
# C3 (docs/OMEGA.md): sum, max, min and prefix sum of any length 1..2^28, bit-exact against the frozen order.
# test-gpu-scan: host refusals, codegen, references vs exact sums and vs the E1 reference, then the warp simulator
# (both orders, mutants caught). The chip tier is "$(GPU_SCAN_TEST)" with no flag, under the GB10 lock.
GPU_SCAN_TEST = $(OUT_DIR)/gpu_scan_test
$(GPU_SCAN_TEST): tests/gpu_scan_test.c tests/bw_warp_sim.h src/omega_gpu_scan.h src/omega_numeric_reduce.c src/omega_numeric.c $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -Itests -o $@ tests/gpu_scan_test.c src/omega_numeric_reduce.c src/omega_numeric.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
.PHONY: test-gpu-scan
test-gpu-scan: $(GPU_SCAN_TEST)
	./$(GPU_SCAN_TEST) --sim

# C3 (docs/OMEGA.md): matrix multiply of any shape, BF16 and FP8 (e4m3), both layouts, on the tensor cores; bit-exact
# against the chip-measured tensor-core model. test-gpu-gemm: host refusals and codegen, then the warp simulator.
# The chip tier is "$(GPU_GEMM_TEST)" with no flag (>= 200 shapes up to 8192, speed vs the measured ceiling), under the GB10 lock.
GPU_GEMM_TEST = $(OUT_DIR)/gpu_gemm_test
$(GPU_GEMM_TEST): tests/gpu_gemm_test.c tests/bw_warp_sim_tc.h tests/bw_hmma_model.h tests/bw_qmma_model.h src/omega_gpu_gemm.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -Itests -o $@ tests/gpu_gemm_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
.PHONY: test-gpu-gemm
test-gpu-gemm: $(GPU_GEMM_TEST)
	./$(GPU_GEMM_TEST) --sim

# Expert Ribbon P1 (aienix#4 / omega#533, 2026-10-18): versioned replaceable FP8 expert slots (omega_gpu_fp8_slots.h).
# test-gpu-fp8-slots is host-only (slot state machine, threaded race, mutant); the chip gate is
# tools/run_gpu_fp8_slots_chip.sh under the GB10 lock (parity vs resident, churn, reader fence via a command list, negative control).
.PHONY: test-gpu-fp8-slots
GPU_FP8_SLOTS_TEST = $(OUT_DIR)/gpu_fp8_slots_test
$(GPU_FP8_SLOTS_TEST): tests/gpu_fp8_slots_test.c src/omega_gpu_fp8_slots.h src/omega_fp8_slot_table.h src/omega_gpu_fp8_api.h src/omega_gpu_cmdlist.h $(OUT_DIR)/libomega_gpu.a
	$(CC) $(CFLAGS) -ffp-contract=off -o $@ tests/gpu_fp8_slots_test.c $(OUT_DIR)/libomega_gpu.a -lpthread -lm
test-gpu-fp8-slots: $(GPU_FP8_SLOTS_TEST)
	./$(GPU_FP8_SLOTS_TEST) --host-only
