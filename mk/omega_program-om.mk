# Program identity v2, realization, lifting, evaluation, composition & task eval in pure seeded OM-2 (src/omega_program.om, twin of src/omega_program.c).
# Pure seeded OM-2, physics-free, host-only.
OMEGA_PROGRAM_OM_OMC ?= seed/out/omc
OMEGA_PROGRAM_OM_SRCS := seed/ng/sha256.om om/visor/canonical_om2.om om/aarch64/aarch64_om2.om src/omega_canonical.om src/omega_core.om src/aarch64_encoder.om src/aarch64_decoder.om src/omega_realize.om src/omega_program.om tests/test_omega_program.om
OMEGA_PROGRAM_OM_TEST = $(OUT_DIR)/test_omega_program_om

$(OMEGA_PROGRAM_OM_TEST): $(OMEGA_PROGRAM_OM_SRCS) $(OMEGA_PROGRAM_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(OMEGA_PROGRAM_OM_SRCS)) | $(OMEGA_PROGRAM_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-omega-program-om
test-omega-program-om: $(OMEGA_PROGRAM_OM_TEST)
	$(abspath $(OMEGA_PROGRAM_OM_TEST))
