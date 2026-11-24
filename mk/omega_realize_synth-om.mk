# Machine-aware realization synthesis (G_S x G_M -> G_R) in pure seeded OM-2 (src/omega_realize_synth.om, twin of src/omega_realize_synth.c).
# Pure seeded OM-2, physics-free, host-only.
OMEGA_REALIZE_SYNTH_OM_OMC ?= seed/out/omc
OMEGA_REALIZE_SYNTH_OM_SRCS := seed/ng/sha256.om om/visor/canonical_om2.om om/aarch64/aarch64_om2.om src/omega_canonical.om src/omega_core.om src/aarch64_encoder.om src/aarch64_decoder.om src/omega_realize.om src/omega_machine.om src/omega_program.om src/omega_realize_synth.om tests/test_omega_realize_synth.om
OMEGA_REALIZE_SYNTH_OM_TEST = $(OUT_DIR)/test_omega_realize_synth_om

$(OMEGA_REALIZE_SYNTH_OM_TEST): $(OMEGA_REALIZE_SYNTH_OM_SRCS) $(OMEGA_REALIZE_SYNTH_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(OMEGA_REALIZE_SYNTH_OM_SRCS)) | $(OMEGA_REALIZE_SYNTH_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-omega-realize-synth-om
test-omega-realize-synth-om: $(OMEGA_REALIZE_SYNTH_OM_TEST)
	$(abspath $(OMEGA_REALIZE_SYNTH_OM_TEST))
