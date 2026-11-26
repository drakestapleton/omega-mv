# ALLEN host tool (tools/allen.om, pure seeded OM-2 replacement for tools/allen.c).
# Pure seeded OM-2, physics-free, host-only.
ALLEN_TOOL_OM_OMC ?= seed/out/omc
ALLEN_TOOL_OM_SRCS := \
	seed/ng/sha256.om \
	src/allen/allen_core.om \
	src/allen/allen_bind.om \
	src/runtime/rx_cortex.om \
	src/runtime/rx_aien.om \
	tools/allen.om
ALLEN_TOOL_OM_BIN = $(OUT_DIR)/allen_om

$(ALLEN_TOOL_OM_BIN): $(ALLEN_TOOL_OM_SRCS) $(ALLEN_TOOL_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(ALLEN_TOOL_OM_SRCS)) | $(ALLEN_TOOL_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-allen-tool-om
test-allen-tool-om: $(ALLEN_TOOL_OM_BIN)
	@set -e; D=$$(mktemp -d); trap 'rm -rf "$$D"' EXIT; \
	B=$(abspath $(ALLEN_TOOL_OM_BIN)); \
	A=a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1; \
	R=0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a; \
	P=c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3; \
	"$$B" seed-journal "$$D/j1.cx" 1 | grep -q "^ALLEN seeded journal .* lineage "; \
	"$$B" seed-journal "$$D/j2.cx" 2 | grep -q "^ALLEN seeded journal .* lineage "; \
	"$$B" lineage "$$D/j1.cx" | grep -q "^ALLEN lineage "; \
	"$$B" make -o "$$D/s1.bin" --agent "$$A" --root "$$R" --prov "$$P" --intent 7,1000 --cortex "$$D/j1.cx" | grep -q "^ALLEN subject "; \
	"$$B" inspect "$$D/s1.bin" | grep -q "^ALLEN agent $$A$$"; \
	D1=$$("$$B" digest "$$D/s1.bin"); test "$${#D1}" -eq 64; \
	"$$B" publish "$$D/s1.bin" "$$D/j1.cx" | grep -q "^ALLEN publish intent .* -> EXTERNAL crumb 1$$"; \
	"$$B" probe "$$D/j1.cx" | grep -q "^ALLEN probe journal_records 3 goals_in_world 0 goal_seq 0 assessment_goal_seq 0$$"; \
	if "$$B" publish "$$D/s1.bin" "$$D/j2.cx" >/dev/null 2>&1; then exit 1; fi; \
	echo "PASS test_allen_tool_om"
