# ALLEN bindings (src/allen/allen_bind.om, twin of src/allen/allen_bind.c).
# Pure seeded OM-2, physics-free, host-only.
ALLEN_BIND_OM_OMC ?= seed/out/omc
ALLEN_BIND_OM_SRCS := seed/ng/sha256.om src/allen/allen_core.om src/allen/allen_bind.om tests/test_allen_bind.om
ALLEN_BIND_OM_TEST = $(OUT_DIR)/test_allen_bind_om

$(ALLEN_BIND_OM_TEST): $(ALLEN_BIND_OM_SRCS) $(ALLEN_BIND_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(ALLEN_BIND_OM_SRCS)) | $(ALLEN_BIND_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-allen-bind-om
test-allen-bind-om: $(ALLEN_BIND_OM_TEST)
	$(abspath $(ALLEN_BIND_OM_TEST))
