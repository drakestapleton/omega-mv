# Program realization V0 (spec/program-realization.md). Pure seeded OM-2, physics-free, host-only.
PROGRAM_REALIZE_OMC ?= seed/out/omc
PROGRAM_REALIZE_OM_SRCS := seed/ng/sha256.om om/aarch64/aarch64_om2.om src/omega_realize.om src/omega_exec.om tests/realize/test_program_realize.om
PROGRAM_REALIZE_TEST = $(OUT_DIR)/tests-realize/test_program_realize

$(PROGRAM_REALIZE_TEST): $(PROGRAM_REALIZE_OM_SRCS) $(PROGRAM_REALIZE_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(PROGRAM_REALIZE_OM_SRCS)) | $(PROGRAM_REALIZE_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-program-realize
test-program-realize: $(PROGRAM_REALIZE_TEST)
	$(abspath $(PROGRAM_REALIZE_TEST))
