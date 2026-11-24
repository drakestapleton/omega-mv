# Deterministic program synthesis (bank, equiv table, depth 1..3 search, affine/composed targets) in pure seeded OM-2 (src/omega_synthesis.om, twin of src/omega_synthesis.c).
# Pure seeded OM-2, physics-free, host-only.
OMEGA_SYNTHESIS_OM_OMC ?= seed/out/omc
OMEGA_SYNTHESIS_OM_SRCS := seed/ng/sha256.om om/visor/canonical_om2.om om/aarch64/aarch64_om2.om src/omega_canonical.om src/omega_core.om src/aarch64_encoder.om src/aarch64_decoder.om src/omega_realize.om src/omega_program.om src/omega_synthesis.om tests/test_omega_synthesis.om
OMEGA_SYNTHESIS_OM_TEST = $(OUT_DIR)/test_omega_synthesis_om

$(OMEGA_SYNTHESIS_OM_TEST): $(OMEGA_SYNTHESIS_OM_SRCS) $(OMEGA_SYNTHESIS_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(OMEGA_SYNTHESIS_OM_SRCS)) | $(OMEGA_SYNTHESIS_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-omega-synthesis-om
test-omega-synthesis-om: $(OMEGA_SYNTHESIS_OM_TEST)
	$(abspath $(OMEGA_SYNTHESIS_OM_TEST))
