# ESTIMATION v6 pre-freeze development tools (docs/estimation/protocols/est-v6.md section 9,
# appendix docs/estimation/protocols/est-v6-appendix-prefreeze.md). Pure seeded OM-2.
# Development tools only: not the v6 tool, no protocol identity, no binding mode.
# Picked up by `-include mk/*.mk`; not part of `all` or `test`.
#
# est6dev            G1 PIT / miss-rate / block-bootstrap analysis, reduced G1S check, schedule and seed balance
# est6opchar         operating-characteristics simulation (reads no data file)
# test-est6dev       tests for both (D1 development data and synthetic only; held-out refusals)
# est6-opchar-table  prints the appendix operating-characteristics table (about 3 minutes)
# est6-opchar-table2 prints the appendix section 5b SIMULATION table (regime case, replication, false accept)
ifndef ESTIMATION_V6DEV_MK
ESTIMATION_V6DEV_MK := 1
include mk/estimation_v4.mk
.PHONY: est6dev est6opchar test-est6dev est6-opchar-table est6-opchar-table2
ESTV6D_DIR = $(OUT_DIR)/estimation-v6dev
ESTV6D_OM_LIB = $(ESTT_OM_LIB) tools/estimation/est3c_common.om
$(ESTV6D_DIR)/est6dev: $(ESTV6D_OM_LIB) tools/estimation/est6dev.om $(EST_OMC)
	@mkdir -p $(ESTV6D_DIR)
	cat $(ESTV6D_OM_LIB) tools/estimation/est6dev.om | $(EST_OMC) > $@ && chmod +x $@
$(ESTV6D_DIR)/est6opchar: src/estimation/est_math.om tools/estimation/est6opchar.om $(EST_OMC)
	@mkdir -p $(ESTV6D_DIR)
	(echo om2; cat src/estimation/est_math.om tools/estimation/est6opchar.om) | $(EST_OMC) > $@ && chmod +x $@
est6dev: $(ESTV6D_DIR)/est6dev
est6opchar: $(ESTV6D_DIR)/est6opchar
test-est6dev: $(ESTV6D_DIR)/est6dev $(ESTV6D_DIR)/est6opchar
	sh tools/estimation/test_est6dev.sh $(ESTV6D_DIR)/est6dev $(ESTV6D_DIR)/est6opchar
est6-opchar-table: $(ESTV6D_DIR)/est6opchar
	sh tools/estimation/est6opchar_table.sh $(ESTV6D_DIR)/est6opchar 4000
est6-opchar-table2: $(ESTV6D_DIR)/est6opchar
	sh tools/estimation/est6opchar_table2.sh $(ESTV6D_DIR)/est6opchar 20000
endif
