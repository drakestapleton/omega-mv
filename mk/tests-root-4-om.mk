# Top-level tests/*.c + tests/physics0/verify/ CPU-only pure seeded OM-2 migration wave 4 (tests-root-4).
# Pure seeded OM-2 twins of:
#   tests/test_omega_gpu_code_alloc.c (existing tests/test_omega_gpu_code_alloc.om)
#   tests/test_omega_gpu_platform_linux.c
#   tests/test_omega_gpu_session_platform.c
#   tests/gpu_moe_plan_test.c
#   tests/bw_hazard_test.c
#   tests/test_omega_gpu_wait.c (existing tests/test_omega_gpu_wait.om)
#   tests/physics0/verify/test_pd0_ladder.c (existing tests/physics0/verify/test_pd0_ladder.om)
#   tests/physics0/verify/test_pd0_score.c (existing tests/physics0/verify/test_pd0_score.om)
# Physics-free, host-only, CPU-only, zero GPU / /dev/nvidia* access.

TESTS_ROOT_4_OMC ?= seed/out/omc
TR4_COMMIT := $(shell git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)

TR4_CODE_ALLOC_SRCS := \
	src/omega_gpu_code_alloc.om \
	tests/test_omega_gpu_code_alloc.om
TR4_CODE_ALLOC_BIN = $(OUT_DIR)/tr4_test_omega_gpu_code_alloc_om

TR4_GPU_WAIT_SRCS := \
	src/omega_gpu_wait.om \
	tests/test_omega_gpu_wait.om
TR4_GPU_WAIT_BIN = $(OUT_DIR)/tr4_test_omega_gpu_wait_om

TR4_MOE_PLAN_SRCS := \
	om/gpu/moe_plan.om \
	src/omega_gpu_moe_plan.om \
	tests/test_gpu_moe_plan.om
TR4_MOE_PLAN_BIN = $(OUT_DIR)/tr4_test_gpu_moe_plan_om

TR4_BW_HAZARD_SRCS := \
	src/omega_bw_hazard.om \
	tests/test_bw_hazard.om
TR4_BW_HAZARD_BIN = $(OUT_DIR)/tr4_test_bw_hazard_om

TR4_PLATFORM_LINUX_SRCS := \
	gpu/nvidia/native/nvrm/context.om \
	om/gpu/bw_qmd.om \
	om/gpu/bw_vecadd.om \
	src/omega_gpu_code_alloc.om \
	src/omega_gpu_platform.om \
	src/omega_gpu_platform_linux.om \
	src/omega_gpu_mem_cached.om \
	src/omega_gpu_engine.om \
	src/omega_blackwell_engine.om \
	src/omega_gpu_session.om \
	src/omega_gpu_cmdlist.om \
	tests/test_omega_gpu_platform_linux.om
TR4_PLATFORM_LINUX_BIN = $(OUT_DIR)/tr4_test_omega_gpu_platform_linux_om

TR4_SESSION_PLATFORM_SRCS := \
	gpu/nvidia/native/nvrm/context.om \
	om/gpu/bw_qmd.om \
	om/gpu/bw_vecadd.om \
	src/omega_gpu_code_alloc.om \
	src/omega_gpu_platform.om \
	src/omega_gpu_platform_linux.om \
	src/omega_gpu_mem_cached.om \
	src/omega_gpu_engine.om \
	src/omega_blackwell_engine.om \
	src/omega_gpu_session.om \
	src/omega_gpu_fmt.om \
	tests/test_omega_gpu_session_platform.om
TR4_SESSION_PLATFORM_BIN = $(OUT_DIR)/tr4_test_omega_gpu_session_platform_om

