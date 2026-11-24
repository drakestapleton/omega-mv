# tools/omega_ref: pure seeded OM-2 reference interpreter for the om4 language.
# Picked up by `-include mk/*.mk`; not part of `all` or `test`. CPU only, no model, no GPU.
ifndef OMEGA_REF_MK
OMEGA_REF_MK := 1
.PHONY: omega-ref test-omega-ref
OMEGA_REF_OMC ?= seed/out/omc
OMEGA_REF_BIN = $(OUT_DIR)/omega_ref

$(OMEGA_REF_BIN): tools/omega_ref/omega_ref.om $(OMEGA_REF_OMC)
	@mkdir -p $(OUT_DIR)
	$(OMEGA_REF_OMC) < tools/omega_ref/omega_ref.om > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

omega-ref: $(OMEGA_REF_BIN)

test-omega-ref: $(OMEGA_REF_BIN) $(OMEGA_REF_OMC)
	@set -u; T=$$(mktemp -d "$${TMPDIR:-/tmp}/omega-ref-test.XXXXXX"); trap 'rm -rf "$$T"' EXIT; \
	B=./$(OMEGA_REF_BIN); \
	for f in bound environment environment-index pool-bounds pool-max-index pool-refusal pools; do \
	  "$$B" check "tools/omega_ref/fixtures/$$f.om" || exit 1; \
	done; \
	"$$B" check tools/omega_ref/fixtures/enlarge-expression.om 2>/dev/null; [ $$? = 9 ] || exit 1; \
	"$$B" check tools/omega_ref/fixtures/enlarge-fixed.om 2>/dev/null; [ $$? = 7 ] || exit 1; \
	"$$B" run tools/omega_ref/fixtures/pools.om || exit 1; \
	"$$B" run tools/omega_ref/fixtures/bound.om || exit 1; \
	"$$B" run tools/omega_ref/fixtures/pool-bounds.om; [ $$? = 103 ] || exit 1; \
	"$$B" run tools/omega_ref/fixtures/pool-max-index.om; [ $$? = 103 ] || exit 1; \
	env -i TOKEN=value "$$B" run tools/omega_ref/fixtures/environment.om || exit 1; \
	env -i TOKEN=value "$$B" run tools/omega_ref/fixtures/environment-index.om; [ $$? = 103 ] || exit 1; \
	(ulimit -v 8388608; "$$B" run tools/omega_ref/fixtures/pool-refusal.om) || exit 1; \
	$(OMEGA_REF_OMC) < tools/omega_ref/stress.om > "$$T/gen" && chmod +x "$$T/gen" || exit 1; \
	"$$T/gen" > "$$T/stress.om" && "$$B" run "$$T/stress.om" || exit 1; \
	"$$T/gen" names > "$$T/stress_names.om" && "$$B" run "$$T/stress_names.om" || exit 1; \
	"$$B" run seed/omc/omc.om < seed/omc/omc.om > "$$T/omc.out" || exit 1; \
	cmp -s "$$T/omc.out" $(OMEGA_REF_OMC) || { echo "FAIL: omc.om self-hosting mismatch"; exit 1; }; \
	echo "test-omega-ref: PASS (9 fixtures, stress, stress+names, omc.om == seed/out/omc)"
endif
