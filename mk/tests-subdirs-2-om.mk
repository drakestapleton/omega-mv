# Subdirectory tests/ CPU-only pure seeded OM-2 migration wave 2 (tests-subdirs-2).
# Pure seeded OM-2 twins of:
#   tests/universal/arithmetic.c
#   tests/arboris/caproot_issuer.c
#   tests/fabric/fabric_living_test.c
#   tests/model/{world_model,world_explore,world_diff}.c
# Physics-free, host-only, CPU-only, zero GPU access.
# Picked up automatically by `-include mk/*.mk`.

TSUB2_OMC ?= seed/out/omc
OUT_DIR   ?= build

TSUB2_ARITH_SRCS := tests/universal/arithmetic.om
TSUB2_ARITH_BIN   = $(OUT_DIR)/universal_arithmetic_om

TSUB2_CAPROOT_SRCS := \
	seed/authority/cap_table_om2.om \
	src/runtime/rx_caproot.om \
	seed/authority/caproot.om \
	tests/arboris/caproot_issuer.om
TSUB2_CAPROOT_BIN = $(OUT_DIR)/arboris_caproot_issuer_om

TSUB2_FABLIVING_SRCS := \
	seed/ng/sha256.om \
	src/runtime/aien_machine_id.om \
	src/fabric/fab_hmac.om \
	src/fabric/fab_loopback.om \
	src/fabric/fabric.om \
	src/fabric/fab_dispatch.om \
	src/runtime/rx_compose.om \
	tests/fabric/fabric_living_test.om
TSUB2_FABLIVING_BIN = $(OUT_DIR)/fabric_living_test_om

TSUB2_WDIFF_SRCS := \
	seed/ng/sha256.om \
	src/runtime/rx_world.om \
	tests/model/world_diff.om
TSUB2_WDIFF_BIN = $(OUT_DIR)/model_world_diff_om

$(TSUB2_ARITH_BIN): $(TSUB2_ARITH_SRCS) $(TSUB2_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TSUB2_ARITH_SRCS)) | $(TSUB2_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TSUB2_CAPROOT_BIN): $(TSUB2_CAPROOT_SRCS) $(TSUB2_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TSUB2_CAPROOT_SRCS)) | $(TSUB2_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TSUB2_FABLIVING_BIN): $(TSUB2_FABLIVING_SRCS) $(TSUB2_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TSUB2_FABLIVING_SRCS)) | $(TSUB2_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TSUB2_WDIFF_BIN): $(TSUB2_WDIFF_SRCS) $(TSUB2_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TSUB2_WDIFF_SRCS)) | $(TSUB2_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-universal-arithmetic-om test-arboris-caproot-issuer-om \
	test-fabric-living-om test-model-world-diff-om test-tests-subdirs-2-om

test-universal-arithmetic-om: $(TSUB2_ARITH_BIN)
	@got=$$(printf '10 3\n0 1\n18446744073709551615 1\n18446744073709551615 2\n' | $(abspath $(TSUB2_ARITH_BIN))); \
	want=$$(printf '13 7 30 3\n1 18446744073709551615 0 0\n0 18446744073709551614 18446744073709551615 18446744073709551615\n1 18446744073709551613 18446744073709551614 9223372036854775807'); \
	[ "$$got" = "$$want" ] || { echo "FAIL universal_arithmetic_om mismatch"; exit 1; }; \
	rc=0; printf '5 0\n' | $(abspath $(TSUB2_ARITH_BIN)) >/dev/null || rc=$$?; \
	[ "$$rc" = 2 ] || { echo "FAIL universal_arithmetic_om div0 rc=$$rc"; exit 1; }; \
	echo "PASS universal_arithmetic_om (4 boundary rows + div-by-zero exit 2)"

test-arboris-caproot-issuer-om: $(TSUB2_CAPROOT_BIN)
	$(abspath $(TSUB2_CAPROOT_BIN))

test-fabric-living-om: $(TSUB2_FABLIVING_BIN)
	$(abspath $(TSUB2_FABLIVING_BIN))

test-model-world-diff-om: $(TSUB2_WDIFF_BIN)
	$(abspath $(TSUB2_WDIFF_BIN))

test-tests-subdirs-2-om: \
	test-universal-arithmetic-om \
	test-arboris-caproot-issuer-om \
	test-fabric-living-om \
	test-model-world-diff-om
