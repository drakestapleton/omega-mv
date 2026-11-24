# OMEGA-NUMERIC-0 host-pure FP32 substrate (src/omega_numeric.om,
# twin of src/omega_numeric.c). Pure seeded OM-2, physics-free, host-only.
NUMERIC_OM_OMC ?= seed/out/omc
NUMERIC_OM_SRCS := om/gpu/bw_vecadd.om om/gpu/bw_qmd.om src/omega_numeric.om tests/test_omega_numeric.om
NUMERIC_OM_TEST = $(OUT_DIR)/test_omega_numeric_om

$(NUMERIC_OM_TEST): $(NUMERIC_OM_SRCS) $(NUMERIC_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(NUMERIC_OM_SRCS)) | $(NUMERIC_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-numeric-om
test-numeric-om: $(NUMERIC_OM_TEST)
	$(abspath $(NUMERIC_OM_TEST))
