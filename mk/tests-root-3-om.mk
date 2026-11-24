# Top-level tests/*.c CPU-only pure seeded OM-2 migration wave 3 (tests-root-3).
# Pure seeded OM-2 twins of:
#   tests/gpu_gpr_boundary_test.c
#   tests/gpu_imadhi_rc_test.c
#   tests/q36_dec_sim_test.c
#   tests/test_bw_om_codegen_bounds.c (retired; 0 remaining C callers)
#   tests/test_omega_gpu_engine.c
#   tests/test_omega_blackwell_engine.c
#   tests/test_omega_reduce.c
#   tests/test_omega_transc.c
# Physics-free, host-only, CPU-only, zero GPU / /dev/nvidia* access.

TESTS_ROOT_3_OMC ?= seed/out/omc

TR3_GPR_BOUNDARY_SRCS := \
	om/gpu/cg_moe.om \
	om/gpu/cg_bf16.om \
	om/gpu/cg_gemm.om \
	om/gpu/cg_router.om \
	om/gpu/cg_attn.om \
	om/gpu/bw_regalloc.om \
	om/gpu/bw_sched.om \
	src/omega_blackwell_codegen_moe.om \
	src/omega_blackwell_codegen_bf16.om \
	src/omega_blackwell_codegen_gemm.om \
	src/omega_blackwell_codegen_router.om \
	src/omega_blackwell_codegen_attn.om \
	tests/test_gpu_gpr_boundary.om
TR3_GPR_BOUNDARY_BIN = $(OUT_DIR)/test_gpu_gpr_boundary_om

TR3_IMADHI_RC_SRCS := \
	om/gpu/cg_matmul.om \
	om/gpu/bw_regalloc.om \
	om/encoder/bw_enc_sm121.om \
	seed/ng/sha256.om \
	src/omega_blackwell_codegen.om \
	tests/test_gpu_imadhi_rc.om
TR3_IMADHI_RC_BIN = $(OUT_DIR)/test_gpu_imadhi_rc_om

TR3_Q36_DEC_SIM_SRCS := \
	om/gpu/cg_dec.om \
	om/gpu/bw_regalloc.om \
	src/omega_blackwell_codegen_dec.om \
	tests/test_q36_dec_sim.om
TR3_Q36_DEC_SIM_BIN = $(OUT_DIR)/test_q36_dec_sim_om

TR3_CG_BOUNDS_SRCS := \
	om/gpu/cg_matmul.om \
	om/gpu/cg_qmma.om \
	om/gpu/cg_pfhost.om \
	om/gpu/bw_regalloc.om \
	om/gpu/bw_sched.om \
	om/encoder/bw_enc_sm121.om \
	seed/ng/sha256.om \
	src/omega_blackwell_codegen.om \
	src/omega_blackwell_codegen_qmma.om \
	src/omega_blackwell_codegen_pfhost.om \
	tests/test_bw_om_codegen_bounds.om
TR3_CG_BOUNDS_BIN = $(OUT_DIR)/test_bw_om_codegen_bounds_om

TR3_GPU_ENGINE_SRCS := \
	gpu/nvidia/native/nvrm/context.om \
	om/gpu/bw_qmd.om \
	om/gpu/bw_vecadd.om \
	src/omega_gpu_platform.om \
	src/omega_gpu_platform_linux.om \
	src/omega_gpu_mem_cached.om \
	src/omega_gpu_engine.om \
	src/omega_blackwell_engine.om \
	tests/test_omega_gpu_engine.om
TR3_GPU_ENGINE_BIN = $(OUT_DIR)/test_omega_gpu_engine_om

TR3_BW_ENGINE_SRCS := \
	gpu/nvidia/native/nvrm/context.om \
	om/gpu/bw_qmd.om \
	om/gpu/bw_vecadd.om \
	src/omega_gpu_platform.om \
	src/omega_gpu_platform_linux.om \
	src/omega_gpu_mem_cached.om \
	src/omega_gpu_engine.om \
	src/omega_blackwell_engine.om \
	src/omega_blackwell_submit.om \
	tests/test_omega_blackwell_engine.om
TR3_BW_ENGINE_BIN = $(OUT_DIR)/test_omega_blackwell_engine_om

TR3_REDUCE_SRCS := \
	src/omega_numeric_reduce.om \
	tests/test_omega_reduce.om
TR3_REDUCE_BIN = $(OUT_DIR)/test_omega_reduce_om

TR3_TRANSC_SRCS := \
	src/omega_numeric_transc.om \
	tests/test_omega_transc.om
TR3_TRANSC_BIN = $(OUT_DIR)/test_omega_transc_om

$(TR3_GPR_BOUNDARY_BIN): $(TR3_GPR_BOUNDARY_SRCS) $(TESTS_ROOT_3_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR3_GPR_BOUNDARY_SRCS)) | $(TESTS_ROOT_3_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR3_IMADHI_RC_BIN): $(TR3_IMADHI_RC_SRCS) $(TESTS_ROOT_3_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR3_IMADHI_RC_SRCS)) | $(TESTS_ROOT_3_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR3_Q36_DEC_SIM_BIN): $(TR3_Q36_DEC_SIM_SRCS) $(TESTS_ROOT_3_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR3_Q36_DEC_SIM_SRCS)) | $(TESTS_ROOT_3_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR3_CG_BOUNDS_BIN): $(TR3_CG_BOUNDS_SRCS) $(TESTS_ROOT_3_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR3_CG_BOUNDS_SRCS)) | $(TESTS_ROOT_3_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR3_GPU_ENGINE_BIN): $(TR3_GPU_ENGINE_SRCS) $(TESTS_ROOT_3_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR3_GPU_ENGINE_SRCS)) | $(TESTS_ROOT_3_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR3_BW_ENGINE_BIN): $(TR3_BW_ENGINE_SRCS) $(TESTS_ROOT_3_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR3_BW_ENGINE_SRCS)) | $(TESTS_ROOT_3_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR3_REDUCE_BIN): $(TR3_REDUCE_SRCS) $(TESTS_ROOT_3_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR3_REDUCE_SRCS)) | $(TESTS_ROOT_3_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR3_TRANSC_BIN): $(TR3_TRANSC_SRCS) $(TESTS_ROOT_3_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR3_TRANSC_SRCS)) | $(TESTS_ROOT_3_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-tests-root-3-om
test-tests-root-3-om: \
	$(TR3_GPR_BOUNDARY_BIN) \
	$(TR3_IMADHI_RC_BIN) \
	$(TR3_Q36_DEC_SIM_BIN) \
	$(TR3_CG_BOUNDS_BIN) \
	$(TR3_GPU_ENGINE_BIN) \
	$(TR3_BW_ENGINE_BIN) \
	$(TR3_REDUCE_BIN) \
	$(TR3_TRANSC_BIN)
	$(abspath $(TR3_GPR_BOUNDARY_BIN))
	$(abspath $(TR3_IMADHI_RC_BIN))
	$(abspath $(TR3_Q36_DEC_SIM_BIN))
	$(abspath $(TR3_CG_BOUNDS_BIN))
	$(abspath $(TR3_GPU_ENGINE_BIN))
	$(abspath $(TR3_BW_ENGINE_BIN))
	$(abspath $(TR3_REDUCE_BIN))
	$(abspath $(TR3_TRANSC_BIN))
