# Run-evidence plumbing in pure seeded OM-2 (src/omega_evidence.om, twin of src/omega_evidence.c).
# Pure seeded OM-2, physics-free, host-only.
OMEGA_EVIDENCE_OM_OMC ?= seed/out/omc
OMEGA_EVIDENCE_OM_SRCS := seed/ng/sha256.om src/omega_evidence.om tests/test_omega_evidence.om
OMEGA_EVIDENCE_OM_TEST = $(OUT_DIR)/test_omega_evidence_om

$(OMEGA_EVIDENCE_OM_TEST): $(OMEGA_EVIDENCE_OM_SRCS) $(OMEGA_EVIDENCE_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(OMEGA_EVIDENCE_OM_SRCS)) | $(OMEGA_EVIDENCE_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-omega-evidence-om
test-omega-evidence-om: $(OMEGA_EVIDENCE_OM_TEST)
	$(abspath $(OMEGA_EVIDENCE_OM_TEST))
