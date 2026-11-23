# GEN-1: pre-registered generalization protocol tools (aien-spark/omega#476, docs/one_layer/GEN_PROTOCOL_V1.md).
# Picked up by `-include mk/*.mk`; not part of `all` or `test`. CPU only.
#
# gen-protocol-tools   build/gen_protocol/{famsig,gencheck,genstats,genjac}, pure OM-2 built by the seeded omc
#                      (GENP_OMC, default seed/out/omc). The .c/.h files beside the .om stay only as the reference
#                      implementations tests/one_layer/generalization/protocol.json pins (and mk/gen-abstract.mk reads).
# test-gen-protocol    genstats selftest, genjac known answers + byte-identical stats_vectors.tsv, famsig known answers and mutants,
#                      gencheck on tests/one_layer/generalization/protocol.json and its mutants (manifest,
#                      tree, synthetic held-out split), dev pack reproducibility + oracle negative control.
#                      GEN_TASKS_CHECK=1 also runs ola.sh tasks-check on the dev pack (clean tree needed).
ifndef GEN_PROTOCOL_MK
GEN_PROTOCOL_MK := 1
.PHONY: gen-protocol-tools test-gen-protocol
GENP_SRC = tools/gen/protocol
GENP_DIR = $(OUT_DIR)/gen_protocol
GENP_OMC ?= seed/out/omc
GENP_FSLIB = seed/ng/sha256.om $(GENP_SRC)/famsig_lib.om

$(GENP_DIR)/famsig: $(GENP_FSLIB) $(GENP_SRC)/famsig.om $(GENP_OMC)
	@mkdir -p $(GENP_DIR)
	(printf 'om2\n'; sed '/^om2$$/d' $(GENP_FSLIB) $(GENP_SRC)/famsig.om) | $(GENP_OMC) > $@ && chmod +x $@

$(GENP_DIR)/gencheck: $(GENP_FSLIB) $(GENP_SRC)/gencheck.om $(GENP_OMC)
	@mkdir -p $(GENP_DIR)
	(printf 'om2\n'; sed '/^om2$$/d' $(GENP_FSLIB) $(GENP_SRC)/gencheck.om) | $(GENP_OMC) > $@ && chmod +x $@

$(GENP_DIR)/genstats: $(GENP_SRC)/genstats.om $(GENP_OMC)
	@mkdir -p $(GENP_DIR)
	$(GENP_OMC) < $(GENP_SRC)/genstats.om > $@ && chmod +x $@

$(GENP_DIR)/genjac: $(GENP_SRC)/genjac.om $(GENP_OMC)
	@mkdir -p $(GENP_DIR)
	$(GENP_OMC) < $(GENP_SRC)/genjac.om > $@ && chmod +x $@

gen-protocol-tools: $(GENP_DIR)/famsig $(GENP_DIR)/gencheck $(GENP_DIR)/genstats $(GENP_DIR)/genjac

test-gen-protocol:
	GENP_OMC="$(abspath $(GENP_OMC))" bash $(GENP_SRC)/test_gen_protocol.sh $(abspath $(GENP_DIR))/test
endif
