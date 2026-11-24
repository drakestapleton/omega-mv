# SM121 numeric opcode provenance table & cross-check verifier
# (src/omega_numeric_provenance.om, twin of src/omega_numeric_provenance.c).
# Pure seeded OM-2, physics-free, host-only.
NUMERIC_PROV_OM_OMC ?= seed/out/omc
NUMERIC_PROV_OM_SRCS := om/gpu/bw_vecadd.om om/gpu/bw_qmd.om src/omega_numeric.om src/omega_numeric_provenance.om tests/test_omega_numeric_provenance.om
NUMERIC_PROV_OM_TEST = $(OUT_DIR)/test_omega_numeric_provenance_om

$(NUMERIC_PROV_OM_TEST): $(NUMERIC_PROV_OM_SRCS) $(NUMERIC_PROV_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(NUMERIC_PROV_OM_SRCS)) | $(NUMERIC_PROV_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-numeric-provenance-om
test-numeric-provenance-om: $(NUMERIC_PROV_OM_TEST)
	$(abspath $(NUMERIC_PROV_OM_TEST))
