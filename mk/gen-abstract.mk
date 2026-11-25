# tools/gen/abstract (GEN-3, aien-spark/omega#478): GEN record schema v1 (RECORD_SCHEMA.md), the strict
# validator, the abstraction extractor and its corpus (tests/one_layer/generalization/corpus).
# Picked up by `-include mk/*.mk`; not part of `all` or `test`. CPU only, no model, no GPU.
#
# gen-abstract         build/gen_abstract/{recheck,gabs,oracle,famsig}
#                      (recheck and oracle are pure seeded OM-2; recheck.c and oracle.c stay on disk
#                      as pinned references for committed GEN receipts and mk/gen-retrieval.mk)
# test-gen-abstract    tools/gen/abstract/test_gen_abstract.sh: recheck, corpus, extract, verify, probes, mutants
# test-gen-abstract-parity  byte-exact C-vs-OM differential for recheck and oracle (fixtures, committed records,
#                      all 49 corpus tasks, --bound, and usage/error cases)
#
# famsig is GEN-1's tool (tools/gen/protocol, FAMSIG v1, aien-spark/omega#476). Until that branch is merged the
# rule builds it from the pinned git commit 7eb8534c (gen/protocol, FAMSIG v1 with R6/R7) (read with git show, nothing is copied into this tree).
ifndef GEN_ABSTRACT_MK
GEN_ABSTRACT_MK := 1
.PHONY: gen-abstract test-gen-abstract test-gen-abstract-parity
GENABS_DIR = $(OUT_DIR)/gen_abstract
GENABS_CFLAGS = -std=gnu11 -Wall -Wextra -Werror -D_GNU_SOURCE -O2 -Isrc
GENABS_OMC ?= seed/out/omc
GENABS_FAMSIG_COMMIT = 7eb8534c42304505640013f64753d9c9db40dcf3

