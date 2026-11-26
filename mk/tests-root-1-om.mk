# Top-level tests/*.c CPU-only pure seeded OM-2 migration wave 1 (tests-root-1).
# Pure seeded OM-2 twins of:
#   tests/bw_encode_control_test.c
#   tests/test_sha256_freestanding_parity.c
#   tests/bw_mufu_ftz_test.c
#   tests/test_omega_genesis.c
#   tests/test_omega_program_ir.c
#   tests/test_omega_codegen_freestanding.c
#   tests/q36_codegen_hash.c
# Physics-free, host-only, CPU-only, zero GPU access.

TESTS_ROOT_1_OMC ?= seed/out/omc

TR1_BW_ENC_CTL_SRCS := \
	om/gpu/cg_matmul.om \
	om/gpu/bw_regalloc.om \
	om/encoder/bw_enc_sm121.om \
	seed/ng/sha256.om \
	src/omega_blackwell_codegen.om \
	tests/test_bw_encode_control.om
TR1_BW_ENC_CTL_BIN = $(OUT_DIR)/test_bw_encode_control_om

TR1_SHA256_PAR_SRCS := \
	om/sha256/sha256-om2.om \
	tests/test_sha256_freestanding_parity.om
TR1_SHA256_PAR_BIN = $(OUT_DIR)/test_sha256_freestanding_parity_om

TR1_MUFU_FTZ_SRCS := \
	tests/test_bw_mufu_ftz.om
TR1_MUFU_FTZ_BIN = $(OUT_DIR)/test_bw_mufu_ftz_om

TR1_GENESIS_SRCS := \
	src/omega_genesis.om \
	tests/test_omega_genesis.om
TR1_GENESIS_BIN = $(OUT_DIR)/test_omega_genesis_om

TR1_PROGRAM_IR_SRCS := \
	seed/ng/sha256.om \
	src/omega_program_ir.om \
	tests/test_omega_program_ir.om
TR1_PROGRAM_IR_BIN = $(OUT_DIR)/test_omega_program_ir_om

TR1_CG_FS_SRCS := \
	om/gpu/cg_matmul.om \
	om/gpu/bw_regalloc.om \
	om/encoder/bw_enc_sm121.om \
	seed/ng/sha256.om \
	src/omega_blackwell_codegen.om \
	src/omega_blackwell_matmul.om \
	tests/test_omega_codegen_freestanding.om
TR1_CG_FS_BIN = $(OUT_DIR)/test_omega_codegen_freestanding_om

TR1_Q36_HASH_SRCS := \
	om/gpu/cg_gdn.om \
	om/gpu/cg_attn256.om \
	om/gpu/cg_pattn256.om \
	om/gpu/cg_router.om \
	om/gpu/cg_dec.om \
	om/gpu/bw_regalloc.om \
	seed/ng/sha256.om \
	src/omega_blackwell_codegen_gdn.om \
	src/omega_blackwell_codegen_attn256.om \
	src/omega_blackwell_codegen_pattn256.om \
	src/omega_blackwell_codegen_router.om \
	src/omega_blackwell_codegen_dec.om \
	tests/test_q36_codegen_hash.om
TR1_Q36_HASH_BIN = $(OUT_DIR)/test_q36_codegen_hash_om

$(TR1_BW_ENC_CTL_BIN): $(TR1_BW_ENC_CTL_SRCS) $(TESTS_ROOT_1_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR1_BW_ENC_CTL_SRCS)) | $(TESTS_ROOT_1_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR1_SHA256_PAR_BIN): $(TR1_SHA256_PAR_SRCS) $(TESTS_ROOT_1_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR1_SHA256_PAR_SRCS)) | $(TESTS_ROOT_1_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR1_MUFU_FTZ_BIN): $(TR1_MUFU_FTZ_SRCS) $(TESTS_ROOT_1_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR1_MUFU_FTZ_SRCS)) | $(TESTS_ROOT_1_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR1_GENESIS_BIN): $(TR1_GENESIS_SRCS) $(TESTS_ROOT_1_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR1_GENESIS_SRCS)) | $(TESTS_ROOT_1_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR1_PROGRAM_IR_BIN): $(TR1_PROGRAM_IR_SRCS) $(TESTS_ROOT_1_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR1_PROGRAM_IR_SRCS)) | $(TESTS_ROOT_1_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR1_CG_FS_BIN): $(TR1_CG_FS_SRCS) $(TESTS_ROOT_1_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR1_CG_FS_SRCS)) | $(TESTS_ROOT_1_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(TR1_Q36_HASH_BIN): $(TR1_Q36_HASH_SRCS) $(TESTS_ROOT_1_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(TR1_Q36_HASH_SRCS)) | $(TESTS_ROOT_1_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-tests-root-1-om
test-tests-root-1-om: \
	$(TR1_BW_ENC_CTL_BIN) \
	$(TR1_SHA256_PAR_BIN) \
	$(TR1_MUFU_FTZ_BIN) \
	$(TR1_GENESIS_BIN) \
	$(TR1_PROGRAM_IR_BIN) \
	$(TR1_CG_FS_BIN) \
	$(TR1_Q36_HASH_BIN)
	$(abspath $(TR1_BW_ENC_CTL_BIN))
	$(abspath $(TR1_SHA256_PAR_BIN))
	$(abspath $(TR1_MUFU_FTZ_BIN))
	$(abspath $(TR1_GENESIS_BIN))
	$(abspath $(TR1_PROGRAM_IR_BIN))
	$(abspath $(TR1_CG_FS_BIN))
	$(abspath $(TR1_Q36_HASH_BIN))
