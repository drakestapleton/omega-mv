# Live GB10 GPU runtime/platform/engine/submission pure seeded OM-2 wave (gb10-gpu-1).
# Pure seeded OM-2 twins of:
#   src/omega_gpu_platform.c
#   src/omega_gpu_platform_linux.c
#   src/omega_gpu_mem_cached.c
#   src/omega_gpu_engine.c
#   src/omega_blackwell_engine.c
#   src/omega_blackwell_submit.c
# Zero CUDA, zero libc, static AArch64 ELF.
# Two modes:
#   test-gb10-gpu-1-host    : CPU-only structural/API/negative-control test (zero /dev/nvidia* access)
#   test-gb10-gpu-1-silicon : Live GB10 silicon value/parity test (run only inside a spark-window GB10 slot)

GB10_GPU_1_OMC ?= seed/out/omc

GB10_GPU_1_COMMON_SRCS := \
	gpu/nvidia/native/nvrm/context.om \
	om/gpu/bw_qmd.om \
	om/gpu/bw_vecadd.om \
	src/omega_gpu_platform.om \
	src/omega_gpu_platform_linux.om \
	src/omega_gpu_mem_cached.om \
	src/omega_gpu_engine.om \
	src/omega_blackwell_engine.om \
	src/omega_blackwell_submit.om

GB10_GPU_1_HOST_SRCS := $(GB10_GPU_1_COMMON_SRCS) tests/test_gb10_gpu_1_host.om
GB10_GPU_1_HOST_BIN = $(OUT_DIR)/test_gb10_gpu_1_host_om

GB10_GPU_1_SILICON_SRCS := $(GB10_GPU_1_COMMON_SRCS) tests/test_gb10_gpu_1_silicon.om
GB10_GPU_1_SILICON_BIN = $(OUT_DIR)/test_gb10_gpu_1_silicon_om

$(GB10_GPU_1_HOST_BIN): $(GB10_GPU_1_HOST_SRCS) $(GB10_GPU_1_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(GB10_GPU_1_HOST_SRCS)) | $(GB10_GPU_1_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(GB10_GPU_1_SILICON_BIN): $(GB10_GPU_1_SILICON_SRCS) $(GB10_GPU_1_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(GB10_GPU_1_SILICON_SRCS)) | $(GB10_GPU_1_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-gb10-gpu-1-host test-gb10-gpu-1-silicon
test-gb10-gpu-1-host: $(GB10_GPU_1_HOST_BIN)
	$(abspath $(GB10_GPU_1_HOST_BIN))

test-gb10-gpu-1-silicon: $(GB10_GPU_1_SILICON_BIN)
	$(abspath $(GB10_GPU_1_SILICON_BIN))
