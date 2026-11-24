# EXP-001 lane A (calibration profile, candidate set, power simulation).
# Pure seeded OM-2: tools/turing_cal_dev.om, tools/turing_cal_candidates.om,
# calibration/scripts/power_simulation.om (built by TXA_OMC, default seed/out/omc).
# Picked up by `-include mk/*.mk`. New files only; every variable is TXA_-prefixed
# and every target turing-exp001-a-* so no other mk/turing_exp001*.mk collides.
#
#   make turing-exp001-a-build        build the candidate tool and the power simulation
#   make turing-exp001-a-candidates   write the seven TYM0 candidates (dev seeds 1-7) + print L(M), dev L(D|M)
#   make turing-exp001-a-power        run the power simulation (fit 1-6, score 7 per crumb)
#   make turing-exp001-a-check        profile TOML vs code constants + field list (pre-freeze mode)
#   make test-turing-exp001-a         build + check + B3/consts self-test (no dev data needed)
.PHONY: turing-exp001-a-build turing-exp001-a-candidates turing-exp001-a-power turing-exp001-a-check test-turing-exp001-a
TXA_OMC ?= seed/out/omc
TXA_DEV_OM = tools/turing_cal_dev.om
TXA_DIR = $(OUT_DIR)/turing-exp001-a
TXA_CAND = $(TXA_DIR)/turing-cal-candidates
TXA_POWER = $(TXA_DIR)/power-simulation
TXA_MANIFEST = evidence/TURING_YIELD/trace_manifest_rep10_control.sha256
TXA_DATA_ROOT ?= $(HOME)/aien-data/crumbline
TXA_CAND_OUT ?= $(TXA_DIR)/candidates

$(TXA_CAND): $(TXA_DEV_OM) tools/turing_cal_candidates.om $(TXA_OMC)
	@mkdir -p $(TXA_DIR)
	(printf 'om2\n'; sed -e '/^om2$$/d' $(TXA_DEV_OM) tools/turing_cal_candidates.om) | $(TXA_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TXA_POWER): $(TXA_DEV_OM) calibration/scripts/power_simulation.om $(TXA_OMC)
	@mkdir -p $(TXA_DIR)
	(printf 'om2\n'; sed -e '/^om2$$/d' $(TXA_DEV_OM) calibration/scripts/power_simulation.om) | $(TXA_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

turing-exp001-a-build: $(TXA_CAND) $(TXA_POWER)

turing-exp001-a-candidates: $(TXA_CAND)
	@mkdir -p $(TXA_CAND_OUT)
	$(abspath $(TXA_CAND)) write $(TXA_MANIFEST) $(TXA_DATA_ROOT) evidence/TURING_YIELD $(TXA_CAND_OUT)

turing-exp001-a-power: $(TXA_POWER)
	$(abspath $(TXA_POWER)) $(TXA_MANIFEST) $(TXA_DATA_ROOT)

turing-exp001-a-check: $(TXA_CAND)
	TXA_CAND=$(abspath $(TXA_CAND)) sh calibration/scripts/check_profile.sh

test-turing-exp001-a: turing-exp001-a-build turing-exp001-a-check
	@echo "test-turing-exp001-a: pure OM-2 tools build clean, profile TOML agrees with code constants"
