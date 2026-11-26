# DUAL-3a: read-only observation tap at decision site "jspace.residency"
# (ADR 0031 section 7.3; src/runtime/rx_jspace.om js_forge_enforce).
# Pure seeded OM-2 (seed/out/omc). Not part of `all` or `test`. Host only; no GPU.
#
# test-dual-jspace-tap          parity suite in pure seeded OM-2
# test-dual-jspace-tap-hostile  negative control: a hostile observer mutates residency
#                               costs during observation; the parity suite must FAIL
# dual-jspace-tap-purity        rx_jspace.om references no aienos_cap_*, rx_gen_*, aegis
# dual-jspace-tap-hygiene       the hostile seam exists in tests only (grep src/)
# bench-dual-jspace-tap         multi-round observer-off vs recording-observer workload
# test-dual-3a                  purity + hygiene + parity + hostile
ifndef DUAL_JSPACE_TAP_MK
DUAL_JSPACE_TAP_MK := 1
.PHONY: test-dual-jspace-tap test-dual-jspace-tap-hostile dual-jspace-tap-purity \
	dual-jspace-tap-hygiene bench-dual-jspace-tap test-dual-3a
DJT_OMC ?= seed/out/omc
DJT_DIR = $(OUT_DIR)/tests-dual-jspace-tap
DJT_OM_LIB = seed/ng/sha256.om src/runtime/rx_jspace.om
DJT_OM_TEST = tests/runtime/rx_dual_jspace_tap.om
DJT_OM_BENCH = tests/runtime/rx_dual_jspace_tap_bench.om

$(DJT_DIR)/rx_dual_jspace_tap: $(DJT_OM_LIB) $(DJT_OM_TEST) $(DJT_OMC)
	@mkdir -p $(DJT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(DJT_OM_LIB) $(DJT_OM_TEST) ) | $(DJT_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(DJT_DIR)/rx_dual_jspace_tap_hostile: $(DJT_OM_LIB) $(DJT_OM_TEST) $(DJT_OMC)
	@mkdir -p $(DJT_DIR)
	@awk '{ print; if ($$0 ~ /djt_check_obs bud/) print "    put js_costs 2 100000.0f64" }' $(DJT_OM_TEST) > $(DJT_DIR)/hostile.om
	@! cmp -s $(DJT_OM_TEST) $(DJT_DIR)/hostile.om || { echo "hostile observer injection did not apply"; exit 1; }
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(DJT_OM_LIB) $(DJT_DIR)/hostile.om ) | $(DJT_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(DJT_DIR)/rx_dual_jspace_tap_bench: $(DJT_OM_LIB) $(DJT_OM_BENCH) $(DJT_OMC)
	@mkdir -p $(DJT_DIR)
	( echo om2; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(DJT_OM_LIB) $(DJT_OM_BENCH) ) | $(DJT_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

test-dual-jspace-tap: $(DJT_DIR)/rx_dual_jspace_tap
	./$(DJT_DIR)/rx_dual_jspace_tap
	@echo "test-dual-jspace-tap: parity with and without the observer (pure seeded OM-2)"

test-dual-jspace-tap-hostile: $(DJT_DIR)/rx_dual_jspace_tap_hostile
	@if ./$(DJT_DIR)/rx_dual_jspace_tap_hostile; then \
		echo "test-dual-jspace-tap-hostile: a hostile observer changed decisions and went UNDETECTED"; exit 1; fi
	@echo "test-dual-jspace-tap-hostile: hostile observer detected (parity suite failed as required)"

dual-jspace-tap-purity: src/runtime/rx_jspace.om
	@if grep -Eq '\b(aienos_cap_|rx_gen_|aegis)' src/runtime/rx_jspace.om ; then \
		echo "rx_jspace.om references an authority or promotion symbol"; exit 1; fi
	@echo "dual-jspace-tap-purity: rx_jspace.om references no aienos_cap_*, rx_gen_* or aegis symbol"

dual-jspace-tap-hygiene:
	@if grep -rn 'DUAL_TAP_HOSTILE' src/ ; then \
		echo "the hostile test seam leaked into src/"; exit 1; fi
	@echo "dual-jspace-tap-hygiene: DUAL_TAP_HOSTILE appears nowhere under src/"

bench-dual-jspace-tap: $(DJT_DIR)/rx_dual_jspace_tap_bench
	./$(DJT_DIR)/rx_dual_jspace_tap_bench

test-dual-3a: dual-jspace-tap-purity dual-jspace-tap-hygiene test-dual-jspace-tap test-dual-jspace-tap-hostile
	@echo "test-dual-3a: DUAL-3a tap implemented; DUAL_ADVISORY_SCHEDULER not claimed"
endif
