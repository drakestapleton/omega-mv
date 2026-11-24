# ESTIMATION v5 (docs/estimation/protocols/est-v5.md): the v4 families (src/estimation/est_v4.om)
# with the est5 tool (pure seeded OM-2) and an enforced collection window.
# Picked up by `-include mk/*.mk`; not part of `all` or `test`.
#
# test-est5-tools     tool tests on synthetic data (held-out refusal, open trace, binding refusals)
# test-est5-window    collector and window-check tests (no data, no load)
# test-est-json       strict-JSON receipt rules (est-json-1): unit checks + strict parse of emitted receipts
# test-estimation-v5  v4 library tests (reused) + the three above
# est5                the binding tool (identity compiled in)
ifndef ESTIMATION_V5_MK
ESTIMATION_V5_MK := 1
include mk/estimation_v4.mk
.PHONY: test-est-json test-est5-tools test-est5-window test-estimation-v5 est5 est5-force
ESTV5_DIR = $(OUT_DIR)/estimation-v5
ESTV5_OM_LIB = $(ESTT_OM_LIB) tools/estimation/est3c_common.om
# identity baked in: commit, dirty flag, protocol SHA, D1 identity, D2 identity, params SHA, repo root
ESTV5_COMMIT := $(shell git rev-parse HEAD 2>/dev/null || echo unknown)
ESTV5_DIRTY := $(shell if [ -n "$$(git status --porcelain 2>/dev/null)" ]; then echo 1; else echo 0; fi)
ESTV5_PROTO := $(shell sha256sum docs/estimation/protocols/est-v5.md 2>/dev/null | cut -c1-64)
ESTV5_RC = docs/estimation/receipts/est-v5
ESTV5_SUM = $(shell awk '$$2 == "$(2)" && length($$1) == 64 { print $$1 }' $(ESTV5_RC)/$(1) 2>/dev/null | head -1)
ESTV5_D1RAW := $(call ESTV5_SUM,d1.sha256,machine-state.ndjson)
ESTV5_D1MARKS := $(call ESTV5_SUM,d1.sha256,machine-state-marks.txt)
ESTV5_D2RAW := $(call ESTV5_SUM,d2.sha256,machine-state.ndjson)
ESTV5_D2MARKS := $(call ESTV5_SUM,d2.sha256,machine-state-marks.txt)
ESTV5_D2SCHED := $(call ESTV5_SUM,d2.sha256,schedule.txt)
ESTV5_PARAMS := $(shell sha256sum $(ESTV5_RC)/params.txt 2>/dev/null | cut -c1-64)
ESTV5_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null || echo unknown)
ESTV5_OR = $(if $(1),$(1),$(2))

$(ESTV5_DIR)/toolid.stamp: est5-force
	@mkdir -p $(ESTV5_DIR)
	@echo "$(ESTV5_COMMIT) $(ESTV5_DIRTY) $(ESTV5_PROTO) $(ESTV5_D1RAW) $(ESTV5_D1MARKS) $(ESTV5_D2RAW) $(ESTV5_D2MARKS) $(ESTV5_D2SCHED) $(ESTV5_PARAMS) $(ESTV5_ROOT)" > $(ESTV5_DIR)/toolid.new; \
	cmp -s $(ESTV5_DIR)/toolid.new $(ESTV5_DIR)/toolid.stamp || mv $(ESTV5_DIR)/toolid.new $(ESTV5_DIR)/toolid.stamp; rm -f $(ESTV5_DIR)/toolid.new
est5-force: ;

