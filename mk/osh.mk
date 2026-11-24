# osh shell core (aien-architecture#158). Picked up by `-include mk/*.mk`; not part of `all` or `test`.
# Pure seeded OM-2 implementation built with seed/out/omc (zero C on the osh path).
#   make osh-gen          regenerate src/osh/osh_lex.osc, osh_parse.osc, osh_expand.osc and src/osh/osh_layout.om
#   make osh-gen-check    regenerating gives byte-identical files
#   make test-osh-lex     pure OM-2 lexer driver (vectors + chunked + ABI + fuzz)
#   make test-osh-parse   pure OM-2 parser driver (vectors + parse_vectors + chunked + fuzz)
#   make test-osh-expand  pure OM-2 expander + request decoder driver
#   make osh              pure OM-2 osh shell binary
#   make test-osh-e2e     pure OM-2 end-to-end test suite (osh + argprint)
#   make osh-bash-diff    osh against /usr/bin/bash case by case + negative control
#   make osh-bash-verify  prove tests/osh/vectors/bash_vectors.tsv against real bash 5.2
#   make osh-trace        pure OM-2 core-only step trace
ifndef OSH_MK
OSH_MK := 1
.PHONY: osh-gen osh-gen-check test-osh-lex test-osh-parse test-osh-expand osh test-osh-e2e osh-bash-verify osh-bash-diff osh-trace osh-trace-gen
OSH_DIR = $(OUT_DIR)/osh
OSH_OMC ?= seed/out/omc
OSH_GEN = src/osh/osh_gen.sh
OSH_GEN_ARGS = src/osh/osh_layout.lst src/osh/osh_lex.osc.in src/osh/osh_lex.osc src/osh/osh_layout.om
OSH_GEN_ARGS_P = src/osh/osh_layout.lst src/osh/osh_parse.osc.in src/osh/osh_parse.osc src/osh/osh_layout.om
OSH_GEN_ARGS_X = src/osh/osh_layout.lst src/osh/osh_expand.osc.in src/osh/osh_expand.osc src/osh/osh_layout.om

OSH_CORE_OM = src/osh/osh_core.om src/osh/osh_layout.om src/osh/osh_lex.om src/osh/osh_parse.om src/osh/osh_expand.om
OSH_HOST_OM = src/osh/host/osh_codes.om src/osh/host/osh_req.om src/osh/host/osh_vars.om \
	src/osh/host/osh_journal.om src/osh/host/osh_caps.om src/osh/host/osh_builtin.om \
	src/osh/host/osh_exec.om src/osh/host/osh_shell.om src/osh/host/osh_main.om
OSH_BIN_OM = om/sha256/sha256-om2.om $(OSH_CORE_OM) $(OSH_HOST_OM)

define OSH_OM_BUILD
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $^) | $(OSH_OMC) > $@ && chmod +x $@
endef

osh-gen:
	sh $(OSH_GEN) gen $(OSH_GEN_ARGS)
	sh $(OSH_GEN) gen $(OSH_GEN_ARGS_P)
	sh $(OSH_GEN) gen $(OSH_GEN_ARGS_X)

osh-bash-verify:
	bash tests/osh/vectors/bash_verify.sh

osh-gen-check:
	sh $(OSH_GEN) check $(OSH_GEN_ARGS)
	sh $(OSH_GEN) check $(OSH_GEN_ARGS_P)
	sh $(OSH_GEN) check $(OSH_GEN_ARGS_X)

$(OSH_DIR)/test_osh_lex: src/osh/osh_layout.om src/osh/osh_lex.om tests/osh/test_osh_lex.om
	$(OSH_OM_BUILD)

$(OSH_DIR)/test_osh_parse: src/osh/osh_layout.om src/osh/osh_lex.om src/osh/osh_parse.om tests/osh/test_osh_parse.om
	$(OSH_OM_BUILD)

$(OSH_DIR)/test_osh_expand: $(OSH_CORE_OM) src/osh/host/osh_codes.om src/osh/host/osh_req.om tests/osh/test_osh_expand.om
	$(OSH_OM_BUILD)

test-osh-lex: osh-gen-check $(OSH_DIR)/test_osh_lex
	$(abspath $(OSH_DIR)/test_osh_lex) tests/osh/vectors > $(OSH_DIR)/lex.out
	@tail -5 $(OSH_DIR)/lex.out; tail -1 $(OSH_DIR)/lex.out | grep -q '^OSH_LEX_PASS$$'
	@echo "test-osh-lex: PASS (pure OM-2)"

