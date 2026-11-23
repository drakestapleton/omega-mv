# Omega Visor V1 lane 5 (machine + realization lab) test targets.
# The Blackwell realize objects compile and link physics-free (only sha256 +
# omega_core deps). visor_machine.c references omega_blackwell_get_machine_id
# WEAKLY, so build/omega links with or without them; these lane tests link
# them explicitly so the declared Blackwell target shows linked=yes.
VISOR_BW_CORE = omega_vector omega_blackwell_qmd omega_blackwell_encoder omega_blackwell_realize
VISOR_BW_OBJS = $(addprefix $(OUT_DIR)/,$(addsuffix .o,$(filter-out $(VISOR_CORE),$(VISOR_BW_CORE))))

# test_visor_machine: pure seeded OM-2 (tests/visor/test_visor_machine.om), built by
# $(VISOR_OMC) from the machine module and the shared Visor core.
VISOR_MACHINE_OM_SRCS = src/visor/visor.om src/visor/visor_machine.om

$(OUT_DIR)/tests-visor/test_visor_machine: tests/visor/test_visor_machine.om $(VISOR_MACHINE_OM_SRCS) $(VISOR_OMC) | $(OUT_DIR)/tests-visor
	(printf 'om2\n'; sed '/^om2$$/d' $(VISOR_MACHINE_OM_SRCS) tests/visor/test_visor_machine.om) | $(VISOR_OMC) > $@ && chmod +x $@

# The realization lab is pure seeded OM-2 too (visor_program.om + visor_realization.om over the
# shared OM-2 AArch64 and verifier units, whose `export fn` is a plain fn in a program).
VISOR_REALIZATION_OM_SRCS = src/visor/visor.om $(VISOR_OM_UNITS) src/visor/visor_machine.om \
	src/visor/visor_program.om src/visor/visor_realization.om
$(OUT_DIR)/tests-visor/test_visor_realization: tests/visor/test_visor_realization.om $(VISOR_REALIZATION_OM_SRCS) $(VISOR_OMC) | $(OUT_DIR)/tests-visor
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(VISOR_REALIZATION_OM_SRCS) tests/visor/test_visor_realization.om) | $(VISOR_OMC) > $@ && chmod +x $@

.PHONY: test-visor-machine test-visor-realization
test-visor-machine: $(OUT_DIR)/tests-visor/test_visor_machine
	./$(OUT_DIR)/tests-visor/test_visor_machine

test-visor-realization: $(OUT_DIR)/tests-visor/test_visor_realization
	./$(OUT_DIR)/tests-visor/test_visor_realization
