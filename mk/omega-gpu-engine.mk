# Omega GPU Engine (docs/numeric/OMEGA_GPU_ENGINE.md). Picked up by
# `-include mk/*.mk`. Host only: opens no device; needs no physics headers except the two A3b1 targets, not
# part of `all` or `test`.
#   test-gpu-engine-compile  header + core compile, enum names, refusals, no-op backend (A2/A3a)
#   test-gpu-engine          the engine core against a fake backend (every state and failure)
#   test-gpu-engine-backend-compile  syntax-checks src/omega_blackwell_engine.c (A3b1): -c only, no link, no device
#   test-gpu-engine-prod-build       production build of build/omegatool at the physics pin: links only, opens no device
#   test-gpu-engine-mutants  removes each protection from src/omega_gpu_engine.c in a scratch
#                            copy; the host test must fail each one (exit nonzero on a survivor)
#   test-gpu-engine-sim      (A3b2) the REAL engine core + Blackwell backend + vector wrapper against a simulated driver
#                            (tests/fake_m16_native.c); host only, no device, no physics C sources
#   test-gpu-engine-backend-mutants  (A3b2) one mutant per protection in the backend and the vector wrapper
#   test-gpu-engine-gb10-compile     (A3b2) compile-only check of tests/test_omega_gpu_engine_gb10.c (Phase B chip test, never run here)
#   gpu-engine-freestanding          (native v1 P07 cut A) the portable GPU files built -ffreestanding with
#                                    OMEGA_GPU_NO_POSIX: no Linux header, no errno, no clock, no libc beyond mem*/str*
#   test-codegen-freestanding        (cut A.2) codegen hosted vs freestanding byte-identical, bounded code buffers,
#                                    and test-sha256-freestanding-parity (hosted vs freestanding SHA-256 binding)
#   test-gpu-engine-freestanding     the engine contract test and the platform contract test linked against
#                                    those freestanding objects (host runner, opens no device)
.PHONY: test-gpu-engine-compile test-gpu-engine test-gpu-engine-mutants test-gpu-engine-backend-compile test-gpu-engine-prod-build test-gpu-engine-sim test-gpu-engine-backend-mutants test-gpu-engine-gb10-compile gpu-engine-freestanding test-gpu-engine-freestanding
test-gpu-engine-compile: $(OUT_DIR)/test_omega_gpu_engine_compile_om
	./$(OUT_DIR)/test_omega_gpu_engine_compile_om

test-gpu-engine: $(OUT_DIR)/test_omega_gpu_engine_om
	./$(OUT_DIR)/test_omega_gpu_engine_om

test-gpu-engine-mutants: seed/out/omc
	sh tools/gpu_engine_mutations.sh

# A3b1: the Blackwell backend includes physics headers (m16_native.h, nvrm.h), so it
# uses the same physics -I paths as the top-level Makefile CFLAGS (Makefile lines 9-14).
GPU_ENGINE_PHYS_INC = -I$(PHYSICS_DIR)/m16 -I$(PHYSICS_DIR)/nvrm \
	-I$(PHYSICS_DIR)/third_party/nvidia-open-580.173.02/src/common/sdk/nvidia/inc \
	-I$(PHYSICS_DIR)/third_party/nvidia-open-580.173.02/kernel-open/common/inc \
	-I$(PHYSICS_DIR)/third_party/nvidia-open-580.173.02/kernel-open/nvidia-uvm \
	-I$(PHYSICS_DIR)/third_party/nvidia-open-580.173.02/src/nvidia/arch/nvalloc/unix/include

build/omega_blackwell_engine_syntax.o: src/omega_blackwell_engine.c src/omega_blackwell_engine.h src/omega_gpu_engine.h
	@mkdir -p build
	gcc -std=gnu11 -O2 -Wall -Wextra -Werror -D_GNU_SOURCE -Isrc $(GPU_ENGINE_PHYS_INC) -c -o $@ src/omega_blackwell_engine.c
test-gpu-engine-backend-compile: build/omega_blackwell_engine_syntax.o

# Links only, opens no device. Uses the real m16_native and nvrm sources at the physics pin.
test-gpu-engine-prod-build:
	$(MAKE) build/omegatool

# A3b2: pure seeded OM-2 Blackwell engine + submit-wrapper host test (zero physics headers, zero GPU).
test-gpu-engine-sim: $(OUT_DIR)/test_omega_blackwell_engine_om
	./$(OUT_DIR)/test_omega_blackwell_engine_om

