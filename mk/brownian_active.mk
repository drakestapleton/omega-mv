# BRW-ACT-DEV0: active measurement choice, development demonstration (not EXP-003).
# Pure seeded OM-2 implementation: tools/brownian/brw_active.om,
# tests/brownian/{brw_act_report,test_brw_act_report,brw_act_reanalyse,test_brw_active,brw_active_dev0}.om.
# Picked up by `-include mk/*.mk`. Spec: docs/turing/BRW_ACT_DEV0_PROFILE.md.
#
# test-brownian-active: pure OM-2 unit tests and library purity check.
# brownian-active-dev0: builds the runner, runs the `dev` worlds twice, fails if the table digests differ.
# The `hold` worlds are run by hand once: build/brownian-active/brw_active_dev0 hold <fresh-dir> <commit>
ifndef BROWNIAN_ACTIVE_MK
BROWNIAN_ACTIVE_MK := 1
.PHONY: brownian-active-reanalyse test-brownian-active brownian-active-dev0 brwa-purity brwa-cli brownian-active-dev1-power brownian-active-dev1 brownian-active-dev0-regress
BRWA_OMC ?= seed/out/omc
BRWA_LIB_OM = src/turing/ty_qcont_lib.om tools/brownian/brw_active.om
BRWA_DIR = $(OUT_DIR)/brownian-active
BRW_DEVIATIONS ?= none
BRWA_COMMIT = $(shell git rev-parse HEAD 2>/dev/null || echo unknown)$(shell git diff --quiet HEAD -- tools tests mk src docs 2>/dev/null || echo -dirty)
# the candidate library must not name a world, a truth, or a generator
BRWA_FORBIDDEN = 'world|truth|oracle|splitmix|xorshift|poisson|box_muller|rand|generator|hidden|heldout'

$(BRWA_DIR)/test_brw_active: $(BRWA_LIB_OM) tests/brownian/test_brw_active.om $(BRWA_OMC)
	@mkdir -p $(BRWA_DIR)
	cat $(BRWA_LIB_OM) tests/brownian/test_brw_active.om | $(BRWA_OMC) > $@ && chmod +x $@
$(BRWA_DIR)/brw_active_dev0: $(BRWA_LIB_OM) tests/brownian/brw_act_report.om tests/brownian/brw_active_dev0.om $(BRWA_OMC)
	@mkdir -p $(BRWA_DIR)
	cat $(BRWA_LIB_OM) tests/brownian/brw_act_report.om tests/brownian/brw_active_dev0.om | $(BRWA_OMC) > $@ && chmod +x $@

brwa-purity:
	@if grep -n -i -E $(BRWA_FORBIDDEN) tools/brownian/brw_active.om; then echo "brw_active names a world, truth or generator"; exit 1; fi
	@echo "brwa-purity: tools/brownian/brw_active.om carries no world, truth or generator symbol"

# runner argument contract: DEV1 needs an explicit budget, unknown profile ids are refused
brwa-cli: $(BRWA_DIR)/brw_active_dev0
	@$(BRWA_DIR)/brw_active_dev0 dev1 $(BRWA_DIR)/cli-x t none >/dev/null 2>&1; [ $$? -eq 64 ] || { echo "dev1 without B= must exit 64"; exit 1; }
	@$(BRWA_DIR)/brw_active_dev0 hold1 $(BRWA_DIR)/cli-x t B=2 >/dev/null 2>&1; [ $$? -eq 64 ] || { echo "B below 3 must exit 64"; exit 1; }
	@$(BRWA_DIR)/brw_active_dev0 bogus $(BRWA_DIR)/cli-x t >/dev/null 2>&1; [ $$? -eq 64 ] || { echo "unknown profile id must exit 64"; exit 1; }
	@echo "brwa-cli: runner argument contract holds"

$(BRWA_DIR)/test_brw_act_report: tests/brownian/brw_act_report.om tests/brownian/test_brw_act_report.om $(BRWA_OMC)
	@mkdir -p $(BRWA_DIR)
	(echo om2; cat tests/brownian/brw_act_report.om tests/brownian/test_brw_act_report.om) | $(BRWA_OMC) > $@ && chmod +x $@
$(BRWA_DIR)/brw_act_reanalyse: tests/brownian/brw_act_report.om tests/brownian/brw_act_reanalyse.om $(BRWA_OMC)
	@mkdir -p $(BRWA_DIR)
	(echo om2; cat tests/brownian/brw_act_report.om tests/brownian/brw_act_reanalyse.om) | $(BRWA_OMC) > $@ && chmod +x $@

test-brownian-active: brwa-purity brwa-cli $(BRWA_DIR)/test_brw_active $(BRWA_DIR)/test_brw_act_report
	./$(BRWA_DIR)/test_brw_act_report
	./$(BRWA_DIR)/test_brw_active
	@echo "test-brownian-active: pure OM-2 candidate library unit tests pass; purity holds"

brownian-active-dev0: $(BRWA_DIR)/brw_active_dev0
	@rm -rf $(BRWA_DIR)/dev-a $(BRWA_DIR)/dev-b
	./$(BRWA_DIR)/brw_active_dev0 dev $(BRWA_DIR)/dev-a $(BRWA_COMMIT) "$(BRW_DEVIATIONS)" | tee $(BRWA_DIR)/dev-a.out | tail -12
	./$(BRWA_DIR)/brw_active_dev0 dev $(BRWA_DIR)/dev-b $(BRWA_COMMIT) "$(BRW_DEVIATIONS)" > $(BRWA_DIR)/dev-b.out
	@a=$$(sha256sum < $(BRWA_DIR)/dev-a/table.tsv); b=$$(sha256sum < $(BRWA_DIR)/dev-b/table.tsv); \
	  if [ "$$a" != "$$b" ]; then echo "brownian-active-dev0: REPLAY MISMATCH ($$a vs $$b)"; exit 1; fi; \
	  echo "brownian-active-dev0: two dev runs produced identical tables ($$a)"

