# Program identity v2 (spec/program-identity.md). Pure seeded OM-2 (tests/program/test_program_id.om).
PROGRAM_ID_TEST = $(OUT_DIR)/tests-program/test_program_id

$(PROGRAM_ID_TEST): tests/program/test_program_id.om seed/out/omc
	@mkdir -p $(dir $@)
	seed/out/omc < tests/program/test_program_id.om > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-program-id
test-program-id: $(PROGRAM_ID_TEST)
	./$(PROGRAM_ID_TEST)
