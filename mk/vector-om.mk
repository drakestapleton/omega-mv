# Vector spec digest, u32 oracle, and deterministic generator (src/omega_vector.om,
# twin of src/omega_vector.c). Pure seeded OM-2, physics-free, host-only.
VECTOR_OM_OMC ?= seed/out/omc
VECTOR_OM_SRCS := seed/ng/sha256.om src/omega_vector.om tests/test_omega_vector.om
VECTOR_OM_TEST = $(OUT_DIR)/test_omega_vector_om

$(VECTOR_OM_TEST): $(VECTOR_OM_SRCS) $(VECTOR_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed '/^om2$$/d' $(VECTOR_OM_SRCS)) | $(VECTOR_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-vector-om
test-vector-om: $(VECTOR_OM_TEST)
	$(abspath $(VECTOR_OM_TEST))