test-osh-parse: osh-gen-check $(OSH_DIR)/test_osh_parse
	$(abspath $(OSH_DIR)/test_osh_parse) tests/osh/vectors tests/osh/parse_vectors > $(OSH_DIR)/parse.out
	@tail -5 $(OSH_DIR)/parse.out; tail -1 $(OSH_DIR)/parse.out | grep -q '^OSH_PARSE_PASS$$'
	@echo "test-osh-parse: PASS (pure OM-2)"

test-osh-expand: osh-gen-check $(OSH_DIR)/test_osh_expand
	$(abspath $(OSH_DIR)/test_osh_expand) tests/osh/vectors > $(OSH_DIR)/expand.out
	@tail -5 $(OSH_DIR)/expand.out; tail -1 $(OSH_DIR)/expand.out | grep -q '^OSH_EXPAND_PASS$$'
	@echo "test-osh-expand: PASS (pure OM-2)"

$(OSH_DIR)/osh: $(OSH_BIN_OM)
	$(OSH_OM_BUILD)

osh: $(OSH_DIR)/osh

$(OSH_DIR)/argprint: tests/osh/e2e/argprint.om
	$(OSH_OM_BUILD)

$(OSH_DIR)/test_osh_e2e: tests/osh/e2e/test_osh_e2e.om
	$(OSH_OM_BUILD)

test-osh-e2e: osh-gen-check $(OSH_DIR)/osh $(OSH_DIR)/argprint $(OSH_DIR)/test_osh_e2e
	rm -rf $(abspath $(OSH_DIR))/state; XDG_STATE_HOME=$(abspath $(OSH_DIR))/state $(abspath $(OSH_DIR)/test_osh_e2e) $(abspath $(OSH_DIR)/osh) $(abspath $(OSH_DIR)/argprint) > $(OSH_DIR)/e2e.out
	@tail -3 $(OSH_DIR)/e2e.out; tail -1 $(OSH_DIR)/e2e.out | grep -q '^OSH_E2E_PASS$$'
	@echo "test-osh-e2e: PASS (pure OM-2)"

osh-bash-diff: $(OSH_DIR)/osh
	bash tests/osh/bashdiff/bashdiff.sh $(abspath $(OSH_DIR)/osh) tests/osh/bashdiff/cases.txt
	BASHDIFF_NEGCTL=1 bash tests/osh/bashdiff/bashdiff.sh $(abspath $(OSH_DIR)/osh) tests/osh/bashdiff/cases.txt

$(OSH_DIR)/osh_trace: om/sha256/sha256-om2.om $(OSH_CORE_OM) src/osh/host/osh_codes.om tests/osh/osh_trace.om
	$(OSH_OM_BUILD)

osh-trace-gen: osh-gen-check $(OSH_DIR)/osh_trace
	@for x in tests/osh/trace/*.trace tests/osh/trace/*.status tests/osh/trace/*.args; do [ -e "$$x" ] || continue; [ -f "$${x%.*}.sh" ] || { echo "$@: $$x has no matching .sh"; exit 1; }; done; \
	g=$(OSH_DIR)/trace-gen; rm -rf $$g; mkdir -p $$g; \
	for f in tests/osh/trace/*.sh; do b=$$(basename $$f .sh); \
	  $(OSH_DIR)/osh_trace $$f > $$g/$$b.native || exit 1; \
	  { tail -n 1 $$g/$$b.native | grep -q '^event exit=' && grep -v '^event exit=' $$g/$$b.native | grep -q .; } || { echo "osh-trace-gen: empty or cut-off trace for $$f"; exit 1; }; \
	done; \
	for f in tests/osh/trace/*.sh; do b=$$(basename $$f .sh); cp $$g/$$b.native tests/osh/trace/$$b.trace || exit 1; done; \
	echo "osh-trace-gen: wrote traces"

osh-trace: osh-gen-check $(OSH_DIR)/osh_trace
	@for x in tests/osh/trace/*.trace tests/osh/trace/*.status tests/osh/trace/*.args; do [ -e "$$x" ] || continue; [ -f "$${x%.*}.sh" ] || { echo "$@: $$x has no matching .sh"; exit 1; }; done; \
	n=0; for f in tests/osh/trace/*.sh; do b=$$(basename $$f .sh); \
	  $(OSH_DIR)/osh_trace $$f > $(OSH_DIR)/$$b.native || exit 1; \
	  { tail -n 1 $(OSH_DIR)/$$b.native | grep -q '^event exit=' && grep -v '^event exit=' $(OSH_DIR)/$$b.native | grep -q .; } || { echo "osh-trace: empty or cut-off trace for $$f"; exit 1; }; \
	  n=$$((n+1)); done; echo "osh-trace: PASS ($$n scripts, pure OM-2)"
endif
