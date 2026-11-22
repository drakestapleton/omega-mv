# Turing calibration EXP-001, lane D: the independent scorer (tools/turing_verify_indep, copied unchanged from
# the lane D workspace; its own Makefile is kept as delivered but not used here). Picked up by -include mk/*.mk.
# All variables TVI_-prefixed.
#
#   make turing-verify-indep        build build/turing-verify-indep/indep-scorer (+ indep-selftest)
#   make test-turing-verify-indep   independence grep check + the scorer's own self-test (no dev data needed)
#
# Independence: the build uses ONLY tools/turing_verify_indep/src (never -Isrc, never an omega object), and the
# check refuses any #include outside that directory's own headers and libc, and any ty_/tc_ identifier in code
# (comments stripped first; the scorer's comments cite omega file names as provenance only).
.PHONY: turing-verify-indep test-turing-verify-indep
TVI_SRC = tools/turing_verify_indep/src
TVI_DIR = $(OUT_DIR)/turing-verify-indep
TVI_BIN = $(TVI_DIR)/indep-scorer
TVI_SELF = $(TVI_DIR)/indep-selftest
TVI_OMC ?= seed/out/omc
TVI_BASE = $(TVI_SRC)/sha256.om $(TVI_SRC)/core.om

$(TVI_BIN): $(TVI_BASE) $(TVI_SRC)/main.om $(TVI_OMC)
	@mkdir -p $(TVI_DIR)
	cat $(TVI_BASE) $(TVI_SRC)/main.om | $(TVI_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@
$(TVI_SELF): $(TVI_BASE) $(TVI_SRC)/selftest.om $(TVI_OMC)
	@mkdir -p $(TVI_DIR)
	cat $(TVI_BASE) $(TVI_SRC)/selftest.om | $(TVI_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

turing-verify-indep: $(TVI_BIN) $(TVI_SELF)

test-turing-verify-indep: $(TVI_BIN) $(TVI_SELF)
	@bad=$$(grep -h '^[[:space:]]*#[[:space:]]*include' $(TVI_SRC)/* | grep -v -E '#[[:space:]]*include[[:space:]]*(<[a-z0-9_/]+\.h>|"(core|sha256)\.h")' || true); \
	 [ -z "$$bad" ] || { echo "turing-verify-indep: non-local include: $$bad"; exit 1; }
	@ids=$$(for f in $(TVI_SRC)/*; do awk '{ s = s $$0 "\n" } END { gsub(/\/\*([^*]|\*+[^*\/])*\*+\//, "", s); printf "%s", s }' "$$f" \
	   | sed 's://.*$$::' | grep -n -E '\b(ty|tc)_[A-Za-z0-9_]+' | sed "s|^|$$f:|"; done); \
	 [ -z "$$ids" ] || { echo "turing-verify-indep: omega identifiers in code:"; echo "$$ids"; exit 1; }
	@echo "turing-verify-indep: no omega include, no ty_/tc_ identifier"
	cd $(TVI_DIR) && ./indep-selftest
	@echo "turing-verify-indep source digest: $$(sh calibration/scripts/indep_source_digest.sh)"
