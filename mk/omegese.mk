# tools/omegese: Omegese, the AI-writer program language (docs/one_layer/OMEGESE.md). Omegese lowers to the
# omega_emit op list, so the IR, checker2 and the signed receipt chain are unchanged.
# Picked up by `-include mk/*.mk`; not part of `all` or `test`.
#
# omegese        build/omegese/omegese (pure seeded OM-2 compiled by seed/out/omc)
# test-omegese   tools/omegese/test_omegese.sh against the pure OM-2 binary. The script checks the dev
#                programs (omegese -> omega_emit -> checker2 ACCEPT), refusals with reasons, the loop-guard
#                negative control, the exact next oracle (completeness, soundness and truncation fuzz) and,
#                when OMEGESE_TOKCOUNT and OMEGESE_TOKENIZER are set, the tokenizer gate (every fixed word
#                is one token)
ifndef OMEGESE_MK
OMEGESE_MK := 1
.PHONY: omegese test-omegese
OMEGESE_DIR = $(OUT_DIR)/omegese

$(OMEGESE_DIR)/omegese: tools/omegese/omegese.om seed/out/omc
	@mkdir -p $(OMEGESE_DIR)
	seed/out/omc < tools/omegese/omegese.om > $@ && chmod +x $@

omegese: $(OMEGESE_DIR)/omegese

test-omegese: omegese omega-emit checker2
	bash tools/omegese/test_omegese.sh $(abspath $(OMEGESE_DIR)/omegese) $(abspath $(OUT_DIR)/omega_emit/omega_emit) $(abspath $(C2_DIR)/checker2)
endif
