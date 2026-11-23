# Omega Visor lane 2 (console / REPL).
# `make test-visor-console` runs the console test twice:
#  1. lane-only: pure seeded OM-2 (tests/visor/test_visor_console.om, the checks
#     of the C test that run with VISOR_CONSOLE_LANE_ONLY), built by the seed omc
#     from ONLY visor.om, the parser, the console and the test stubs, so the
#     console framework can be tested even while other lanes are broken;
#  2. full: the generic rule build/tests-visor/test_visor_console (all visor +
#     language objects), which also runs the end-to-end session through the real
#     hook wiring in tools/omega.c.
$(OUT_DIR)/lane2:
	mkdir -p $@

VISOR_CONSOLE_LANE_OM_SRCS = src/visor/visor.om src/visor/visor_parse_command.om \
	src/visor/visor_console_hooks.om tests/visor/test_visor_console_hooks.om \
	tests/visor/test_visor_console_lane.om src/visor/visor_console.om \
	tests/visor/test_visor_console.om tests/visor/test_visor_console_main.om

$(OUT_DIR)/lane2/test_visor_console: $(VISOR_CONSOLE_LANE_OM_SRCS) $(VISOR_OMC) | $(OUT_DIR)/lane2
	(printf 'om2\n'; sed '/^om2$$/d' $(VISOR_CONSOLE_LANE_OM_SRCS)) | $(VISOR_OMC) > $@ && chmod +x $@

# The full test #includes tools/omega.c (with OMEGA_TOOL_NO_MAIN) for the wiring.
$(OUT_DIR)/tests-visor/test_visor_console: tools/omega.c

.PHONY: test-visor-console
test-visor-console: $(OUT_DIR)/lane2/test_visor_console $(OUT_DIR)/tests-visor/test_visor_console
	$(OUT_DIR)/lane2/test_visor_console
	$(OUT_DIR)/tests-visor/test_visor_console