$(ESTV5_DIR)/toolid.om: $(ESTV5_DIR)/toolid.stamp
	@mkdir -p $(ESTV5_DIR)
	printf 'text t_e5_tool_commit "%s"\nconst E5_TOOL_DIRTY ulong %s\nconst E5_TEST_BUILD ulong 0\ntext t_e5_protocol_sha "%s"\ntext t_e5_d1_raw_sha "%s"\ntext t_e5_d1_marks_sha "%s"\ntext t_e5_d2_raw_sha "%s"\ntext t_e5_d2_marks_sha "%s"\ntext t_e5_d2_sched_sha "%s"\ntext t_e5_params_sha "%s"\ntext t_e5_repo_root "%s"\n' \
		'$(ESTV5_COMMIT)' '$(ESTV5_DIRTY)' '$(call ESTV5_OR,$(ESTV5_PROTO),unknown)' \
		'$(call ESTV5_OR,$(ESTV5_D1RAW),absent)' '$(call ESTV5_OR,$(ESTV5_D1MARKS),absent)' \
		'$(call ESTV5_OR,$(ESTV5_D2RAW),absent)' '$(call ESTV5_OR,$(ESTV5_D2MARKS),absent)' \
		'$(call ESTV5_OR,$(ESTV5_D2SCHED),absent)' '$(call ESTV5_OR,$(ESTV5_PARAMS),absent)' '$(ESTV5_ROOT)' > $@

$(ESTV5_DIR)/toolid_t.om:
	@mkdir -p $(ESTV5_DIR)
	printf 'text t_e5_tool_commit "test-build"\nconst E5_TOOL_DIRTY ulong 1\nconst E5_TEST_BUILD ulong 1\ntext t_e5_protocol_sha "unknown"\ntext t_e5_d1_raw_sha "absent"\ntext t_e5_d1_marks_sha "absent"\ntext t_e5_d2_raw_sha "absent"\ntext t_e5_d2_marks_sha "absent"\ntext t_e5_d2_sched_sha "absent"\ntext t_e5_params_sha "absent"\ntext t_e5_repo_root "unknown"\n' > $@

$(ESTV5_DIR)/est5: $(ESTV5_OM_LIB) $(ESTV5_DIR)/toolid.om tools/estimation/est5.om $(EST_OMC)
	@mkdir -p $(ESTV5_DIR)
	cat $(ESTV5_OM_LIB) $(ESTV5_DIR)/toolid.om tools/estimation/est5.om | $(EST_OMC) > $@ && chmod +x $@
est5: $(ESTV5_DIR)/est5
$(ESTV5_DIR)/est5_test: $(ESTV5_OM_LIB) $(ESTV5_DIR)/toolid_t.om tools/estimation/est5.om $(EST_OMC)
	@mkdir -p $(ESTV5_DIR)
	cat $(ESTV5_OM_LIB) $(ESTV5_DIR)/toolid_t.om tools/estimation/est5.om | $(EST_OMC) > $@ && chmod +x $@
test-est5-tools: $(ESTV5_DIR)/test_est_json $(ESTV5_DIR)/est5 $(ESTV5_DIR)/est5_test
	sh tools/estimation/test_est5_tools.sh ./$(ESTV5_DIR)/est5_test $(ESTV5_DIR)/work ./$(ESTV5_DIR)/test_est_json
	@echo "test-est5-tools: fit, held-out refusal, open-trace purity, binding refusals and receipt path pass (pure OM-2, synthetic data)"

$(ESTV5_DIR)/test_est_json: $(ESTV5_OM_LIB) tools/estimation/test_est_json.om $(EST_OMC)
	@mkdir -p $(ESTV5_DIR)
	cat $(ESTV5_OM_LIB) tools/estimation/test_est_json.om | $(EST_OMC) > $@ && chmod +x $@
test-est-json: $(ESTV5_DIR)/test_est_json
	./$(ESTV5_DIR)/test_est_json .
	@echo "test-est-json: strict-JSON receipt rules pass (pure OM-2)"

test-est5-window:
	sh tools/estimation/test_est5_window.sh

test-estimation-v5: est-v4-purity test-est-v4 test-est-json test-est5-tools test-est5-window
	@echo "test-estimation-v5: ESTIMATION v5 passes"
endif
