# One-layer stage 3 (omega#446): independent checker2 and signed realization receipts (pure seeded OM-2).
# Files: src/checker2/*.om, tests/checker2/*, spec/one-layer-receipts.md. Picked up by
# `-include mk/*.mk`; not part of `all` or `test`. checker2 is pure seeded OM-2 compiled by
# $(C2_OMC) (seed/out/omc), reusing seed/ng/sha256.om and protocol/omnet/om/{sha512,ed25519}/ +
# protocol/uor-gpu/ed_sign.om with zero C code.
# The untrusted solver c2sat is pure seeded OM-2 (src/checker2/untrusted/c2sat.om, built with C2_OMC).
# Only test_c2_blast_native.c remains minimal C (executable mmap + siglongjmp native ABI cross-check,
# invoking the pure OM-2 checker2 binary with zero checker2 C dependencies).
#   make checker2                build/checker2/checker2
#   make test-checker2-pure      pure OM-2 receipt and LRAT unit tests (no legacy oscc required)
#   make test-checker2           receipt, checker, LRAT, corpus + differential, native blaster cross-check,
#                                and GUARD mutant negative controls
#   make test-checker2-mutants   negative controls only: each GUARD line removed must fail a test
ifndef CHECKER2_MK
CHECKER2_MK := 1
.PHONY: checker2 test-checker2 test-checker2-pure test-checker2-owner-receipt test-checker2-lrat test-checker2-unit test-checker2-mutants test-checker2-differential test-checker2-blast-native
C2_DIR = $(OUT_DIR)/checker2
C2_CFLAGS = -std=gnu11 -Wall -Wextra -Werror -D_GNU_SOURCE -O2
C2_OMC ?= seed/out/omc

C2_HDR_OM = src/checker2/c2_om2_hdr.om
C2_CRYPTO_OM = seed/ng/sha256.om protocol/omnet/om/sha512/sha512.om protocol/omnet/om/ed25519/ed25519.om protocol/uor-gpu/ed_sign.om
C2_CORE_OM = src/checker2/c2_ir.om src/checker2/c2_check.om src/checker2/c2_lrat.om src/checker2/c2_blast.om
# checker identity input (spec section 5): SHA-256 over the checker2 OM-2 sources in a fixed order
C2_ID_SRCS = $(C2_HDR_OM) src/checker2/c2_receipt.om $(C2_CORE_OM) src/checker2/checker2_main.om
C2_SOURCES_SHA256 = $(shell cat $(C2_ID_SRCS) | sha256sum | cut -c1-64)
C2_IRDIR = $(C2_DIR)/differential/ir

checker2: $(C2_DIR)/checker2

$(C2_DIR)/checker2: $(C2_ID_SRCS) $(C2_CRYPTO_OM) $(C2_OMC)
	@mkdir -p $(C2_DIR)
	(cat $(C2_HDR_OM) $(C2_CRYPTO_OM) src/checker2/c2_receipt.om $(C2_CORE_OM); \
	 printf '\ntext c2_sources_sha256 "%s"\n' "$(C2_SOURCES_SHA256)"; \
	 cat src/checker2/checker2_main.om) | $(C2_OMC) > $@.tmp && chmod +x $@.tmp && mv $@.tmp $@

# the same sources built under another checker identity: receipts it issues must be refused by
# checker2 unless that identity is accepted explicitly (lrat.sh, spec section 6 step 6)
$(C2_DIR)/checker2_other: $(C2_ID_SRCS) $(C2_CRYPTO_OM) $(C2_OMC)
	@mkdir -p $(C2_DIR)
	(cat $(C2_HDR_OM) $(C2_CRYPTO_OM) src/checker2/c2_receipt.om $(C2_CORE_OM); \
	 printf '\ntext c2_sources_sha256 "other-checker-build-for-tests"\n'; \
	 cat src/checker2/checker2_main.om) | $(C2_OMC) > $@.tmp && chmod +x $@.tmp && mv $@.tmp $@

$(C2_DIR)/test_c2_receipt: $(C2_HDR_OM) $(C2_CRYPTO_OM) src/checker2/c2_receipt.om tests/checker2/test_c2_receipt.om $(C2_OMC)
	@mkdir -p $(C2_DIR)
	cat $(C2_HDR_OM) $(C2_CRYPTO_OM) src/checker2/c2_receipt.om tests/checker2/test_c2_receipt.om | $(C2_OMC) > $@.tmp && chmod +x $@.tmp && mv $@.tmp $@

$(C2_DIR)/test_c2_lrat: $(C2_HDR_OM) src/checker2/c2_lrat.om tests/checker2/test_c2_lrat.om $(C2_OMC)
	@mkdir -p $(C2_DIR)
	cat $(C2_HDR_OM) src/checker2/c2_lrat.om tests/checker2/test_c2_lrat.om | $(C2_OMC) > $@.tmp && chmod +x $@.tmp && mv $@.tmp $@

$(C2_DIR)/test_c2_ir: $(C2_HDR_OM) src/checker2/c2_ir.om src/checker2/c2_check.om tests/checker2/test_c2_ir.om $(C2_OMC)
	@mkdir -p $(C2_DIR)
	cat $(C2_HDR_OM) src/checker2/c2_ir.om src/checker2/c2_check.om tests/checker2/test_c2_ir.om | $(C2_OMC) > $@.tmp && chmod +x $@.tmp && mv $@.tmp $@

