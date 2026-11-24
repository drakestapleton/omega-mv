# ESTIMATION v4 (docs/estimation/protocols/est-v4.md): lag / AR-change /
# two-time-constant families (src/estimation/est_v4.om) and the est4 tool (pure OM-2).
# Picked up by `-include mk/*.mk`; not part of `all` or `test`.
#
# test-est-v4         unit suite (analytic multi-step propagation, pure OM-2)
# est-v4-purity       OM-2 purity scan on est_v4.om against EST_OM_FORBIDDEN
# test-est4-tools     tool tests on synthetic data (held-out refusal, open trace, binding refusals)
# test-estimation-v4  all three
# est4                the binding tool (identity compiled in)
ifndef ESTIMATION_V4_MK
ESTIMATION_V4_MK := 1
include mk/estimation_tools.mk
.PHONY: test-est-v4 est-v4-purity test-est4-tools test-estimation-v4 est4 est4-force
ESTV4_DIR = $(OUT_DIR)/estimation-v4
ESTV4_OM_LIB = $(ESTT_OM_LIB) tools/estimation/est3c_common.om
# identity baked in: commit, dirty flag, protocol SHA, D1 identity, D2 identity, params SHA, repo root
ESTV4_COMMIT := $(shell git rev-parse HEAD 2>/dev/null || echo unknown)
ESTV4_DIRTY := $(shell if [ -n "$$(git status --porcelain 2>/dev/null)" ]; then echo 1; else echo 0; fi)
ESTV4_PROTO := $(shell sha256sum docs/estimation/protocols/est-v4.md 2>/dev/null | cut -c1-64)
ESTV4_RC = docs/estimation/receipts/est-v4
ESTV4_SUM = $(shell awk '$$2 == "$(2)" && length($$1) == 64 { print $$1 }' $(ESTV4_RC)/$(1) 2>/dev/null | head -1)
ESTV4_D1RAW := $(call ESTV4_SUM,d1.sha256,machine-state.ndjson)
ESTV4_D1MARKS := $(call ESTV4_SUM,d1.sha256,machine-state-marks.txt)
ESTV4_D2RAW := $(call ESTV4_SUM,d2.sha256,machine-state.ndjson)
ESTV4_D2MARKS := $(call ESTV4_SUM,d2.sha256,machine-state-marks.txt)
ESTV4_D2SCHED := $(call ESTV4_SUM,d2.sha256,schedule.txt)
ESTV4_PARAMS := $(shell sha256sum $(ESTV4_RC)/params.txt 2>/dev/null | cut -c1-64)
ESTV4_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null || echo unknown)
ESTV4_OR = $(if $(1),$(1),$(2))

$(ESTV4_DIR)/toolid.stamp: est4-force
	@mkdir -p $(ESTV4_DIR)
	@echo "$(ESTV4_COMMIT) $(ESTV4_DIRTY) $(ESTV4_PROTO) $(ESTV4_D1RAW) $(ESTV4_D1MARKS) $(ESTV4_D2RAW) $(ESTV4_D2MARKS) $(ESTV4_D2SCHED) $(ESTV4_PARAMS) $(ESTV4_ROOT)" > $(ESTV4_DIR)/toolid.new; \
	cmp -s $(ESTV4_DIR)/toolid.new $(ESTV4_DIR)/toolid.stamp || mv $(ESTV4_DIR)/toolid.new $(ESTV4_DIR)/toolid.stamp; rm -f $(ESTV4_DIR)/toolid.new
est4-force: ;

