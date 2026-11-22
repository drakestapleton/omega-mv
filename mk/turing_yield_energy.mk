# TURING Yield TY-4/TY-5: energy measurement reuse and concurrent attribution.
# docs/turing/TURING_YIELD_ENERGY_PROTOCOL_V0.md
#
# Picked up by the top-level `-include mk/*.mk` (no Makefile edit). This file is
# read before most of the Makefile, so it uses only its own variables plus
# CC and OUT_DIR (both set before the include).
#
# Targets:
#   test-turing-energy  hostile tests, plain + ASan/UBSan; no meter, no timing,
#                       runs in CI on recorded fixtures (tests/turing/fixtures/ty_energy)
#   ty-energy-tools     the workload, window tool and reducer
#   ty-energy-run       the timed stage 1 + stage 2 run, detached (setsid nohup);
#                       waits for an idle machine and holds its own quiet flag
ifndef TURING_YIELD_ENERGY_MK
TURING_YIELD_ENERGY_MK := 1

TYE_DIR = $(OUT_DIR)/ty
TYE_CFLAGS = -std=gnu11 -Wall -Wextra -Werror -D_GNU_SOURCE -O2 -Isrc -Itests/runtime
# -Wno-pedantic: generated binding src/omega_om_units.c uses GNU range designators; see mk/estimation.mk.
TYE_LIB_CFLAGS = -std=c11 -Wall -Wextra -Werror -pedantic -O2 -Isrc -Wno-pedantic
TYE_ARCH = -march=armv8.6-a+dotprod+i8mm+sve
TYE_ASAN = -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=all
TYE_ALG_SRCS = src/algebra/realize_common.c src/algebra/realize_binary.c src/algebra/realize_bitplane.c \
	src/algebra/realize_sparse.c src/algebra/realize_rns.c src/algebra/realize_dense.c
TYE_OM_LIB = src/turing/ty_energy.om
TYE_WORKLOAD = $(TYE_DIR)/ty_workload
TYE_WINDOW = $(TYE_DIR)/ty_energy_window
TYE_REDUCE = $(TYE_DIR)/ty_energy_reduce
TYE_TEST = $(TYE_DIR)/test_ty_energy
TYE_FIXTURE = $(TYE_DIR)/ty_energy_fixture

$(TYE_WORKLOAD): tests/turing/ty_workload.c tests/runtime/r15_measure.c tests/runtime/r15_measure.h $(TYE_ALG_SRCS) src/algebra/realize_common.h
	@mkdir -p $(dir $@)
	$(CC) $(TYE_CFLAGS) $(TYE_ARCH) -o $@ tests/turing/ty_workload.c tests/runtime/r15_measure.c $(TYE_ALG_SRCS) -lpthread -ldl

$(TYE_WINDOW): tests/turing/ty_energy_window.c tests/runtime/r15_measure.c tests/runtime/r15_measure.h
	@mkdir -p $(dir $@)
	$(CC) $(TYE_CFLAGS) -o $@ tests/turing/ty_energy_window.c tests/runtime/r15_measure.c -lpthread -ldl

$(TYE_REDUCE): $(TYE_OM_LIB) tools/ty_energy_reduce.om seed/out/omc
	@mkdir -p $(dir $@)
	cat $(TYE_OM_LIB) tools/ty_energy_reduce.om | seed/out/omc > $@ && chmod +x $@

$(TYE_TEST): $(TYE_OM_LIB) tests/turing/test_ty_energy.om seed/out/omc
	@mkdir -p $(dir $@)
	cat $(TYE_OM_LIB) tests/turing/test_ty_energy.om | seed/out/omc > $@ && chmod +x $@

.PHONY: test-turing-energy ty-energy-tools ty-energy-run
$(TYE_FIXTURE): tests/turing/ty_energy_fixture.om seed/out/omc
	@mkdir -p $(dir $@)
	seed/out/omc < $< > $@ && chmod +x $@

ty-energy-tools: $(TYE_WORKLOAD) $(TYE_WINDOW) $(TYE_REDUCE)

test-turing-energy: $(TYE_TEST) $(TYE_REDUCE) $(TYE_FIXTURE)
	./$(TYE_TEST)
	sh tests/turing/test_ty_energy_fixtures.sh ./$(TYE_REDUCE) $(TYE_DIR)/fixtures ./$(TYE_FIXTURE)

TYE_RUN_ID ?= $(shell date -u +%Y%m%dT%H%M%SZ)
ty-energy-run: ty-energy-tools
	@mkdir -p evidence/TURING_YIELD/energy/$(TYE_RUN_ID)
	setsid nohup sh tools/ty_energy_run.sh all evidence/TURING_YIELD/energy/$(TYE_RUN_ID) $(TYE_DIR) \
		> evidence/TURING_YIELD/energy/$(TYE_RUN_ID)/run.log 2>&1 < /dev/null &
	@echo "detached: evidence/TURING_YIELD/energy/$(TYE_RUN_ID)/run.log"

endif
