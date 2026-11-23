# Turing Yield TY-1 (math contract) + TY-2 (held-out predictive compression)
# in pure seeded OM-2. docs/turing/TURING_YIELD_PROFILE_V0.md. Picked up by
# `-include mk/*.mk` in the Makefile.
#
# test-turing-yield: runs the pure OM-2 test suite twice and verifies
# byte-identical .det output, then runs the pure OM-2 CLI fixture check twice
# and verifies byte-identical output (fixed-point determinism).
.PHONY: test-turing-yield turing-yield
TY_OM_LIB = src/turing/ty_core_lib.om
TY_DIR = $(OUT_DIR)/tests-turing-yield
TY_TEST = $(TY_DIR)/test_ty_math
TY_TOOL = $(TY_DIR)/turing-yield
TY_FIX_A = tests/turing/fixtures/ctr1_seed1_crumbs05-07.ctr
TY_FIX_B = tests/turing/fixtures/ctr1_seed1_crumbs10-12.ctr

$(TY_TEST): tests/turing/test_ty_math.om $(TY_OM_LIB) seed/out/omc
	@mkdir -p $(TY_DIR)
	cat $(TY_OM_LIB) tests/turing/test_ty_math.om | seed/out/omc > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TY_TOOL): tools/turing_yield.om $(TY_OM_LIB) seed/out/omc
	@mkdir -p $(TY_DIR)
	cat $(TY_OM_LIB) tools/turing_yield.om | seed/out/omc > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

turing-yield: $(TY_TOOL)

test-turing-yield: $(TY_TEST) $(TY_TOOL)
	./$(TY_TEST) $(TY_DIR)/run1
	./$(TY_TEST) $(TY_DIR)/run2
	cmp $(TY_DIR)/run1.det $(TY_DIR)/run2.det
	./$(TY_TOOL) fixture $(TY_FIX_A) $(TY_FIX_B) > $(TY_DIR)/fixture_1.txt
	./$(TY_TOOL) fixture $(TY_FIX_A) $(TY_FIX_B) > $(TY_DIR)/fixture_2.txt
	cmp $(TY_DIR)/fixture_1.txt $(TY_DIR)/fixture_2.txt
	@echo "test-turing-yield: pure OM-2 T arithmetic, records and fixture scores pass deterministically"
