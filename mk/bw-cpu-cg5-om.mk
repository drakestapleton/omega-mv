# CPU-only Blackwell SM121 IR codegen wrappers in pure seeded OM-2 (wave 5:
# twins of src/omega_blackwell_codegen_{qmma,router,tc,tc2,tern,tgemm}.c).
# Physics-free, host-only, zero GPU access.
BW_CPU_CG5_OM_OMC ?= seed/out/omc
BW_CPU_CG5_OM_SRCS := \
	om/gpu/cg_qmma.om \
	om/gpu/cg_router.om \
	om/gpu/cg_tc.om \
	om/gpu/cg_tc2.om \
	om/gpu/cg_tern.om \
	om/gpu/cg_tgemm.om \
	om/gpu/bw_regalloc.om \
	src/omega_blackwell_codegen_qmma.om \
	src/omega_blackwell_codegen_router.om \
	src/omega_blackwell_codegen_tc.om \
	src/omega_blackwell_codegen_tc2.om \
	src/omega_blackwell_codegen_tern.om \
	src/omega_blackwell_codegen_tgemm.om \
	tests/test_bw_cpu_cg5.om
BW_CPU_CG5_OM_TEST = $(OUT_DIR)/test_bw_cpu_cg5_om

$(BW_CPU_CG5_OM_TEST): $(BW_CPU_CG5_OM_SRCS) $(BW_CPU_CG5_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(BW_CPU_CG5_OM_SRCS)) | $(BW_CPU_CG5_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-bw-cpu-cg5-om
test-bw-cpu-cg5-om: $(BW_CPU_CG5_OM_TEST)
	$(abspath $(BW_CPU_CG5_OM_TEST))
