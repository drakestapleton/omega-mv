# Decode-graph performance receipt (aien-architecture#233, lane P1): tools/dgraph_receipt.om turns an
# existing decode-graph chip run (tools/run_gpu_decode_graph_chip.sh evidence) into one commit-bound
# receipt "omega-decode-graph-receipt/1" and checks such receipts. Host only: pure seeded OM-2,
# links nothing of libomega_gpu and no GPU header. Spec: docs/perf/DECODE_GRAPH_RECEIPT.md. Picked up
# by `-include mk/*.mk`; not part of `all` or `test`; run by tests/gates/run.sh chip-tool-selftests.
#   make dgraph-receipt        build/dgraph_receipt/dgraph_receipt
#   make test-dgraph-receipt   golden receipts regenerated from evidence/, checker accepts them,
#                              every negative fixture refused for its named reason
ifndef DGRAPH_RECEIPT_MK
DGRAPH_RECEIPT_MK := 1
.PHONY: dgraph-receipt test-dgraph-receipt
DGR_DIR = $(OUT_DIR)/dgraph_receipt

dgraph-receipt: $(DGR_DIR)/dgraph_receipt

$(DGR_DIR)/dgraph_receipt: tools/dgraph_receipt.om seed/out/omc
	@mkdir -p $(DGR_DIR)
	seed/out/omc < tools/dgraph_receipt.om > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

# independent strict-JSON check of the golden receipts (tools/json_canon.om, pure OM-2)
$(DGR_DIR)/json_canon: tools/json_canon.om seed/out/omc
	@mkdir -p $(DGR_DIR)
	seed/out/omc < tools/json_canon.om > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

test-dgraph-receipt: $(DGR_DIR)/dgraph_receipt $(DGR_DIR)/json_canon
	sh tests/dgraph_receipt/run.sh $(DGR_DIR)/dgraph_receipt $(DGR_DIR)/json_canon $(DGR_DIR)/work

endif
