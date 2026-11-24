# PD-0 learner v2 (adaptive-intelligence milestone 3, gap G3). Pure seeded OM-2.
#   test-physics0-learner-v2   isolation of the v2 learner OM units + pure OM-2 unit tests + dev-driver smoke
#   physics0-learner-v2-dev    C1: hidden-state flag and prediction quality, v1 baseline vs v2, public dev seeds
#   physics0-regime-dev        C2: regime switch between episodes, FIXED vs UPDATING vs FRESH learner
#   physics0-prior-dev         C3: wrong / stale prior injected into the updating learner
#   physics0-shift-dev         v2.1 C2: change detection + bounded forgetting; arms fixed / updating-retain / updating-v2.1 (and fresh) after a regime switch, plus a no-switch false-alarm run
#   physics0-prior21-dev       v2.1 C3: wrong / stale prior, v2 arm then v2.1 arm
# Receipts (text, deterministic, seeded) are written to tests/physics0/learner_v2/receipts/ (new files only for a new commit).
ifndef PHYSICS0_LEARNER_V2_MK
PHYSICS0_LEARNER_V2_MK := 1
.PHONY: test-physics0-learner-v2 physics0-learner-v2-dev physics0-regime-dev physics0-prior-dev p0l2-isolation physics0-shift-dev physics0-prior21-dev
P0L2_DIR = $(OUT_DIR)/physics0-learner-v2
P0L2_OMC ?= seed/out/omc
P0L2_COMMIT := $(shell git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)
P0L2_OM_COMMIT = echo 'text PD0_VERIFIER_COMMIT "$(P0L2_COMMIT)"'
P0L2_REC = tests/physics0/learner_v2/receipts

P0L2_OM_BASE = src/physics0/pd0_types.om src/physics0/pd0_rng.om src/physics0/pd0_wire.om src/physics0/ladder/pd0_codes.om src/physics0/ladder/pd0_fmt.om src/physics0/controls/pd0_receipt.om
P0L2_OM_VERIFY = $(P0L2_OM_BASE) src/physics0/ladder/pd0_ladder.om src/physics0/score/pd0_score.om src/physics0/controls/pd0_controls.om
P0L2_OM_WORLD_DRV = src/physics0/pd0_types.om src/physics0/pd0_rng.om src/physics0/pd0_chan.om src/physics0/pd0_wire.om src/physics0/pd0_relation.om src/physics0/pd0_world.om src/physics0/regime/pd0_regime.om src/physics0/ladder/pd0_codes.om src/physics0/ladder/pd0_fmt.om src/physics0/controls/pd0_receipt.om src/physics0/ladder/pd0_ladder.om src/physics0/score/pd0_score.om
P0L2_OM_ISOL_UNITS = src/physics0/learner_v2/pd0_learner.om src/physics0/ladder/pd0_fmt.om
P0L2_FORBIDDEN = 'truth_|oracle|rx_|aienos_|argus_|forge_|mmap|fork|exec|socket|getenv|system|regime'

p0l2-isolation: $(P0L2_OM_ISOL_UNITS) src/physics0/pd0_world.om
	@mkdir -p $(P0L2_DIR)
	PD0_GEN_OM=src/physics0/pd0_world.om sh tests/physics0/isolation.sh $(P0L2_OM_ISOL_UNITS) | tee $(P0L2_DIR)/isolation.out | tail -1; grep -q '^PHYSICS0_ISOLATION: PASS' $(P0L2_DIR)/isolation.out
	@if grep -hv '^[[:space:]]*note' $(P0L2_OM_ISOL_UNITS) | grep -E $(P0L2_FORBIDDEN); then echo "v2 learner OM source references forbidden symbol"; exit 1; fi
	@echo "p0l2-isolation: v2 learner OM sources carry no generator, world, regime, file, process or authority symbol"

