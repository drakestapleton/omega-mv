# EvidenceReceiptV1 parser, canonical encoder & BLAKE3 verifier in pure seeded OM-2 (src/omega_receipt.om, twin of src/omega_receipt.c).
# Pure seeded OM-2, physics-free, host-only.
OMEGA_RECEIPT_OM_OMC ?= seed/out/omc
OMEGA_RECEIPT_OM_SRCS := om/blake3/b3unit.om src/omega_blake3.om src/omega_receipt.om tests/test_omega_receipt.om
OMEGA_RECEIPT_OM_TEST = $(OUT_DIR)/test_omega_receipt_om

$(OMEGA_RECEIPT_OM_TEST): $(OMEGA_RECEIPT_OM_SRCS) $(OMEGA_RECEIPT_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(OMEGA_RECEIPT_OM_SRCS)) | $(OMEGA_RECEIPT_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-omega-receipt-om
test-omega-receipt-om: $(OMEGA_RECEIPT_OM_TEST)
	$(abspath $(OMEGA_RECEIPT_OM_TEST))
