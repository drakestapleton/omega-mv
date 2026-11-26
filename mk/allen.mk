# ALLEN v0 (ARCH-0035 PROPOSED, OS-0018 PROPOSED): the durable subject inside
# the AIEN organism, pure seeded OM-2 (zero C, zero external Aienux C build).
# Picked up by `-include mk/*.mk`.
#
# Implements the exact Aienux continuity_subject v0 wire format (AIENSUBJ /
# AIENOS-STORE-OBJECT-V1 / AIENOS_INTENT_v0:) in src/allen/allen_bind.om,
# paired with src/allen/allen_core.om, src/runtime/rx_cortex.om,
# src/runtime/rx_aien.om, and tools/allen.om.
#
# test-allen: tests/allen/run.sh runs gates G1..G6 (identity, restart,
# memory, model independence, no authority / no loop, negative control) plus
# the refusals (unknown version, corruption, replay, supersession, subject
# mismatch, model mismatch tolerance) and writes nothing outside $(ALLEN_DIR).
.PHONY: test-allen allen
ALLEN_OMC ?= seed/out/omc
ALLEN_DIR = $(OUT_DIR)/allen
ALLEN_TOOL = $(ALLEN_DIR)/allen
ALLEN_OM_SRCS := \
	seed/ng/sha256.om \
	src/allen/allen_core.om \
	src/allen/allen_bind.om \
	src/runtime/rx_cortex.om \
	src/runtime/rx_aien.om \
	tools/allen.om

$(ALLEN_TOOL): $(ALLEN_OM_SRCS) $(ALLEN_OMC)
	@mkdir -p $(ALLEN_DIR)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(ALLEN_OM_SRCS)) | $(ALLEN_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

allen: $(ALLEN_TOOL)

test-allen: $(ALLEN_TOOL)
	ALLEN_TOOL=$(ALLEN_TOOL) ALLEN_OUT=$(ALLEN_DIR)/run sh tests/allen/run.sh
