# Turing calibration EXP-001 lane C: sealed-data tooling.
# calibration/docs/BLINDING_PROTOCOL.md. Picked up by `-include mk/*.mk`.
# New files only: tools/turing_cal_overlap.om, calibration/scripts/*.sh.
#
# turing-cal-overlap: dev vs sealed CTR1 overlap audit helper (pure seeded OM-2).
# test-turing-cal-blinding: proves the candidate jail cannot read the sealed
#   root and the evaluator jail cannot write candidate artifacts or reach the
#   network (bubblewrap; no sudo).
.PHONY: turing-cal-overlap test-turing-cal-blinding
TCO_DIR = $(OUT_DIR)/turing-cal
TCO_TOOL = $(TCO_DIR)/turing-cal-overlap

$(TCO_TOOL): tools/turing_cal_overlap.om seed/out/omc
	@mkdir -p $(dir $@)
	seed/out/omc < tools/turing_cal_overlap.om > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

turing-cal-overlap: $(TCO_TOOL)

test-turing-cal-blinding:
	./calibration/scripts/test_blinding.sh
