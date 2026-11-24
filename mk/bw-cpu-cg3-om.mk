# CPU-only Blackwell SM121 IR codegen wrappers in pure seeded OM-2 (wave 3:
# twins of src/omega_blackwell_codegen_{bf16,dec,gdn,gemm,moe,moe2}.c).
# Physics-free, host-only, zero GPU access.
BW_CPU_CG3_OM_OMC ?= seed/out/omc
BW_CPU_CG3_OM_SRCS := \
	om/gpu/cg_bf16.om \
	om/gpu/cg_dec.om \
	om/gpu/cg_gdn.om \
	om/gpu/cg_gemm.om \
	om/gpu/cg_moe.om \
	om/gpu/cg_moe2.om \
	om/gpu/bw_regalloc.om \
	om/gpu/bw_sched.om \
	src/omega_blackwell_codegen_bf16.om \
	src/omega_blackwell_codegen_dec.om \
	src/omega_blackwell_codegen_gdn.om \
	src/omega_blackwell_codegen_gemm.om \
	src/omega_blackwell_codegen_moe.om \
	src/omega_blackwell_codegen_moe2.om \
	tests/test_bw_cpu_cg3.om
BW_CPU_CG3_OM_TEST = $(OUT_DIR)/test_bw_cpu_cg3_om

$(BW_CPU_CG3_OM_TEST): $(BW_CPU_CG3_OM_SRCS) $(BW_CPU_CG3_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(BW_CPU_CG3_OM_SRCS)) | $(BW_CPU_CG3_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-bw-cpu-cg3-om
test-bw-cpu-cg3-om: $(BW_CPU_CG3_OM_TEST)
	$(abspath $(BW_CPU_CG3_OM_TEST))