$(P0L2_DIR)/test_pd0_learner2: $(P0L2_OM_VERIFY) src/physics0/learner_v2/pd0_learner.om tests/physics0/learner_v2/test_pd0_learner2.om $(P0L2_OMC)
	@mkdir -p $(P0L2_DIR)
	{ echo "om2"; $(P0L2_OM_COMMIT); cat $(P0L2_OM_VERIFY) src/physics0/learner_v2/pd0_learner.om tests/physics0/learner_v2/test_pd0_learner2.om; } | $(P0L2_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@
$(P0L2_DIR)/pd0-dev2: $(P0L2_OM_WORLD_DRV) src/physics0/learner_v2/pd0_learner.om tests/physics0/learner_v2/pd0_dev2.om $(P0L2_OMC)
	@mkdir -p $(P0L2_DIR)
	{ echo "om2"; $(P0L2_OM_COMMIT); cat $(P0L2_OM_WORLD_DRV) src/physics0/learner_v2/pd0_learner.om tests/physics0/learner_v2/pd0_dev2.om; } | $(P0L2_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@
$(P0L2_DIR)/pd0-dev1: $(P0L2_OM_WORLD_DRV) src/physics0/learner/pd0_learner.om tests/physics0/learner_v2/pd0_dev1.om $(P0L2_OMC)
	@mkdir -p $(P0L2_DIR)
	{ echo "om2"; $(P0L2_OM_COMMIT); cat $(P0L2_OM_WORLD_DRV) src/physics0/learner/pd0_learner.om tests/physics0/learner_v2/pd0_dev1.om; } | $(P0L2_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

test-physics0-learner-v2: p0l2-isolation $(P0L2_DIR)/test_pd0_learner2 $(P0L2_DIR)/pd0-dev2
	./$(P0L2_DIR)/test_pd0_learner2 | tail -1 | grep -q '^PHYSICS0_LEARNER2_UNIT: PASS'
	./$(P0L2_DIR)/pd0-dev2 flag 1 1 > $(P0L2_DIR)/smoke.out
	grep -q '^P0V2F-SUM learner=v2 level=L6 seeds=1 hidden_fired=1' $(P0L2_DIR)/smoke.out
	./$(P0L2_DIR)/pd0-dev2 detect 1 1 > $(P0L2_DIR)/smoke-detect.out
	grep -q "^P0V21D-SUM level=L1 false_alarms=0/1 switch_detected=1/1" $(P0L2_DIR)/smoke-detect.out
	@echo "test-physics0-learner-v2: PASS (isolation, pure OM-2 unit tests, dev driver smoke)"

# C1: one line per level and seed for the seal-1 learner (baseline) and v2, then the acceptance check. Seeds 1-5 are the acceptance seeds; 6-25 are extra dev seeds.
physics0-learner-v2-dev: $(P0L2_DIR)/pd0-dev1 $(P0L2_DIR)/pd0-dev2
	@mkdir -p $(P0L2_REC)
	{ echo "receipt: PD0_LEARNER_V2_C1"; echo "commit: $$(git rev-parse HEAD)"; echo "kind: development evidence, public dev seeds only; not a sealed run, not scientific verification"; \
	  ./$(P0L2_DIR)/pd0-dev1 flag 1 25; ./$(P0L2_DIR)/pd0-dev2 flag 1 25; } > $(P0L2_DIR)/c1.txt
	bash tests/physics0/learner_v2/c1_check.sh $(P0L2_DIR)/c1.txt | tee -a $(P0L2_DIR)/c1.txt
	cp $(P0L2_DIR)/c1.txt $(P0L2_REC)/c1-$$(git rev-parse --short=12 HEAD).txt
physics0-regime-dev: $(P0L2_DIR)/pd0-dev2
	@mkdir -p $(P0L2_REC)
	{ echo "receipt: PD0_LEARNER_V2_C2"; echo "commit: $$(git rev-parse HEAD)"; echo "kind: development evidence, public dev seeds only; not a sealed run, not scientific verification"; ./$(P0L2_DIR)/pd0-dev2 regime 1 5; } > $(P0L2_DIR)/c2.txt
	cp $(P0L2_DIR)/c2.txt $(P0L2_REC)/c2-$$(git rev-parse --short=12 HEAD).txt
physics0-prior-dev: $(P0L2_DIR)/pd0-dev2
	@mkdir -p $(P0L2_REC)
	{ echo "receipt: PD0_LEARNER_V2_C3"; echo "commit: $$(git rev-parse HEAD)"; echo "kind: development evidence, public dev seeds only; not a sealed run, not scientific verification"; ./$(P0L2_DIR)/pd0-dev2 prior 1 5; } > $(P0L2_DIR)/c3.txt
	cp $(P0L2_DIR)/c3.txt $(P0L2_REC)/c3-$$(git rev-parse --short=12 HEAD).txt

physics0-shift-dev: $(P0L2_DIR)/pd0-dev2
	@mkdir -p $(P0L2_REC)
	{ echo "receipt: PD0_LEARNER_V21_SHIFT"; echo "commit: $$(git rev-parse HEAD)"; echo "kind: development evidence, public dev seeds 1-25 (detector thresholds tuned on seeds 101-150 and 201-250); not a sealed run, not scientific verification"; ./$(P0L2_DIR)/pd0-dev2 shift 1 25; } > $(P0L2_DIR)/shift.txt
	cp $(P0L2_DIR)/shift.txt $(P0L2_REC)/c4-shift-$$(git rev-parse --short=12 HEAD).txt
physics0-prior21-dev: $(P0L2_DIR)/pd0-dev2
	@mkdir -p $(P0L2_REC)
	{ echo "receipt: PD0_LEARNER_V21_PRIOR"; echo "commit: $$(git rev-parse HEAD)"; echo "kind: development evidence, public dev seeds 1-5; not a sealed run, not scientific verification"; ./$(P0L2_DIR)/pd0-dev2 prior21 1 5; } > $(P0L2_DIR)/prior21.txt
	cp $(P0L2_DIR)/prior21.txt $(P0L2_REC)/c4-prior21-$$(git rev-parse --short=12 HEAD).txt
endif