# One mutant per pure OM-2 backend and vector-wrapper protection; the OM-2 test must fail each one.
test-gpu-engine-backend-mutants: seed/out/omc
	sh tools/gpu_engine_backend_mutations.sh

# Phase B chip test, compile only here. Never run in Phase A.
build/test_omega_gpu_engine_gb10.o: tests/test_omega_gpu_engine_gb10.c src/omega_gpu_engine.h src/omega_blackwell_engine.h src/omega_blackwell_submit.h
	@mkdir -p build
	gcc -std=gnu11 -O2 -Wall -Wextra -Werror -ffp-contract=off -fno-fast-math -pthread -Isrc $(GPU_ENGINE_PHYS_INC) -c -o $@ tests/test_omega_gpu_engine_gb10.c
test-gpu-engine-gb10-compile: build/test_omega_gpu_engine_gb10.o

# Measurement (sc#277): driver allocations and frees made by the REAL session + matmul + attention
# APIs while serving a Qwen3-4B-shaped sequence, against the simulated driver. Host only, no device.
# Prints MEASURE lines; asserts only bookkeeping. Links no physics C sources, only its headers.
GPU_SERVE_ALLOC_SRCS = src/omega_gpu_session.c src/omega_gpu_platform.c src/omega_gpu_platform_linux.c src/omega_gpu_fmt.c src/omega_gpu_matmul_api.c src/omega_gpu_attention_api.c src/omega_gpu_serving.c \
	src/omega_gpu_wait.c src/omega_blackwell_codegen.c src/omega_blackwell_encoder.c src/omega_blackwell_qmd.c \
	src/omega_blackwell_matmul.c src/omega_om_units.c
build/gpu_serving_alloc_count_test: tests/gpu_serving_alloc_count_test.c tests/fake_m16_native.c tests/fake_m16_native.h $(GPU_SERVE_ALLOC_SRCS)
	@mkdir -p build
	gcc -std=gnu11 -O2 -Wall -Wextra -Werror -D_GNU_SOURCE -pthread -ffp-contract=off -Isrc -Itests $(GPU_ENGINE_PHYS_INC) \
		-o $@ tests/gpu_serving_alloc_count_test.c tests/fake_m16_native.c $(GPU_SERVE_ALLOC_SRCS) -lm
.PHONY: test-gpu-serving-alloc
test-gpu-serving-alloc: build/gpu_serving_alloc_count_test
	./build/gpu_serving_alloc_count_test plain
	./build/gpu_serving_alloc_count_test reserve
	./build/gpu_serving_alloc_count_test bounds
	./build/gpu_serving_alloc_count_test bounds-block
	./build/gpu_serving_alloc_count_test rollback
	./build/gpu_serving_alloc_count_test sweep
	./build/gpu_serving_alloc_count_test pin
	./build/gpu_serving_alloc_count_test seal-bare
	./build/gpu_serving_alloc_count_test update
	@if ./build/gpu_serving_alloc_count_test sweep-skip >build/gpu_serving_alloc_count_sweep_skip.log 2>&1; then echo "RED RUN PASSED: zero allocations over the row sweep do not need prepare + seal"; exit 1; fi
	@if [ "$$(grep -c "^FAIL" build/gpu_serving_alloc_count_sweep_skip.log)" -lt 1 ]; then echo "sweep-skip exited nonzero without a FAIL check (crash, not the red assertion)"; exit 1; fi
	@grep -E "^MEASURE sweep" build/gpu_serving_alloc_count_sweep_skip.log | sed "s/^/sweep-skip (control): /"
	@if ./build/gpu_serving_alloc_count_test reserve-skip >build/gpu_serving_alloc_count_skip.log 2>&1; then echo "RED RUN PASSED: the zero-allocation assertion does not need the reservation call"; exit 1; fi
	@if [ "$$(grep -c "^FAIL" build/gpu_serving_alloc_count_skip.log)" -lt 1 ]; then echo "reserve-skip exited nonzero without a FAIL check (crash, not the red assertion)"; exit 1; fi
	@echo "reserve-skip (no reservation call): fails as required ($$(grep -c "^FAIL" build/gpu_serving_alloc_count_skip.log) failing checks)"

