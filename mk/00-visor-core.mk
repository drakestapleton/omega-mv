# Omega Visor V1 (lead-owned). The `omega` binary is pure seeded OM-2 and
# PHYSICS-FREE: it is compiled directly from $(OMEGA_OM_SRCS) by seed/out/omc.
# Every Visor lane and its test is pure OM-2. The only Visor C left is what the
# runtime-linked, test-only binaries link: visor_world.c (mk/visor-world.mk) and
# visor_effect_request.c (mk/visor-authority.mk, test-effect-cap64).
VISOR_CORE = omega_om_units omega_canonical omega_validate omega_core omega_codec aarch64_encoder aarch64_decoder \
	omega_realize omega_realize_synth omega_machine omega_exec omega_verify omega_program omega_synthesis omega_library \
	omega_vector omega_blackwell_qmd omega_blackwell_encoder omega_blackwell_realize
VISOR_CORE_OBJS = $(addprefix $(OUT_DIR)/,$(addsuffix .o,$(VISOR_CORE)))
VISOR_CFLAGS = -std=gnu11 -Wall -Wextra -Werror -MMD -MP -D_GNU_SOURCE -O2 -Isrc -Isrc/visor
VISOR_SRCS = src/visor/visor_world.c src/visor/visor_effect_request.c
VISOR_OBJS = $(patsubst src/visor/%.c,$(OUT_DIR)/visor/%.o,$(VISOR_SRCS))
VISOR_DEPS = $(VISOR_OBJS:.o=.d)
-include $(VISOR_DEPS)
OMEGA_BIN = $(OUT_DIR)/omega
# Seeded compiler for the pure OM-2 Visor lane tests.
VISOR_OMC ?= seed/out/omc
# Pure OM-2 units shared with the C bridge (om/units.sh); their `export fn` is a plain fn here.
VISOR_OM_UNITS = om/aarch64/aarch64_om2.om om/visor/verify_om2.om om/visor/validate_om2.om
# The language lane lowers fn definitions through visor_program.om, so it follows it.
OMEGA_OM_SRCS = src/visor/visor.om $(VISOR_OM_UNITS) src/visor/visor_program.om \
	src/language/omega_lex.om src/language/omega_parse.om src/language/omega_lower.om \
	src/visor/visor_semantic.om src/visor/visor_machine.om \
	src/visor/visor_realization.om \
	src/visor/visor_verify.om src/visor/visor_evidence.om src/visor/visor_world.om \
	src/visor/visor_effect_request.om src/visor/visor_parse_command.om src/visor/visor_console_hooks.om \
	tools/omega_ops.om tools/omega_wire.om src/visor/visor_console.om tools/omega.om

$(OUT_DIR)/visor $(OUT_DIR)/tests-visor $(OUT_DIR)/tests-language:
	mkdir -p $@

$(OUT_DIR)/visor/%.o: src/visor/%.c | $(OUT_DIR)/visor
	$(CC) $(VISOR_CFLAGS) -c $< -o $@

$(OMEGA_BIN): $(OMEGA_OM_SRCS) seed/out/omc | $(OUT_DIR)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(OMEGA_OM_SRCS)) | seed/out/omc > $@ && chmod +x $@

.PHONY: omega
omega: $(OMEGA_BIN)
	cp $(OMEGA_BIN) ./omega

$(OUT_DIR)/tests-language/%: tests/language/%.om seed/out/omc | $(OUT_DIR)/tests-language
	seed/out/omc < $< > $@ && chmod +x $@

# ---- aggregate Visor gates (lead-owned) --------------------------------------
# Physics-free lane tests (no PHYSICS_DIR needed):
.PHONY: test-visor-core visor-physics-free-check test-visor
test-visor-core: test-visor-semantic test-language test-visor-verify test-visor-evidence \
	test-visor-machine test-visor-realization test-visor-console visor-authority-check

# Proves the omega binary builds without any physics checkout at all.
visor-physics-free-check:
	rm -rf $(OUT_DIR)/pf-check
	$(MAKE) OUT_DIR=$(OUT_DIR)/pf-check PHYSICS_DIR=/nonexistent PHYSICS_LOCK_CHECK=0 $(OUT_DIR)/pf-check/omega
	@echo OMEGA_VISOR_PHYSICS_FREE_BUILD_PASS

# Full Visor suite: physics-free gates + the two runtime-linked hostile/world tests
# (those need PHYSICS_DIR for omega_evidence.c's nvrm.h and VISOR_AUTH_CAP_LIB).
test-visor: test-visor-core visor-physics-free-check test-visor-world test-visor-authority
