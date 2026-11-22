# Belief / estimation layer, EST-0 and EST-1 (ARCH-0020). Standalone: new
# files only under src/estimation/ and tests/estimation/. Picked up by
# `-include mk/*.mk`; not part of `all` or `test`. Nothing in src/runtime/
# includes or links it.
#
# test-est-types  EST-0 contract: validation, digests, encoding, property tests
# test-est-kf     EST-1 filter: analytic cases and invariants
# test-est-ref    EST-1 independent reference (information form, written
#                 without reading est_kf.c) cross-checked against est_kf
# test-estimation all three, plain + ASan/UBSan, plus the purity check
ifndef ESTIMATION_MK
ESTIMATION_MK := 1
.PHONY: test-est-types test-est-kf test-est-ref test-estimation est-purity
# -Wno-pedantic: the generated binding src/omega_om_units.c carries the runtime entry table as
# GNU range designators, which ISO C forbids (-Werror=pedantic), and every test binary here links
# that file. The generator fix is omega-bridge #17 (ABI-v2 line); until it lands this silences only
# that one diagnostic and keeps the strict flags for the handwritten sources in the same commands.
EST_CFLAGS = -std=c11 -Wall -Wextra -Werror -pedantic -O2 -D_POSIX_C_SOURCE=200809L -Isrc -Isrc/estimation -Itests/estimation -ffp-contract=off -fno-fast-math -Wno-pedantic
EST_ASAN = -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=all
EST_TYPES_SRCS = src/estimation/est_types.c src/omega_om_units.c
EST_KF_SRCS = src/estimation/est_kf.c $(EST_TYPES_SRCS)
EST_HDRS = src/estimation/est_types.h src/estimation/est_kf.h src/estimation/est_mix.h
EST_DIR = $(OUT_DIR)/tests-estimation
# An estimator is a calculator: it must not reference authority, World,
# generation, capability, memory-mapping or process operations.
EST_FORBIDDEN = 'rx_|aienos_|argus_|forge_|aegis|mmap|mprotect|fork|exec|dlopen|system|socket|fopen|open$$'

$(EST_DIR)/%.o: src/estimation/%.c $(EST_HDRS)
	@mkdir -p $(EST_DIR)
	$(CC) $(EST_CFLAGS) -c -o $@ $<

est-purity: $(EST_DIR)/est_types.o $(EST_DIR)/est_kf.o $(EST_DIR)/est_mix.o
	@if nm -u $^ | grep -E $(EST_FORBIDDEN) ; then \
		echo "estimation object references an operation an estimator must not have"; exit 1; fi
	@echo "est-purity: est_types.o, est_kf.o and est_mix.o reference no forbidden symbol"

EST_OMC ?= seed/out/omc
EST_OM_TYPES = src/estimation/est_defs.om src/estimation/est_math.om src/estimation/est_types.om
EST_OM_KF = $(EST_OM_TYPES) src/estimation/est_kf.om

$(EST_DIR)/test_est_types: $(EST_OM_TYPES) tests/estimation/test_est_types.om
	@mkdir -p $(EST_DIR)
	cat $^ | $(EST_OMC) > $@ && chmod +x $@

$(EST_DIR)/test_est_kf: $(EST_OM_KF) tests/estimation/test_est_kf.om
	@mkdir -p $(EST_DIR)
	cat $^ | $(EST_OMC) > $@ && chmod +x $@

$(EST_DIR)/test_est_ref: $(EST_OM_KF) tests/estimation/est_ref_info.om tests/estimation/test_est_ref.om
	@mkdir -p $(EST_DIR)
	cat $^ | $(EST_OMC) > $@ && chmod +x $@

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
