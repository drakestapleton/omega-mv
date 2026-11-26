# ---------------------------------------------------------------------------
# COMPOSITION-2 host ABI facade in pure seeded OM-2 (src/runtime/rxc_host_abi.om,
# src/runtime/rx_compose.om, tests/runtime/rxc_host_abi_test.om,
# tests/runtime/rxc_host_abi_unit.om). Zero C, zero external authority archive.
# ---------------------------------------------------------------------------
ifndef RX_COMPOSE_LIB_MK_LOADED
RX_COMPOSE_LIB_MK_LOADED := 1

.PHONY: rx-compose-lib test-rxc-host-abi

RXC_HOST_ABI_OMC ?= seed/out/omc
RXC_HOST_ABI_TEST = $(OUT_DIR)/rxc_host_abi_test_om

rx-compose-lib: $(RXC_HOST_ABI_TEST) test-rxc-host-abi-unit-om
	@echo "rx-compose-lib: pure seeded OM-2 composition host ABI verified"

test-rxc-host-abi: $(RXC_HOST_ABI_TEST) test-rxc-host-abi-unit-om
	./$(RXC_HOST_ABI_TEST)

endif
