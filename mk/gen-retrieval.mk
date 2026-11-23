# tools/gen/retrieval (GEN-4, aien-spark/omega#479): genret, the file-backed retrieval provider of the GEN
# experiment (contract tools/gen/retrieval/CONTRACT.md, genret-cli-v3). Picked up by `-include mk/*.mk`; not
# part of `all` or `test`. CPU only, no model, no GPU, no network.
#
# gen-retrieval        build/gen_retrieval/genret, build/gen_retrieval/recheck and recheck.sha256 (the value
#                      callers pass as --recheck-sha256)
# test-gen-retrieval   tools/gen/retrieval/test_genret.sh on the genret and genret_anyrecheck builds
#
# genret is pure OM-2 (tools/gen/retrieval/genret.om), built by the seeded compiler GENRET_OMC as one unit:
# seed/ng/sha256.om, a binding unit generated in this make run, then genret.om.
# The ASan/UBSan pass of the C build is gone. OM-2 traps at run time an out-of-range array get or put
# (3), signed overflow (1), div or rem by 0 (2), a shift amount outside 0..width-1 (7) and an
# out-of-range conversion (5) (docs/one_layer/OMEGESE.md 9.3); unsigned arithmetic wraps as in C.
# Sanitizer checks with no OM-2 counterpart (alignment, use after free, leaks) are not replaced.
#
# genret validates records with Agent D's recheck (tools/gen/abstract/recheck.c). Its source must hash to
# GENRET_RECHECK_SHA256; that is checked every time make runs a gen-retrieval target, whether the source is in
# this tree or taken from D's frozen schema v1 commit. The same value is compiled into genret and written to
# every receipt (recheck_source_sha256).
ifndef GEN_RETRIEVAL_MK
GEN_RETRIEVAL_MK := 1
.PHONY: gen-retrieval test-gen-retrieval gen-retrieval-recheck-source
GENRET_DIR = $(OUT_DIR)/gen_retrieval
GENRET_RECHECK_COMMIT = e521e818e42421884d5fd9826426bba56ad10531
GENRET_RECHECK_SHA256 = 9d7a3c74de404170d32eacbc0ab551e3b598a086d9b300a94825e70614533e6c
GENRET_CFLAGS = -std=gnu11 -Wall -Wextra -Werror -D_GNU_SOURCE -Isrc
GENRET_OMC ?= seed/out/omc
GENRET_OM_SRCS = seed/ng/sha256.om tools/gen/retrieval/genret.om mk/gen-retrieval.mk
# $(call GENRET_UNIT,<binding unit>): the whole OM-2 source of one genret build, on stdout
GENRET_UNIT = (printf 'om2\n'; sed '/^om2$$/d' seed/ng/sha256.om $(1) tools/gen/retrieval/genret.om)

ifneq ($(wildcard tools/gen/abstract/recheck.c),)
GENRET_RECHECK_SRC = tools/gen/abstract/recheck.c
else
# named by its pinned digest, so a changed pin extracts a fresh copy
GENRET_RECHECK_SRC = $(GENRET_DIR)/recheck_$(GENRET_RECHECK_SHA256).c
$(GENRET_RECHECK_SRC):
	@mkdir -p $(GENRET_DIR)
	@git show $(GENRET_RECHECK_COMMIT):tools/gen/abstract/recheck.c > $@.tmp || \
	  { rm -f $@.tmp; echo "gen-retrieval: commit $(GENRET_RECHECK_COMMIT) missing: git fetch origin gen/abstract"; exit 1; }
	@echo "$(GENRET_RECHECK_SHA256)  $@.tmp" | sha256sum -c --quiet || { rm -f $@.tmp; exit 1; }
	@mv $@.tmp $@
endif

# runs on every invocation of the targets below, not only when a file is first extracted
gen-retrieval-recheck-source: $(GENRET_RECHECK_SRC)
	@echo "$(GENRET_RECHECK_SHA256)  $(GENRET_RECHECK_SRC)" | sha256sum -c --quiet || \
	  { echo "gen-retrieval: $(GENRET_RECHECK_SRC) does not match GENRET_RECHECK_SHA256"; exit 1; }

# genret is bound to the recheck binary built (from the verified source) in this make run: both digests go
# into the binding unit (gr_bin_pin, gr_src_claim), and genret refuses any other validator binary
$(GENRET_DIR)/genret_bind.om: $(GENRET_DIR)/recheck mk/gen-retrieval.mk
	@grep -qx '[0-9a-f]\{64\}' $(GENRET_DIR)/recheck.sha256 || { echo "gen-retrieval: bad recheck.sha256"; exit 1; }
	printf 'text gr_bin_pin "%s"\ntext gr_src_claim "%s"\n' "$$(cat $(GENRET_DIR)/recheck.sha256)" \
	  "$(GENRET_RECHECK_SHA256)" > $@

# test-only binding without the built-in binary pin (receipt: recheck_source_sha256=unverified); the tests use
# genret_anyrecheck only to drive fake validators. Never use it for experiment runs.
$(GENRET_DIR)/genret_bind_any.om: mk/gen-retrieval.mk
	@mkdir -p $(GENRET_DIR)
	printf 'text gr_bin_pin ""\ntext gr_src_claim "unverified"\n' > $@

$(GENRET_DIR)/genret: $(GENRET_OM_SRCS) $(GENRET_DIR)/genret_bind.om $(GENRET_OMC)
	$(call GENRET_UNIT,$(GENRET_DIR)/genret_bind.om) | $(GENRET_OMC) > $@.tmp && chmod +x $@.tmp && mv $@.tmp $@

$(GENRET_DIR)/genret_anyrecheck: $(GENRET_OM_SRCS) $(GENRET_DIR)/genret_bind_any.om $(GENRET_OMC)
	$(call GENRET_UNIT,$(GENRET_DIR)/genret_bind_any.om) | $(GENRET_OMC) > $@.tmp && chmod +x $@.tmp && mv $@.tmp $@

$(GENRET_DIR)/recheck: $(GENRET_RECHECK_SRC) src/omega_om_units.c src/sha256.h mk/gen-retrieval.mk
	@mkdir -p $(GENRET_DIR)
	@echo "$(GENRET_RECHECK_SHA256)  $(GENRET_RECHECK_SRC)" | sha256sum -c --quiet
	$(CC) $(GENRET_CFLAGS) -O2 -o $@ $(GENRET_RECHECK_SRC) src/omega_om_units.c
	sha256sum $@ | cut -c1-64 > $@.sha256

gen-retrieval: gen-retrieval-recheck-source $(GENRET_DIR)/genret $(GENRET_DIR)/recheck

test-gen-retrieval: gen-retrieval-recheck-source $(GENRET_DIR)/genret $(GENRET_DIR)/genret_anyrecheck $(GENRET_DIR)/recheck
	sh tools/gen/retrieval/test_genret.sh $(abspath $(GENRET_DIR)/genret) $(abspath $(GENRET_DIR)/genret_anyrecheck) \
	  $(abspath $(GENRET_DIR)/recheck) $(abspath $(GENRET_RECHECK_SRC))
endif
