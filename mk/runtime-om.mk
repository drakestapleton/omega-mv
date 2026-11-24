# Pure seeded OM-2 runtime waves 1 & 2:
#   wave 1: rx_costmodel, rx_cortex, rx_projection, rx_regulate
#   wave 2: rx_caproot, rx_graph, rx_capq, rx_skillroute, rx_jspace
# Host-only, no GPU, no physics checkout. Picked up automatically by `-include mk/*.mk`.
RT_OM_OMC ?= seed/out/omc

RT_OM_CM_SRCS = seed/ng/sha256.om src/runtime/rx_costmodel.om tests/runtime/rx_costmodel_unit.om
RT_OM_CXJ_SRCS = seed/ng/sha256.om src/runtime/rx_cortex.om tests/runtime/rx_cortex_journal.om
RT_OM_PJ_SRCS = seed/ng/sha256.om src/runtime/rx_cortex.om src/runtime/rx_projection.om tests/runtime/rx_projection_unit.om
RT_OM_REG_SRCS = src/runtime/rx_regulate.om tests/runtime/rx_regulate_unit.om

RT_OM_CAPROOT_SRCS = seed/authority/cap_table_om2.om src/runtime/rx_caproot.om tests/runtime/rx_caproot_unit.om
RT_OM_GRAPH_SRCS = seed/ng/sha256.om src/runtime/rx_graph.om tests/runtime/rx_graph_unit.om
RT_OM_CAPQ_SRCS = seed/ng/sha256.om om/runtime/rx_mid.om om/runtime/rx_capq_core.om src/runtime/rx_graph.om src/runtime/rx_capq.om tests/runtime/rx_capq_unit.om
RT_OM_SR_SRCS = seed/ng/sha256.om om/runtime/rx_mid.om om/runtime/rx_capq_core.om om/runtime/rx_skillroute_core.om src/runtime/rx_graph.om src/runtime/rx_capq.om src/runtime/rx_skillroute.om tests/runtime/rx_skillroute_unit.om
RT_OM_JSPACE_SRCS = seed/ng/sha256.om src/runtime/rx_jspace.om tests/runtime/rx_jspace_unit.om

RT_OM_CXJ_TEST = $(OUT_DIR)/rx_cortex_journal_test
RT_OM_PJ_UNIT = $(OUT_DIR)/rx_projection_unit_om
RT_OM_REG_UNIT = $(OUT_DIR)/rx_regulate_unit_om
RT_OM_CAPROOT_UNIT = $(OUT_DIR)/rx_caproot_unit_om
RT_OM_GRAPH_UNIT = $(OUT_DIR)/rx_graph_unit_om
RT_OM_CAPQ_UNIT = $(OUT_DIR)/rx_capq_unit_om
RT_OM_SR_UNIT = $(OUT_DIR)/rx_skillroute_unit_om
RT_OM_JSPACE_UNIT = $(OUT_DIR)/rx_jspace_unit_om

$(RT_OM_PJ_UNIT): $(RT_OM_PJ_SRCS) $(RT_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT_OM_PJ_SRCS) ) | $(RT_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(RT_OM_REG_UNIT): $(RT_OM_REG_SRCS) $(RT_OM_OMC) | $(OUT_DIR)
	( echo om2; cat $(RT_OM_REG_SRCS) ) | $(RT_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(RT_OM_CAPROOT_UNIT): $(RT_OM_CAPROOT_SRCS) $(RT_OM_OMC) | $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(RT_OM_CAPROOT_SRCS) ) | $(RT_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(RT_OM_GRAPH_UNIT): $(RT_OM_GRAPH_SRCS) $(RT_OM_OMC) | $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(RT_OM_GRAPH_SRCS) ) | $(RT_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(RT_OM_CAPQ_UNIT): $(RT_OM_CAPQ_SRCS) $(RT_OM_OMC) | $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(RT_OM_CAPQ_SRCS) ) | $(RT_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(RT_OM_SR_UNIT): $(RT_OM_SR_SRCS) $(RT_OM_OMC) | $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(RT_OM_SR_SRCS) ) | $(RT_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(RT_OM_JSPACE_UNIT): $(RT_OM_JSPACE_SRCS) $(RT_OM_OMC) | $(OUT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(RT_OM_JSPACE_SRCS) ) | $(RT_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-projection-om test-regulate-om test-cortex-journal-om \
	test-caproot-om test-graph-om test-capq-om test-skillroute-om test-jspace-om \
	test-runtime-om

test-projection-om: $(RT_OM_PJ_UNIT)
	./$(RT_OM_PJ_UNIT)

test-regulate-om: $(RT_OM_REG_UNIT)
	./$(RT_OM_REG_UNIT)

test-cortex-journal-om: $(RT_OM_CXJ_TEST)
	./$(RT_OM_CXJ_TEST)

test-caproot-om: $(RT_OM_CAPROOT_UNIT)
	./$(RT_OM_CAPROOT_UNIT)

test-graph-om: $(RT_OM_GRAPH_UNIT)
	./$(RT_OM_GRAPH_UNIT)

test-capq-om: $(RT_OM_CAPQ_UNIT)
	./$(RT_OM_CAPQ_UNIT)

test-skillroute-om: $(RT_OM_SR_UNIT)
	./$(RT_OM_SR_UNIT)

test-jspace-om: $(RT_OM_JSPACE_UNIT)
	./$(RT_OM_JSPACE_UNIT)

test-runtime-om: test-costmodel test-projection-om test-regulate-om test-cortex-journal-om \
	test-caproot-om test-graph-om test-capq-om test-skillroute-om test-jspace-om
