# Top-level tests/*.c CPU-only pure seeded OM-2 migration wave 2 (tests-root-2).
# Pure seeded OM-2 twins of:
#   tests/test_omega_genesis_set.c
#   tests/test_omega_gpu_q38_graph_host.c
#   tests/test_omega_gpu_engine_compile.c
#   tests/test_omega_gpu_platform.c
#   tests/test_omega_gpu_decode_graph_timeline.c
#   tests/test_omega_gpu_decode_graph_abort.c
#   tests/test_omega_gpu_decode_attn_maxpos.c
#   tests/bench_rx_argus.c
# Physics-free, host-only, CPU-only, zero GPU access.

TESTS_ROOT_2_OMC ?= seed/out/omc

TR2_GENESIS_SET_SRCS := \
	tests/test_omega_genesis_set.om
TR2_GENESIS_SET_BIN = $(OUT_DIR)/test_omega_genesis_set_om

TR2_Q38_HOST_SRCS := \
	om/gpu/cg_dec.om \
	om/gpu/cg_gemm.om \
	om/gpu/cg_bf16.om \
	om/gpu/bw_regalloc.om \
	om/gpu/bw_sched.om \
	src/omega_blackwell_codegen_dec.om \
	src/omega_blackwell_codegen_gemm.om \
	src/omega_blackwell_codegen_bf16.om \
	tests/test_omega_gpu_q38_graph_host.om
TR2_Q38_HOST_BIN = $(OUT_DIR)/test_omega_gpu_q38_graph_host_om

TR2_GPU_ENG_CMP_SRCS := \
	tests/test_omega_gpu_engine_compile.om
TR2_GPU_ENG_CMP_BIN = $(OUT_DIR)/test_omega_gpu_engine_compile_om

TR2_GPU_PLAT_SRCS := \
	tests/test_omega_gpu_platform.om
TR2_GPU_PLAT_BIN = $(OUT_DIR)/test_omega_gpu_platform_om

TR2_DGRAPH_TL_SRCS := \
	tests/test_omega_gpu_decode_graph_timeline.om
TR2_DGRAPH_TL_BIN = $(OUT_DIR)/test_omega_gpu_decode_graph_timeline_om

TR2_DGRAPH_ABORT_SRCS := \
	tests/test_omega_gpu_decode_graph_abort.om
TR2_DGRAPH_ABORT_BIN = $(OUT_DIR)/test_omega_gpu_decode_graph_abort_om

TR2_DATTN_MAXPOS_SRCS := \
	src/omega_gpu_hostmath.om \
	tests/test_omega_gpu_decode_attn_maxpos.om
TR2_DATTN_MAXPOS_BIN = $(OUT_DIR)/test_omega_gpu_decode_attn_maxpos_om

TR2_BENCH_ARGUS_SRCS := \
	seed/ng/sha256.om \
	src/runtime/rx_aegis.om \
	src/runtime/rx_argus.om \
	tests/test_bench_rx_argus.om
TR2_BENCH_ARGUS_BIN = $(OUT_DIR)/test_bench_rx_argus_om

$(TR2_GENESIS_SET_BIN): $(TR2_GENESIS_SET_SRCS) $(TESTS_ROOT_2_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR2_GENESIS_SET_SRCS)) | $(TESTS_ROOT_2_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR2_Q38_HOST_BIN): $(TR2_Q38_HOST_SRCS) $(TESTS_ROOT_2_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR2_Q38_HOST_SRCS)) | $(TESTS_ROOT_2_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR2_GPU_ENG_CMP_BIN): $(TR2_GPU_ENG_CMP_SRCS) $(TESTS_ROOT_2_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR2_GPU_ENG_CMP_SRCS)) | $(TESTS_ROOT_2_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR2_GPU_PLAT_BIN): $(TR2_GPU_PLAT_SRCS) $(TESTS_ROOT_2_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR2_GPU_PLAT_SRCS)) | $(TESTS_ROOT_2_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR2_DGRAPH_TL_BIN): $(TR2_DGRAPH_TL_SRCS) $(TESTS_ROOT_2_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR2_DGRAPH_TL_SRCS)) | $(TESTS_ROOT_2_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR2_DGRAPH_ABORT_BIN): $(TR2_DGRAPH_ABORT_SRCS) $(TESTS_ROOT_2_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR2_DGRAPH_ABORT_SRCS)) | $(TESTS_ROOT_2_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR2_DATTN_MAXPOS_BIN): $(TR2_DATTN_MAXPOS_SRCS) $(TESTS_ROOT_2_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR2_DATTN_MAXPOS_SRCS)) | $(TESTS_ROOT_2_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR2_BENCH_ARGUS_BIN): $(TR2_BENCH_ARGUS_SRCS) $(TESTS_ROOT_2_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR2_BENCH_ARGUS_SRCS)) | $(TESTS_ROOT_2_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-tests-root-2-om
test-tests-root-2-om: \
	$(TR2_GENESIS_SET_BIN) \
	$(TR2_Q38_HOST_BIN) \
	$(TR2_GPU_ENG_CMP_BIN) \
	$(TR2_GPU_PLAT_BIN) \
	$(TR2_DGRAPH_TL_BIN) \
	$(TR2_DGRAPH_ABORT_BIN) \
	$(TR2_DATTN_MAXPOS_BIN) \
	$(TR2_BENCH_ARGUS_BIN)
	$(abspath $(TR2_GENESIS_SET_BIN))
	$(abspath $(TR2_Q38_HOST_BIN))
	$(abspath $(TR2_GPU_ENG_CMP_BIN))
	$(abspath $(TR2_GPU_PLAT_BIN))
	$(abspath $(TR2_DGRAPH_TL_BIN))
	$(abspath $(TR2_DGRAPH_ABORT_BIN))
	$(abspath $(TR2_DATTN_MAXPOS_BIN))
	$(abspath $(TR2_BENCH_ARGUS_BIN))
