# CPU-only SM121 disassembler and freestanding GPU formatter in pure seeded OM-2
# (twins of src/omega_sm121_disasm.c and src/omega_gpu_fmt.c).
# Physics-free, host-only, zero GPU access.
BW_CPU_DISASM_OM_OMC ?= seed/out/omc
BW_CPU_DISASM_OM_SRCS := \
	src/omega_sm121_disasm.om \
	src/omega_gpu_fmt.om \
	tests/test_bw_cpu_disasm.om
BW_CPU_DISASM_OM_TEST = $(OUT_DIR)/test_bw_cpu_disasm_om

$(BW_CPU_DISASM_OM_TEST): $(BW_CPU_DISASM_OM_SRCS) $(BW_CPU_DISASM_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(BW_CPU_DISASM_OM_SRCS)) | $(BW_CPU_DISASM_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-bw-cpu-disasm-om
test-bw-cpu-disasm-om: $(BW_CPU_DISASM_OM_TEST)
	$(abspath $(BW_CPU_DISASM_OM_TEST))
