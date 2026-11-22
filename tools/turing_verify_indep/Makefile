# Lane D independent scorer (EXP-001). Pure seeded OM-2, no dependency outside seed/out/omc.
OMC ?= ../../seed/out/omc
BUILD := build

all: $(BUILD)/indep-scorer $(BUILD)/indep-selftest

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/indep-scorer: src/sha256.om src/core.om src/main.om | $(BUILD)
	cat src/sha256.om src/core.om src/main.om | $(OMC) > $@ && chmod +x $@

$(BUILD)/indep-selftest: src/sha256.om src/core.om src/selftest.om | $(BUILD)
	cat src/sha256.om src/core.om src/selftest.om | $(OMC) > $@ && chmod +x $@

test: $(BUILD)/indep-selftest
	cd $(BUILD) && ./indep-selftest ../../docs-only-v2 $(HOME)/aien-data/turing-cal/candidates

clean:
	rm -rf $(BUILD)

.PHONY: all test clean
