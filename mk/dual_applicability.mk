# DUAL applicability experiment (ARCH-0031 / ADR 0031, offline evidence lane):
# when is aggregate (macroscopic) load control predictive, and when must
# discrete per-item scheduling dominate? Standalone: pure seeded OM-2 under
# src/dual_experiment/, tools/dual_experiment/, tests/dual_experiment/,
# docs/dual/, evidence/DUAL/applicability/. Picked up by `-include mk/*.mk`;
# not part of `all` or `test`. Nothing in src/runtime/ includes or links it.
# EXPERIMENT ONLY: no production gate, no production classifier.
#
# test-dual-applicability  unit suite (determinism, ledger, predictor, controls)
#                          built with seed/out/omc, plus the purity check
# dual-applic-purity       static purity scan on src/dual_experiment/*.om
# dual-applic-run          run the campaign, write evidence/DUAL/applicability/
ifndef DUAL_APPLICABILITY_MK
DUAL_APPLICABILITY_MK := 1
.PHONY: test-dual-applicability dual-applic-purity dual-applic-run
DAP_DIR = $(OUT_DIR)/dual-applicability
DAP_OMC = seed/out/omc
DAP_LIB = src/dual_experiment/applic.om
DAP_EVIDENCE = evidence/DUAL/applicability
DAP_FORBIDDEN = '\b(rx_[A-Za-z0-9_]*|aienos_[A-Za-z0-9_]*|argus_[A-Za-z0-9_]*|forge_[A-Za-z0-9_]*|aegis[A-Za-z0-9_]*|mmap|mprotect|fork|exec|execprog|execenv|execpure|dlopen|system|socket|socknew|connect|bind|listen|accept|fopen|fclose|read|write|pread|pwrite|unlink|makedir|rmdir|chdir|chmod|chown|killpid|waitpid|pipefds|dupfd|mapnew|devctl|uvmctl|vfioctl|random|monons|realns|sleepns|open)\b'

# The experiment library is a pure calculator: no authority, World, generation,
# capability, memory-mapping, process, network or file host words.
dual-applic-purity: src/dual_experiment/applic.om src/dual_experiment/applic_core.om
	@for f in src/dual_experiment/*.om; do \
		if grep -v '^[[:space:]]*note\([[:space:]]\|$$\)' "$$f" | grep -En $(DAP_FORBIDDEN) ; then \
			echo "dual-applic-purity: $$f references a forbidden operation"; exit 1; \
		fi; \
	done
	@echo "dual-applic-purity: src/dual_experiment/*.om reference no forbidden symbol or host word"

$(DAP_DIR)/test_applic: $(DAP_LIB) tests/dual_experiment/test_applic.om $(DAP_OMC)
	@mkdir -p $(DAP_DIR)
	cat $(DAP_LIB) tests/dual_experiment/test_applic.om | $(DAP_OMC) > $@ && chmod +x $@

$(DAP_DIR)/applic_run: $(DAP_LIB) tools/dual_experiment/applic_run.om $(DAP_OMC)
	@mkdir -p $(DAP_DIR)
	cat $(DAP_LIB) tools/dual_experiment/applic_run.om | $(DAP_OMC) > $@ && chmod +x $@

test-dual-applicability: dual-applic-purity $(DAP_DIR)/test_applic
	./$(DAP_DIR)/test_applic
	@echo "test-dual-applicability: determinism, ledger, predictor and negative-control checks pass (pure seeded OM-2)"

dual-applic-run: $(DAP_DIR)/applic_run
	@mkdir -p $(DAP_EVIDENCE)
	./$(DAP_DIR)/applic_run $(DAP_EVIDENCE)
endif