# native v1 P07 cut A (aienos#286 cut A, aien-architecture#190): the freestanding link target.
# Each file below is compiled with no hosted headers available (-ffreestanding, -fno-builtin,
# OMEGA_GPU_NO_POSIX) and the partial link of all of them may leave only the mem*/str* symbols
# undefined. Any other undefined symbol (errno, clock_gettime, printf, malloc, pthread_*, nvrm_*,
# m16_*) fails the target. This proves the first-compute PATH links without Linux headers or
# runtime symbols; it proves nothing about device ownership (NOT_RUN until cut B runs on the Spark).
GPU_FS_DIR = build/gpu_fs
GPU_FS_CFLAGS = -std=gnu11 -O2 -Wall -Wextra -Werror -ffreestanding -fno-builtin -fno-stack-protector \
	-U_FORTIFY_SOURCE -DOMEGA_GPU_NO_POSIX -DOMEGA_NUMERIC_CPU_ONLY -Isrc
# P07 cut C (session part): the persistent session, the matmul and attention APIs, the serving reservation and the
# bounded wait join the link. Their machine comes from an installed OmegaGpuPlatform; the Linux reference
# (src/omega_gpu_platform_linux.c) is deliberately NOT in this list. Still outside it: the elementwise API, the
# numeric launchers, the vector executor, the resident runtime (docs/numeric/OMEGA_GPU_NATIVE_BOUNDARY.md).
# The Omega SHA-256 joins as src/omega_om_units_fs.c (om/units.sh, the bridge's freestanding outputs freest and
# fapic): the hosted binding src/omega_om_units.c needs pthread TLS, mmap/mprotect/munmap and abort.
GPU_FS_SRCS = src/omega_gpu_engine.c src/omega_gpu_platform.c src/omega_blackwell_encoder.c src/omega_blackwell_codegen.c \
	src/omega_blackwell_matmul.c src/omega_blackwell_qmd.c src/omega_blackwell_realize.c src/omega_om_units_fs.c \
	src/omega_gpu_session.c src/omega_gpu_fmt.c src/omega_gpu_matmul_api.c src/omega_gpu_attention_api.c \
	src/omega_gpu_serving.c src/omega_gpu_wait.c
GPU_FS_HDRS = src/omega_gpu_engine.h src/omega_gpu_platform.h src/omega_blackwell_codegen.h src/omega_blackwell_matmul.h \
	src/omega_gpu_session.h src/omega_gpu_fmt.h src/omega_gpu_matmul_api.h src/omega_gpu_attention_api.h \
	src/omega_gpu_serving.h src/omega_gpu_wait.h
GPU_FS_OBJS = $(patsubst src/%.c,$(GPU_FS_DIR)/%.o,$(GPU_FS_SRCS))
GPU_FS_LINK = $(GPU_FS_DIR)/omega_gpu_freestanding.o
GPU_FS_ALLOWED = memcpy|memmove|memset|memcmp|strlen|strcmp

$(GPU_FS_DIR)/%.o: src/%.c $(GPU_FS_HDRS)
	@mkdir -p $(GPU_FS_DIR)
	gcc $(GPU_FS_CFLAGS) -c -o $@ $<

$(GPU_FS_LINK): $(GPU_FS_OBJS)
	gcc -r -nostdlib -o $@ $(GPU_FS_OBJS)
	@bad=$$(nm -u $@ | awk '{print $$NF}' | grep -Ev '^(_GLOBAL_OFFSET_TABLE_|($(GPU_FS_ALLOWED)))$$' || true); \
	if [ -n "$$bad" ]; then echo "freestanding GPU link still needs: $$bad"; rm -f $@; exit 1; fi
	@echo "freestanding GPU link ($(words $(GPU_FS_SRCS)) files): only $$(nm -u $@ | awk '{print $$NF}' | grep -Ev '^_GLOBAL_OFFSET_TABLE_$$' | sort -u | tr '\n' ' ')undefined"
gpu-engine-freestanding: $(GPU_FS_LINK)

test-gpu-engine-freestanding: $(GPU_FS_LINK) $(OUT_DIR)/test_omega_gpu_engine_om $(OUT_DIR)/test_omega_gpu_platform_om
	./$(OUT_DIR)/test_omega_gpu_engine_om
	./$(OUT_DIR)/test_omega_gpu_platform_om

