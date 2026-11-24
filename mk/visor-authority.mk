# Omega Visor V1, lane 7 (authority / effect safety). "The Visor can ask. The Visor cannot grant."
#
# test-visor-authority   pure seeded OM-2 hostile test: Visor effect requests vs capability root
#                        (rx_caproot.om) and AEGIS policy (rx_aegis.om). Host-only, physics-free.
# visor-authority-check  isolation check: no Visor object references/defines an authority-mutating
#                        symbol, and no OM-2 source of omega names one (with bite controls).
VISOR_AUTH_OMC ?= seed/out/omc
VISOR_AUTH_OM_SRCS := src/visor/visor.om src/visor/visor_machine.om \
	om/aarch64/aarch64_om2.om om/visor/verify_om2.om om/visor/validate_om2.om \
	src/visor/visor_verify.om src/visor/visor_effect_request.om \
	seed/authority/cap_table_om2.om src/runtime/rx_caproot.om src/runtime/rx_aegis.om \
	tests/visor/test_visor_authority.om
VISOR_AUTH_TEST = $(OUT_DIR)/tests-visor-authority/test_visor_authority

$(OUT_DIR)/tests-visor-authority:
	mkdir -p $@

$(VISOR_AUTH_TEST): $(VISOR_AUTH_OM_SRCS) $(VISOR_AUTH_OMC) | $(OUT_DIR)/tests-visor-authority
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(VISOR_AUTH_OM_SRCS)) | $(VISOR_AUTH_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-visor-authority visor-authority-check
test-visor-authority: $(VISOR_AUTH_TEST)
	$(abspath $(VISOR_AUTH_TEST))

# The omega binary is pure OM-2 and has no symbol table, so nm cannot see into it. The check
# scans the OM-2 sources it is built from ($(OMEGA_OM_SRCS), plus every tools/omega*.om,
# om/visor, src/visor and src/language unit) for forbidden authority names, runtime prefixes
# and authorization state, with planted-name bite controls that must be caught. The binary
# stays a prerequisite so a source that does not compile fails the check.
visor-authority-check: $(OUT_DIR)/visor/visor_effect_request.o $(OMEGA_BIN)
	OMEGA_OM_SRCS='$(OMEGA_OM_SRCS)' sh tests/visor/check_authority_link.sh $(OUT_DIR)
