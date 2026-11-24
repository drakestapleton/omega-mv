# CPU-only Blackwell encoder, QMD, and realize modules in pure seeded OM-2
# (twins of src/omega_blackwell_encoder.c, src/omega_blackwell_qmd.c,
# src/omega_blackwell_realize.c). Physics-free, host-only, zero GPU access.
BW_CPU_CORE_OM_OMC ?= seed/out/omc
BW_CPU_CORE_OM_SRCS := \
	seed/ng/sha256.om \
	om/gpu/bw_vecadd.om \
	om/gpu/bw_qmd.om \
	src/omega_blackwell_encoder.om \
	src/omega_blackwell_qmd.om \
	src/omega_blackwell_realize.om \
	tests/test_bw_cpu_core.om
BW_CPU_CORE_OM_TEST = $(OUT_DIR)/test_bw_cpu_core_om

$(BW_CPU_CORE_OM_TEST): $(BW_CPU_CORE_OM_SRCS) $(BW_CPU_CORE_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(BW_CPU_CORE_OM_SRCS)) | $(BW_CPU_CORE_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-bw-cpu-core-om
test-bw-cpu-core-om: $(BW_CPU_CORE_OM_TEST)
	$(abspath $(BW_CPU_CORE_OM_TEST))
