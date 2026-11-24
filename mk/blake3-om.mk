# BLAKE3 chunking wrapper in pure seeded OM-2 (src/omega_blake3.om over om/blake3/b3unit.om,
# twin of src/omega_blake3.c). Physics-free, host-only.
BLAKE3_OM_OMC ?= seed/out/omc
BLAKE3_OM_SRCS := om/blake3/b3unit.om src/omega_blake3.om tests/test_omega_blake3.om
BLAKE3_OM_TEST = $(OUT_DIR)/test_omega_blake3_om

$(BLAKE3_OM_TEST): $(BLAKE3_OM_SRCS) $(BLAKE3_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(BLAKE3_OM_SRCS)) | $(BLAKE3_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-blake3-om
test-blake3-om: $(BLAKE3_OM_TEST)
	$(abspath $(BLAKE3_OM_TEST))
