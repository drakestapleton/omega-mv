# Proof layer, hardening lane LG: World lifecycle model and differential harness
# against rx_world.om, pure seeded OM-2 (zero C). Host only (no graphics chip,
# no physics headers). Owned files: tests/model/, this file.
#
#   make test-model       exhaustive model check + mutants (tests/model/model_check.om)
#   make test-model-diff  model vs real rx_world.om (tests/model/world_diff.om)
#   make test-model-tsan  records NOT_RUN (pure OM-2 single-threaded binary, no C/libtsan)
#   make test-proof       all three, then build/proof/LG-receipt.json
#
# Every target refuses to start while ~/workspace/.spark-quiet exists and
# says NOT_RUN instead.

PROOF_OMC        ?= seed/out/omc
PROOF_OUT        ?= $(OUT_DIR)/proof
PROOF_QUIET      ?= $(HOME)/workspace/.spark-quiet
PROOF_DIFF_SRCS  := seed/ng/sha256.om src/runtime/rx_world.om tests/model/world_diff.om

PROOF_MODEL_BIN  = $(PROOF_OUT)/model_check
PROOF_DIFF_BIN   = $(PROOF_OUT)/world_diff

define proof_quiet_guard
	@if [ -e "$(PROOF_QUIET)" ]; then echo "$(1): NOT_RUN (quiet flag $(PROOF_QUIET) is set)"; exit 1; fi
endef

$(PROOF_OUT):
	mkdir -p $@

$(PROOF_MODEL_BIN): tests/model/model_check.om $(PROOF_OMC) | $(PROOF_OUT)
	./$(PROOF_OMC) < tests/model/model_check.om > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(PROOF_DIFF_BIN): $(PROOF_DIFF_SRCS) $(PROOF_OMC) | $(PROOF_OUT)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(PROOF_DIFF_SRCS)) | $(PROOF_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-model test-model-diff test-model-tsan test-proof

test-model:
	$(call proof_quiet_guard,test-model)
	@$(MAKE) --no-print-directory $(PROOF_MODEL_BIN)
	./$(PROOF_MODEL_BIN) > $(PROOF_OUT)/model.log 2>&1; rc=$$?; cat $(PROOF_OUT)/model.log; exit $$rc

test-model-diff:
	$(call proof_quiet_guard,test-model-diff)
	@$(MAKE) --no-print-directory $(PROOF_DIFF_BIN)
	./$(PROOF_DIFF_BIN) > $(PROOF_OUT)/diff.log 2>&1; rc=$$?; \
		cat $(PROOF_OUT)/diff.log; exit $$rc

test-model-tsan:
	$(call proof_quiet_guard,test-model-tsan)
	@mkdir -p $(PROOF_OUT)
	@echo "RESULT tsan=NOT_RUN (pure OM-2; single-threaded deterministic binary, no C/libtsan)" | tee $(PROOF_OUT)/tsan.log

test-proof:
	@mkdir -p $(PROOF_OUT)
	@rm -f $(PROOF_OUT)/model.log $(PROOF_OUT)/diff.log $(PROOF_OUT)/tsan.log
	@if [ -e "$(PROOF_QUIET)" ]; then \
		echo "test-proof: NOT_RUN (quiet flag $(PROOF_QUIET) is set)"; \
		sh tests/model/receipt.sh $(PROOF_OUT) quiet; exit 1; fi
	-@$(MAKE) --no-print-directory test-model
	-@$(MAKE) --no-print-directory test-model-diff
	-@$(MAKE) --no-print-directory test-model-tsan
	sh tests/model/receipt.sh $(PROOF_OUT)
