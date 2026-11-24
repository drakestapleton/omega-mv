# E1 WP-D frozen-order FP32 reductions (src/omega_numeric_reduce.om,
# twin of src/omega_numeric_reduce.c). Pure seeded OM-2, physics-free, host-only.
NUMERIC_REDUCE_OM_OMC ?= seed/out/omc
NUMERIC_REDUCE_OM_SRCS := src/omega_numeric_reduce.om tests/test_omega_numeric_reduce.om
NUMERIC_REDUCE_OM_TEST = $(OUT_DIR)/test_omega_numeric_reduce_om

$(NUMERIC_REDUCE_OM_TEST): $(NUMERIC_REDUCE_OM_SRCS) $(NUMERIC_REDUCE_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed '/^om2$$/d' $(NUMERIC_REDUCE_OM_SRCS)) | $(NUMERIC_REDUCE_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-numeric-reduce-om
test-numeric-reduce-om: $(NUMERIC_REDUCE_OM_TEST)
	$(abspath $(NUMERIC_REDUCE_OM_TEST))
