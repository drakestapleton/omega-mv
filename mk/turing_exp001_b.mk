# Turing calibration EXP-001, lane B: probability stream (TPS1/TSY1) + two
# reference coders (range, rANS) in pure seeded OM-2. Spec: calibration/docs/CODER_SPEC.md.
# Picked up by `-include mk/*.mk`. All variables are TC_-prefixed.
#
# test-turing-exp001-coders: coder suite (built WITHOUT tc_produce.om, so the
# coders cannot reach the model), producer suite on the committed fixtures, CLI
# accept/refuse checks.
# turing-exp001-envelope TC_DATA=<dir with seed-N/control/trace.ctr>: overhead
# measurement on dev seeds 1-7 (not part of the test target).
.PHONY: test-turing-exp001-coders turing-exp001-envelope turing-coder
TC_OM_SHA = seed/ng/sha256.om
TC_CODER_OM = $(TC_OM_SHA) src/turing/tc_pstream.om src/turing/tc_range_lib.om src/turing/tc_rans.om
TC_PROD_OM = $(TC_CODER_OM) src/turing/tc_produce.om
TC_DIR = $(OUT_DIR)/tests-turing-exp001-b
TC_TOOL = $(TC_DIR)/turing-coder
TC_FIX = tests/turing/fixtures/ctr1_seed1_crumbs05-07.ctr
TC_CAND = evidence/TURING_YIELD/ty2_candidate.tym
TC_ZERO = 0000000000000000000000000000000000000000000000000000000000000000
TC_DATA ?= $(HOME)/aien-data/crumbline/exp-20260927-rep10

$(TC_DIR)/test_tc: tests/turing/test_tc.om $(TC_CODER_OM) seed/out/omc
	@mkdir -p $(TC_DIR)
	(printf 'om2\n'; cat $(TC_CODER_OM) tests/turing/test_tc.om) | seed/out/omc > $@ && chmod +x $@

$(TC_DIR)/test_tc_produce: tests/turing/test_tc_produce.om $(TC_PROD_OM) seed/out/omc
	@mkdir -p $(TC_DIR)
	(printf 'om2\n'; cat $(TC_PROD_OM) tests/turing/test_tc_produce.om) | seed/out/omc > $@ && chmod +x $@

$(TC_TOOL): src/turing/tc_tool.om $(TC_PROD_OM) seed/out/omc
	@mkdir -p $(TC_DIR)
	(printf 'om2\n'; cat $(TC_PROD_OM) src/turing/tc_tool.om) | seed/out/omc > $@ && chmod +x $@

turing-coder: $(TC_TOOL)

test-turing-exp001-coders: $(TC_DIR)/test_tc $(TC_DIR)/test_tc_produce $(TC_TOOL)
	@if grep -n 'ty_model\|tc_produce\|tp_model' src/turing/tc_pstream.om src/turing/tc_range_lib.om src/turing/tc_rans.om; then \
		echo "coder sources reference the model"; exit 1; fi
	./$(TC_DIR)/test_tc $(TC_DIR)/coders
	./$(TC_DIR)/test_tc_produce $(TC_DIR)/produce
	@set -e; D=$(TC_DIR)/cli_turing-coder; mkdir -p $$D; \
		./$(TC_TOOL) pstream $(TC_CAND) $(TC_ZERO) $(TC_FIX) $$D/f.tps $$D/f.tsy > $$D/pstream.txt; \
		M=$$(sed -n 's/^model_digest=//p' $$D/pstream.txt); \
		for C in range rans; do \
			./$(TC_TOOL) encode $$C $$D/f.tps $$D/f.tsy $$D/f.$$C > /dev/null; \
			./$(TC_TOOL) verify $$C $$D/f.tps $$D/f.tsy $$D/f.$$C --profile $(TC_ZERO) --model $$M > $$D/verify_$$C.txt; \
			./$(TC_TOOL) decode $$C $$D/f.tps $$D/f.$$C $$D/dec_$$C.tsy; cmp $$D/f.tsy $$D/dec_$$C.tsy; \
			if ./$(TC_TOOL) verify $$C $$D/f.tps $$D/f.tsy $$D/f.$$C --model $(TC_ZERO) 2>/dev/null; then \
				echo "CLI accepted a wrong model digest"; exit 1; fi; \
			head -c -1 $$D/f.$$C > $$D/trunc.$$C; \
			if ./$(TC_TOOL) decode $$C $$D/f.tps $$D/trunc.$$C $$D/x.tsy 2>/dev/null; then \
				echo "CLI accepted a truncated bitstream"; exit 1; fi; \
		done
	@echo "test-turing-exp001-coders: pure OM-2 TPS1/TSY1, range + rANS round trips and refusals pass"

# All seven EXP-001 candidates (profile section "envelope"), per file and per crumb, both coders.
TC_ENV_CANDS = B0_uniform B1_order0 B2_order1 B3_heuristic M_candidate M_mem M_mem_seed1
TC_ENV_CDIRS ?= calibration/experiments/EXP-001/candidates $(HOME)/aien-data/turing-cal/candidates
turing-exp001-envelope: $(TC_TOOL)
	@mkdir -p $(TC_DIR)/envelope
	@for S in 1 2 3 4 5 6 7; do for C in $(TC_ENV_CANDS); do \
		F=""; for D in $(TC_ENV_CDIRS); do [ -f "$$D/$$C.tym" ] && { F="$$D/$$C.tym"; break; }; done; \
		[ -n "$$F" ] || { echo "envelope: $$C.tym not found"; exit 1; }; \
		./$(TC_TOOL) envelope $(TC_ZERO) $(TC_DIR)/envelope/seed-$$S.$$C.csv $(TC_DATA)/seed-$$S/control/trace.ctr \
			"$$F" > $(TC_DIR)/envelope/seed-$$S.$$C.txt || { echo "envelope: seed $$S $$C refused"; exit 1; }; \
		test $$(grep -c "^file " $(TC_DIR)/envelope/seed-$$S.$$C.txt) -eq 1 || { echo "envelope: seed $$S $$C incomplete"; exit 1; }; \
	done; done
	sh calibration/scripts/envelope_summary.sh $(TC_DIR)/envelope | tee $(TC_DIR)/envelope/summary.txt
