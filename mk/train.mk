# M22 OMEGA_OPTIMIZER substrate + E5 training provenance (Lane 21, pure seeded OM-2).
# Transactional generation store over plain byte buffers (src/train/tg_store.om),
# SGD as the first updater (src/train/tg_sgd.om). No tensor/autodiff dependency.
# Picked up by `-include mk/*.mk`; not part of `all` or `test`. Host only,
# single core, no GPU, no quiet flag.
#
# test-train      purity check, then the pure OM-2 exit tests run twice;
#                 both runs must print the same replay digest
# train-purity    src/train contains only pure .om sources (0 C/H files)
# train-receipt   digest-named receipt under evidence/M22/receipts (clean tree only)
#
# The receipt says M22 NOT QUALIFIED: this is the substrate + SGD path only.
ifndef TRAIN_MK
TRAIN_MK := 1
.PHONY: test-train train-purity train-receipt
TRAIN_OMC ?= seed/out/omc
TRAIN_DIR = $(OUT_DIR)/train
TRAIN_OM_SRCS = src/train/generation.om src/train/sgd_update.om src/train/tg_sha256.om \
	src/train/tg_store.om src/train/tg_sgd.om

$(TRAIN_DIR)/test_train: tests/train/test_train.om $(TRAIN_OM_SRCS) $(TRAIN_OMC)
	@mkdir -p $(TRAIN_DIR)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TRAIN_OM_SRCS) tests/train/test_train.om) | $(TRAIN_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

train-purity:
	@bad=$$(find src/train -maxdepth 1 \( -name '*.c' -o -name '*.h' \) 2>/dev/null); \
	if [ -n "$$bad" ]; then echo "train-purity: FAIL, unexpected C/H files:"; echo "$$bad"; exit 1; fi; \
	echo "train-purity: src/train is 100% pure seeded OM-2 (0 C/H files)"

test-train: train-purity $(TRAIN_DIR)/test_train
	@rm -rf $(TRAIN_DIR)/scratch $(TRAIN_DIR)/scratch-2
	./$(TRAIN_DIR)/test_train $(TRAIN_DIR)/scratch > $(TRAIN_DIR)/run1.log 2>&1; rc=$$?; \
		cat $(TRAIN_DIR)/run1.log; [ $$rc -eq 0 ]
	./$(TRAIN_DIR)/test_train $(TRAIN_DIR)/scratch-2 > $(TRAIN_DIR)/run2.log 2>&1; rc=$$?; \
		cat $(TRAIN_DIR)/run2.log; [ $$rc -eq 0 ]
	@a=$$(awk '$$1=="replay_digest"{print $$2}' $(TRAIN_DIR)/run1.log); \
	 b=$$(awk '$$1=="replay_digest"{print $$2}' $(TRAIN_DIR)/run2.log); \
	 if [ -z "$$a" ] || [ "$$a" != "$$b" ]; then echo "test-train: replay digest differs between runs"; exit 1; fi; \
	 echo "test-train: pure OM-2 PASS, replay digest equal across runs ($$a)"

train-receipt:
	bash tests/train/train_receipt.sh
endif
