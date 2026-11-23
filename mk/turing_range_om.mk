# SPDX-License-Identifier: Apache-2.0
# Turing Yield coder A in Omega (L111): src/turing/tc_range.om, built with the repository's own
# seed/out/omc after seed/ng/sha256.om, checked against the C reference turing-coder
# (mk/turing_exp001_b.mk) by tests/turing/tc_range_om.sh. Picked up by `-include mk/*.mk`.
# Spec and bound: docs/turing/TURING_YIELD_RANGE_CODER_OM.md.
.PHONY: test-turing-range-om
TROM_DIR = $(OUT_DIR)/tests-turing-range-om

test-turing-range-om: $(TC_TOOL)
	@mkdir -p $(TROM_DIR)
	sh tests/turing/tc_range_om.sh ./$(TC_TOOL) $(TROM_DIR)