# ---- BRW-ACT-DEV1 (docs/turing/BRW_ACT_DEV1_PROFILE.md): same runner, profile ids dev1/hold1 and the power sub-command.
# Built into its own directory. The power receipt (evidence/BRW-ACT-DEV1/power/receipt.txt, never overwritten) fixes B.
BRWA1_DIR = $(OUT_DIR)/brownian-active-dev1
BRWA1_POWER = evidence/BRW-ACT-DEV1/power
$(BRWA1_DIR)/brw_active_dev0: $(BRWA_LIB_OM) tests/brownian/brw_act_report.om tests/brownian/brw_active_dev0.om $(BRWA_OMC)
	@mkdir -p $(BRWA1_DIR)
	cat $(BRWA_LIB_OM) tests/brownian/brw_act_report.om tests/brownian/brw_active_dev0.om | $(BRWA_OMC) > $@ && chmod +x $@

brownian-active-dev0-regress: $(BRWA1_DIR)/brw_active_dev0
	@rm -rf $(BRWA1_DIR)/regress0
	./$(BRWA1_DIR)/brw_active_dev0 dev $(BRWA1_DIR)/regress0 $(BRWA_COMMIT) none > /dev/null
	@a=$$(sha256sum < $(BRWA1_DIR)/regress0/table.tsv); b=$$(sha256sum < evidence/BRW-ACT-DEV0/dev/table.tsv); \
	  if [ "$$a" != "$$b" ]; then echo "DEV0 regress: table differs ($$a vs $$b)"; exit 1; fi; echo "DEV0 regress: table identical to evidence/BRW-ACT-DEV0/dev ($$a)"

brownian-active-dev1-power: $(BRWA1_DIR)/brw_active_dev0
	@mkdir -p $(dir $(BRWA1_POWER))
	./$(BRWA1_DIR)/brw_active_dev0 power $(BRWA1_POWER) $(BRWA_COMMIT) "$(BRW_DEVIATIONS)"

brownian-active-dev1: $(BRWA1_DIR)/brw_active_dev0
	@test -f $(BRWA1_POWER)/receipt.txt || { echo "run brownian-active-dev1-power first and commit its evidence"; exit 1; }
	@B=$$(sed -n 's/^chosen_B: //p' $(BRWA1_POWER)/receipt.txt); test -n "$$B" || { echo "no chosen_B in power receipt"; exit 1; }; \
	  rm -rf $(BRWA1_DIR)/dev1-a $(BRWA1_DIR)/dev1-b; \
	  echo "B=$$B"; \
	  ./$(BRWA1_DIR)/brw_active_dev0 dev1 $(BRWA1_DIR)/dev1-a $(BRWA_COMMIT) B=$$B "$(BRW_DEVIATIONS)" | tee $(BRWA1_DIR)/dev1-a.out | tail -14; \
	  ./$(BRWA1_DIR)/brw_active_dev0 dev1 $(BRWA1_DIR)/dev1-b $(BRWA_COMMIT) B=$$B "$(BRW_DEVIATIONS)" > $(BRWA1_DIR)/dev1-b.out; \
	  a=$$(sha256sum < $(BRWA1_DIR)/dev1-a/table.tsv); b=$$(sha256sum < $(BRWA1_DIR)/dev1-b/table.tsv); \
	  if [ "$$a" != "$$b" ]; then echo "brownian-active-dev1: REPLAY MISMATCH"; exit 1; fi; \
	  echo "brownian-active-dev1: two dev1 runs produced identical tables ($$a)"

# Re-analysis of the committed held-out tables (reads table.tsv only, runs no world). Writes a new evidence file,
# never over an existing one: evidence/BRW-ACT-DEV<n>/<run>-reanalysis/reanalysis.txt.
brownian-active-reanalyse: $(BRWA_DIR)/brw_act_reanalyse
	@for r in DEV0:hold:dev0 DEV1:hold1:dev1; do \
	  d=$${r%%:*}; rest=$${r#*:}; run=$${rest%%:*}; p=$${rest#*:}; t=evidence/BRW-ACT-$$d/$$run/table.tsv; \
	  o=evidence/BRW-ACT-$$d/$$run-reanalysis; test -e $$o/reanalysis.txt && { echo "$$o/reanalysis.txt exists, not overwritten"; continue; }; \
	  mkdir -p $$o; { echo "source commit: $(BRWA_COMMIT)"; echo "input: $$t sha256 $$(sha256sum < $$t | cut -c1-64)"; \
	    echo "tool: tests/brownian/brw_act_reanalyse.om sha256 $$(sha256sum < tests/brownian/brw_act_reanalyse.om | cut -c1-64)"; \
	    echo "flags: om2"; ./$(BRWA_DIR)/brw_act_reanalyse $$p $$t; } > $$o/reanalysis.txt.tmp || { rm -f $$o/reanalysis.txt.tmp; exit 1; }; \
	  mv $$o/reanalysis.txt.tmp $$o/reanalysis.txt; \
	  echo "wrote $$o/reanalysis.txt"; done

endif
