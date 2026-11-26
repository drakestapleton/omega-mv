# PD-0 independent verifier (Direction 3): ladder checker, scorer, negative
# controls, append-only receipts. Standalone under src/physics0/{ladder,score,
# controls} and tests/physics0/verify. Not part of `all` or `test`.
# Test-only truth generators (tests/physics0/verify/pd0_bundle.om) copy the spec
# equations; the verifier sources never see them (p0v-purity checks it).
#
# test-physics0-verify   formats + ladder + scorer/controls in pure seeded OM-2
ifndef PHYSICS0_VERIFY_MK
PHYSICS0_VERIFY_MK := 1
.PHONY: test-physics0-verify p0v-purity
P0V_COMMIT := $(shell git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)
P0V_DIR = $(OUT_DIR)/tests-physics0-verify
P0V_OMC ?= seed/out/omc
# Pure OM-2 (wave 36; C verifier library retired in Stage 1 Wave S1-3): formats, codes, receipts,
# ladder checker, scorer and negative controls, built from .om by the seed omc. The receipt commit
# string is prepended as an OM text constant. OM-2 itself traps an out-of-range array get or put (3),
# signed overflow (1), div or rem by 0 (2), a shift amount outside 0..width-1 (7) and an out-of-range
# conversion (5) (docs/one_layer/OMEGESE.md 9.3); unsigned arithmetic wraps as in C.
P0V_OM_BASE = src/physics0/pd0_types.om src/physics0/pd0_rng.om src/physics0/pd0_wire.om src/physics0/ladder/pd0_codes.om src/physics0/ladder/pd0_fmt.om src/physics0/controls/pd0_receipt.om
P0V_OM_VERIFY = $(P0V_OM_BASE) src/physics0/ladder/pd0_ladder.om src/physics0/score/pd0_score.om src/physics0/controls/pd0_controls.om
P0V_OM_FMT = $(P0V_OM_BASE) tests/physics0/verify/test_pd0_fmt.om
P0V_OM_LADDER = $(P0V_OM_VERIFY) tests/physics0/verify/pd0_bundle.om tests/physics0/verify/test_pd0_ladder.om
P0V_OM_SCORE = $(P0V_OM_VERIFY) tests/physics0/verify/pd0_bundle.om tests/physics0/verify/test_pd0_score.om
P0V_OM_COMMIT = echo 'text PD0_VERIFIER_COMMIT "$(P0V_COMMIT)"'
# the verifier must not contain generator knowledge: no symbol or string from the test truth generators
P0V_FORBIDDEN = 'truth_|oracle_rel|rx_|aienos_|argus_|forge_|mmap|fork|exec|socket'
$(P0V_DIR)/test_pd0_fmt: $(P0V_OM_FMT) $(P0V_OMC)
	@mkdir -p $(P0V_DIR)/receipts
	{ echo "om2"; $(P0V_OM_COMMIT); cat $(P0V_OM_FMT); } | $(P0V_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@
$(P0V_DIR)/test_pd0_ladder: $(P0V_OM_LADDER) $(P0V_OMC)
	@mkdir -p $(P0V_DIR)/receipts
	{ echo "om2"; $(P0V_OM_COMMIT); cat $(P0V_OM_LADDER); } | $(P0V_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@
$(P0V_DIR)/test_pd0_score: $(P0V_OM_SCORE) $(P0V_OMC)
	@mkdir -p $(P0V_DIR)/receipts
	{ echo "om2"; $(P0V_OM_COMMIT); cat $(P0V_OM_SCORE); } | $(P0V_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@
# purity: the OM verifier sources (code lines; notes excluded) carry no generator or authority name
p0v-purity:
	@if grep -hv '^[[:space:]]*note' $(P0V_OM_VERIFY) | grep -E $(P0V_FORBIDDEN); then echo "verifier OM source references generator or authority names"; exit 1; fi
	@# bite control: the same scan must catch each forbidden name planted in a copy of a verifier unit
	@mkdir -p $(P0V_DIR)/purity
	@for p in '  x = truth_get 0' '  oracle_rel_read 1' '  rx_world_init 0' '  aienos_cap_mint 0' '  pid = fork'; do \
		{ cat src/physics0/score/pd0_score.om; printf '%s\n' "$$p"; } > $(P0V_DIR)/purity/plant.om; \
		grep -hv '^[[:space:]]*note' $(P0V_DIR)/purity/plant.om | grep -qE $(P0V_FORBIDDEN) \
			|| { echo "p0v-purity: the OM scan does not bite on planted '$$p'"; exit 1; }; \
	done
	@echo "p0v-purity: verifier OM sources carry no generator or authority symbol (the OM scan bites on 5 planted names)"
test-physics0-verify: p0v-purity $(P0V_DIR)/test_pd0_fmt $(P0V_DIR)/test_pd0_ladder $(P0V_DIR)/test_pd0_score
	./$(P0V_DIR)/test_pd0_fmt
	./$(P0V_DIR)/test_pd0_ladder
	./$(P0V_DIR)/test_pd0_score
	@echo "test-physics0-verify: PD-0 verifier formats, ladder, scorer and negative controls pass (pure OM-2); receipts in $(P0V_DIR)/receipts"
endif
