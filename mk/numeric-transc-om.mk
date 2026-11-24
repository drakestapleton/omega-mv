# E1 WP-B frozen FP32 transcendental sequences (src/omega_numeric_transc.om,
# twin of src/omega_numeric_transc.c). Pure seeded OM-2, physics-free, host-only.
NUMERIC_TRANSC_OM_OMC ?= seed/out/omc
NUMERIC_TRANSC_OM_SRCS := src/omega_numeric_transc.om tests/test_omega_numeric_transc.om
NUMERIC_TRANSC_OM_TEST = $(OUT_DIR)/test_omega_numeric_transc_om

$(NUMERIC_TRANSC_OM_TEST): $(NUMERIC_TRANSC_OM_SRCS) $(NUMERIC_TRANSC_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(NUMERIC_TRANSC_OM_SRCS)) | $(NUMERIC_TRANSC_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-numeric-transc-om
test-numeric-transc-om: $(NUMERIC_TRANSC_OM_TEST)
	$(abspath $(NUMERIC_TRANSC_OM_TEST))
