# EST-3c protocol v3 tools: est3c_fit, est3c_eval, est3c_forensics, est_load and their tests
# (docs/estimation/EST3C_PROTOCOL_V3.md). Pure seeded OM-2. Not part of `all` or `test`.
ifndef ESTIMATION_V3_TOOLS_MK
ESTIMATION_V3_TOOLS_MK := 1
include mk/estimation_tools.mk
.PHONY: est3c-fit est3c-eval est3c-forensics est-load test-est3c-tools est3c-tools-force
ESTV3T_DIR = $(OUT_DIR)/est3c-tools
ESTV3T_OM_LIB = $(ESTT_OM_LIB) tools/estimation/est3c_common.om
# Tool identity baked in at build time via generated toolid.om
ESTV3T_COMMIT := $(shell git rev-parse HEAD 2>/dev/null || echo unknown)
ESTV3T_DIRTY := $(shell if [ -n "$$(git status --porcelain 2>/dev/null)" ]; then echo 1; else echo 0; fi)
ESTV3T_PROTO := $(shell sha256sum docs/estimation/EST3C_PROTOCOL_V3.md 2>/dev/null | cut -c1-64)
ESTV3T_D2FILE = docs/estimation/receipts/est3c-v3/d2.sha256
ESTV3T_D2RAW := $(shell awk '$$2 == "machine-state.ndjson" && length($$1) == 64 { print $$1 }' $(ESTV3T_D2FILE) 2>/dev/null | head -1)
ESTV3T_D2MARKS := $(shell awk '$$2 == "machine-state-marks.txt" && length($$1) == 64 { print $$1 }' $(ESTV3T_D2FILE) 2>/dev/null | head -1)
ESTV3T_D2SCHED := $(shell awk '$$2 == "schedule.txt" && length($$1) == 64 { print $$1 }' $(ESTV3T_D2FILE) 2>/dev/null | head -1)
ESTV3T_PARAMS := $(shell sha256sum docs/estimation/receipts/est3c-v3/params.txt 2>/dev/null | cut -c1-64)
ESTV3T_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null || echo unknown)
ESTV3T_OR = $(if $(1),$(1),$(2))

$(ESTV3T_DIR)/toolid.stamp: est3c-tools-force
	@mkdir -p $(ESTV3T_DIR)
	@echo "$(ESTV3T_COMMIT) $(ESTV3T_DIRTY) $(ESTV3T_PROTO) $(ESTV3T_D2RAW) $(ESTV3T_D2MARKS) $(ESTV3T_D2SCHED) $(ESTV3T_PARAMS) $(ESTV3T_ROOT)" > $(ESTV3T_DIR)/toolid.new; \
	cmp -s $(ESTV3T_DIR)/toolid.new $(ESTV3T_DIR)/toolid.stamp || mv $(ESTV3T_DIR)/toolid.new $(ESTV3T_DIR)/toolid.stamp; rm -f $(ESTV3T_DIR)/toolid.new
est3c-tools-force: ;

$(ESTV3T_DIR)/toolid.om: $(ESTV3T_DIR)/toolid.stamp
	@mkdir -p $(ESTV3T_DIR)
	printf 'text t_c3_tool_commit "%s"\nconst C3_TOOL_DIRTY ulong %s\nconst C3_TEST_BUILD ulong 0\ntext t_c3_protocol_sha "%s"\ntext t_c3_d2_raw_sha "%s"\ntext t_c3_d2_marks_sha "%s"\ntext t_c3_d2_sched_sha "%s"\ntext t_c3_params_sha "%s"\ntext t_c3_repo_root "%s"\n' \
		'$(ESTV3T_COMMIT)' '$(ESTV3T_DIRTY)' '$(call ESTV3T_OR,$(ESTV3T_PROTO),unknown)' \
		'$(call ESTV3T_OR,$(ESTV3T_D2RAW),absent)' '$(call ESTV3T_OR,$(ESTV3T_D2MARKS),absent)' \
		'$(call ESTV3T_OR,$(ESTV3T_D2SCHED),absent)' '$(call ESTV3T_OR,$(ESTV3T_PARAMS),absent)' '$(ESTV3T_ROOT)' > $@

