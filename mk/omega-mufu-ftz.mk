# MUFU flush rule (omega #462): the GB10 MUFU unit (EX2 / RCP / RSQ) flushes a subnormal input or result to a
# sign-preserving zero. Cut over to pure seeded OM-2 (tests/test_bw_mufu_ftz.om, built as
# $(OUT_DIR)/test_bw_mufu_ftz_om in mk/tests-root-1-om.mk). Host only: opens no device, needs no physics headers,
# takes no chip lock.
.PHONY: test-mufu-ftz
test-mufu-ftz: $(OUT_DIR)/test_bw_mufu_ftz_om
	./$(OUT_DIR)/test_bw_mufu_ftz_om
	@echo "test-mufu-ftz: PASS (pure OM-2 helper + 22 MUFU EX2/RCP/RSQ cases)"
