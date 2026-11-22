# DUAL, constraint pricing for soft resource budgets (ADR 0031 / ARCH-0031).
# Standalone pure seeded OM-2 module: src/dual/rx_dual.om + tests/dual/test_dual_*.om.
# Picked up by `-include mk/*.mk`; not part of `all` or `test`. Nothing in
# src/runtime/ includes or links it. DUAL is scarcity information: it never
# authorizes, never promotes, never decides validity.
#
# test-dual-types    DUAL-0a contract: validation, refusal, canonical encoding, digests, properties
# test-dual-bind     DUAL-0b binding to ESTIMATION records and freshness classification
# test-dual-update   DUAL-1a reference price update: analytic, property and refusal checks
# test-dual-replay   DUAL-1b deterministic replay, golden digests, R15 recorded CSV traces, negative control
# dual-purity        source scan of src/dual/rx_dual.om against authority / promotion / process symbols
# test-dual          everything above
ifndef DUAL_MK
DUAL_MK := 1
.PHONY: test-dual-types test-dual-bind test-dual-update test-dual-replay dual-purity test-dual
OMC ?= seed/out/omc
DUAL_DIR = $(OUT_DIR)/tests-dual
DUAL_OM = src/dual/rx_dual.om
# A price is information, not authority: no capability, promotion, generation
# administration, World, ARGUS, AEGIS, memory-mapping or process symbol.
DUAL_FORBIDDEN = 'aienos_|rx_gen_|rx_cap|rx_world|rx_js|argus_|forge_|aegis|mmap|mprotect|fork|exec|dlopen|system|socket|fopen|\bopen\b'

dual-purity: $(DUAL_OM)
	@if sed -E '/^[[:space:]]*note([[:space:]].*)?$$/d' $(DUAL_OM) | grep -E $(DUAL_FORBIDDEN) ; then \
		echo "dual module references an operation a pricing module must not have"; exit 1; fi
	@echo "dual-purity: $(DUAL_OM) references no authority, promotion or process symbol"

$(DUAL_DIR)/test_dual_types: $(DUAL_OM) tests/dual/test_dual_types.om
	@mkdir -p $(DUAL_DIR)
	cat $(DUAL_OM) tests/dual/test_dual_types.om > $(DUAL_DIR)/test_dual_types.om
	$(OMC) < $(DUAL_DIR)/test_dual_types.om > $@
	chmod +x $@

$(DUAL_DIR)/test_dual_bind: $(DUAL_OM) tests/dual/test_dual_bind.om
	@mkdir -p $(DUAL_DIR)
	cat $(DUAL_OM) tests/dual/test_dual_bind.om > $(DUAL_DIR)/test_dual_bind.om
	$(OMC) < $(DUAL_DIR)/test_dual_bind.om > $@
	chmod +x $@

$(DUAL_DIR)/test_dual_update: $(DUAL_OM) tests/dual/test_dual_update.om
	@mkdir -p $(DUAL_DIR)
	cat $(DUAL_OM) tests/dual/test_dual_update.om > $(DUAL_DIR)/test_dual_update.om
	$(OMC) < $(DUAL_DIR)/test_dual_update.om > $@
	chmod +x $@

$(DUAL_DIR)/test_dual_replay: $(DUAL_OM) tests/dual/test_dual_replay.om
	@mkdir -p $(DUAL_DIR)
	cat $(DUAL_OM) tests/dual/test_dual_replay.om > $(DUAL_DIR)/test_dual_replay.om
	$(OMC) < $(DUAL_DIR)/test_dual_replay.om > $@
	chmod +x $@

test-dual-types: $(DUAL_DIR)/test_dual_types
	./$(DUAL_DIR)/test_dual_types
	@echo "test-dual-types: DUAL-0a contract checks pass (pure seeded OM-2)"

test-dual-bind: $(DUAL_DIR)/test_dual_bind
	./$(DUAL_DIR)/test_dual_bind
	@echo "test-dual-bind: DUAL-0b binding and staleness checks pass (pure seeded OM-2)"

test-dual-update: $(DUAL_DIR)/test_dual_update
	./$(DUAL_DIR)/test_dual_update
	@echo "test-dual-update: DUAL-1a reference update passes analytic, property and refusal checks (pure seeded OM-2)"

test-dual-replay: $(DUAL_DIR)/test_dual_replay
	./$(DUAL_DIR)/test_dual_replay
	@echo "test-dual-replay: DUAL-1b replay, pre-registered measures and negative control pass (pure seeded OM-2, all inputs UNCALIBRATED)"

test-dual: dual-purity test-dual-types test-dual-bind test-dual-update test-dual-replay
	@echo "test-dual: DUAL standalone module passes"
endif