# native v1 P07 cut A.2 (aienos#286): code generation joins the freestanding link above with a caller-owned
# code buffer (omega_blackwell_kernel_encode_into, no allocator). The same test source is built hosted (the
# allocating generators) and freestanding (the *_prog generators into a caller buffer); their instruction
# stream dumps of every fixture must be byte-identical (cmp). The freestanding run then checks the bounded
# buffer contract, the golden-word fixture verifiers on the freestanding object and the bf16 rounding path on
# all 2^32 inputs. The allowlist control links a malloc caller into the freestanding object and requires the
# nm -u check to refuse it (a check that can never fail proves nothing).
.PHONY: test-codegen-freestanding test-gpu-fs-allowlist-control
CODEGEN_FS_TEST_DEPS = tests/test_omega_codegen_freestanding.c src/omega_blackwell_codegen.h src/omega_blackwell_matmul.h
# The hosted side encodes through the .om encoder (om/encoder/bw_enc_sm121.om via src/omega_om_units.c), the
# freestanding side through the migration-pending C encoder, so the cmp below is also an .om-vs-C differential.
build/test_codegen_hosted: $(CODEGEN_FS_TEST_DEPS) src/omega_blackwell_codegen.c src/omega_blackwell_matmul.c src/omega_om_units.c \
		src/omega_native.h
	@mkdir -p build
	gcc -std=gnu11 -O2 -Wall -Wextra -Werror -Isrc -o $@ tests/test_omega_codegen_freestanding.c \
		src/omega_blackwell_codegen.c src/omega_blackwell_matmul.c src/omega_om_units.c
build/test_codegen_freestanding: $(CODEGEN_FS_TEST_DEPS) $(GPU_FS_LINK)
	@mkdir -p build
	gcc -std=gnu11 -O2 -Wall -Wextra -Werror -Isrc -DOMEGA_GPU_NO_POSIX -o $@ tests/test_omega_codegen_freestanding.c \
		$(GPU_FS_DIR)/omega_blackwell_codegen.o $(GPU_FS_DIR)/omega_blackwell_matmul.o $(GPU_FS_DIR)/omega_om_units_fs.o

# The freestanding SHA-256 binding against the hosted one: tests/test_sha256_freestanding_parity.c built over
# src/omega_om_units.c (hosted) and over the GPU_FS_CFLAGS object of src/omega_om_units_fs.c must print the same
# digests (the FIPS 180-2 vectors; lengths 0..1100, 4096, 65536 and 1048583 of a fixed-seed stream one-shot and
# split), and the FIPS digests must be the published ones. Controls: the hosted codegen test hashes through the
# Omega binding (omega2_sha256_*), and a copy of the freestanding binding whose machine code loads round constant
# K[0] as 0x428a2f99 (movz x1,#0x2f98 -> #0x2f99) must FAIL the comparison.
.PHONY: test-sha256-freestanding-parity
SHA256_FS_PARITY_DEPS = tests/test_sha256_freestanding_parity.c src/sha256.h src/omega_api_decl.h src/omega_native.h
SHA256_FS_RED = build/sha256_parity_red
build/test_sha256_parity_hosted: $(SHA256_FS_PARITY_DEPS) src/omega_om_units.c
	@mkdir -p build
	gcc -std=gnu11 -O2 -Wall -Wextra -Werror -D_GNU_SOURCE -Isrc -o $@ tests/test_sha256_freestanding_parity.c src/omega_om_units.c -pthread
build/test_sha256_parity_freestanding: $(SHA256_FS_PARITY_DEPS) $(GPU_FS_DIR)/omega_om_units_fs.o
	@mkdir -p build
	gcc -std=gnu11 -O2 -Wall -Wextra -Werror -Isrc -o $@ tests/test_sha256_freestanding_parity.c $(GPU_FS_DIR)/omega_om_units_fs.o
