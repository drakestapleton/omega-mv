# omega#440 ionic-droplet reservoir, Gate 1 & Gate 2 (docs/reservoir/RESERVOIR_REFERENCE.md):
# Pure seeded OM-2 CPU simulator of the droplet-network model of Armendarez et al.
# (Sci. Adv. 2026) plus binary64 ridge readout, tests, and Gate 2 CLI tool.
# Picked up by `-include mk/*.mk`; not part of `all` or `test`.
# CPU only: opens no device, no CUDA, never touches the GB10.
#
# test-reservoir   purity check on src/reservoir/reservoir.om, then builds and
#                  runs test_reservoir, test_res_mat, and res_qualify via
#                  seed/out/omc (checking docs/reservoir/gate2_config.json)
# reservoir-purity src/reservoir/reservoir.om contains no allocator, host I/O,
#                  socket, device, clock, or process words (after stripping
#                  OM-2 `note` comments)
# qualify-reservoir RES_ARCHIVE=<unpacked project-zenodo-ready_with-paper dir>
#                  [RES_V2_RESULTS=<v2 results .mat>]: runs qualify_reservoir.sh
ifndef RESERVOIR_MK
RESERVOIR_MK := 1
.PHONY: test-reservoir test-res-mat reservoir-purity qualify-reservoir

RES_OMC ?= seed/out/omc
OUT_DIR ?= build
RES_DIR = $(OUT_DIR)/tests-reservoir
RES_CORE_OM = src/reservoir/reservoir.om
RES_MAT_OM = tools/reservoir/res_inflate.om tools/reservoir/res_mat.om
RES_TOOL_OM = $(RES_MAT_OM) tools/reservoir/res_common.om tools/reservoir/res_bench.om tools/reservoir/res_qualify.om
RES_TEST_OM = tests/reservoir/test_reservoir.om
RES_MAT_TEST_OM = tests/reservoir/test_res_mat.om

# Forbidden host / allocator / I/O / device / clock / process words in pure reservoir.om
RES_FORBIDDEN_OM = '\b(enlarge|fopen|fclose|read|write|fseek|ftell|unlink|rename|mkdir|rmdir|stat|lstat|fork|execprog|execenv|execpure|waitpid|kill|socknew|sockbind|sockconn|socklisten|sockaccept|devctl|mapnew|mapfree|monons|realns|sleepns|random|argcnt|argread|envcnt|envread|cpuset|cpuget|cpunow|setprio|getprio)\b'

reservoir-purity: $(RES_CORE_OM)
	@if sed -E '/^[[:space:]]*note([[:space:]].*)?$$/d' $(RES_CORE_OM) | grep -En $(RES_FORBIDDEN_OM) ; then \
		echo "reservoir-purity: $(RES_CORE_OM) references a forbidden host/allocator/I/O/process word"; exit 1; fi
	@echo "reservoir-purity: $(RES_CORE_OM) is 100% pure seeded OM-2 (zero host/alloc/I/O/process words)"

$(RES_DIR)/test_reservoir: $(RES_CORE_OM) $(RES_TEST_OM) $(RES_OMC)
	@mkdir -p $(RES_DIR)
	cat $(RES_CORE_OM) $(RES_TEST_OM) | $(RES_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@ || { rm -f $@.tmp.$$$$; exit 1; }

$(RES_DIR)/test_res_mat: $(RES_CORE_OM) $(RES_MAT_OM) $(RES_MAT_TEST_OM) $(RES_OMC)
	@mkdir -p $(RES_DIR)
	cat $(RES_CORE_OM) $(RES_MAT_OM) $(RES_MAT_TEST_OM) | $(RES_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@ || { rm -f $@.tmp.$$$$; exit 1; }

$(RES_DIR)/res_qualify: $(RES_CORE_OM) $(RES_TOOL_OM) $(RES_OMC)
	@mkdir -p $(RES_DIR)
	cat $(RES_CORE_OM) $(RES_TOOL_OM) | $(RES_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@ || { rm -f $@.tmp.$$$$; exit 1; }

test-res-mat: $(RES_DIR)/test_res_mat
	$(RES_DIR)/test_res_mat

test-reservoir: reservoir-purity $(RES_DIR)/test_reservoir $(RES_DIR)/test_res_mat $(RES_DIR)/res_qualify
	$(RES_DIR)/test_reservoir
	$(RES_DIR)/test_res_mat
	$(RES_DIR)/res_qualify config | cmp - docs/reservoir/gate2_config.json
	@echo "test-reservoir: pure OM-2 reservoir checks pass; Gate 2 config unchanged"

qualify-reservoir:
	@test -n "$(RES_ARCHIVE)" || { echo "qualify-reservoir: set RES_ARCHIVE=<unpacked project-zenodo-ready_with-paper dir>"; exit 2; }
	RES_ARCHIVE="$(RES_ARCHIVE)" RES_V2_RESULTS="$(RES_V2_RESULTS)" tools/reservoir/qualify_reservoir.sh
endif
