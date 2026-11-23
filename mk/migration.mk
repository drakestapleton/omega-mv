# C-to-OM retirement check (REVIEW-LESSONS.md "C to OM migration": a pre-review step for any change
# that deletes C or switches a consumer to OM). Host only; needs git history (the base commit and
# the deleted files' ref commits).
#
# check-retirement: tools/migration/parity_check.sh on docs/migration/PARITY.tsv (CA-1: a row per
#   deleted C file and per C file whose same-stem .om the change touches, naming its differential
#   target and every function covered or excluded with a reason; CA-2: no nm/objdump/grep check on
#   retired C that scans no OM source), then its bite controls, which must FAIL:
#   1. the ledger without the row of a deleted C file;
#   2. a row with one function dropped;
#   3. a check line in mk/ that runs nm on the object of a deleted C file and names no .om.
# PARITY_BASE: the commit the change is measured from. Default: the pre-retirement ledger baseline
# 3f2c70dc5 whenever it is an ancestor of HEAD (the bite controls name C it retired, e.g. visor_semantic.c),
# else the merge-base of HEAD and origin/main.
PARITY_DEFAULT_BASE = 3f2c70dc5dca7009b496d261c893ed0dc74c7a89
PARITY_BASE ?= $(shell if git merge-base --is-ancestor $(PARITY_DEFAULT_BASE) HEAD 2>/dev/null; then printf "%s" "$(PARITY_DEFAULT_BASE)"; else git merge-base HEAD origin/main 2>/dev/null; fi)
.PHONY: check-retirement
check-retirement:
	PARITY_BASE=$(PARITY_BASE) sh tools/migration/parity_check.sh
	@d=$(abspath $(OUT_DIR))/retirement-bite; rm -rf $$d; mkdir -p $$d/mk; n=0; \
	grep -v '^c	src/visor/visor_semantic\.c	' docs/migration/PARITY.tsv > $$d/no-row.tsv; \
	if cmp -s $$d/no-row.tsv docs/migration/PARITY.tsv; then echo "RETIREMENT BITE BROKEN: control 1 removed nothing"; exit 1; fi; \
	if PARITY_BASE=$(PARITY_BASE) PARITY_TSV=$$d/no-row.tsv sh tools/migration/parity_check.sh > $$d/1.out; then echo "RETIREMENT BITE FAIL: a deleted C file without a row passed"; exit 1; fi; \
	grep -q 'visor_semantic.c is deleted by this change and has no row' $$d/1.out || { echo "RETIREMENT BITE FAIL: control 1 failed for another reason"; cat $$d/1.out; exit 1; }; n=$$((n + 1)); \
	sed -e '/^c	src\/visor\/visor_effect_request\.c	/s/visor_effect_request_classify,//' docs/migration/PARITY.tsv > $$d/no-fn.tsv; \
	if cmp -s $$d/no-fn.tsv docs/migration/PARITY.tsv; then echo "RETIREMENT BITE BROKEN: control 2 removed nothing"; exit 1; fi; \
	if PARITY_BASE=$(PARITY_BASE) PARITY_TSV=$$d/no-fn.tsv sh tools/migration/parity_check.sh > $$d/2.out; then echo "RETIREMENT BITE FAIL: a row missing a function passed"; exit 1; fi; \
	grep -q 'function visor_effect_request_classify is neither covered' $$d/2.out || { echo "RETIREMENT BITE FAIL: control 2 failed for another reason"; cat $$d/2.out; exit 1; }; n=$$((n + 1)); \
	printf 'stale-check:\n\tnm -u $$(OUT_DIR)/visor/visor_semantic.o | grep rx_\n' > $$d/mk/stale.mk; \
	if PARITY_BASE=$(PARITY_BASE) PARITY_SCAN="mk tests $$d/mk" sh tools/migration/parity_check.sh > $$d/3.out; then echo "RETIREMENT BITE FAIL: an nm check on retired C passed"; exit 1; fi; \
	grep -q 'CA-2: .*stale.mk runs a check on retired C visor_semantic' $$d/3.out || { echo "RETIREMENT BITE FAIL: control 3 failed for another reason"; cat $$d/3.out; exit 1; }; n=$$((n + 1)); \
	echo "RETIREMENT bite controls: $$n/3 caught"
