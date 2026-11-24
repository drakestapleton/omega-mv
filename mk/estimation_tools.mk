# EST-2/EST-3 replay, fit and evaluation tools (protocol v1, v2). Pure seeded OM-2.
# Not part of `all` or `test`. Tools may open files and print; core estimators stay
# pure (est-purity).
ifndef ESTIMATION_TOOLS_MK
ESTIMATION_TOOLS_MK := 1
include mk/estimation.mk
.PHONY: test-est-tools est-tools-purity est-tools test-est-replay-parity test-est-eval-tmpdir
ESTT_DIR = $(OUT_DIR)/est-tools
# Tool identity baked in at build time as a generated toolid.om (t_ee_tool_commit,
# EE_TOOL_DIRTY, EE_TEST_BUILD) composed before est_eval.om. The stamp is rewritten
# only when the commit or the dirty flag changes, so est_eval rebuilds then.
ESTT_COMMIT := $(shell git rev-parse HEAD 2>/dev/null || echo unknown)
ESTT_DIRTY := $(shell if [ -n "$$(git status --porcelain 2>/dev/null)" ]; then echo 1; else echo 0; fi)
# OM-2 host words an estimation tool must not use (process, socket, mapping and device
# words), checked on every code line (not note or text lines) of the composed sources.
ESTT_OM_FORBIDDEN = (^|[^A-Za-z0-9_])(fork|execprog|execpure|execenv|killpid|setsid|setpgid|prlimit|socknew|connect|bind|listen|accept|send|recv|sendmsg|mapnew|mapdrop|mapread|mapwrite|mapaddr|mapget|mapset|maphold|mapbind|devctl|devcall|uvmctl|mmap|mprotect|dlopen|system|socket)([^A-Za-z0-9_]|$$)|rx_|aienos_|argus_|forge_|aegis

.PHONY: est-tools-stamp
est-tools-stamp:
	@mkdir -p $(ESTT_DIR)
	@echo "$(ESTT_COMMIT) $(ESTT_DIRTY)" > $(ESTT_DIR)/toolid.new; \
	cmp -s $(ESTT_DIR)/toolid.new $(ESTT_DIR)/toolid.stamp || mv $(ESTT_DIR)/toolid.new $(ESTT_DIR)/toolid.stamp; rm -f $(ESTT_DIR)/toolid.new
$(ESTT_DIR)/toolid.stamp: | est-tools-stamp
$(ESTT_DIR)/toolid.om: $(ESTT_DIR)/toolid.stamp
	printf 'text t_ee_tool_commit "%s"\nconst EE_TOOL_DIRTY ulong %s\nconst EE_TEST_BUILD ulong 0\n' '$(ESTT_COMMIT)' '$(ESTT_DIRTY)' > $@
# est_eval built for tests only: run B / C2 identities and the dirty flag come from the environment
$(ESTT_DIR)/toolid_t.om:
	@mkdir -p $(ESTT_DIR)
	printf 'text t_ee_tool_commit "test-build"\nconst EE_TOOL_DIRTY ulong 1\nconst EE_TEST_BUILD ulong 1\n' > $@
ESTT_OMC ?= seed/out/omc
ESTT_OM_LIB = src/estimation/est_defs.om src/estimation/est_math.om src/estimation/est_types.om \
	src/estimation/est_kf.om src/estimation/est_mix.om src/estimation/est_pred.om \
	src/estimation/est_v4.om tools/estimation/est_replay.om
ESTT_OM_MAINS = tools/estimation/est_replay_main.om tools/estimation/est_fit.om tools/estimation/est_eval.om

$(ESTT_DIR)/est_replay: $(ESTT_OM_LIB) tools/estimation/est_replay_main.om $(ESTT_OMC)
	@mkdir -p $(ESTT_DIR)
	cat $(ESTT_OM_LIB) tools/estimation/est_replay_main.om | $(ESTT_OMC) > $@ && chmod +x $@
$(ESTT_DIR)/est_fit: $(ESTT_OM_LIB) tools/estimation/est_fit.om $(ESTT_OMC)
	@mkdir -p $(ESTT_DIR)
	cat $(ESTT_OM_LIB) tools/estimation/est_fit.om | $(ESTT_OMC) > $@ && chmod +x $@
$(ESTT_DIR)/est_eval: $(ESTT_OM_LIB) $(ESTT_DIR)/toolid.om tools/estimation/est_eval.om $(ESTT_OMC)
	cat $(ESTT_OM_LIB) $(ESTT_DIR)/toolid.om tools/estimation/est_eval.om | $(ESTT_OMC) > $@ && chmod +x $@
