# Differential qualification of the pure OM-2 genret (tools/gen/retrieval/genret.om) against the C it replaced
# (tools/gen/retrieval/genret.c, retired by wave 31). Host only, CPU only, no cc, no git history.
#
# test-genret-parity
#   1. tests/gen_retrieval/genret_parity.sh: the hand, query, synthetic and record-validation corpora through the
#      OM genret (both bindings: test-only `any` and the pinned `prod`, built from the shipped source as
#      mk/gen-retrieval.mk joins it), byte for byte against the committed goldens of the C genret at main
#      3f2c70dc5 (tests/gen_retrieval/golden, MANIFEST with commit, generator and sha256): exit status, stdout,
#      stderr, every --out file and any .tmp.* directory left behind;
#   2. tests/gen_retrieval/genret_mutants.sh: every mutant of the OM genret must differ from the goldens.
.PHONY: test-genret-parity
test-genret-parity: $(GENRET_OMC)
	GENRET_PARITY_WORK=$(abspath $(OUT_DIR))/genret-parity sh tests/gen_retrieval/genret_parity.sh $(abspath $(GENRET_OMC))
	GENRET_PARITY_WORK=$(abspath $(OUT_DIR))/genret-parity sh tests/gen_retrieval/genret_mutants.sh $(abspath $(GENRET_OMC))
