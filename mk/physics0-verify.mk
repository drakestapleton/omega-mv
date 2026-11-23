# PD-0 independent verifier (Direction 3): ladder checker, scorer, negative
# controls, append-only receipts. Standalone under src/physics0/{ladder,score,
# controls} and tests/physics0/verify. Not part of `all` or `test`.
# Test-only truth generators (tests/physics0/verify/pd0_bundle.om) copy the spec
# equations; the verifier sources never see them (p0v-purity checks it).
#
# test-physics0-verify   formats + ladder + scorer/controls in OM-2, and the live C library tests plain and ASan/UBSan
ifndef PHYSICS0_VERIFY_MK
PHYSICS0_VERIFY_MK := 1
.PHONY: test-physics0-verify p0v-purity
P0V_COMMIT := $(shell git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)
P0V_DIR = $(OUT_DIR)/tests-physics0-verify
P0V_OMC ?= seed/out/omc
# Pure OM-2 (wave 36): formats, codes, receipts, ladder checker, scorer and negative controls, built
# from .om by the seed omc. The receipt commit string is prepended as an OM text constant, the way the
# C build passed -DPD0_VERIFIER_COMMIT. OM-2 arrays are bounds checked (an out-of-range get traps).
P0V_OM_BASE = src/physics0/pd0_types.om src/physics0/pd0_rng.om src/physics0/pd0_wire.om src/physics0/ladder/pd0_codes.om src/physics0/ladder/pd0_fmt.om src/physics0/controls/pd0_receipt.om
P0V_OM_VERIFY = $(P0V_OM_BASE) src/physics0/ladder/pd0_ladder.om src/physics0/score/pd0_score.om src/physics0/controls/pd0_controls.om
P0V_OM_FMT = $(P0V_OM_BASE) tests/physics0/verify/test_pd0_fmt.om
P0V_OM_LADDER = $(P0V_OM_VERIFY) tests/physics0/verify/pd0_bundle.om tests/physics0/verify/test_pd0_ladder.om
P0V_OM_SCORE = $(P0V_OM_VERIFY) tests/physics0/verify/pd0_bundle.om tests/physics0/verify/test_pd0_score.om
P0V_OM_COMMIT = echo 'text PD0_VERIFIER_COMMIT "$(P0V_COMMIT)"'
# The live C verifier library (the learners and planner link it, mk/physics0-learner*.mk): its C tests
# keep running, plain and ASan/UBSan, beside the OM tests.
# -Wno-pedantic: generated binding src/omega_om_units.c uses GNU range designators; see mk/estimation.mk.
P0V_CFLAGS = -std=c11 -Wall -Wextra -Werror -pedantic -Wno-misleading-indentation -O2 -D_POSIX_C_SOURCE=200809L -ffp-contract=off -fno-fast-math \
  -Isrc -Isrc/physics0/ladder -Isrc/physics0/score -Isrc/physics0/controls -Itests/physics0/verify -DPD0_VERIFIER_COMMIT=\"$(P0V_COMMIT)\" -DGOLDEN_PATH=\"tests/physics0/verify/golden_pd0rec1_pr243.bin\" -Wno-pedantic
P0V_ASAN = -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=all
P0V_SRCS = src/physics0/ladder/pd0_fmt.c src/physics0/ladder/pd0_codes.c src/physics0/ladder/pd0_ladder.c src/physics0/score/pd0_score.c src/physics0/controls/pd0_controls.c src/physics0/controls/pd0_receipt.c src/omega_om_units.c
P0V_HDRS = src/physics0/ladder/pd0_fmt.h src/physics0/ladder/pd0_codes.h src/physics0/ladder/pd0_rng.h src/physics0/ladder/pd0_ladder.h src/physics0/score/pd0_score.h src/physics0/controls/pd0_controls.h src/physics0/controls/pd0_receipt.h tests/physics0/verify/truth.h tests/physics0/verify/bundle.h
# the verifier must not contain generator knowledge: no symbol or string from the test truth generators
P0V_FORBIDDEN = 'truth_|oracle_rel|rx_|aienos_|argus_|forge_|mmap|fork|exec|socket'
$(P0V_DIR)/test_pd0_fmt: $(P0V_OM_FMT) $(P0V_OMC)
	@mkdir -p $(P0V_DIR)/receipts
	{ echo "om2"; $(P0V_OM_COMMIT); cat $(P0V_OM_FMT); } | $(P0V_OMC) > $@ && chmod +x $@
$(P0V_DIR)/test_pd0_ladder: $(P0V_OM_LADDER) $(P0V_OMC)
	@mkdir -p $(P0V_DIR)/receipts
	{ echo "om2"; $(P0V_OM_COMMIT); cat $(P0V_OM_LADDER); } | $(P0V_OMC) > $@ && chmod +x $@
$(P0V_DIR)/test_pd0_score: $(P0V_OM_SCORE) $(P0V_OMC)
	@mkdir -p $(P0V_DIR)/receipts
	{ echo "om2"; $(P0V_OM_COMMIT); cat $(P0V_OM_SCORE); } | $(P0V_OMC) > $@ && chmod +x $@
$(P0V_DIR)/c/%: tests/physics0/verify/%.c $(P0V_SRCS) $(P0V_HDRS)
	@mkdir -p $(P0V_DIR)/c $(P0V_DIR)/receipts
	$(CC) $(P0V_CFLAGS) -o $@ $< $(P0V_SRCS) -lm
$(P0V_DIR)/c/%_asan: tests/physics0/verify/%.c $(P0V_SRCS) $(P0V_HDRS)
	@mkdir -p $(P0V_DIR)/c $(P0V_DIR)/receipts
	$(CC) $(P0V_CFLAGS) $(P0V_ASAN) -o $@ $< $(P0V_SRCS) -lm
# purity: the OM verifier sources (code lines; notes excluded) and the live C verifier objects carry no generator or authority name
p0v-purity:
	@if grep -v '^note' $(P0V_OM_VERIFY) | grep -E $(P0V_FORBIDDEN); then echo "verifier OM source references generator or authority names"; exit 1; fi
	@mkdir -p $(P0V_DIR)/purity
	@for f in $(filter-out src/omega_om_units.c,$(P0V_SRCS)); do $(CC) $(P0V_CFLAGS) -c -o $(P0V_DIR)/purity/$$(basename $$f .c).o $$f || exit 1; done
	@if nm $(P0V_DIR)/purity/*.o | grep -E $(P0V_FORBIDDEN); then echo "verifier object references generator or authority symbols"; exit 1; fi
	@echo "p0v-purity: verifier OM sources and C library objects carry no generator or authority symbol"
P0V_C_TESTS = $(P0V_DIR)/c/test_pd0_ladder $(P0V_DIR)/c/test_pd0_ladder_asan $(P0V_DIR)/c/test_pd0_score $(P0V_DIR)/c/test_pd0_score_asan
test-physics0-verify: p0v-purity $(P0V_DIR)/test_pd0_fmt $(P0V_DIR)/test_pd0_ladder $(P0V_DIR)/test_pd0_score $(P0V_C_TESTS)
	./$(P0V_DIR)/test_pd0_fmt
	./$(P0V_DIR)/test_pd0_ladder
	./$(P0V_DIR)/test_pd0_score
	@for t in $(P0V_C_TESTS); do ./$$t || exit 1; done
	@echo "test-physics0-verify: PD-0 verifier formats, ladder, scorer and negative controls pass (OM-2, and the live C library plain + ASan/UBSan); receipts in $(P0V_DIR)/receipts"
endif
