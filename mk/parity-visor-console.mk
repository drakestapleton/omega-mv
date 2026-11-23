# Differential qualification of the pure OM-2 omega console (the omega binary built from
# $(OMEGA_OM_SRCS): src/visor/visor_console.om, visor_parse_command.om, visor.om, tools/omega.om,
# omega_ops.om, omega_wire.om and the lanes they call) against the C console it replaced
# (tools/omega.c, src/visor/visor_console.c, visor_parse_command.c, visor.c at main 3f2c70dc5).
# Host only, CPU only, no physics checkout, no C compiler.
#
# test-visor-console-parity
#   1. tests/visor/console_parity.sh: the console sessions (committed, hand and generated, each
#      in text and JSON mode) and the argv cases of tests/visor/console_parity/args.cases through
#      the OM omega: stdout, stderr and exit code byte for byte against the committed goldens of
#      the C omega at main 3f2c70dc5 (tests/visor/console_golden, MANIFEST with the commit, the
#      generator, tools/omega.c's blob and sha256, and the sha256 of every corpus and golden);
#   2. tests/visor/console_mutants.sh: every mutant of the shipped console sources must differ
#      from the goldens.
.PHONY: test-visor-console-parity
test-visor-console-parity: $(VISOR_OMC)
	CONSOLE_PARITY_WORK=$(abspath $(OUT_DIR))/console-parity CONSOLE_PARITY_OMS='$(OMEGA_OM_SRCS)' sh tests/visor/console_parity.sh $(abspath $(VISOR_OMC))
	CONSOLE_PARITY_WORK=$(abspath $(OUT_DIR))/console-parity CONSOLE_PARITY_OMS='$(OMEGA_OM_SRCS)' sh tests/visor/console_mutants.sh $(abspath $(VISOR_OMC))