$(ESTV3T_DIR)/toolid_t.om: $(ESTV3T_DIR)/toolid.stamp
	@mkdir -p $(ESTV3T_DIR)
	printf 'text t_c3_tool_commit "test-build"\nconst C3_TOOL_DIRTY ulong 1\nconst C3_TEST_BUILD ulong 1\ntext t_c3_protocol_sha "%s"\ntext t_c3_d2_raw_sha "absent"\ntext t_c3_d2_marks_sha "absent"\ntext t_c3_d2_sched_sha "absent"\ntext t_c3_params_sha "absent"\ntext t_c3_repo_root "unknown"\n' \
		'$(call ESTV3T_OR,$(ESTV3T_PROTO),unknown)' > $@

$(ESTV3T_DIR)/est3c_fit: $(ESTV3T_OM_LIB) $(ESTV3T_DIR)/toolid.om tools/estimation/est3c_fit.om $(EST_OMC)
	@mkdir -p $(ESTV3T_DIR)
	cat $(ESTV3T_OM_LIB) $(ESTV3T_DIR)/toolid.om tools/estimation/est3c_fit.om | $(EST_OMC) > $@ && chmod +x $@
$(ESTV3T_DIR)/est3c_eval: $(ESTV3T_OM_LIB) $(ESTV3T_DIR)/toolid.om tools/estimation/est3c_eval.om $(EST_OMC)
	@mkdir -p $(ESTV3T_DIR)
	cat $(ESTV3T_OM_LIB) $(ESTV3T_DIR)/toolid.om tools/estimation/est3c_eval.om | $(EST_OMC) > $@ && chmod +x $@
$(ESTV3T_DIR)/est3c_fit_t: $(ESTV3T_OM_LIB) $(ESTV3T_DIR)/toolid_t.om tools/estimation/est3c_fit.om $(EST_OMC)
	@mkdir -p $(ESTV3T_DIR)
	cat $(ESTV3T_OM_LIB) $(ESTV3T_DIR)/toolid_t.om tools/estimation/est3c_fit.om | $(EST_OMC) > $@ && chmod +x $@
$(ESTV3T_DIR)/est3c_eval_t: $(ESTV3T_OM_LIB) $(ESTV3T_DIR)/toolid_t.om tools/estimation/est3c_eval.om $(EST_OMC)
	@mkdir -p $(ESTV3T_DIR)
	cat $(ESTV3T_OM_LIB) $(ESTV3T_DIR)/toolid_t.om tools/estimation/est3c_eval.om | $(EST_OMC) > $@ && chmod +x $@
$(ESTV3T_DIR)/test_est3c_tools: $(ESTV3T_OM_LIB) tools/estimation/test_est3c_tools.om $(EST_OMC)
	@mkdir -p $(ESTV3T_DIR)
	cat $(ESTV3T_OM_LIB) tools/estimation/test_est3c_tools.om | $(EST_OMC) > $@ && chmod +x $@
$(ESTV3T_DIR)/est3c_forensics: $(ESTT_OM_LIB) tools/estimation/est3c_forensics.om $(EST_OMC)
	@mkdir -p $(ESTV3T_DIR)
	cat $(ESTT_OM_LIB) tools/estimation/est3c_forensics.om | $(EST_OMC) > $@ && chmod +x $@
$(ESTV3T_DIR)/est_load: tools/estimation/est_load.om $(EST_OMC)
	@mkdir -p $(ESTV3T_DIR)
	cat tools/estimation/est_load.om | $(EST_OMC) > $@ && chmod +x $@

est3c-fit: $(ESTV3T_DIR)/est3c_fit
est3c-eval: $(ESTV3T_DIR)/est3c_eval
est3c-forensics: $(ESTV3T_DIR)/est3c_forensics
est-load: $(ESTV3T_DIR)/est_load

test-est3c-tools: $(ESTV3T_DIR)/est3c_fit $(ESTV3T_DIR)/est3c_eval $(ESTV3T_DIR)/est3c_fit_t $(ESTV3T_DIR)/est3c_eval_t $(ESTV3T_DIR)/test_est3c_tools
	rm -rf $(ESTV3T_DIR)/work
	./$(ESTV3T_DIR)/test_est3c_tools ./$(ESTV3T_DIR)/est3c_fit_t ./$(ESTV3T_DIR)/est3c_eval_t $(ESTV3T_DIR)/work
	@echo "test-est3c-tools: tick mapping, pre-check triggers, marks pairs, selection, E0, receipt refusals pass (pure OM-2, synthetic data)"
endif
