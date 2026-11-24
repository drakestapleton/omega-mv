# Verified OSC driver (VC1 stage 4, ADR 0029) path, metadata, build_id, and store check
# (src/oscv_main.om, twin of src/oscv_main.c). Pure seeded OM-2, physics-free, host-only.
OSCV_MAIN_OM_OMC ?= seed/out/omc
OSCV_MAIN_OM_SRCS := seed/ng/sha256.om src/omega_vcstore.om src/oscv_main.om tests/test_oscv_main.om
OSCV_MAIN_OM_TEST = $(OUT_DIR)/test_oscv_main_om

$(OSCV_MAIN_OM_TEST): $(OSCV_MAIN_OM_SRCS) $(OSCV_MAIN_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(OSCV_MAIN_OM_SRCS)) | $(OSCV_MAIN_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-oscv-main-om
test-oscv-main-om: $(OSCV_MAIN_OM_TEST)
	$(abspath $(OSCV_MAIN_OM_TEST))
