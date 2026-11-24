# Pure seeded OM-2 migration of tools/omegatool.c (CPU-only CLI, M4..M15 gates, R16 surface, test vectors).
# Pure seeded OM-2, physics-free, host-only (never opens /dev/nvidia* or GB10 GPU).
OUT_DIR ?= build
OMEGATOOL_OM_OMC ?= seed/out/omc
OMEGATOOL_OM_SRCS := \
	seed/ng/sha256.om \
	om/visor/canonical_om2.om \
	om/visor/codec_om2.om \
	om/visor/validate_om2.om \
	om/visor/verify_om2.om \
	om/aarch64/aarch64_om2.om \
	src/omega_canonical.om \
	src/omega_core.om \
	src/omega_validate.om \
	src/omega_codec.om \
	src/aarch64_encoder.om \
	src/aarch64_decoder.om \
	src/omega_realize.om \
	src/omega_exec.om \
	src/omega_self_host.om \
	src/omega_verify.om \
	src/omega_machine.om \
	src/omega_program.om \
	src/omega_synthesis.om \
	src/omega_library.om \
	src/omega_discovery.om \
	src/omega_matvec.om \
	src/omega_realize_synth.om \
	src/omega_accelerator.om \
	src/omega_evidence.om \
	tools/omegatool.om
OMEGATOOL_OM_BIN = $(OUT_DIR)/omegatool_om

$(OMEGATOOL_OM_BIN): $(OMEGATOOL_OM_SRCS) $(OMEGATOOL_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(OMEGATOOL_OM_SRCS)) | $(OMEGATOOL_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: omegatool-om test-omegatool-om
omegatool-om: $(OMEGATOOL_OM_BIN)

test-omegatool-om: $(OMEGATOOL_OM_BIN)
	sh tests/test_omegatool_om.sh $(abspath $(OMEGATOOL_OM_BIN))
