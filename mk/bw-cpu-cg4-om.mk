# CPU-only Blackwell SM121 SASS codegen in pure seeded OM-2 (wave 4:
# twins of src/omega_blackwell_codegen{,_attn256,_pattn,_pattn256,_pfhost,_qg}.c).
# Physics-free, host-only, zero GPU access.
BW_CPU_CG4_OM_OMC ?= seed/out/omc

BW_CPU_CG4_OM_SRCS := \
	om/gpu/cg_attn256.om \
	om/gpu/cg_pattn.om \
	om/gpu/cg_pattn256.om \
	om/gpu/cg_pfhost.om \
	om/gpu/cg_qg.om \
	om/gpu/bw_regalloc.om \
	src/omega_blackwell_codegen_attn256.om \
	src/omega_blackwell_codegen_pattn.om \
	src/omega_blackwell_codegen_pattn256.om \
	src/omega_blackwell_codegen_pfhost.om \
	src/omega_blackwell_codegen_qg.om \
	tests/test_bw_cpu_cg4.om
BW_CPU_CG4_OM_TEST = $(OUT_DIR)/test_bw_cpu_cg4_om

BW_CPU_CG4_CORE_OM_SRCS := \
	om/gpu/cg_matmul.om \
	om/gpu/bw_regalloc.om \
	om/encoder/bw_enc_sm121.om \
	seed/ng/sha256.om \
	src/omega_blackwell_codegen.om \
	tests/test_bw_cpu_cg4_core.om
BW_CPU_CG4_CORE_OM_TEST = $(OUT_DIR)/test_bw_cpu_cg4_core_om

$(BW_CPU_CG4_OM_TEST): $(BW_CPU_CG4_OM_SRCS) $(BW_CPU_CG4_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(BW_CPU_CG4_OM_SRCS)) | $(BW_CPU_CG4_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(BW_CPU_CG4_CORE_OM_TEST): $(BW_CPU_CG4_CORE_OM_SRCS) $(BW_CPU_CG4_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(BW_CPU_CG4_CORE_OM_SRCS)) | $(BW_CPU_CG4_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-bw-cpu-cg4-om
test-bw-cpu-cg4-om: $(BW_CPU_CG4_OM_TEST) $(BW_CPU_CG4_CORE_OM_TEST)
	$(abspath $(BW_CPU_CG4_OM_TEST))
	$(abspath $(BW_CPU_CG4_CORE_OM_TEST))