test-sha256-freestanding-parity: build/test_sha256_parity_hosted build/test_sha256_parity_freestanding build/test_codegen_hosted
	./build/test_sha256_parity_hosted > build/sha256_parity_hosted.txt
	./build/test_sha256_parity_freestanding > build/sha256_parity_freestanding.txt
	cmp build/sha256_parity_hosted.txt build/sha256_parity_freestanding.txt
	@printf 'fips %s\n' '0 e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' \
	  '1 ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' \
	  '2 248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1' \
	  '3 cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0' > build/sha256_parity_fips.txt
	@grep '^fips ' build/sha256_parity_freestanding.txt | cmp -s - build/sha256_parity_fips.txt \
	  || { echo "sha256 freestanding parity: FIPS digests wrong"; exit 1; }
	@[ "$$(grep -c '^len ' build/sha256_parity_freestanding.txt)" = 1104 ] || { echo "sha256 freestanding parity: expected 1104 lengths"; exit 1; }
	@echo "sha256 freestanding parity: hosted and freestanding bindings agree on 4 FIPS vectors and 1104 lengths (0..1100, 4096, 65536, 1048583)"
	@n=$$(nm build/test_codegen_hosted | grep -c ' T omega2_sha256_'); [ "$$n" -ge 4 ] || \
		{ echo "FAIL: the hosted codegen test does not hash through the Omega binding"; exit 1; }; \
	echo "control: hosted codegen test links $$n omega2_sha256_* functions"
	@mkdir -p $(SHA256_FS_RED)
	sed 's/0x01,0xf3,0x85,0xd2/0x21,0xf3,0x85,0xd2/' src/omega_om_units_fs.c > $(SHA256_FS_RED)/red.c
	@! cmp -s $(SHA256_FS_RED)/red.c src/omega_om_units_fs.c || { echo "RED MUTANT BROKEN: sed changed nothing"; exit 1; }
	gcc $(GPU_FS_CFLAGS) -c -o $(SHA256_FS_RED)/red.o $(SHA256_FS_RED)/red.c
	gcc -std=gnu11 -O2 -Wall -Wextra -Werror -Isrc -o $(SHA256_FS_RED)/parity_red tests/test_sha256_freestanding_parity.c \
		$(SHA256_FS_RED)/red.o
	@./$(SHA256_FS_RED)/parity_red > $(SHA256_FS_RED)/red.txt || true; \
	if cmp -s $(SHA256_FS_RED)/red.txt build/sha256_parity_hosted.txt; then echo "RED CHECK BROKEN: a wrong round constant passed"; exit 1; \
	else echo "red check: K[0] changed in the freestanding machine code FAILS the comparison ($$(cmp $(SHA256_FS_RED)/red.txt build/sha256_parity_hosted.txt | head -1))"; fi
test-codegen-freestanding: build/test_codegen_hosted build/test_codegen_freestanding test-gpu-fs-allowlist-control \
		test-sha256-freestanding-parity
	./build/test_codegen_hosted --dump > build/codegen_dump_hosted.txt
	./build/test_codegen_freestanding --dump > build/codegen_dump_freestanding.txt
	cmp build/codegen_dump_hosted.txt build/codegen_dump_freestanding.txt
	@echo "codegen dumps byte-identical: $$(grep -c '^fixture ' build/codegen_dump_hosted.txt) fixtures, $$(grep -v -E '^(fixture|digest) ' build/codegen_dump_hosted.txt | tr -d '\n' | wc -c | awk '{print $$1/2}') code bytes"
	./build/test_codegen_freestanding

test-gpu-fs-allowlist-control: $(GPU_FS_LINK)
	@mkdir -p $(GPU_FS_DIR)/control
	printf 'void *malloc(unsigned long);\nvoid *omega_gpu_fs_control(void) { return malloc(16); }\n' > $(GPU_FS_DIR)/control/canary.c
	gcc $(GPU_FS_CFLAGS) -c -o $(GPU_FS_DIR)/control/canary.o $(GPU_FS_DIR)/control/canary.c
	gcc -r -nostdlib -o $(GPU_FS_DIR)/control/with_canary.o $(GPU_FS_OBJS) $(GPU_FS_DIR)/control/canary.o
	@bad=$$(nm -u $(GPU_FS_DIR)/control/with_canary.o | awk '{print $$NF}' | grep -Ev '^(_GLOBAL_OFFSET_TABLE_|($(GPU_FS_ALLOWED)))$$' || true); \
	if [ "$$bad" != "malloc" ]; then echo "allowlist control: expected exactly malloc refused, got '$$bad'"; exit 1; fi; \
	echo "allowlist control: a malloc caller is refused by the nm -u check (as required)"

# native v1 P07 cut C, session part (aienos#286): pure seeded OM-2 session over omega_gpu_platform.om.
#  - tr4_test_omega_gpu_session_platform_om drives src/omega_gpu_session.om in mock platform mode.
#  - tr4_test_omega_gpu_platform_linux_om drives src/omega_gpu_platform_linux.om + cmdlist in mock mode.
#  - test-gpu-session-mutants breaks each of the 11 rules in a scratch copy of src/omega_gpu_session.om
#    and requires the OM-2 session test to FAIL every one.
.PHONY: test-gpu-session-platform test-gpu-session-mutants
test-gpu-session-platform: $(OUT_DIR)/tr4_test_omega_gpu_session_platform_om $(OUT_DIR)/tr4_test_omega_gpu_platform_linux_om test-gpu-session-mutants
	./$(OUT_DIR)/tr4_test_omega_gpu_session_platform_om
	./$(OUT_DIR)/tr4_test_omega_gpu_platform_linux_om

