# PD-0 hidden-equation benchmark substrate (Physics-0 Discovery Engine,
# spec aien-dev/physics docs/PD0_HIDDEN_EQUATION_BENCHMARK.md @ 5bd2b04, revision 3).
# Files under src/physics0/ and tests/physics0/. Picked up by `-include mk/*.mk`;
# not part of `all` or `test`. Direction 2 lane only: wire records, world
# process (generators), STAND_IN recorder and range guard, oracle + reference
# sparse solver (test-only), G0/G1 gates, Omega-language helpers. No ladder
# checker, scorer, controls or learner here (other lanes).
#
# physics0-test      G0 self-test (plain + ASan/UBSan), G5 isolation, G1 oracle
#                    calibration (V1 + V3 per level), mutant check, OSC differential
# physics0-evidence  copy the G0/G1 receipts into evidence/physics0/ (new names per cut, never overwritten)
# pd0-world          build/physics0/pd0-world <level|null> <seed>: the world process
ifndef PHYSICS0_MK
PHYSICS0_MK := 1
.PHONY: physics0-test physics0-evidence pd0-world
P0_DIR = $(OUT_DIR)/physics0
P0_OMC ?= seed/out/omc
# learner-side pure OM-2 (no generator, no world, no file I/O): G5 isolation runs on these units
P0_OM_LEARNER = src/physics0/pd0_types.om src/physics0/pd0_rng.om src/physics0/pd0_chan.om src/physics0/pd0_wire.om src/physics0/pd0_relation.om
# world-side pure OM-2
P0_OM_WORLD = $(P0_OM_LEARNER) src/physics0/pd0_world.om

$(P0_DIR)/pd0-world: $(P0_OM_WORLD) src/physics0/pd0_world_main.om $(P0_OMC)
	@mkdir -p $(P0_DIR)
	{ echo "om2"; cat $(P0_OM_WORLD) src/physics0/pd0_world_main.om; } | $(P0_OMC) > $@ && chmod +x $@

pd0-world: $(P0_DIR)/pd0-world

$(P0_DIR)/test_pd0_world: $(P0_OM_WORLD) tests/physics0/test_pd0_world.om $(P0_OMC)
	@mkdir -p $(P0_DIR)
	{ echo "om2"; cat $(P0_OM_WORLD) tests/physics0/test_pd0_world.om; } | $(P0_OMC) > $@ && chmod +x $@

$(P0_DIR)/pd0-oracle: $(P0_OM_WORLD) tests/physics0/pd0_oracle.om $(P0_OMC)
	@mkdir -p $(P0_DIR)
	{ echo "om2"; cat $(P0_OM_WORLD) tests/physics0/pd0_oracle.om; } | $(P0_OMC) > $@ && chmod +x $@

$(P0_DIR)/test_pd0_osc: $(P0_OM_LEARNER) tests/physics0/test_pd0_osc.om $(P0_OMC)
	@mkdir -p $(P0_DIR)
	{ echo "om2"; cat $(P0_OM_LEARNER) tests/physics0/test_pd0_osc.om; } | $(P0_OMC) > $@ && chmod +x $@

physics0-test: $(P0_DIR)/test_pd0_world $(P0_DIR)/pd0-oracle $(P0_DIR)/test_pd0_osc $(P0_DIR)/pd0-world
	@mkdir -p $(P0_DIR)/receipts
	./$(P0_DIR)/test_pd0_world > $(P0_DIR)/g0.out; tail -1 $(P0_DIR)/g0.out; grep -q '^PHYSICS0_G0: PASS$$' $(P0_DIR)/g0.out
	PD0_GEN_OM=src/physics0/pd0_world.om sh tests/physics0/isolation.sh $(P0_OM_LEARNER) | tee $(P0_DIR)/isolation.out | tail -1; grep -q '^PHYSICS0_ISOLATION: PASS' $(P0_DIR)/isolation.out
	./$(P0_DIR)/pd0-oracle all $(P0_DIR)/receipts > $(P0_DIR)/g1.out; cat $(P0_DIR)/g1.out; grep -q '^PHYSICS0_ORACLE: PASS$$' $(P0_DIR)/g1.out
	-./$(P0_DIR)/pd0-oracle 1 $(P0_DIR) -mutant > $(P0_DIR)/mutant.out
	@grep -q '^PHYSICS0_G1_V1_L1-mutant: FAIL' $(P0_DIR)/mutant.out && echo "PHYSICS0_MUTANT_SIGN: PASS (wrong generator sign is caught by the oracle check)" || { echo "PHYSICS0_MUTANT_SIGN: FAIL"; exit 1; }
	-./$(P0_DIR)/pd0-oracle 6 $(P0_DIR) -mutlat > $(P0_DIR)/mutant_latent.out
	@grep -q "^PHYSICS0_G1_V1_L6-mutlat: FAIL (oracle_exact FAIL, oracle_fit FAIL)" $(P0_DIR)/mutant_latent.out && echo "PHYSICS0_MUTANT_LATENT_SIGN: PASS (wrong latent sign makes oracle_fit FAIL)" || { echo "PHYSICS0_MUTANT_LATENT_SIGN: FAIL"; exit 1; }
	./$(P0_DIR)/test_pd0_osc > $(P0_DIR)/osc.out; tail -2 $(P0_DIR)/osc.out; grep -q '^PHYSICS0_OSC_DIFF: PASS$$' $(P0_DIR)/osc.out
	@echo "physics0-test: PASS (G0, G5 isolation, G1 V1 oracle all levels, V3 breach rates recorded, mutant caught, OSC differential; pure OM-2 substrate)"

# Receipts are immutable: existing evidence files are never rewritten (cp -n); each cut adds new files.
physics0-evidence: physics0-test
	mkdir -p evidence/physics0
	for f in $(P0_DIR)/receipts/pd0-oracle-*.json; do b=$$(basename "$$f" .json); cp -n "$$f" "evidence/physics0/$$b-rev3b.json"; done
	{ echo "receipt: PD0_G0"; echo "spec: aien-dev/physics docs/PD0_HIDDEN_EQUATION_BENCHMARK.md @ 5bd2b04 (rev 3, PD0DESC2)"; echo "recorder: STAND_IN"; echo "range_guard: STAND_IN"; \
	  echo "commit: $$(git rev-parse HEAD)"; echo "date_utc: $$(date -u +%Y-%m-%dT%H:%M:%SZ)"; echo "--- test_pd0_world"; cat $(P0_DIR)/g0.out; \
	  echo "--- isolation"; cat $(P0_DIR)/isolation.out; echo "--- G1 oracle"; cat $(P0_DIR)/g1.out; echo "--- osc differential"; cat $(P0_DIR)/osc.out; \
	  echo "--- mutant"; cat $(P0_DIR)/mutant.out; echo "--- mutant latent sign"; cat $(P0_DIR)/mutant_latent.out; } > evidence/physics0/pd0-g0-receipt-cut3b.txt
endif
