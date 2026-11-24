# Native realization exec cache test (tests/exec/test_exec_native_cache.om). Pure seeded OM-2, host-only.
EXEC_CACHE_OMC ?= seed/out/omc
EXEC_CACHE_OM_SRCS := seed/ng/sha256.om om/aarch64/aarch64_om2.om src/omega_exec.om tests/exec/test_exec_native_cache.om
EXEC_CACHE_OM_TEST = $(OUT_DIR)/test_exec_native_cache_om

$(EXEC_CACHE_OM_TEST): $(EXEC_CACHE_OM_SRCS) $(EXEC_CACHE_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(EXEC_CACHE_OM_SRCS)) | $(EXEC_CACHE_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-exec-native-cache-om
test-exec-native-cache-om: $(EXEC_CACHE_OM_TEST)
	$(abspath $(EXEC_CACHE_OM_TEST))
