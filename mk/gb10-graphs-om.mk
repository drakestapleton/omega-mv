# CPU-only host verification for the FINAL 2 src/ root GB10 graph builders (wave-gb10-graphs).
# Pure seeded OM-2 twins of:
#   src/omega_gpu_q36_graph.c
#   src/omega_gpu_q38_graph.c
# Zero CUDA, zero libc, zero /dev/nvidia* access, static AArch64 ELF.

GB10_GRAPHS_OMC ?= seed/out/omc

GB10_GRAPHS_HOST_SRCS := \
	gpu/nvidia/native/nvrm/context.om \
	om/gpu/bw_qmd.om \
	om/gpu/bw_vecadd.om \
	om/gpu/q38_plan.om \
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
	src/omega_gpu_decode_graph.om \
	src/omega_gpu_q36_graph.om \
	src/omega_gpu_q38_graph.om \
	tests/test_gb10_graphs_host.om

GB10_GRAPHS_HOST_BIN = $(OUT_DIR)/test_gb10_graphs_host_om

$(GB10_GRAPHS_HOST_BIN): $(GB10_GRAPHS_HOST_SRCS) $(GB10_GRAPHS_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(GB10_GRAPHS_HOST_SRCS)) | $(GB10_GRAPHS_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-gb10-graphs-host
test-gb10-graphs-host: $(GB10_GRAPHS_HOST_BIN)
	$(abspath $(GB10_GRAPHS_HOST_BIN))
