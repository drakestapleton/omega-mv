# Content-addressed verified program library (src/omega_library.om, twin of src/omega_library.c).
# Pure seeded OM-2, physics-free, host-only.
OMEGA_LIBRARY_OM_OMC ?= seed/out/omc
OMEGA_LIBRARY_OM_SRCS := seed/ng/sha256.om src/omega_library.om tests/test_omega_library.om
OMEGA_LIBRARY_OM_TEST = $(OUT_DIR)/test_omega_library_om

$(OMEGA_LIBRARY_OM_TEST): $(OMEGA_LIBRARY_OM_SRCS) $(OMEGA_LIBRARY_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(OMEGA_LIBRARY_OM_SRCS)) | $(OMEGA_LIBRARY_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-omega-library-om
test-omega-library-om: $(OMEGA_LIBRARY_OM_TEST)
	$(abspath $(OMEGA_LIBRARY_OM_TEST))
