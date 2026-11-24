# Typed FORGE realization request/lowering/submission boundary (src/forge_realization.om,
# twin of src/forge_realization.c). Pure seeded OM-2, physics-free, host-only.
FORGE_REALIZATION_OM_OMC ?= seed/out/omc
FORGE_REALIZATION_OM_SRCS := seed/ng/sha256.om src/forge_realization.om tests/test_forge_realization.om
FORGE_REALIZATION_OM_TEST = $(OUT_DIR)/test_forge_realization_om

$(FORGE_REALIZATION_OM_TEST): $(FORGE_REALIZATION_OM_SRCS) $(FORGE_REALIZATION_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(FORGE_REALIZATION_OM_SRCS)) | $(FORGE_REALIZATION_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-forge-realization-om
test-forge-realization-om: $(FORGE_REALIZATION_OM_TEST)
	$(abspath $(FORGE_REALIZATION_OM_TEST))
