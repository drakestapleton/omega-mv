# Pure seeded-Omega build, birth, UXL, and release coordinators (seed/build/*.om).
# Birth the Omega compiler from seed-0 through pure-Omega seed/build/birth.om (seed0 -> hex1 ->
# asm2 -> om4 -> omc fixpoint -> diaggen -> 8-case size-record -> names-pass probes).
# No C compiler and no Python runs on this path.
.PHONY: omega-from-seed om-build-gate om-check-locks om-check-paths om-uxl om-layers om-release

OMC_BIN ?= seed/out/omc
OM_BUILD_DIR ?= build/om-coord

$(OM_BUILD_DIR):
	@mkdir -p $(OM_BUILD_DIR)

$(OM_BUILD_DIR)/om-birth: seed/build/common.om seed/build/birth.om | $(OM_BUILD_DIR)
	cat seed/build/common.om seed/build/birth.om | $(OMC_BIN) > $@ && chmod 755 $@

$(OM_BUILD_DIR)/om-release: seed/build/common.om seed/build/release.om | $(OM_BUILD_DIR)
	cat seed/build/common.om seed/build/release.om | $(OMC_BIN) > $@ && chmod 755 $@

$(OM_BUILD_DIR)/om-build-gate: seed/build/common.om seed/build/gate.om | $(OM_BUILD_DIR)
	cat seed/build/common.om seed/build/gate.om | $(OMC_BIN) > $@ && chmod 755 $@

omega-from-seed:
	@if [ -x "$(OMC_BIN)" ] && [ "$$(uname -s)-$$(uname -m)" = "Linux-aarch64" ]; then \
		mkdir -p "$(OM_BUILD_DIR)" && \
		cat seed/build/common.om seed/build/birth.om | "$(OMC_BIN)" > "$(OM_BUILD_DIR)/om-birth" && \
		chmod 755 "$(OM_BUILD_DIR)/om-birth" && \
		exec "$(OM_BUILD_DIR)/om-birth"; \
	else \
		exec sh seed/omega-from-seed.sh; \
	fi

om-build-gate: $(OM_BUILD_DIR)/om-build-gate
	rm -rf $(OM_BUILD_DIR)/gate-work
	./$(OM_BUILD_DIR)/om-build-gate $(OM_BUILD_DIR)/gate-work

om-check-locks: $(OM_BUILD_DIR)/om-release
	./$(OM_BUILD_DIR)/om-release check-locks

om-check-paths: $(OM_BUILD_DIR)/om-release
	./$(OM_BUILD_DIR)/om-release check-paths

om-uxl: $(OM_BUILD_DIR)/om-release
	rm -rf $(OM_BUILD_DIR)/uxl-work
	./$(OM_BUILD_DIR)/om-release uxl $(OM_BUILD_DIR)/uxl-work

om-layers: $(OM_BUILD_DIR)/om-release
	rm -rf $(OM_BUILD_DIR)/layers-work
	./$(OM_BUILD_DIR)/om-release layers $(OM_BUILD_DIR)/layers-work

OM_RELEASE_OUT ?= build/release-pkg
OM_RELEASE_VER ?= 1.0.0-dev
om-release: $(OM_BUILD_DIR)/om-release
	rm -rf $(OM_RELEASE_OUT)
	./$(OM_BUILD_DIR)/om-release package $(OM_RELEASE_OUT) $(OM_RELEASE_VER)
	./$(OM_BUILD_DIR)/om-release verify $(OM_RELEASE_OUT)
