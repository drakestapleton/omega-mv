# Pure seeded OM-2 runtime wave 5 (rx_seq_reference, rx_plan_arrange, rx_fusion, rx_compose, rx_generation).
# Host-only, no GPU, no physics checkout. Picked up automatically by `-include mk/*.mk`.
RT5_OM_OMC ?= seed/out/omc

RT5_SEQREF_SRCS = src/runtime/rx_seq_reference.om tests/runtime/rx_seq_reference_unit.om
RT5_PLAN_ARRANGE_SRCS = seed/ng/sha256.om src/runtime/rx_graph.om src/runtime/rx_plan.om src/runtime/rx_plan_arrange.om tests/runtime/rx_plan_arrange_unit.om
RT5_FUSION_SRCS = seed/ng/sha256.om src/runtime/rx_graph.om src/runtime/rx_fusion.om tests/runtime/rx_fusion_unit.om
RT5_COMPOSE_SRCS = seed/ng/sha256.om src/runtime/rx_compose.om tests/runtime/rx_compose_unit.om
RT5_GENERATION_SRCS = seed/ng/sha256.om src/runtime/rx_generation.om tests/runtime/rx_generation_unit.om

RT5_SEQREF_BIN = $(OUT_DIR)/rx_seq_reference_unit_om
RT5_PLAN_ARRANGE_BIN = $(OUT_DIR)/rx_plan_arrange_unit_om
RT5_FUSION_BIN = $(OUT_DIR)/rx_fusion_unit_om
RT5_COMPOSE_BIN = $(OUT_DIR)/rx_compose_unit_om
RT5_GENERATION_BIN = $(OUT_DIR)/rx_generation_unit_om

$(RT5_SEQREF_BIN): $(RT5_SEQREF_SRCS) $(RT5_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT5_SEQREF_SRCS) ) | $(RT5_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(RT5_PLAN_ARRANGE_BIN): $(RT5_PLAN_ARRANGE_SRCS) $(RT5_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT5_PLAN_ARRANGE_SRCS) ) | $(RT5_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(RT5_FUSION_BIN): $(RT5_FUSION_SRCS) $(RT5_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT5_FUSION_SRCS) ) | $(RT5_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(RT5_COMPOSE_BIN): $(RT5_COMPOSE_SRCS) $(RT5_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT5_COMPOSE_SRCS) ) | $(RT5_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(RT5_GENERATION_BIN): $(RT5_GENERATION_SRCS) $(RT5_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT5_GENERATION_SRCS) ) | $(RT5_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-seq-reference-om test-plan-arrange-om test-fusion-om test-compose-om test-generation-om test-runtime-om-5
test-seq-reference-om: $(RT5_SEQREF_BIN)
	./$(RT5_SEQREF_BIN)

test-plan-arrange-om: $(RT5_PLAN_ARRANGE_BIN)
	./$(RT5_PLAN_ARRANGE_BIN)

test-fusion-om: $(RT5_FUSION_BIN)
	./$(RT5_FUSION_BIN)

test-compose-om: $(RT5_COMPOSE_BIN)
	./$(RT5_COMPOSE_BIN)

test-generation-om: $(RT5_GENERATION_BIN)
	./$(RT5_GENERATION_BIN)

test-runtime-om-5: test-seq-reference-om test-plan-arrange-om test-fusion-om test-compose-om test-generation-om
