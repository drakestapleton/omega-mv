# Omega language V0 (lane 3) test target (pure seeded OM-2: tests/language/test_language_v0.om).
# Build+run from the repo root so the golden file path tests/language/golden/v0.txt resolves.
.PHONY: test-language
test-language: $(OUT_DIR)/tests-language/test_language_v0
	./$(OUT_DIR)/tests-language/test_language_v0

# C-vs-OM parity of the language lane src/language/*.om (lexer, parser, lowering, eval) over the
# hand, golden, session and generated corpora, then its negative controls (every mutant must be
# caught). Needs git and cc: the C lane is the reference only and is built from LANG_C_REF, the
# last revision that has it (tests/language/lang_parity.sh). Not part of test-visor-core.
.PHONY: test-language-parity
test-language-parity: $(VISOR_OMC)
	LANG_PARITY_WORK=$(abspath $(OUT_DIR))/lang-parity sh tests/language/lang_parity.sh $(abspath $(VISOR_OMC))
	LANG_PARITY_WORK=$(abspath $(OUT_DIR))/lang-parity sh tests/language/lang_mutants.sh $(abspath $(VISOR_OMC))
