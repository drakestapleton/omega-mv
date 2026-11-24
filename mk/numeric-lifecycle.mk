# Pure host lifecycle tests. The fake M16 header is confined to the C target;
# test-numeric-lifecycle-om runs the pure seeded OM-2 port and its three mutants.
NUMERIC_LIFECYCLE_OMC ?= seed/out/omc
NUMERIC_LIFECYCLE_OM_SRCS := src/omega_numeric_lifecycle.om tests/test_numeric_lifecycle.om
NUMERIC_LIFECYCLE_OM_BIN = $(OUT_DIR)/numeric-lifecycle/test_om

$(NUMERIC_LIFECYCLE_OM_BIN): $(NUMERIC_LIFECYCLE_OM_SRCS) $(NUMERIC_LIFECYCLE_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed '/^om2$$/d' $(NUMERIC_LIFECYCLE_OM_SRCS)) | $(NUMERIC_LIFECYCLE_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-numeric-lifecycle-om
test-numeric-lifecycle-om: $(NUMERIC_LIFECYCLE_OM_BIN)
	$(abspath $(NUMERIC_LIFECYCLE_OM_BIN))
	@set -e; for m in POISON RETAIN EXACT; do \
	  sed "s/^const OMEGA_NL_MUTANT_$$m ulong 0$$/const OMEGA_NL_MUTANT_$$m ulong 1/" src/omega_numeric_lifecycle.om > $(OUT_DIR)/numeric-lifecycle/mut_$$m.om; \
	  if cmp -s src/omega_numeric_lifecycle.om $(OUT_DIR)/numeric-lifecycle/mut_$$m.om; then echo "FAIL: OM mutant $$m changed nothing"; exit 1; fi; \
	  (printf 'om2\n'; sed '/^om2$$/d' $(OUT_DIR)/numeric-lifecycle/mut_$$m.om tests/test_numeric_lifecycle.om) | $(NUMERIC_LIFECYCLE_OMC) > $(OUT_DIR)/numeric-lifecycle/test_om_$$m.tmp.$$$$; \
	  chmod +x $(OUT_DIR)/numeric-lifecycle/test_om_$$m.tmp.$$$$; \
	  mv -f $(OUT_DIR)/numeric-lifecycle/test_om_$$m.tmp.$$$$ $(OUT_DIR)/numeric-lifecycle/test_om_$$m; \
	  if $(abspath $(OUT_DIR)/numeric-lifecycle/test_om_$$m) >$(OUT_DIR)/numeric-lifecycle/mut_$$m.log 2>&1; then echo "FAIL: OM mutant $$m survived"; exit 1; fi; \
	  echo "numeric lifecycle OM mutant $$m: killed"; \
	done

.PHONY: test-numeric-lifecycle
test-numeric-lifecycle: test-numeric-lifecycle-om
	@mkdir -p $(OUT_DIR)/numeric-lifecycle
	$(CC) -std=c11 -O2 -Wall -Wextra -Werror -Isrc -Itests/numeric_native tests/test_numeric_lifecycle.c tests/numeric_native/other_launcher.c -o $(OUT_DIR)/numeric-lifecycle/test
	$(OUT_DIR)/numeric-lifecycle/test
	$(CC) -std=c11 -O1 -g -Wall -Wextra -Werror -fsanitize=address,undefined -fno-sanitize-recover=all -Isrc -Itests/numeric_native tests/test_numeric_lifecycle.c tests/numeric_native/other_launcher.c -o $(OUT_DIR)/numeric-lifecycle/test-sanitize
	$(OUT_DIR)/numeric-lifecycle/test-sanitize
	CC='$(CC)' sh tests/numeric_native/mutants.sh $(OUT_DIR)/numeric-lifecycle/mutants
	@for f in src/omega_numeric_gb10.c src/omega_numeric_reduce_gb10.c src/omega_numeric_divsqrt_gb10.c src/omega_numeric_ldst_gb10.c; do \
	  if grep -Eq 'm16_native_(open|close|wait_marker)[[:space:]]*\(' $$f; then echo "FAIL: lifecycle bypass in $$f"; exit 1; fi; \
	done
