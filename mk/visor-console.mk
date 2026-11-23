# Omega Visor lane 2 (console / REPL). Pure seeded OM-2, no C.
# `make test-visor-console` runs the console test twice:
#  1. lane-only: tests/visor/test_visor_console.om with the lane stubs, built by the seed
#     omc from ONLY visor.om, the parser, the console and the test stubs, so the console
#     framework can be tested even while other lanes are broken (134 checks);
#  2. full: the same checks plus tests/visor/test_visor_console_e2e.om, built from the
#     omega binary's sources (OMEGA_OM_SRCS) with the test hook dispatcher in place of
#     tools/omega_wire.om, so the end-to-end sessions run through the real hook wiring of
#     tools/omega_ops.om (172 checks). Both run from the repository root (fixture paths).
$(OUT_DIR)/lane2:
	mkdir -p $@

VISOR_CONSOLE_LANE_OM_SRCS = src/visor/visor.om src/visor/visor_parse_command.om \
	src/visor/visor_console_hooks.om tests/visor/test_visor_console_hooks.om \
	tests/visor/test_visor_console_lane.om src/visor/visor_console.om \
	tests/visor/test_visor_console.om tests/visor/test_visor_console_main.om

$(OUT_DIR)/lane2/test_visor_console: $(VISOR_CONSOLE_LANE_OM_SRCS) $(VISOR_OMC) | $(OUT_DIR)/lane2
	(printf 'om2\n'; sed '/^om2$$/d' $(VISOR_CONSOLE_LANE_OM_SRCS)) | $(VISOR_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

VISOR_CONSOLE_FULL_OM_SRCS = \
	$(filter-out tools/omega_wire.om src/visor/visor_console.om tools/omega.om,$(OMEGA_OM_SRCS)) \
	tests/visor/test_visor_console_hooks.om tests/visor/test_visor_console_wire.om \
	src/visor/visor_console.om tests/visor/test_visor_console.om tests/visor/test_visor_console_e2e.om

$(OUT_DIR)/lane2/test_visor_console_full: $(VISOR_CONSOLE_FULL_OM_SRCS) $(VISOR_OMC) | $(OUT_DIR)/lane2
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(VISOR_CONSOLE_FULL_OM_SRCS)) | $(VISOR_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-visor-console
test-visor-console: $(OUT_DIR)/lane2/test_visor_console $(OUT_DIR)/lane2/test_visor_console_full
	$(OUT_DIR)/lane2/test_visor_console
	$(OUT_DIR)/lane2/test_visor_console_full
