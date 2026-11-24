# PD-0 learner (Physics-0 Discovery Engine, Direction 4): src/physics0/learner,
# tests/physics0/learner. Pure seeded OM-2: the learner links only the verifier's
# byte formats (ladder/pd0_fmt.om, pd0_rng.om, pd0_wire.om) and never the
# generators, the world, or any file I/O (isolation check below). The harness
# drives the world process and a test-only truth process over pipes.
#
# test-physics0-learner     isolation + pure OM-2 unit tests + protocol v2 + pd0b run smoke
# physics0-learner-dev      development run: levels L0..L6 + null, seeds 1..5
# physics0-learner-evidence copy new receipts into evidence/physics0/learner/ (cp -n)
# physics0-pd0b-run / physics0-pd0b-freeze  PD-0b harness against an external world (see the end of this file)
ifndef PHYSICS0_LEARNER_MK
PHYSICS0_LEARNER_MK := 1
.PHONY: test-physics0-learner physics0-learner-dev physics0-learner-evidence p0l-isolation
P0L_DIR = $(OUT_DIR)/physics0-learner
P0L_OMC ?= seed/out/omc
P0L_COMMIT := $(shell git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)
P0L_OM_COMMIT = echo 'text PD0_VERIFIER_COMMIT "$(P0L_COMMIT)"'

# Kept for mk/physics0-pd1.mk (live C planner still links the C learner and verifier)
P0L_CFLAGS = -std=c11 -Wall -Wextra -Werror -pedantic -Wno-misleading-indentation -O2 -D_POSIX_C_SOURCE=200809L -ffp-contract=off -fno-fast-math \
  -Isrc -Isrc/physics0/ladder -Isrc/physics0/score -Isrc/physics0/controls -Isrc/physics0/learner -Wno-pedantic
P0L_LEARNER_SRCS = src/physics0/learner/pd0_learner.c src/physics0/ladder/pd0_fmt.c
P0L_VERIFIER_SRCS = src/physics0/ladder/pd0_codes.c src/physics0/ladder/pd0_ladder.c src/physics0/score/pd0_score.c src/physics0/controls/pd0_controls.c
P0L_HDRS = src/physics0/learner/pd0_learner.h src/physics0/ladder/pd0_fmt.h src/physics0/ladder/pd0_rng.h src/physics0/ladder/pd0_ladder.h src/physics0/ladder/pd0_codes.h src/physics0/score/pd0_score.h src/physics0/controls/pd0_controls.h

# Pure seeded OM-2 module lists
P0L_OM_BASE = src/physics0/pd0_types.om src/physics0/pd0_rng.om src/physics0/pd0_wire.om src/physics0/ladder/pd0_codes.om src/physics0/ladder/pd0_fmt.om src/physics0/controls/pd0_receipt.om
P0L_OM_LEARNER = $(P0L_OM_BASE) src/physics0/learner/pd0_learner.om
P0L_OM_VERIFY = $(P0L_OM_BASE) src/physics0/ladder/pd0_ladder.om src/physics0/score/pd0_score.om src/physics0/controls/pd0_controls.om
P0L_OM_WORLD = src/physics0/pd0_types.om src/physics0/pd0_rng.om src/physics0/pd0_chan.om src/physics0/pd0_wire.om src/physics0/pd0_relation.om src/physics0/pd0_world.om
P0L_OM_ISOL_UNITS = src/physics0/learner/pd0_learner.om src/physics0/learner/pd0_learner_main.om src/physics0/ladder/pd0_fmt.om
P0L_FORBIDDEN = 'truth_|oracle|rx_|aienos_|argus_|forge_|mmap|fork|exec|socket|getenv|system'

P0L_LEVELS ?= 0 1 2 3 4 5 6 null
P0L_SEEDS ?= 1 2 3 4 5

# G5 isolation (spec I10) on the learner OM units, plus: no truth/oracle/process/socket/authority symbol
p0l-isolation: $(P0L_OM_ISOL_UNITS) src/physics0/pd0_world.om
	@mkdir -p $(P0L_DIR)
	PD0_GEN_OM=src/physics0/pd0_world.om sh tests/physics0/isolation.sh $(P0L_OM_ISOL_UNITS) | tee $(P0L_DIR)/isolation.out | tail -1; grep -q '^PHYSICS0_ISOLATION: PASS' $(P0L_DIR)/isolation.out
	@if grep -hv '^[[:space:]]*note' $(P0L_OM_ISOL_UNITS) | grep -E $(P0L_FORBIDDEN); then echo "learner OM source references forbidden symbol"; exit 1; fi
	@echo "p0l-isolation: learner OM sources carry no generator, world, file, process or authority symbol"