$(GENABS_DIR)/recheck: seed/ng/sha256.om tools/gen/abstract/recheck.om $(GENABS_OMC)
	@mkdir -p $(GENABS_DIR)
	(printf 'om2\n'; sed '/^om2$$/d' seed/ng/sha256.om tools/gen/abstract/recheck.om) | $(GENABS_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(GENABS_DIR)/recheck_c: tools/gen/abstract/recheck.c src/omega_om_units.c src/sha256.h
	@mkdir -p $(GENABS_DIR)
	$(CC) $(GENABS_CFLAGS) -o $@ tools/gen/abstract/recheck.c src/omega_om_units.c

$(GENABS_DIR)/gabs: tools/gen/abstract/gabs.c
	@mkdir -p $(GENABS_DIR)
	$(CC) $(GENABS_CFLAGS) -o $@ tools/gen/abstract/gabs.c

$(GENABS_DIR)/gabs_om: tools/gen/abstract/gabs.om $(GENABS_OMC)
	@mkdir -p $(GENABS_DIR)
	$(GENABS_OMC) < tools/gen/abstract/gabs.om > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(GENABS_DIR)/oracle: tests/one_layer/generalization/corpus/oracle.om $(GENABS_OMC)
	@mkdir -p $(GENABS_DIR)
	$(GENABS_OMC) < tests/one_layer/generalization/corpus/oracle.om > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(GENABS_DIR)/oracle_c: tests/one_layer/generalization/corpus/oracle.c
	@mkdir -p $(GENABS_DIR)
	$(CC) $(GENABS_CFLAGS) -o $@ tests/one_layer/generalization/corpus/oracle.c

$(GENABS_DIR)/famsig: src/omega_om_units.c src/sha256.h mk/gen-abstract.mk \
  $(wildcard tools/gen/protocol/famsig.c tools/gen/protocol/famsig_lib.h)
	@mkdir -p $(GENABS_DIR)/famsig-src/tools/gen/protocol
	@if [ -f tools/gen/protocol/famsig.c ]; then \
	  cp tools/gen/protocol/famsig.c tools/gen/protocol/famsig_lib.h $(GENABS_DIR)/famsig-src/tools/gen/protocol/; \
	else \
	  git show $(GENABS_FAMSIG_COMMIT):tools/gen/protocol/famsig.c > $(GENABS_DIR)/famsig-src/tools/gen/protocol/famsig.c && \
	  git show $(GENABS_FAMSIG_COMMIT):tools/gen/protocol/famsig_lib.h > $(GENABS_DIR)/famsig-src/tools/gen/protocol/famsig_lib.h; \
	fi
	$(CC) -std=gnu11 -Wall -Wextra -Werror -O2 -Isrc -o $@ $(GENABS_DIR)/famsig-src/tools/gen/protocol/famsig.c src/omega_om_units.c

gen-abstract: $(GENABS_DIR)/recheck $(GENABS_DIR)/gabs $(GENABS_DIR)/oracle $(GENABS_DIR)/famsig

test-gen-abstract-parity: $(GENABS_DIR)/recheck $(GENABS_DIR)/recheck_c $(GENABS_DIR)/oracle $(GENABS_DIR)/oracle_c $(GENABS_DIR)/gabs $(GENABS_DIR)/gabs_om
	@set -eu; D=$(GENABS_DIR)/parity; rm -rf "$$D"; mkdir -p "$$D"; \
	FX=tools/gen/abstract/fixtures; RS=tests/one_layer/generalization/records; CO=tests/one_layer/generalization/corpus; \
	./$(GENABS_DIR)/recheck --root . --receipts "$$FX/receipts" "$$FX/abs-fixture.rec" "$$FX/raw-fixture.rec" > "$$D/om.f"; \
	./$(GENABS_DIR)/recheck_c --root . --receipts "$$FX/receipts" "$$FX/abs-fixture.rec" "$$FX/raw-fixture.rec" > "$$D/c.f"; \
	cmp "$$D/om.f" "$$D/c.f"; \
	./$(GENABS_DIR)/recheck --root . --receipts "$$RS/receipts" "$$RS"/abstraction/*.rec "$$RS"/raw/*.rec > "$$D/om.r"; \
	./$(GENABS_DIR)/recheck_c --root . --receipts "$$RS/receipts" "$$RS"/abstraction/*.rec "$$RS"/raw/*.rec > "$$D/c.r"; \
	cmp "$$D/om.r" "$$D/c.r"; \
	for d in "$$CO"/tasks/*/; do \
	  t=$$(basename "$$d"); \
	  ./$(GENABS_DIR)/oracle "$$t" < "$$d/inputs" > "$$D/om.o"; \
	  ./$(GENABS_DIR)/oracle_c "$$t" < "$$d/inputs" > "$$D/c.o"; \
	  cmp "$$D/om.o" "$$D/c.o"; cmp "$$D/om.o" "$$d/expected"; \
	  ./$(GENABS_DIR)/gabs_om split "$$d/solution.omegese" "$$D/om.sp.$$t" > "$$D/om.s"; \
	  ./$(GENABS_DIR)/gabs split "$$d/solution.omegese" "$$D/c.sp.$$t" > "$$D/c.s"; \
	  cmp "$$D/om.s" "$$D/c.s"; \
	  for f in "$$D/c.sp.$$t".*.omegese; do cmp "$$D/om.sp.$$t$${f#$$D/c.sp.$$t}" "$$f"; done; \
	done; \
	for t in even_digsums sum_clamped sum_dists sum_sat clamp_sum; do \
	  ./$(GENABS_DIR)/oracle --bound "$$t" > "$$D/om.b"; \
	  ./$(GENABS_DIR)/oracle_c --bound "$$t" > "$$D/c.b"; \
	  cmp "$$D/om.b" "$$D/c.b"; \
	done; \
	./$(GENABS_DIR)/gabs_om inputs 256 u32 i32 u8 i64 bool u16 > "$$D/om.in1"; \
	./$(GENABS_DIR)/gabs inputs 256 u32 i32 u8 i64 bool u16 > "$$D/c.in1"; \
	cmp "$$D/om.in1" "$$D/c.in1"; \
	./$(GENABS_DIR)/gabs_om inputs 256 --max 0:4096 u32 u32 > "$$D/om.in2"; \
	./$(GENABS_DIR)/gabs inputs 256 --max 0:4096 u32 u32 > "$$D/c.in2"; \
	cmp "$$D/om.in2" "$$D/c.in2"; \
	printf '{"ops": [{"name": "helper", "op": "ret"}, {"name": "main", "func": "helper"}]}\n' > "$$D/cj.json"; \
	./$(GENABS_DIR)/gabs_om canon "$$D/cj.json" "$$D/om.cj"; \
	./$(GENABS_DIR)/gabs canon "$$D/cj.json" "$$D/c.cj"; \
	cmp "$$D/om.cj" "$$D/c.cj"; \
	echo "test-gen-abstract-parity: recheck, oracle (49 tasks + --bound), and gabs_om (split/canon/inputs) byte-identical to C"

test-gen-abstract: gen-abstract omegese omega-emit checker2 one-layer-acceptance-tools $(OUT_DIR)/compiler/oscc
	bash tools/gen/abstract/test_gen_abstract.sh $(abspath $(OUT_DIR))
endif
