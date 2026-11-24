# FP32 in the program IR (spec/program-fp32.md, E1 gap row 12). Physics-free, host-only.
# Pure seeded OM-2 (src/omega_program_fp32.om + src/omega_program_ir.om + tests/realize/test_program_fp32.om).
PROGRAM_FP32_OMC ?= seed/out/omc
PROGRAM_FP32_OM_SRCS := seed/ng/sha256.om src/omega_program_ir.om src/omega_program_fp32.om tests/realize/test_program_fp32.om
PROGRAM_FP32_TEST = $(OUT_DIR)/tests-realize/test_program_fp32

$(PROGRAM_FP32_TEST): $(PROGRAM_FP32_OM_SRCS) $(PROGRAM_FP32_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed '/^om2$$/d' $(PROGRAM_FP32_OM_SRCS)) | $(PROGRAM_FP32_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-program-fp32
test-program-fp32: $(PROGRAM_FP32_TEST)
	$(abspath $(PROGRAM_FP32_TEST))
