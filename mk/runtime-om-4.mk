# Pure seeded OM-2 runtime wave 4 (rx_argus, rx_coherent, rx_contract, rx_operator, rx_route, rx_semantic).
# Host-only, no GPU, no physics checkout. Picked up automatically by `-include mk/*.mk`.
RT4_OM_OMC ?= seed/out/omc

RT4_ARGUS_SRCS = seed/ng/sha256.om src/runtime/rx_argus.om tests/runtime/rx_argus_unit.om
RT4_COHERENT_SRCS = src/runtime/rx_coherent.om tests/runtime/rx_coherent_unit.om
RT4_CONTRACT_SRCS = seed/ng/sha256.om src/runtime/rx_contract.om tests/runtime/rx_contract_unit.om
RT4_OPERATOR_SRCS = src/runtime/rx_operator.om tests/runtime/rx_operator_unit.om
RT4_ROUTE_SRCS = seed/ng/sha256.om src/runtime/rx_route.om tests/runtime/rx_route_unit.om
RT4_SEMANTIC_SRCS = seed/ng/sha256.om src/runtime/rx_semantic.om tests/runtime/rx_semantic_unit.om

RT4_ARGUS_BIN = $(OUT_DIR)/rx_argus_unit_om
RT4_COHERENT_BIN = $(OUT_DIR)/rx_coherent_unit_om
RT4_CONTRACT_BIN = $(OUT_DIR)/rx_contract_unit_om
RT4_OPERATOR_BIN = $(OUT_DIR)/rx_operator_unit_om
RT4_ROUTE_BIN = $(OUT_DIR)/rx_route_unit_om
RT4_SEMANTIC_BIN = $(OUT_DIR)/rx_semantic_unit_om

$(RT4_ARGUS_BIN): $(RT4_ARGUS_SRCS) $(RT4_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT4_ARGUS_SRCS) ) | $(RT4_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(RT4_COHERENT_BIN): $(RT4_COHERENT_SRCS) $(RT4_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT4_COHERENT_SRCS) ) | $(RT4_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(RT4_CONTRACT_BIN): $(RT4_CONTRACT_SRCS) $(RT4_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT4_CONTRACT_SRCS) ) | $(RT4_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(RT4_OPERATOR_BIN): $(RT4_OPERATOR_SRCS) $(RT4_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT4_OPERATOR_SRCS) ) | $(RT4_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(RT4_ROUTE_BIN): $(RT4_ROUTE_SRCS) $(RT4_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT4_ROUTE_SRCS) ) | $(RT4_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(RT4_SEMANTIC_BIN): $(RT4_SEMANTIC_SRCS) $(RT4_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT4_SEMANTIC_SRCS) ) | $(RT4_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-argus-om test-coherent-om test-contract-om test-operator-om test-route-om test-semantic-om test-runtime-om-4
test-argus-om: $(RT4_ARGUS_BIN)
	./$(RT4_ARGUS_BIN)

test-coherent-om: $(RT4_COHERENT_BIN)
	./$(RT4_COHERENT_BIN)

test-contract-om: $(RT4_CONTRACT_BIN)
	./$(RT4_CONTRACT_BIN)

test-operator-om: $(RT4_OPERATOR_BIN)
	./$(RT4_OPERATOR_BIN)

test-route-om: $(RT4_ROUTE_BIN)
	./$(RT4_ROUTE_BIN)

test-semantic-om: $(RT4_SEMANTIC_BIN)
	./$(RT4_SEMANTIC_BIN)

test-runtime-om-4: test-argus-om test-coherent-om test-contract-om test-operator-om test-route-om test-semantic-om
