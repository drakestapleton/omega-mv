# CPU-only host verification for GPU kernel-dispatch API / GEMM pure seeded OM-2 wave (wave-gb10-api-3).
# Pure seeded OM-2 twins of:
#   src/omega_gpu_router_api.c
#   src/omega_gpu_tcgemm_api.c
#   src/omega_gpu_tern_api.c
#   src/omega_gpu_tgemm_api.c
#   src/omega_gpu_gemm.c
#   src/omega_gpu_pfgemm.c
# Zero CUDA, zero libc, zero /dev/nvidia* access, static AArch64 ELF.

GB10_API_3_OMC ?= seed/out/omc

GB10_API_3_HOST_SRCS := \
	om/gpu/bw_regalloc.om \
	om/gpu/bw_sched.om \
	om/gpu/bw_qmd.om \
	om/gpu/cg_router.om \
	om/gpu/cg_tc.om \
	om/gpu/cg_tern.om \
	om/gpu/cg_tgemm.om \
	om/gpu/cg_tc2.om \
	om/gpu/cg_qg.om \
	om/gpu/cg_gpu_gemm.om \
	src/omega_blackwell_qmd.om \
	src/omega_blackwell_codegen_router.om \
	src/omega_blackwell_codegen_tc.om \
	src/omega_blackwell_codegen_tern.om \
	src/omega_blackwell_codegen_tgemm.om \
	src/omega_blackwell_codegen_tc2.om \
	src/omega_blackwell_codegen_qg.om \
	src/omega_gpu_hostmath.om \
	src/omega_gpu_fp8_pack.om \
	src/omega_gpu_router_api.om \
	src/omega_gpu_tcgemm_api.om \
	src/omega_gpu_tern_api.om \
	src/omega_gpu_tgemm_api.om \
	src/omega_gpu_gemm.om \
	src/omega_gpu_pfgemm.om \
	tests/test_gb10_api_3_host.om

GB10_API_3_HOST_BIN = $(OUT_DIR)/test_gb10_api_3_host_om

$(GB10_API_3_HOST_BIN): $(GB10_API_3_HOST_SRCS) $(GB10_API_3_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(GB10_API_3_HOST_SRCS)) | $(GB10_API_3_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-gb10-api-3-host
test-gb10-api-3-host: $(GB10_API_3_HOST_BIN)
	$(abspath $(GB10_API_3_HOST_BIN))