GPU_SESSION_MUT_DIR = $(OUT_DIR)/gpu_session_mut
GPU_SESSION_OM_PRE = gpu/nvidia/native/nvrm/context.om om/gpu/bw_qmd.om om/gpu/bw_vecadd.om \
	src/omega_gpu_code_alloc.om src/omega_gpu_platform.om src/omega_gpu_platform_linux.om \
	src/omega_gpu_mem_cached.om src/omega_gpu_engine.om src/omega_blackwell_engine.om
GPU_SESSION_OM_POST = src/omega_gpu_fmt.om tests/test_omega_gpu_session_platform.om
test-gpu-session-mutants: seed/out/omc src/omega_gpu_session.om $(GPU_SESSION_OM_PRE) $(GPU_SESSION_OM_POST)
	@mkdir -p $(GPU_SESSION_MUT_DIR)
	@set -e; killed=0; \
	smut() { name=$$1; script=$$2; \
	  sed -e "$$script" src/omega_gpu_session.om > $(GPU_SESSION_MUT_DIR)/$$name.om; \
	  if cmp -s src/omega_gpu_session.om $(GPU_SESSION_MUT_DIR)/$$name.om; then echo "mutant $$name: pattern not found"; exit 1; fi; \
	  (printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(GPU_SESSION_OM_PRE) $(GPU_SESSION_MUT_DIR)/$$name.om $(GPU_SESSION_OM_POST)) \
	    | seed/out/omc > $(GPU_SESSION_MUT_DIR)/$$name.tmp && chmod +x $(GPU_SESSION_MUT_DIR)/$$name.tmp && mv -f $(GPU_SESSION_MUT_DIR)/$$name.tmp $(GPU_SESSION_MUT_DIR)/$$name; \
	  if ./$(GPU_SESSION_MUT_DIR)/$$name > $(GPU_SESSION_MUT_DIR)/$$name.log 2>&1; then echo "mutant $$name SURVIVED"; exit 1; fi; \
	  echo "mutant $$name killed: $$(cat $(GPU_SESSION_MUT_DIR)/$$name.log)"; killed=$$((killed+1)); }; \
	smut release-when-latched '/^fn ogps_free /,/^end$$/ s|if ne get ogps_blocked 0 0|if false|'; \
	smut ignore-cancel 's|if ogps_take_cancel|if false|'; \
	smut no-latch-on-timeout 's|ogps_latch_uncertain ogps_e_timeout|ogps_set_error ogps_e_timeout|'; \
	smut stale-not-counted '/^fn ogps_free /,/^end$$/ s|put ogps_astats 4 add get ogps_astats 4 1|put ogps_astats 4 get ogps_astats 4|g'; \
	smut marker-not-polled '/^fn ogps_open /,/^end$$/ s|OGPS_RIGHTS_MARKER|OGPS_RIGHTS_DATA|'; \
	smut close-while-latched '/^fn ogps_close /,/^end$$/ { s|if and ne get ogps_open_flag 0 0 and eq get ogps_blocked 0 0 ne get ogps_plat_set 0 0|if and ne get ogps_open_flag 0 0 ne get ogps_plat_set 0 0|; s|if eq get ogps_blocked 0 0|if true|; }'; \
	smut recover-keeps-latch '/^fn ogps_recover /,/^end$$/ s|put ogps_blocked 0 0|put ogps_blocked 0 get ogps_blocked 0|'; \
	smut recover-without-close '/^fn ogps_recover /,/^end$$/ s|prc = ogpl_device_close get ogps_dev 0 get ogps_dev 1|prc = OGP_OK|'; \
	smut recover-when-not-latched '/^fn ogps_recover /,/^end$$/ s|latched = or ne get ogps_blocked 0 0 ne get ogps_mod_latched 0 0|latched = true|'; \
	smut recover-ignores-teardown-fault '/^fn ogps_recover /,/^end$$/ { s|if ne get ogps_mock_fail_close 0 0|if false|; s|if ne prc OGP_OK|if false|; }'; \
	smut recover-ignores-module-latch '/^fn ogps_recover /,/^end$$/ s|latched = or ne get ogps_blocked 0 0 ne get ogps_mod_latched 0 0|latched = ne get ogps_blocked 0 0|'; \
	echo "test-gpu-session-mutants: $$killed of 11 mutants killed"
