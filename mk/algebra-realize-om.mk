# Pure seeded OM-2 MA-2 algebra realizations (src/algebra/realize_common.om +
# om/algebra/realize_{binary,bitplane,sparse,rns,dense}.om) and E1 tensor
# reduction seam (src/tensor/omega_tensor_reduce_seam.om +
# src/omega_numeric_reduce.om). Physics-free, host-only, zero GPU access.
ALGEBRA_REALIZE_OM_OMC ?= seed/out/omc

ALGEBRA_REALIZE_OM_SRCS := \
	src/omega_numeric_reduce.om \
	src/tensor/omega_tensor_reduce_seam.om \
	src/algebra/realize_common.om \
	om/algebra/realize_binary.om \
	om/algebra/realize_bitplane.om \
	om/algebra/realize_sparse.om \
	om/algebra/realize_rns.om \
	om/algebra/realize_dense.om \
	tests/algebra/test_algebra_realize_om.om

ALGEBRA_REALIZE_OM_TEST = $(OUT_DIR)/test_algebra_realize_om

$(ALGEBRA_REALIZE_OM_TEST): $(ALGEBRA_REALIZE_OM_SRCS) $(ALGEBRA_REALIZE_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(ALGEBRA_REALIZE_OM_SRCS)) | $(ALGEBRA_REALIZE_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-algebra-realize-om
test-algebra-realize-om: $(ALGEBRA_REALIZE_OM_TEST)
	$(abspath $(ALGEBRA_REALIZE_OM_TEST))