$(P0L_DIR)/pd0-learner: $(P0L_OM_LEARNER) src/physics0/learner/pd0_learner_main.om $(P0L_OMC)
	@mkdir -p $(P0L_DIR)
	{ echo "om2"; $(P0L_OM_COMMIT); cat $(P0L_OM_LEARNER) src/physics0/learner/pd0_learner_main.om; } | $(P0L_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@
$(P0L_DIR)/test_pd0_learner: $(P0L_OM_VERIFY) src/physics0/learner/pd0_learner.om tests/physics0/learner/test_pd0_learner.om $(P0L_OMC)
	@mkdir -p $(P0L_DIR)
	{ echo "om2"; $(P0L_OM_COMMIT); cat $(P0L_OM_VERIFY) src/physics0/learner/pd0_learner.om tests/physics0/learner/test_pd0_learner.om; } | $(P0L_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@
$(P0L_DIR)/pd0-harness: $(P0L_OM_VERIFY) src/physics0/learner/pd0_learner.om tests/physics0/learner/pd0_harness.om $(P0L_OMC)
	@mkdir -p $(P0L_DIR)
	{ echo "om2"; $(P0L_OM_COMMIT); cat $(P0L_OM_VERIFY) src/physics0/learner/pd0_learner.om tests/physics0/learner/pd0_harness.om; } | $(P0L_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@
$(P0L_DIR)/pd0-truth: $(P0L_OM_WORLD) tests/physics0/learner/pd0_truth_main.om $(P0L_OMC)
	@mkdir -p $(P0L_DIR)
	{ echo "om2"; cat $(P0L_OM_WORLD) tests/physics0/learner/pd0_truth_main.om; } | $(P0L_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@
$(P0L_DIR)/test_pd0_protocol_v2: $(P0L_OM_WORLD) tests/physics0/learner/test_pd0_protocol_v2.om $(P0L_OMC)
	@mkdir -p $(P0L_DIR)
	{ echo "om2"; cat $(P0L_OM_WORLD) tests/physics0/learner/test_pd0_protocol_v2.om; } | $(P0L_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

test-physics0-learner: p0l-isolation $(P0L_DIR)/test_pd0_learner $(P0L_DIR)/pd0-learner $(P0L_DIR)/test_pd0_protocol_v2
	./$(P0L_DIR)/test_pd0_learner
	./$(P0L_DIR)/test_pd0_protocol_v2
	sh tests/physics0/learner/test_pd0b_run.sh
	@echo "test-physics0-learner: PASS (isolation, pure OM-2 unit tests, protocol v2 world ops)"

# development run on the world process; results in $(P0L_DIR)/dev/ (one line per instance + ledger/law/json per instance)
physics0-learner-dev: $(P0L_DIR)/pd0-harness $(P0L_DIR)/pd0-truth $(OUT_DIR)/physics0/pd0-world
	@mkdir -p $(P0L_DIR)/dev
	@: > $(P0L_DIR)/dev/results.txt
	for l in $(P0L_LEVELS); do for s in $(P0L_SEEDS); do ./$(P0L_DIR)/pd0-harness $(OUT_DIR)/physics0/pd0-world $(P0L_DIR)/pd0-truth $$l $$s $(P0L_DIR)/dev | tee -a $(P0L_DIR)/dev/results.txt; done; done
	@echo "physics0-learner-dev: done, $$(wc -l < $(P0L_DIR)/dev/results.txt) instances in $(P0L_DIR)/dev/results.txt"

# receipts are immutable: new files only (cp -n)
physics0-learner-evidence: physics0-learner-dev test-physics0-learner
	@mkdir -p evidence/physics0/learner
	{ echo "receipt: PD0_LEARNER_DEV"; echo "commit: $$(git rev-parse HEAD)"; echo "date_utc: $$(date -u +%Y-%m-%dT%H:%M:%SZ)"; echo "levels: $(P0L_LEVELS)"; echo "seeds: $(P0L_SEEDS) (development seeds; HOLDOUT/TRIAL/REP withheld by the harness)"; echo "--- isolation"; cat $(P0L_DIR)/isolation.out; echo "--- results"; cat $(P0L_DIR)/dev/results.txt; } > $(P0L_DIR)/dev/receipt.txt
	cp -n $(P0L_DIR)/dev/receipt.txt evidence/physics0/learner/pd0-learner-dev-$$(git rev-parse --short=12 HEAD).txt

# PD-0b run harness (docs/physics0/PD0_PROTOCOL_V2.md): the frozen learner against an EXTERNAL world binary.
# physics0-pd0b-run     PD0_WORLD_BIN=<world> PD0B_SEEDS=<file of "level_index seed", five per level>
#                       writes one NEW receipt evidence/physics0/pd0b/PD0B_RUN-<commit>-<world sha12>.txt (never overwrites)
# physics0-pd0b-freeze  prints the frozen-directory tree hashes, file hashes and harness digest (print only)
.PHONY: physics0-pd0b-run physics0-pd0b-freeze
physics0-pd0b-run: $(P0L_DIR)/pd0-harness
	@test -n "$(PD0_WORLD_BIN)" || { echo "physics0-pd0b-run: set PD0_WORLD_BIN=<world binary>"; exit 2; }
	@test -n "$(PD0B_SEEDS)" || { echo "physics0-pd0b-run: set PD0B_SEEDS=<seeds file>"; exit 2; }
	sh tests/physics0/learner/pd0b_run.sh $(P0L_DIR)/pd0-harness "$(PD0_WORLD_BIN)" "$(PD0B_SEEDS)" "$(PD0B_NOTE)"
physics0-pd0b-freeze: $(P0L_DIR)/pd0-harness
	@sh tests/physics0/learner/pd0b_freeze.sh $(P0L_DIR)/pd0-harness
endif