$(ESTT_DIR)/est_eval_t: $(ESTT_OM_LIB) $(ESTT_DIR)/toolid_t.om tools/estimation/est_eval.om $(ESTT_OMC)
	cat $(ESTT_OM_LIB) $(ESTT_DIR)/toolid_t.om tools/estimation/est_eval.om | $(ESTT_OMC) > $@ && chmod +x $@
$(ESTT_DIR)/test_est_tools: $(ESTT_OM_LIB) tools/estimation/test_est_tools.om $(ESTT_OMC)
	@mkdir -p $(ESTT_DIR)
	cat $(ESTT_OM_LIB) tools/estimation/test_est_tools.om | $(ESTT_OMC) > $@ && chmod +x $@

est-tools: $(ESTT_DIR)/est_fit $(ESTT_DIR)/est_eval $(ESTT_DIR)/est_replay

est-tools-purity: est-purity
	@awk -v re='$(ESTT_OM_FORBIDDEN)' '$$1 != "note" && $$1 != "text" && $$0 ~ re { print FILENAME ":" FNR ": " $$0; bad = 1 } END { exit bad }' \
		$(ESTT_OM_LIB) $(ESTT_OM_MAINS) || { echo "an OM-2 estimation tool uses a process, socket, mapping or device word"; exit 1; }
	@# bite control: the same scan must catch each word class planted in a copy of a shipped tool,
	@# and must not trip on the unplanted copy or on the words in a note or text line
	@mkdir -p $(ESTT_DIR)/purity-bite
	@for p in '  pid = fork' '  s = socknew 2 1 0' '  m = mapnew 4096' '  devctl 3 0 0' '  rx_world_init 0' '  argus_open 1'; do \
		{ cat tools/estimation/est_replay_main.om; printf '%s\n' "$$p"; } > $(ESTT_DIR)/purity-bite/plant.om; \
		if awk -v re='$(ESTT_OM_FORBIDDEN)' '$$1 != "note" && $$1 != "text" && $$0 ~ re { bad = 1 } END { exit bad }' $(ESTT_DIR)/purity-bite/plant.om; then \
			echo "est-tools-purity: the OM scan does not bite on planted '$$p'"; exit 1; fi; \
	done
	@{ cat tools/estimation/est_replay_main.om; printf '%s\n' 'note fork socknew rx_world_init' 'text t_bite "mapnew devctl aegis"'; } > $(ESTT_DIR)/purity-bite/plant.om; \
		awk -v re='$(ESTT_OM_FORBIDDEN)' '$$1 != "note" && $$1 != "text" && $$0 ~ re { bad = 1 } END { exit bad }' $(ESTT_DIR)/purity-bite/plant.om \
		|| { echo "est-tools-purity: the OM scan trips on a note or text line (bite control baseline)"; exit 1; }
	@echo "est-tools-purity: the OM-2 tool sources use no authority/process operation (the OM scan bites on 6 planted words); core estimators pure"

# no input-size cap: more than 8192 steps, 16384 lines, 2 MiB, 8 KiB lines and 64 KiB SHA256SUMS,
# byte for byte against the C est_replay reference goldens
test-est-replay-parity: $(ESTT_DIR)/est_replay
	sh tools/estimation/test_est_replay_parity.sh tools/estimation/est_replay_parity.gold ./$(ESTT_DIR)/est_replay $(ESTT_DIR)/work-parity

# est_eval's prefix temp directory under a 576, 577, 5000-byte and empty TMPDIR, as the C est_eval
test-est-eval-tmpdir: $(ESTT_DIR)/est_fit $(ESTT_DIR)/est_eval
	sh tools/estimation/test_est_eval_tmpdir.sh ./$(ESTT_DIR)/est_fit ./$(ESTT_DIR)/est_eval $(ESTT_DIR)/work-tmpdir

test-est-tools: est-tools-purity test-est-replay-parity test-est-eval-tmpdir $(ESTT_DIR)/est_fit $(ESTT_DIR)/est_eval $(ESTT_DIR)/est_eval_t $(ESTT_DIR)/test_est_tools
	rm -rf $(ESTT_DIR)/work
	./$(ESTT_DIR)/test_est_tools ./$(ESTT_DIR)/est_fit ./$(ESTT_DIR)/est_eval ./$(ESTT_DIR)/est_eval_t $(ESTT_DIR)/work
	@echo "test-est-tools: replay, fit and evaluation tools pass on run A and synthetic data (pure OM-2)"
endif
