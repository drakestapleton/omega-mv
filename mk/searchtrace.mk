# M23 G1 search-trace corpus + G3 sealed-holdout commitment format (pure seeded OM-2).
# Picked up by `-include mk/*.mk`; built with seed/out/omc (no C compiler or libc).
#   make searchtrace        build/searchtrace/searchtrace
#   make test-searchtrace   unit + refusal tests, CLI Ed25519 interop, hookcheck, run & replay
ifndef SEARCHTRACE_MK
SEARCHTRACE_MK := 1
.PHONY: searchtrace test-searchtrace
ST_DIR = $(OUT_DIR)/searchtrace
ST_OMC ?= seed/out/omc
ST_CRYPTO_OM = src/searchtrace/st_om2_hdr.om \
	seed/ng/sha256.om \
	protocol/omnet/om/sha512/sha512.om \
	protocol/omnet/om/ed25519/ed25519.om \
	protocol/uor-gpu/ed_sign.om
ST_HOLDOUT_OM = $(ST_CRYPTO_OM) src/searchtrace/st_holdout.om
ST_CORPUS_OM = $(ST_HOLDOUT_OM) src/searchtrace/st_corpus.om

$(ST_DIR)/searchtrace: $(ST_CORPUS_OM) src/searchtrace/st_tool.om $(ST_OMC)
	@mkdir -p $(ST_DIR)
	cat $(ST_CORPUS_OM) src/searchtrace/st_tool.om | $(ST_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(ST_DIR)/test_st_corpus: $(ST_CORPUS_OM) tests/searchtrace/test_st_corpus.om $(ST_OMC)
	@mkdir -p $(ST_DIR)
	cat $(ST_CORPUS_OM) tests/searchtrace/test_st_corpus.om | $(ST_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(ST_DIR)/test_st_holdout: $(ST_HOLDOUT_OM) tests/searchtrace/test_st_holdout.om $(ST_OMC)
	@mkdir -p $(ST_DIR)
	cat $(ST_HOLDOUT_OM) tests/searchtrace/test_st_holdout.om | $(ST_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(ST_DIR)/test_st_holdout_sig: $(ST_HOLDOUT_OM) tests/searchtrace/test_st_holdout_sig.om $(ST_OMC)
	@mkdir -p $(ST_DIR)
	cat $(ST_HOLDOUT_OM) tests/searchtrace/test_st_holdout_sig.om | $(ST_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

searchtrace: $(ST_DIR)/searchtrace

test-searchtrace: $(ST_DIR)/searchtrace $(ST_DIR)/test_st_corpus $(ST_DIR)/test_st_holdout $(ST_DIR)/test_st_holdout_sig
	./$(ST_DIR)/test_st_corpus
	./$(ST_DIR)/test_st_holdout
	./$(ST_DIR)/test_st_holdout_sig
	bash tests/searchtrace/test_st_holdout_sig_cli.sh ./$(ST_DIR)/searchtrace
	./$(ST_DIR)/searchtrace hookcheck tests/searchtrace/frozen_taskset_v1.txt
	rm -f $(ST_DIR)/corpus-a.txt
	./$(ST_DIR)/searchtrace run tests/searchtrace/frozen_taskset_v1.txt $(ST_DIR)/corpus-a.txt
	./$(ST_DIR)/searchtrace replay tests/searchtrace/frozen_taskset_v1.txt $(ST_DIR)/corpus-a.txt
	@echo "test-searchtrace: pure OM-2 corpus determinism, refusals, hook equivalence and G3 holdout format and signature pass"
endif
