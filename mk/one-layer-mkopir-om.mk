# Pure seeded OM-2 twin of tests/one_layer/acceptance/sample/mkopir.c.
# mkopir.c stays live for tests/one_layer/acceptance/selftest.sh.
# Pure seeded OM-2, physics-free, host-only.
MKOPIR_OM_OMC ?= seed/out/omc
MKOPIR_OM_SRCS := seed/ng/sha256.om src/omega_program_ir.om tests/one_layer/acceptance/sample/mkopir.om
MKOPIR_OM_DIR = $(OUT_DIR)/one-layer-mkopir
MKOPIR_OM_BIN = $(MKOPIR_OM_DIR)/mkopir_om

$(MKOPIR_OM_BIN): $(MKOPIR_OM_SRCS) $(MKOPIR_OM_OMC)
	@mkdir -p $(MKOPIR_OM_DIR)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(MKOPIR_OM_SRCS)) | $(MKOPIR_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-one-layer-mkopir-om
test-one-layer-mkopir-om: $(MKOPIR_OM_BIN)
	@set -e; \
	$(abspath $(MKOPIR_OM_BIN)) $(MKOPIR_OM_DIR)/p8.opir 8 add 200 > $(MKOPIR_OM_DIR)/p8.id; \
	$(abspath $(MKOPIR_OM_BIN)) $(MKOPIR_OM_DIR)/p16.opir 16 add 200 > /dev/null; \
	cmp -s $(MKOPIR_OM_DIR)/p8.opir tests/one_layer/acceptance/sample/cases/s04/candidate.opir; \
	cmp -s $(MKOPIR_OM_DIR)/p16.opir tests/one_layer/acceptance/sample/cases/s11/candidate.opir; \
	pid=$$(sed 's/^program_id=//' $(MKOPIR_OM_DIR)/p8.id); \
	grep -q "program_id $$pid" tests/one_layer/acceptance/sample/cases/s04/requirement; \
	$(abspath $(MKOPIR_OM_BIN)) $(MKOPIR_OM_DIR)/multi.opir 64 add 7 mul 3 or 1 > $(MKOPIR_OM_DIR)/multi.id; \
	grep -q '^program_id=[0-9a-f]\{64\}$$' $(MKOPIR_OM_DIR)/multi.id; \
	echo "ONE_LAYER_MKOPIR_OM_PASS"
