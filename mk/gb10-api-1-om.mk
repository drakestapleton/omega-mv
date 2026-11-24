# Pure seeded OM-2 migration wave gb10-api-1:
#   src/omega_gpu_attention_api.om
#   src/omega_gpu_bf16_gemv_api.om
#   src/omega_gpu_decode_attn_api.om
#   src/omega_gpu_decode_attn256_api.om
#   src/omega_gpu_elementwise_api.om
#   src/omega_gpu_fp8_api.om
# CPU-only host unit/contract/QMD-validation/codegen test (zero /dev/nvidia* access).

GB10_API_1_OMC ?= seed/out/omc

GB10_API_1_SRCS := \
	gpu/nvidia/native/nvrm/context.om \
	om/gpu/bw_qmd.om \
	om/gpu/bw_vecadd.om \
	om/gpu/bw_regalloc.om \
	om/gpu/bw_sched.om \
	om/gpu/q38_plan.om \
	om/gpu/cg_gpu_attn.om \
	om/gpu/cg_bf16.om \
	om/gpu/cg_attn.om \
	om/gpu/cg_attn256.om \
	om/gpu/cg_moe.om \
	om/gpu/cg_moe2.om \
	src/omega_gpu_platform.om \
	src/omega_gpu_platform_linux.om \
	src/omega_gpu_mem_cached.om \
	src/omega_gpu_engine.om \
	src/omega_blackwell_engine.om \
	src/omega_blackwell_submit.om \
	src/omega_blackwell_qmd.om \
	src/omega_blackwell_codegen_bf16.om \
	src/omega_blackwell_codegen_attn.om \
	src/omega_blackwell_codegen_attn256.om \
	src/omega_blackwell_codegen_moe.om \
	src/omega_blackwell_codegen_moe2.om \
	src/omega_gpu_hostmath.om \
	src/omega_gpu_fp8_pack.om \
	src/omega_gpu_attention_api.om \
	src/omega_gpu_bf16_gemv_api.om \
	src/omega_gpu_decode_attn_api.om \
	src/omega_gpu_decode_attn256_api.om \
	src/omega_gpu_elementwise_api.om \
	src/omega_gpu_fp8_api.om \
	tests/test_gb10_api_1_host.om

GB10_API_1_HOST_BIN = $(OUT_DIR)/test_gb10_api_1_host_om

$(GB10_API_1_HOST_BIN): $(GB10_API_1_SRCS) $(GB10_API_1_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(GB10_API_1_SRCS)) | $(GB10_API_1_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-gb10-api-1-host
test-gb10-api-1-host: $(GB10_API_1_HOST_BIN)
	$(abspath $(GB10_API_1_HOST_BIN))
