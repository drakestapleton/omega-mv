# Live GB10 GPU E1 numerics + scan/prefill/pfhost pure seeded OM-2 wave (gb10-gpu-3).
# Pure seeded OM-2 twins of:
#   src/omega_numeric_gb10.c
#   src/omega_numeric_divsqrt_gb10.c
#   src/omega_numeric_ldst_gb10.c
#   src/omega_numeric_reduce_gb10.c
#   src/omega_gpu_scan.c
#   src/omega_gpu_prefill.c
#   src/omega_gpu_pfhost.c
# Zero CUDA, zero libc, static AArch64 ELF.
# Two modes:
#   test-gb10-gpu-3-host    : CPU-only structural/API/negative-control test (zero /dev/nvidia* access)
#   test-gb10-gpu-3-silicon : Live GB10 silicon value/parity test (run only inside a spark-window GB10 slot)

GB10_GPU_3_OMC ?= seed/out/omc

GB10_GPU_3_COMMON_SRCS := \
	om/sha256/sha256-om2.om \
	gpu/nvidia/native/nvrm/context.om \
	om/gpu/bw_qmd.om \
	om/gpu/bw_vecadd.om \
	om/gpu/cg_pf.om \
	om/gpu/cg_pfhost.om \
	src/omega_gpu_code_alloc.om \
	src/omega_gpu_hostmath.om \
	src/omega_gpu_platform.om \
	src/omega_gpu_platform_linux.om \
	src/omega_gpu_mem_cached.om \
	src/omega_gpu_engine.om \
	src/omega_blackwell_engine.om \
	src/omega_blackwell_submit.om \
	src/omega_gpu_session.om \
	src/omega_gpu_cmdlist.om \
	src/omega_numeric.om \
	src/omega_gpu_scan_ref.om \
	src/omega_numeric_divsqrt_gb10.om \
	src/omega_numeric_gb10.om \
	src/omega_numeric_ldst_gb10.om \
	src/omega_numeric_reduce_gb10.om \
	src/omega_gpu_scan.om \
	src/omega_gpu_prefill.om \
	src/omega_gpu_pfhost.om

GB10_GPU_3_HOST_SRCS := $(GB10_GPU_3_COMMON_SRCS) tests/test_gb10_gpu_3_host.om
GB10_GPU_3_HOST_BIN = $(OUT_DIR)/test_gb10_gpu_3_host_om

GB10_GPU_3_SILICON_SRCS := $(GB10_GPU_3_COMMON_SRCS) tests/test_gb10_gpu_3_silicon.om
GB10_GPU_3_SILICON_BIN = $(OUT_DIR)/test_gb10_gpu_3_silicon_om

$(GB10_GPU_3_HOST_BIN): $(GB10_GPU_3_HOST_SRCS) $(GB10_GPU_3_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(GB10_GPU_3_HOST_SRCS)) | $(GB10_GPU_3_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(GB10_GPU_3_SILICON_BIN): $(GB10_GPU_3_SILICON_SRCS) $(GB10_GPU_3_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(GB10_GPU_3_SILICON_SRCS)) | $(GB10_GPU_3_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-gb10-gpu-3-host test-gb10-gpu-3-silicon
test-gb10-gpu-3-host: $(GB10_GPU_3_HOST_BIN)
	$(abspath $(GB10_GPU_3_HOST_BIN))

test-gb10-gpu-3-silicon: $(GB10_GPU_3_SILICON_BIN)
	$(abspath $(GB10_GPU_3_SILICON_BIN))
