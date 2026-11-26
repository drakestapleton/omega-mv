# tools/omega_emit (aien-spark/omega#445, one-layer stage 2): legacy OSC binary IR tools
# (omega_emit.c, x445.c, typediff.c) depended on removed src/compiler/ (bb7f2dd68) and are retired.
# Pure-OM helpers fake445.om and examples_expected.om remain buildable via seed/out/omc.
ifndef OMEGA_EMIT_MK
OMEGA_EMIT_MK := 1
.PHONY: omega-emit test-omega-emit test-exp445
OME_DIR = $(OUT_DIR)/omega_emit

$(OME_DIR)/fake445: tools/exp445/fake445.om seed/out/omc
	@mkdir -p $(OME_DIR)
	seed/out/omc < tools/exp445/fake445.om > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(OME_DIR)/examples_expected: tools/exp445/examples_expected.om seed/out/omc
	@mkdir -p $(OME_DIR)
	seed/out/omc < tools/exp445/examples_expected.om > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

omega-emit test-omega-emit test-exp445:
	@echo "MISSING_IMPLEMENTATION: $@ requires removed legacy src/compiler/ (osc_ir.h / oscc, removed in bb7f2dd68); legacy C tools retired" >&2
	@exit 3
endif
