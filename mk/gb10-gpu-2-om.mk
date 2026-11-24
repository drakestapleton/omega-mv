# Live GB10 GPU session/cmdlist/fp8_slots/serving/decode_graph/gates pure seeded OM-2 wave (gb10-gpu-2).
# Pure seeded OM-2 twins of:
#   src/omega_blackwell_gates.c
#   src/omega_gpu_session.c
#   src/omega_gpu_cmdlist.c
#   src/omega_gpu_fp8_slots.c
#   src/omega_gpu_serving.c
#   src/omega_gpu_decode_graph.c
# Zero CUDA, zero libc, static AArch64 ELF.
# Two modes:
#   test-gb10-gpu-2-host    : CPU-only structural/API/negative-control test (zero /dev/nvidia* access)
#   test-gb10-gpu-2-silicon : Live GB10 silicon value/parity test (run only inside a spark-window GB10 slot)

GB10_GPU_2_OMC ?= seed/out/omc

GB10_GPU_2_COMMON_SRCS := \
	gpu/nvidia/native/nvrm/context.om \
	om/gpu/bw_qmd.om \
	om/gpu/bw_vecadd.om \
	src/omega_gpu_code_alloc.om \
	src/omega_gpu_hostmath.om \
	src/omega_gpu_fp8_pack.om \
	src/omega_fp8_slot_table.om \
	src/omega_gpu_platform.om \
	src/omega_gpu_platform_linux.om \
	src/omega_gpu_mem_cached.om \
	src/omega_gpu_engine.om \
	src/omega_blackwell_engine.om \
	src/omega_blackwell_submit.om \
	src/omega_gpu_session.om \
	src/omega_gpu_cmdlist.om \
	src/omega_gpu_fp8_slots.om \
	src/omega_gpu_serving.om \
	src/omega_gpu_decode_graph.om \
	src/omega_blackwell_gates.om

GB10_GPU_2_HOST_SRCS := $(GB10_GPU_2_COMMON_SRCS) tests/test_gb10_gpu_2_host.om
GB10_GPU_2_HOST_BIN = $(OUT_DIR)/test_gb10_gpu_2_host_om

GB10_GPU_2_SILICON_SRCS := $(GB10_GPU_2_COMMON_SRCS) tests/test_gb10_gpu_2_silicon.om
GB10_GPU_2_SILICON_BIN = $(OUT_DIR)/test_gb10_gpu_2_silicon_om

$(GB10_GPU_2_HOST_BIN): $(GB10_GPU_2_HOST_SRCS) $(GB10_GPU_2_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(GB10_GPU_2_HOST_SRCS)) | $(GB10_GPU_2_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(GB10_GPU_2_SILICON_BIN): $(GB10_GPU_2_SILICON_SRCS) $(GB10_GPU_2_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(GB10_GPU_2_SILICON_SRCS)) | $(GB10_GPU_2_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-gb10-gpu-2-host test-gb10-gpu-2-silicon
test-gb10-gpu-2-host: $(GB10_GPU_2_HOST_BIN)
	$(abspath $(GB10_GPU_2_HOST_BIN))

test-gb10-gpu-2-silicon: $(GB10_GPU_2_SILICON_BIN)
	$(abspath $(GB10_GPU_2_SILICON_BIN))