$(ESTV4_DIR)/toolid.om: $(ESTV4_DIR)/toolid.stamp
	@mkdir -p $(ESTV4_DIR)
	printf 'text t_e4_tool_commit "%s"\nconst E4_TOOL_DIRTY ulong %s\nconst E4_TEST_BUILD ulong 0\ntext t_e4_protocol_sha "%s"\ntext t_e4_d1_raw_sha "%s"\ntext t_e4_d1_marks_sha "%s"\ntext t_e4_d2_raw_sha "%s"\ntext t_e4_d2_marks_sha "%s"\ntext t_e4_d2_sched_sha "%s"\ntext t_e4_params_sha "%s"\ntext t_e4_repo_root "%s"\n' \
		'$(ESTV4_COMMIT)' '$(ESTV4_DIRTY)' '$(call ESTV4_OR,$(ESTV4_PROTO),unknown)' \
		'$(call ESTV4_OR,$(ESTV4_D1RAW),absent)' '$(call ESTV4_OR,$(ESTV4_D1MARKS),absent)' \
		'$(call ESTV4_OR,$(ESTV4_D2RAW),absent)' '$(call ESTV4_OR,$(ESTV4_D2MARKS),absent)' \
		'$(call ESTV4_OR,$(ESTV4_D2SCHED),absent)' '$(call ESTV4_OR,$(ESTV4_PARAMS),absent)' '$(ESTV4_ROOT)' > $@

$(ESTV4_DIR)/toolid_t.om:
	@mkdir -p $(ESTV4_DIR)
	printf 'text t_e4_tool_commit "test-build"\nconst E4_TOOL_DIRTY ulong 1\nconst E4_TEST_BUILD ulong 1\ntext t_e4_protocol_sha "unknown"\ntext t_e4_d1_raw_sha "absent"\ntext t_e4_d1_marks_sha "absent"\ntext t_e4_d2_raw_sha "absent"\ntext t_e4_d2_marks_sha "absent"\ntext t_e4_d2_sched_sha "absent"\ntext t_e4_params_sha "absent"\ntext t_e4_repo_root "unknown"\n' > $@

est-v4-purity: src/estimation/est_v4.om
	@awk -v re='$(EST_OM_FORBIDDEN)' '$$1 != "note" && $$1 != "text" && $$0 ~ re { print FILENAME ":" FNR ": " $$0; bad = 1 } END { exit bad }' \
		src/estimation/est_v4.om || { echo "est_v4.om references an operation an estimator must not have"; exit 1; }
	@echo "est-v4-purity: est_v4.om references no forbidden symbol (pure OM-2)"

EST_OM_V4 = $(EST_OM_TYPES) src/estimation/est_mix.om src/estimation/est_pred.om src/estimation/est_v4.om

$(ESTV4_DIR)/test_est_v4: $(EST_OM_V4) tests/estimation/test_est_v4.om $(EST_OMC)
	@mkdir -p $(ESTV4_DIR)
	cat $(EST_OM_V4) tests/estimation/test_est_v4.om | $(EST_OMC) > $@ && chmod +x $@
test-est-v4: $(ESTV4_DIR)/test_est_v4
	./$(ESTV4_DIR)/test_est_v4
	@echo "test-est-v4: v4 families, multi-step propagation and pmf agree (pure OM-2)"

$(ESTV4_DIR)/est4: $(ESTV4_OM_LIB) $(ESTV4_DIR)/toolid.om tools/estimation/est4.om $(EST_OMC)
	@mkdir -p $(ESTV4_DIR)
	cat $(ESTV4_OM_LIB) $(ESTV4_DIR)/toolid.om tools/estimation/est4.om | $(EST_OMC) > $@ && chmod +x $@
est4: $(ESTV4_DIR)/est4
$(ESTV4_DIR)/est4_test: $(ESTV4_OM_LIB) $(ESTV4_DIR)/toolid_t.om tools/estimation/est4.om $(EST_OMC)
	@mkdir -p $(ESTV4_DIR)
	cat $(ESTV4_OM_LIB) $(ESTV4_DIR)/toolid_t.om tools/estimation/est4.om | $(EST_OMC) > $@ && chmod +x $@
test-est4-tools: $(ESTV4_DIR)/est4 $(ESTV4_DIR)/est4_test
	sh tools/estimation/test_est4_tools.sh ./$(ESTV4_DIR)/est4_test $(ESTV4_DIR)/work
	@echo "test-est4-tools: fit, held-out refusal, open-trace purity, binding refusals and receipt path pass (pure OM-2, synthetic data)"

test-estimation-v4: est-v4-purity test-est-v4 test-est4-tools
	@echo "test-estimation-v4: ESTIMATION v4 passes"
endif
