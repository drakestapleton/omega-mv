# Belief / estimation layer, EST-0 and EST-1 (ARCH-0020). Pure seeded OM-2.
# Picked up by `-include mk/*.mk`; not part of `all` or `test`.
#
# test-est-types  EST-0 contract: validation, digests, encoding, property tests
# test-est-kf     EST-1 filter: analytic cases and invariants
# test-est-ref    EST-1 independent reference (information form) cross-checked against est_kf
# test-estimation all three, plus the pure-OM purity check
ifndef ESTIMATION_MK
ESTIMATION_MK := 1
.PHONY: test-est-types test-est-kf test-est-ref test-estimation est-purity
EST_DIR = $(OUT_DIR)/tests-estimation
EST_OMC ?= seed/out/omc
# An estimator is a pure calculator: it must not reference file I/O, authority, World,
# generation, capability, memory-mapping, socket, device or process operations.
EST_OM_FORBIDDEN = (^|[^A-Za-z0-9_])(fopen|fclose|read|write|pread|pwrite|fork|execprog|execpure|execenv|killpid|setsid|setpgid|prlimit|socknew|connect|bind|listen|accept|send|recv|sendmsg|mapnew|mapdrop|mapread|mapwrite|mapaddr|mapget|mapset|maphold|mapbind|devctl|devcall|uvmctl|mmap|mprotect|dlopen|system|socket)([^A-Za-z0-9_]|$$)|rx_|aienos_|argus_|forge_|aegis

EST_OM_TYPES = src/estimation/est_defs.om src/estimation/est_math.om src/estimation/est_types.om
EST_OM_KF = $(EST_OM_TYPES) src/estimation/est_kf.om
EST_OM_PURE = src/estimation/est_types.om src/estimation/est_kf.om src/estimation/est_mix.om

est-purity: $(EST_OM_PURE)
	@awk -v re='$(EST_OM_FORBIDDEN)' '$$1 != "note" && $$1 != "text" && $$0 ~ re { print FILENAME ":" FNR ": " $$0; bad = 1 } END { exit bad }' \
		$(EST_OM_PURE) || { echo "estimation OM-2 source references an operation an estimator must not have"; exit 1; }
	@echo "est-purity: est_types.om, est_kf.om and est_mix.om reference no forbidden symbol (pure OM-2)"

$(EST_DIR)/test_est_types: $(EST_OM_TYPES) tests/estimation/test_est_types.om $(EST_OMC)
	@mkdir -p $(EST_DIR)
	cat $(EST_OM_TYPES) tests/estimation/test_est_types.om | $(EST_OMC) > $@ && chmod +x $@

$(EST_DIR)/test_est_kf: $(EST_OM_KF) tests/estimation/test_est_kf.om $(EST_OMC)
	@mkdir -p $(EST_DIR)
	cat $(EST_OM_KF) tests/estimation/test_est_kf.om | $(EST_OMC) > $@ && chmod +x $@

$(EST_DIR)/test_est_ref: $(EST_OM_KF) tests/estimation/est_ref_info.om tests/estimation/test_est_ref.om $(EST_OMC)
	@mkdir -p $(EST_DIR)
	cat $(EST_OM_KF) tests/estimation/est_ref_info.om tests/estimation/test_est_ref.om | $(EST_OMC) > $@ && chmod +x $@

test-est-types: $(EST_DIR)/test_est_types
	./$(EST_DIR)/test_est_types
	@echo "test-est-types: EST-0 contract checks pass (pure OM-2)"

test-est-kf: $(EST_DIR)/test_est_kf
	./$(EST_DIR)/test_est_kf
	@echo "test-est-kf: EST-1 filter checks pass (pure OM-2)"

test-est-ref: $(EST_DIR)/test_est_ref
	./$(EST_DIR)/test_est_ref
	@echo "test-est-ref: est_kf agrees with the independent information-form reference (pure OM-2)"

test-estimation: est-purity test-est-types test-est-kf test-est-ref
	@echo "test-estimation: EST-0 and EST-1 pass"
endif