$(C2_DIR)/test_c2_blast: $(C2_HDR_OM) $(C2_CORE_OM) tests/checker2/test_c2_blast.om $(C2_OMC)
	@mkdir -p $(C2_DIR)
	cat $(C2_HDR_OM) $(C2_CORE_OM) tests/checker2/test_c2_blast.om | $(C2_OMC) > $@.tmp && chmod +x $@.tmp && mv $@.tmp $@

# untrusted SAT solver (not in the checker identity; every UNSAT answer is re-checked by c2_lrat),
# pure seeded OM-2 built by the seed omc
$(C2_DIR)/c2sat: src/checker2/untrusted/c2sat.om $(C2_OMC)
	@mkdir -p $(C2_DIR)
	$(C2_OMC) < src/checker2/untrusted/c2sat.om > $@.tmp && chmod +x $@.tmp && mv $@.tmp $@

# producer side, used only by the differential (links the producer library, never checker2)
# NOTE (bb7f2dd68): legacy C compiler src/compiler/ (osc_front.h, oscc) was removed during OM-2 cutover.
C2_PRODUCER_LIB = $(filter-out src/compiler/oscc_main.c,$(wildcard src/compiler/*.c)) src/omega_om_units.c
$(C2_DIR)/osc_emit_ir: tests/checker2/producer/osc_emit_ir.c $(C2_PRODUCER_LIB) $(wildcard src/compiler/*.h)
	@mkdir -p $(C2_DIR)
	$(CC) $(C2_CFLAGS) -Isrc -Isrc/compiler -o $@ tests/checker2/producer/osc_emit_ir.c $(C2_PRODUCER_LIB)

test-checker2-pure: $(C2_DIR)/checker2 $(C2_DIR)/test_c2_receipt $(C2_DIR)/test_c2_lrat
	$(C2_DIR)/checker2 version
	$(C2_DIR)/test_c2_receipt tests/checker2/fixtures
	$(C2_DIR)/test_c2_lrat

test-checker2-differential: $(OUT_DIR)/compiler/oscc $(C2_DIR)/osc_emit_ir $(C2_DIR)/checker2
	sh tests/checker2/differential.sh $(OUT_DIR)/compiler/oscc $(C2_DIR)/osc_emit_ir $(C2_DIR)/checker2 $(C2_DIR)/differential

# 20 bounded programs proved by bit-blasting + c2sat + checker2 LRAT replay, plus negative controls
test-checker2-lrat: $(C2_DIR)/osc_emit_ir $(C2_DIR)/checker2 $(C2_DIR)/checker2_other $(C2_DIR)/c2sat $(C2_DIR)/test_c2_lrat $(C2_DIR)/test_c2_blast test-checker2-differential
	$(C2_DIR)/test_c2_lrat
	sh tests/checker2/lrat.sh $(C2_DIR)/osc_emit_ir $(C2_DIR)/checker2 $(C2_DIR)/c2sat $(C2_DIR)/lrat $(C2_DIR)/checker2_other
	ls -1 $(C2_IRDIR)/*.ir > $(C2_DIR)/corpus.list
	ls -1 $(C2_DIR)/lrat/*.ir > $(C2_DIR)/lrat.list
	$(C2_DIR)/test_c2_blast $(C2_DIR)/corpus.list $(C2_DIR)/lrat.list

# blaster semantics against oscc's compiled AArch64 code, run as a black box (minimal C harness
# kept for executable mmap + siglongjmp; invokes pure OM-2 checker2 prove-cnf with zero C checker deps)
$(C2_DIR)/test_c2_blast_native: tests/checker2/test_c2_blast_native.c
	@mkdir -p $(C2_DIR)
	$(CC) $(C2_CFLAGS) -o $@ tests/checker2/test_c2_blast_native.c

test-checker2-blast-native: $(OUT_DIR)/compiler/oscc $(C2_DIR)/checker2 $(C2_DIR)/test_c2_blast_native
	sh tests/checker2/blast_native.sh $(OUT_DIR)/compiler/oscc $(C2_DIR)/test_c2_blast_native $(C2_DIR)/checker2 $(C2_DIR)/blast_native

test-checker2-unit: $(C2_DIR)/test_c2_receipt $(C2_DIR)/test_c2_ir test-checker2-differential test-checker2-lrat test-checker2-blast-native test-checker2-owner-receipt
	$(C2_DIR)/test_c2_receipt tests/checker2/fixtures
	ls -1 $(C2_IRDIR)/*.ir > $(C2_DIR)/corpus.list
	$(C2_DIR)/test_c2_ir $(C2_DIR)/corpus.list

# positive production case: the receipt signed on Drake's YubiKey (spec section 11; fails PENDING until signed)
test-checker2-owner-receipt: $(C2_DIR)/checker2
	sh tests/checker2/owner_receipt.sh $(C2_DIR)/checker2 tests/checker2/fixtures/owner-receipt $(C2_DIR)/owner-receipt

test-checker2-mutants: test-checker2-differential test-checker2-lrat
	sh tests/checker2/mutants.sh "$(C2_OMC)" "$(C2_DIR)/mutants" "$(C2_IRDIR)" "$(C2_DIR)/lrat"

test-checker2: test-checker2-unit test-checker2-mutants

endif
