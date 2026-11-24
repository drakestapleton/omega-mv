# Pure seeded OM-2 twin of tests/one_layer/generalization/dev/gen_expected.c (devgen01..devgen10).
# gen_expected.c stays live because it is SHA-256 pinned in protocol.json and gencheck.
# Pure seeded OM-2, physics-free, host-only.
GEN_DEV_OM_OMC ?= seed/out/omc
GEN_DEV_OM_DIR = $(OUT_DIR)/one-layer-gen-dev
GEN_DEV_OM_BIN = $(GEN_DEV_OM_DIR)/gen_expected_om
GEN_DEV_C_BIN = $(GEN_DEV_OM_DIR)/gen_expected_c

$(GEN_DEV_OM_BIN): tests/one_layer/generalization/dev/gen_expected.om $(GEN_DEV_OM_OMC)
	@mkdir -p $(GEN_DEV_OM_DIR)
	$(GEN_DEV_OM_OMC) < $< > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(GEN_DEV_C_BIN): tests/one_layer/generalization/dev/gen_expected.c
	@mkdir -p $(GEN_DEV_OM_DIR)
	$(CC) -std=gnu11 -Wall -Wextra -Werror -O2 -o $@ $<

.PHONY: test-one-layer-gen-dev-om
test-one-layer-gen-dev-om: $(GEN_DEV_OM_BIN) $(GEN_DEV_C_BIN)
	@set -e; n=0; \
	for d in tests/one_layer/generalization/dev/tasks/cases/devgen*; do \
	  id=$$(basename "$$d"); \
	  $(abspath $(GEN_DEV_OM_BIN)) "$$id" < "$$d/hidden/inputs" > $(GEN_DEV_OM_DIR)/$$id.om.out; \
	  $(abspath $(GEN_DEV_C_BIN)) "$$id" < "$$d/hidden/inputs" > $(GEN_DEV_OM_DIR)/$$id.c.out; \
	  cmp -s $(GEN_DEV_OM_DIR)/$$id.om.out "$$d/hidden/expected" || { echo "FAIL $$id om vs expected"; exit 1; }; \
	  cmp -s $(GEN_DEV_OM_DIR)/$$id.om.out $(GEN_DEV_OM_DIR)/$$id.c.out || { echo "FAIL $$id om vs c"; exit 1; }; \
	  n=$$((n + 1)); \
	done; \
	rc=0; $(abspath $(GEN_DEV_OM_BIN)) unknown_task </dev/null >/dev/null 2>&1 || rc=$$?; \
	[ "$$rc" -eq 2 ] || { echo "FAIL unknown_task exit $$rc"; exit 1; }; \
	echo "ONE_LAYER_GEN_DEV_OM_PASS tasks=$$n"
