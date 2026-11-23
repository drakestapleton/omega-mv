# POLYGLOT-0 build and test targets (pure seeded OM-2). spec/polyglot-0.md
#
# Targets:
#   test-polyglot         pure OM-2 shared verifier + bench_polyglot --selftest
#   bench-polyglot        timed benchmark writing receipts to $(POLYGLOT_EVIDENCE)
#   bench-polyglot-smoke  smoke run (N=3) writing receipts to $(OUT_DIR)/polyglot/smoke
#   polyglot-explain      deterministic explainer over $(POLYGLOT_RECEIPTS), run twice and cmp'd
ifndef POLYGLOT_MK_LOADED
POLYGLOT_MK_LOADED := 1

.PHONY: test-polyglot bench-polyglot bench-polyglot-smoke polyglot-explain

PG_OMC ?= seed/out/omc
PG_OUT := $(OUT_DIR)/polyglot
POLYGLOT_EVIDENCE ?= evidence/POLYGLOT
POLYGLOT_RECEIPTS ?= $(POLYGLOT_EVIDENCE)
POLYGLOT_BENCH_ARGS ?=
POLYGLOT_RUN ?=

PG_COMMON_OM := src/polyglot/omx_common.om
PG_ENC_OM := src/polyglot/omx_encoder.om
PG_VERIFY := $(PG_OUT)/verify_polyglot
PG_BENCH := $(PG_OUT)/bench_polyglot
PG_EXPLAIN := $(PG_OUT)/polyglot_explain
PG_MANIFEST := $(PG_OUT)/manifest.tsv

$(PG_VERIFY): $(PG_COMMON_OM) $(PG_ENC_OM) tests/polyglot/verify_polyglot.om $(PG_OMC)
	@mkdir -p $(dir $@)
	cat $(PG_COMMON_OM) $(PG_ENC_OM) tests/polyglot/verify_polyglot.om | $(PG_OMC) > $@.tmp && chmod +x $@.tmp && mv $@.tmp $@

$(PG_BENCH): $(PG_COMMON_OM) $(PG_ENC_OM) tests/polyglot/bench_polyglot.om $(PG_OMC)
	@mkdir -p $(dir $@)
	cat $(PG_COMMON_OM) $(PG_ENC_OM) tests/polyglot/bench_polyglot.om | $(PG_OMC) > $@.tmp && chmod +x $@.tmp && mv $@.tmp $@

$(PG_EXPLAIN): $(PG_COMMON_OM) tests/polyglot/polyglot_explain.om $(PG_OMC)
	@mkdir -p $(dir $@)
	cat $(PG_COMMON_OM) tests/polyglot/polyglot_explain.om | $(PG_OMC) > $@.tmp && chmod +x $@.tmp && mv $@.tmp $@

$(PG_MANIFEST): $(PG_BENCH)
	@mkdir -p $(dir $@)
	@printf 'src/polyglot/omx_common.om\tom2\t%s\tcat src/polyglot/omx_common.om src/polyglot/omx_encoder.om tests/polyglot/bench_polyglot.om | $(PG_OMC) > @OUT@\n' '$(PG_BENCH)' > $@.tmp
	@printf 'src/polyglot/omx_encoder.om\tom2\t%s\t-\n' '$(PG_BENCH)' >> $@.tmp
	@mv $@.tmp $@

test-polyglot: $(PG_VERIFY) $(PG_BENCH)
	./$(PG_VERIFY)
	./$(PG_BENCH) --selftest

bench-polyglot: $(PG_BENCH) $(PG_MANIFEST)
	@mkdir -p $(POLYGLOT_EVIDENCE)
	./$(PG_BENCH) --spec spec/polyglot-0.md --manifest $(PG_MANIFEST) --out $(POLYGLOT_EVIDENCE) $(POLYGLOT_BENCH_ARGS)

bench-polyglot-smoke: $(PG_BENCH) $(PG_MANIFEST)
	@mkdir -p $(PG_OUT)/smoke
	./$(PG_BENCH) --spec spec/polyglot-0.md --manifest $(PG_MANIFEST) --out $(PG_OUT)/smoke --smoke --samples 3 --sparsity 0 $(POLYGLOT_BENCH_ARGS)

polyglot-explain: $(PG_EXPLAIN)
	./$(PG_EXPLAIN) --spec spec/polyglot-0.md --receipts $(POLYGLOT_RECEIPTS) $(if $(POLYGLOT_RUN),--run $(POLYGLOT_RUN)) > $(PG_OUT)/polyglot_explain.1.txt
	./$(PG_EXPLAIN) --spec spec/polyglot-0.md --receipts $(POLYGLOT_RECEIPTS) $(if $(POLYGLOT_RUN),--run $(POLYGLOT_RUN)) > $(PG_OUT)/polyglot_explain.2.txt
	cmp $(PG_OUT)/polyglot_explain.1.txt $(PG_OUT)/polyglot_explain.2.txt
	@cat $(PG_OUT)/polyglot_explain.1.txt
	@echo "polyglot-explain: two runs byte-identical ($(PG_OUT)/polyglot_explain.1.txt)"

endif # POLYGLOT_MK_LOADED
