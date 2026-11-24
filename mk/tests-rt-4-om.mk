# Pure seeded OM-2 runtime test wave 4 (10 CPU-only host suites).
# Host-only, no GPU, no physics checkout. Picked up automatically by `-include mk/*.mk`.
TRT4_OM_OMC ?= seed/out/omc
OUT_DIR ?= build

TRT4_AG_SRCS   = seed/ng/sha256.om src/runtime/rx_graph.om tests/runtime/rx_action_graph.om
TRT4_CQ_SRCS   = seed/ng/sha256.om om/runtime/rx_mid.om om/runtime/rx_capq_core.om src/runtime/rx_graph.om src/runtime/rx_capq.om tests/runtime/rx_capability_query.om
TRT4_SC_SRCS   = seed/ng/sha256.om src/runtime/rx_semcomm.om tests/runtime/rx_semantic_comm.om
TRT4_CR_SRCS   = seed/ng/sha256.om src/runtime/rx_route.om tests/runtime/rx_cognitive_routing.om
TRT4_SP_SRCS   = seed/ng/sha256.om src/runtime/rx_cortex.om src/runtime/rx_projection.om tests/runtime/rx_state_projection.om
TRT4_WF_SRCS   = seed/ng/sha256.om src/runtime/rx_graph.om src/runtime/rx_fusion.om tests/runtime/rx_workflow_fusion.om
TRT4_SI_SRCS   = seed/ng/sha256.om src/runtime/rx_semantic.om tests/runtime/rx_sem_incremental.om
TRT4_TR_SRCS   = seed/ng/sha256.om src/runtime/rx_contract.om tests/runtime/rx_typed_results.om
TRT4_EO_SRCS   = seed/ng/sha256.om src/runtime/rx_costmodel.om tests/runtime/rx_empirical_optimizer.om
TRT4_R15P_SRCS = src/runtime/rx_seq_reference.om tests/runtime/rx_r15_parity.om

TRT4_AG_BIN   = $(OUT_DIR)/rx_action_graph_om
TRT4_CQ_BIN   = $(OUT_DIR)/rx_capability_query_om
TRT4_SC_BIN   = $(OUT_DIR)/rx_semantic_comm_om
TRT4_CR_BIN   = $(OUT_DIR)/rx_cognitive_routing_om
TRT4_SP_BIN   = $(OUT_DIR)/rx_state_projection_om
TRT4_WF_BIN   = $(OUT_DIR)/rx_workflow_fusion_om
TRT4_SI_BIN   = $(OUT_DIR)/rx_sem_incremental_om
TRT4_TR_BIN   = $(OUT_DIR)/rx_typed_results_om
TRT4_EO_BIN   = $(OUT_DIR)/rx_empirical_optimizer_om
TRT4_R15P_BIN = $(OUT_DIR)/rx_r15_parity_om

$(TRT4_AG_BIN): $(TRT4_AG_SRCS) $(TRT4_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT4_AG_SRCS) ) | $(TRT4_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT4_CQ_BIN): $(TRT4_CQ_SRCS) $(TRT4_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT4_CQ_SRCS) ) | $(TRT4_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT4_SC_BIN): $(TRT4_SC_SRCS) $(TRT4_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT4_SC_SRCS) ) | $(TRT4_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT4_CR_BIN): $(TRT4_CR_SRCS) $(TRT4_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT4_CR_SRCS) ) | $(TRT4_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT4_SP_BIN): $(TRT4_SP_SRCS) $(TRT4_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT4_SP_SRCS) ) | $(TRT4_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT4_WF_BIN): $(TRT4_WF_SRCS) $(TRT4_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT4_WF_SRCS) ) | $(TRT4_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT4_SI_BIN): $(TRT4_SI_SRCS) $(TRT4_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT4_SI_SRCS) ) | $(TRT4_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT4_TR_BIN): $(TRT4_TR_SRCS) $(TRT4_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT4_TR_SRCS) ) | $(TRT4_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT4_EO_BIN): $(TRT4_EO_SRCS) $(TRT4_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT4_EO_SRCS) ) | $(TRT4_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TRT4_R15P_BIN): $(TRT4_R15P_SRCS) $(TRT4_OM_OMC)
	@mkdir -p $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRT4_R15P_SRCS) ) | $(TRT4_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-rx-action-graph-om test-rx-capability-query-om \
	test-rx-semantic-comm-om test-rx-cognitive-routing-om \
	test-rx-state-projection-om test-rx-workflow-fusion-om \
	test-rx-sem-incremental-om test-rx-typed-results-om \
	test-rx-empirical-optimizer-om test-rx-r15-parity-om \
	test-tests-rt-4-om

test-rx-action-graph-om: $(TRT4_AG_BIN)
	$(TRT4_AG_BIN)

test-rx-capability-query-om: $(TRT4_CQ_BIN)
	$(TRT4_CQ_BIN)

test-rx-semantic-comm-om: $(TRT4_SC_BIN)
	$(TRT4_SC_BIN)

test-rx-cognitive-routing-om: $(TRT4_CR_BIN)
	$(TRT4_CR_BIN)

test-rx-state-projection-om: $(TRT4_SP_BIN)
	$(TRT4_SP_BIN)

test-rx-workflow-fusion-om: $(TRT4_WF_BIN)
	$(TRT4_WF_BIN)

test-rx-sem-incremental-om: $(TRT4_SI_BIN)
	$(TRT4_SI_BIN)

test-rx-typed-results-om: $(TRT4_TR_BIN)
	$(TRT4_TR_BIN)

test-rx-empirical-optimizer-om: $(TRT4_EO_BIN)
	$(TRT4_EO_BIN)

test-rx-r15-parity-om: $(TRT4_R15P_BIN)
	$(TRT4_R15P_BIN)

test-tests-rt-4-om: test-rx-action-graph-om test-rx-capability-query-om \
	test-rx-semantic-comm-om test-rx-cognitive-routing-om \
	test-rx-state-projection-om test-rx-workflow-fusion-om \
	test-rx-sem-incremental-om test-rx-typed-results-om \
	test-rx-empirical-optimizer-om test-rx-r15-parity-om