TR4_P0V_BASE := \
	src/physics0/pd0_types.om \
	src/physics0/pd0_rng.om \
	src/physics0/pd0_wire.om \
	src/physics0/ladder/pd0_codes.om \
	src/physics0/ladder/pd0_fmt.om \
	src/physics0/controls/pd0_receipt.om \
	src/physics0/ladder/pd0_ladder.om \
	src/physics0/score/pd0_score.om \
	src/physics0/controls/pd0_controls.om \
	tests/physics0/verify/pd0_bundle.om

TR4_PD0_LADDER_SRCS := $(TR4_P0V_BASE) tests/physics0/verify/test_pd0_ladder.om
TR4_PD0_LADDER_BIN = $(OUT_DIR)/tr4_test_pd0_ladder_om

TR4_PD0_SCORE_SRCS := $(TR4_P0V_BASE) tests/physics0/verify/test_pd0_score.om
TR4_PD0_SCORE_BIN = $(OUT_DIR)/tr4_test_pd0_score_om

$(TR4_CODE_ALLOC_BIN): $(TR4_CODE_ALLOC_SRCS) $(TESTS_ROOT_4_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR4_CODE_ALLOC_SRCS)) | $(TESTS_ROOT_4_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR4_GPU_WAIT_BIN): $(TR4_GPU_WAIT_SRCS) $(TESTS_ROOT_4_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR4_GPU_WAIT_SRCS)) | $(TESTS_ROOT_4_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR4_MOE_PLAN_BIN): $(TR4_MOE_PLAN_SRCS) $(TESTS_ROOT_4_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR4_MOE_PLAN_SRCS)) | $(TESTS_ROOT_4_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR4_BW_HAZARD_BIN): $(TR4_BW_HAZARD_SRCS) $(TESTS_ROOT_4_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR4_BW_HAZARD_SRCS)) | $(TESTS_ROOT_4_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR4_PLATFORM_LINUX_BIN): $(TR4_PLATFORM_LINUX_SRCS) $(TESTS_ROOT_4_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR4_PLATFORM_LINUX_SRCS)) | $(TESTS_ROOT_4_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR4_SESSION_PLATFORM_BIN): $(TR4_SESSION_PLATFORM_SRCS) $(TESTS_ROOT_4_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR4_SESSION_PLATFORM_SRCS)) | $(TESTS_ROOT_4_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR4_PD0_LADDER_BIN): $(TR4_PD0_LADDER_SRCS) $(TESTS_ROOT_4_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\ntext PD0_VERIFIER_COMMIT "$(TR4_COMMIT)"\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR4_PD0_LADDER_SRCS)) | $(TESTS_ROOT_4_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR4_PD0_SCORE_BIN): $(TR4_PD0_SCORE_SRCS) $(TESTS_ROOT_4_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\ntext PD0_VERIFIER_COMMIT "$(TR4_COMMIT)"\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR4_PD0_SCORE_SRCS)) | $(TESTS_ROOT_4_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-tests-root-4-om
test-tests-root-4-om: \
	$(TR4_CODE_ALLOC_BIN) \
	$(TR4_GPU_WAIT_BIN) \
	$(TR4_MOE_PLAN_BIN) \
	$(TR4_BW_HAZARD_BIN) \
	$(TR4_PLATFORM_LINUX_BIN) \
	$(TR4_SESSION_PLATFORM_BIN) \
	$(TR4_PD0_LADDER_BIN) \
	$(TR4_PD0_SCORE_BIN)
	@mkdir -p $(OUT_DIR)/tests-physics0-verify/receipts build/tests-physics0-verify/receipts
	$(abspath $(TR4_CODE_ALLOC_BIN))
	$(abspath $(TR4_GPU_WAIT_BIN))
	$(abspath $(TR4_MOE_PLAN_BIN))
	$(abspath $(TR4_BW_HAZARD_BIN))
	$(abspath $(TR4_PLATFORM_LINUX_BIN))
	$(abspath $(TR4_SESSION_PLATFORM_BIN))
	$(abspath $(TR4_PD0_LADDER_BIN))
	$(abspath $(TR4_PD0_SCORE_BIN))
