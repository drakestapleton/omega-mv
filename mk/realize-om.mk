# Realization ID and AArch64 binary realization emitters (src/omega_realize.om,
# twin of src/omega_realize.c). Pure seeded OM-2, physics-free, host-only.
REALIZE_OM_OMC ?= seed/out/omc
REALIZE_OM_SRCS := seed/ng/sha256.om om/aarch64/aarch64_om2.om src/omega_realize.om tests/test_omega_realize.om
REALIZE_OM_TEST = $(OUT_DIR)/test_omega_realize_om

$(REALIZE_OM_TEST): $(REALIZE_OM_SRCS) $(REALIZE_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(REALIZE_OM_SRCS)) | $(REALIZE_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-realize-om
test-realize-om: $(REALIZE_OM_TEST)
	$(abspath $(REALIZE_OM_TEST))
