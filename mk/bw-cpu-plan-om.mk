# CPU-only Blackwell matmul oracle/spec/conversions, MoE planner, and IR codegen wrappers in pure seeded OM-2
# (twins of src/omega_blackwell_matmul.c, src/omega_gpu_moe_plan.c,
# src/omega_blackwell_codegen_attn.c, src/omega_blackwell_codegen_pf.c).
# Physics-free, host-only, zero GPU access.
BW_CPU_PLAN_OM_OMC ?= seed/out/omc
BW_CPU_PLAN_OM_SRCS := \
	seed/ng/sha256.om \
	om/gpu/moe_plan.om \
	om/gpu/cg_attn.om \
	om/gpu/cg_pf.om \
	om/gpu/bw_regalloc.om \
	src/omega_blackwell_matmul.om \
	src/omega_gpu_moe_plan.om \
	src/omega_blackwell_codegen_attn.om \
	src/omega_blackwell_codegen_pf.om \
	tests/test_bw_cpu_plan.om
BW_CPU_PLAN_OM_TEST = $(OUT_DIR)/test_bw_cpu_plan_om

$(BW_CPU_PLAN_OM_TEST): $(BW_CPU_PLAN_OM_SRCS) $(BW_CPU_PLAN_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(BW_CPU_PLAN_OM_SRCS)) | $(BW_CPU_PLAN_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-bw-cpu-plan-om
test-bw-cpu-plan-om: $(BW_CPU_PLAN_OM_TEST)
	$(abspath $(BW_CPU_PLAN_OM_TEST))
