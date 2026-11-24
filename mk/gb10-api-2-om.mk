# Pure seeded OM-2 GPU kernel-dispatch API wave 2 (wave-gb10-api-2).
# Pure seeded OM-2 twins of:
#   src/omega_gpu_fp8gemm_api.c
#   src/omega_gpu_gdn_api.c
#   src/omega_gpu_matmul_api.c
#   src/omega_gpu_moe_api.c
#   src/omega_gpu_prefill_attn_api.c
#   src/omega_gpu_prefill_attn256_api.c
# Composes on already-landed om/gpu/*, src/omega_blackwell_codegen*.om,
# src/omega_blackwell_qmd.om, src/omega_blackwell_matmul.om, and src/omega_gpu_hostmath.om.
# CPU-only host verification (zero /dev/nvidia* access, zero CUDA, zero libc).

GB10_API_2_OMC ?= seed/out/omc

GB10_API_2_HOST_SRCS := \
	om/gpu/bw_qmd.om \
	om/gpu/bw_regalloc.om \
	om/gpu/bw_sched.om \
	om/gpu/cg_gemm.om \
	om/gpu/cg_gdn.om \
	om/gpu/cg_pattn.om \
	om/gpu/cg_pattn256.om \
	om/gpu/cg_attn256.om \
	src/omega_blackwell_qmd.om \
	src/omega_blackwell_codegen_gemm.om \
	src/omega_blackwell_codegen_gdn.om \
	src/omega_blackwell_codegen_pattn.om \
	src/omega_blackwell_codegen_pattn256.om \
	src/omega_blackwell_codegen_attn256.om \
	src/omega_gpu_hostmath.om \
	src/omega_gpu_fp8gemm_api.om \
	src/omega_gpu_gdn_api.om \
	src/omega_gpu_prefill_attn_api.om \
	src/omega_gpu_prefill_attn256_api.om \
	tests/test_gb10_api_2_host.om

GB10_API_2_MM_HOST_SRCS := \
	seed/ng/sha256.om \
	om/gpu/bw_qmd.om \
	om/gpu/bw_regalloc.om \
	om/encoder/bw_enc_sm121.om \
	om/gpu/cg_matmul.om \
	src/omega_blackwell_qmd.om \
	src/omega_blackwell_matmul.om \
	src/omega_blackwell_codegen.om \
	src/omega_gpu_matmul_api.om \
	src/omega_gpu_moe_api.om \
	tests/test_gb10_api_2_mm_host.om

GB10_API_2_HOST_BIN = $(OUT_DIR)/test_gb10_api_2_host_om
GB10_API_2_MM_HOST_BIN = $(OUT_DIR)/test_gb10_api_2_mm_host_om

$(GB10_API_2_HOST_BIN): $(GB10_API_2_HOST_SRCS) $(GB10_API_2_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(GB10_API_2_HOST_SRCS)) | $(GB10_API_2_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(GB10_API_2_MM_HOST_BIN): $(GB10_API_2_MM_HOST_SRCS) $(GB10_API_2_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(GB10_API_2_MM_HOST_SRCS)) | $(GB10_API_2_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-gb10-api-2-host
test-gb10-api-2-host: $(GB10_API_2_HOST_BIN) $(GB10_API_2_MM_HOST_BIN)
	$(abspath $(GB10_API_2_HOST_BIN))
	$(abspath $(GB10_API_2_MM_HOST_BIN))
