# Static sm_121 scoreboard hazard checker (src/omega_bw_hazard.om,
# twin of src/omega_bw_hazard.c). Pure seeded OM-2, physics-free, host-only.
BW_HAZARD_OM_OMC ?= seed/out/omc
BW_HAZARD_OM_SRCS := src/omega_bw_hazard.om tests/test_omega_bw_hazard.om
BW_HAZARD_OM_TEST = $(OUT_DIR)/test_omega_bw_hazard_om

$(BW_HAZARD_OM_TEST): $(BW_HAZARD_OM_SRCS) $(BW_HAZARD_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed '/^om2$$/d' $(BW_HAZARD_OM_SRCS)) | $(BW_HAZARD_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-bw-hazard-om
test-bw-hazard-om: $(BW_HAZARD_OM_TEST)
	$(abspath $(BW_HAZARD_OM_TEST))
