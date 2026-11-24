# Canonical binary Program IR codec (src/omega_program_ir.om, twin of src/omega_program_ir.c).
# Pure seeded OM-2, physics-free, host-only.
PROGRAM_IR_OMC ?= seed/out/omc
PROGRAM_IR_OM_SRCS := seed/ng/sha256.om src/omega_program_ir.om src/omega_program_fp32.om tests/program/test_program_ir.om
PROGRAM_IR_TEST = $(OUT_DIR)/tests-program/test_program_ir

$(PROGRAM_IR_TEST): $(PROGRAM_IR_OM_SRCS) $(PROGRAM_IR_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed '/^om2$$/d' $(PROGRAM_IR_OM_SRCS)) | $(PROGRAM_IR_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-program-ir-om
test-program-ir-om: $(PROGRAM_IR_TEST)
	$(abspath $(PROGRAM_IR_TEST))
