# Omega language V0 (lane 3) test target (pure seeded OM-2: tests/language/test_language_v0.om,
# built against the shipped src/language/*.om).
# Build+run from the repo root so the golden file path tests/language/golden/v0.txt resolves.
# The test is built from the SHIPPED front end: the same sources `omega` is built from (visor.om,
# the shared units, visor_program.om, src/language/*.om; `export fn` is a plain fn, one `om2`
# header) with the test, which holds only vectors, checks and a thin adapter over the shipped
# entry points, so a bug in src/language/*.om fails it.
LANG_TEST_OM_SRCS = src/visor/visor.om $(VISOR_OM_UNITS) src/visor/visor_program.om \
	src/language/omega_lex.om src/language/omega_parse.om src/language/omega_lower.om

$(OUT_DIR)/tests-language/test_language_v0: tests/language/test_language_v0.om $(LANG_TEST_OM_SRCS) $(VISOR_OMC) | $(OUT_DIR)/tests-language
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(LANG_TEST_OM_SRCS) tests/language/test_language_v0.om) | $(VISOR_OMC) > $@ && chmod +x $@

.PHONY: test-language
test-language: $(OUT_DIR)/tests-language/test_language_v0
	./$(OUT_DIR)/tests-language/test_language_v0

# Parity of the language lane src/language/*.om (lexer, parser, lowering, eval) with the retired
# C lane over the hand, golden, session and generated corpora, then its negative controls (every
# mutant must be caught). The reference is committed goldens (tests/language/parity_golden),
# generated once from the C lane at main commit 3f2c70dc5; their MANIFEST records the commit, the
# generator command and the sha256 of every corpus and golden. Needs no cc and no git history.
# It is the qualification of the C-to-OM switch, not part of test-visor-core.
.PHONY: test-language-parity
test-language-parity: $(VISOR_OMC)
	LANG_PARITY_WORK=$(abspath $(OUT_DIR))/lang-parity sh tests/language/lang_parity.sh $(abspath $(VISOR_OMC))
	LANG_PARITY_WORK=$(abspath $(OUT_DIR))/lang-parity sh tests/language/lang_mutants.sh $(abspath $(VISOR_OMC))
