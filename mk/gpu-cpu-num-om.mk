# CPU-only GPU hostmath, FP8 pack/oracle, and scan reference modules in pure seeded OM-2
# (twins of src/omega_gpu_hostmath.c, src/omega_gpu_fp8_pack.c, src/omega_gpu_scan_ref.c).
# Physics-free, host-only, zero GPU access.
GPU_CPU_NUM_OM_OMC ?= seed/out/omc
GPU_CPU_NUM_OM_SRCS := \
	src/omega_gpu_hostmath.om \
	src/omega_gpu_fp8_pack.om \
	src/omega_gpu_scan_ref.om \
	tests/test_gpu_cpu_num.om
GPU_CPU_NUM_OM_TEST = $(OUT_DIR)/test_gpu_cpu_num_om

$(GPU_CPU_NUM_OM_TEST): $(GPU_CPU_NUM_OM_SRCS) $(GPU_CPU_NUM_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(GPU_CPU_NUM_OM_SRCS)) | $(GPU_CPU_NUM_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-gpu-cpu-num-om
test-gpu-cpu-num-om: $(GPU_CPU_NUM_OM_TEST)
	$(abspath $(GPU_CPU_NUM_OM_TEST))
