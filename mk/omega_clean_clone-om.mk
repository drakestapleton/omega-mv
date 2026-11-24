# Clean-clone path, subprocess, capture, and tree-removal helpers (src/omega_clean_clone.om,
# twin of src/omega_clean_clone.c). Pure seeded OM-2, physics-free, host-only.
OMEGA_CLEAN_CLONE_OM_OMC ?= seed/out/omc
OMEGA_CLEAN_CLONE_OM_SRCS := src/omega_clean_clone.om tests/test_omega_clean_clone.om
OMEGA_CLEAN_CLONE_OM_TEST = $(OUT_DIR)/test_omega_clean_clone_om

$(OMEGA_CLEAN_CLONE_OM_TEST): $(OMEGA_CLEAN_CLONE_OM_SRCS) $(OMEGA_CLEAN_CLONE_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(OMEGA_CLEAN_CLONE_OM_SRCS)) | $(OMEGA_CLEAN_CLONE_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-omega-clean-clone-om
test-omega-clean-clone-om: $(OMEGA_CLEAN_CLONE_OM_TEST)
	$(abspath $(OMEGA_CLEAN_CLONE_OM_TEST))
