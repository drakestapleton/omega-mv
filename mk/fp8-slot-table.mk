# Host-only FP8 Expert Ribbon slot state machine (src/omega_fp8_slot_table.om,
# twin of src/omega_fp8_slot_table.c). Pure seeded OM-2, physics-free, host-only.
FP8_SLOT_TABLE_OMC ?= seed/out/omc
FP8_SLOT_TABLE_OM_SRCS := src/omega_fp8_slot_table.om tests/test_omega_fp8_slot_table.om
FP8_SLOT_TABLE_OM_TEST = $(OUT_DIR)/test_omega_fp8_slot_table_om

$(FP8_SLOT_TABLE_OM_TEST): $(FP8_SLOT_TABLE_OM_SRCS) $(FP8_SLOT_TABLE_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed '/^om2$$/d' $(FP8_SLOT_TABLE_OM_SRCS)) | $(FP8_SLOT_TABLE_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-fp8-slot-table-om
test-fp8-slot-table-om: $(FP8_SLOT_TABLE_OM_TEST)
	$(abspath $(FP8_SLOT_TABLE_OM_TEST))
