# tools/omega_emit (aien-spark/omega#445, one-layer stage 2): constrained structured emission of OSC
# binary IR, and tools/exp445 (the representation experiment driver helper).
# Picked up by `-include mk/*.mk`; not part of `all` or `test`.
#
# omega-emit          build/omega_emit/{omega_emit,x445,fake445,typediff}
# test-omega-emit     omega_emit: every op of the schema, step refusals with reasons, negative controls,
#                     lift -> emit byte-identical over the compiler corpus; x445 helper checks
# test-exp445         driver dry run against a fake local endpoint (no model, no network beyond loopback);
#                     the r3 worked examples in both forms through the sealed harness; G0; held-out name check
#
# NOTE (bb7f2dd68): legacy C compiler src/compiler/ (osc_ir.h, oscc) was removed during the OM-2 cutover.
# Pure-OM helpers fake445.om and examples_expected.om remain buildable; the C tools omega_emit.c, x445.c,
# and typediff.c have no pure-OM replacement yet and fail closed with MISSING_IMPLEMENTATION when
# src/compiler/osc_ir.h is absent.
ifndef OMEGA_EMIT_MK
OMEGA_EMIT_MK := 1
.PHONY: omega-emit test-omega-emit test-exp445
OME_DIR = $(OUT_DIR)/omega_emit
OME_CFLAGS = -std=gnu11 -Wall -Wextra -Werror -D_GNU_SOURCE -O2 -Isrc -Isrc/compiler
OME_OSC_LIB = $(filter-out src/compiler/oscc_main.c,$(wildcard src/compiler/*.c)) src/omega_om_units.c

$(OME_DIR)/fake445: tools/exp445/fake445.om seed/out/omc
	@mkdir -p $(OME_DIR)
	seed/out/omc < tools/exp445/fake445.om > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(OME_DIR)/examples_expected: tools/exp445/examples_expected.om seed/out/omc
	@mkdir -p $(OME_DIR)
	seed/out/omc < tools/exp445/examples_expected.om > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

ifneq ($(wildcard src/compiler/osc_ir.h),)
$(OME_DIR)/omega_emit: tools/omega_emit/omega_emit.c $(OME_OSC_LIB) $(wildcard src/compiler/*.h)
	@mkdir -p $(OME_DIR)
	$(CC) $(OME_CFLAGS) -o $@ tools/omega_emit/omega_emit.c $(OME_OSC_LIB)

$(OME_DIR)/x445: tools/exp445/x445.c $(OME_OSC_LIB) $(wildcard src/compiler/*.h)
	@mkdir -p $(OME_DIR)
	$(CC) $(OME_CFLAGS) -o $@ tools/exp445/x445.c $(OME_OSC_LIB) -lm

$(OME_DIR)/typediff: tools/omega_emit/typediff.c $(OME_OSC_LIB) $(wildcard src/compiler/*.h)
	@mkdir -p $(OME_DIR)
	$(CC) $(OME_CFLAGS) -o $@ tools/omega_emit/typediff.c $(OME_OSC_LIB)

omega-emit: $(OME_DIR)/omega_emit $(OME_DIR)/x445 $(OME_DIR)/fake445 $(OME_DIR)/typediff

test-omega-emit: omega-emit $(OUT_DIR)/compiler/oscc
	bash tools/omega_emit/test_omega_emit.sh $(abspath $(OME_DIR)) $(abspath $(OUT_DIR)/compiler/oscc)

test-exp445: omega-emit omegese $(OME_DIR)/examples_expected one-layer-acceptance-tools $(OUT_DIR)/compiler/oscc
	bash tools/exp445/test_exp445.sh $(abspath $(OME_DIR)) $(abspath $(OUT_DIR)/compiler/oscc) $(abspath $(OUT_DIR)/omegese/omegese)
else
omega-emit test-omega-emit test-exp445:
	@echo "MISSING_IMPLEMENTATION: $@ requires removed legacy src/compiler/ (osc_ir.h / oscc, removed in bb7f2dd68); no pure-OM replacement for omega_emit/x445/typediff yet" >&2
	@exit 3
endif
endif
