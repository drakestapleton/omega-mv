#!/bin/sh
# bridge/abi-v2-spec/gate_abi_v2.sh:
# RM7 Formal ABI v2 & Multi-Language Trap/Contract + FR-7 Shared-Object Qualification Gate.
# Runs on Linux AArch64 (DGX Spark) using pinned seed/out/omc (zero network, zero telemetry).
set -eu

export DO_NOT_TRACK=1
export DISABLE_TELEMETRY=1
export DISABLE_ERROR_REPORTING=1
export GOPROXY=off
export GOSUMDB=off

# Discover Spark-installed toolchains without relying on interactive shell profiles.
for d in "$HOME/.cargo/bin" "$HOME/.local/opt/zig-linux-aarch64-0.13.0" "$HOME/.local/go1.26.8/go/bin" "$HOME/.local/bin"; do
    if [ -d "$d" ]; then
        PATH="$d:$PATH"
    fi
done
export PATH

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
OMC_PIN_FILE="${OMEGA_OMC_PIN_FILE:-$REPO_ROOT/seed/out/omc.sha256}"
[ -r "$OMC_PIN_FILE" ] || { echo "FAIL: missing omc pin file at $OMC_PIN_FILE" >&2; exit 2; }
OMC_PIN=$(awk 'NR==1{print $1}' "$OMC_PIN_FILE")
OMC="${OMEGA_OMC:-$REPO_ROOT/seed/out/omc}"
WORK="${WORK_DIR:-/tmp/om_sw_rm7}"

[ -x "$OMC" ] || { echo "FAIL: missing executable omc at $OMC" >&2; exit 2; }
GOT_OMC_PIN=$(sha256sum "$OMC" | awk '{print $1}')
if [ "$GOT_OMC_PIN" != "$OMC_PIN" ]; then
    echo "FAIL: omc pin mismatch: got=$GOT_OMC_PIN expected=$OMC_PIN" >&2
    exit 69
fi

rm -rf "$WORK"
mkdir -p "$WORK/gen" "$WORK/c" "$WORK/cpp" \
    "$WORK/rust/abi_v2_sys/src" "$WORK/rust/abi_v2_caller/src" \
    "$WORK/zig" "$WORK/py" "$WORK/go/omeganative" \
    "$WORK/shlib" "$WORK/ver" "$WORK/neg"
RES="$WORK/results.tsv"
printf '# CASE_ID\tCATEGORY\tSTATUS\tDETAIL\n' > "$RES"

rec() {
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$RES"
}

echo "[rm7] work=$WORK omc=$OMC pin=$GOT_OMC_PIN"

# 1. Deterministic 2x compilation of native.om, abi_v2_qual.om (function-mode), shlib.om, gate_abi_v2.om
"$OMC" < "$REPO_ROOT/bridge/omega-bridge/src/native.om" > "$WORK/native.1"
"$OMC" < "$REPO_ROOT/bridge/omega-bridge/src/native.om" > "$WORK/native.2"
cmp -s "$WORK/native.1" "$WORK/native.2" || { echo "FAIL: native.om nondeterministic" >&2; exit 1; }
mv "$WORK/native.1" "$WORK/native"
rm -f "$WORK/native.2"
chmod 755 "$WORK/native"

"$OMC" < "$SCRIPT_DIR/abi_v2_qual.om" > "$WORK/abi_v2_qual.bin.1"
"$OMC" < "$SCRIPT_DIR/abi_v2_qual.om" > "$WORK/abi_v2_qual.bin.2"
cmp -s "$WORK/abi_v2_qual.bin.1" "$WORK/abi_v2_qual.bin.2" || { echo "FAIL: abi_v2_qual.om nondeterministic" >&2; exit 1; }
mv "$WORK/abi_v2_qual.bin.1" "$WORK/abi_v2_qual.bin"
rm -f "$WORK/abi_v2_qual.bin.2"

"$OMC" < "$REPO_ROOT/bridge/shlib/shlib.om" > "$WORK/shlib_bin.1"
"$OMC" < "$REPO_ROOT/bridge/shlib/shlib.om" > "$WORK/shlib_bin.2"
cmp -s "$WORK/shlib_bin.1" "$WORK/shlib_bin.2" || { echo "FAIL: shlib.om nondeterministic" >&2; exit 1; }
mv "$WORK/shlib_bin.1" "$WORK/shlib_bin"
rm -f "$WORK/shlib_bin.2"
chmod 755 "$WORK/shlib_bin"

"$OMC" < "$SCRIPT_DIR/gate_abi_v2.om" > "$WORK/gate_abi_v2.1"
"$OMC" < "$SCRIPT_DIR/gate_abi_v2.om" > "$WORK/gate_abi_v2.2"
cmp -s "$WORK/gate_abi_v2.1" "$WORK/gate_abi_v2.2" || { echo "FAIL: gate_abi_v2.om nondeterministic" >&2; exit 1; }
mv "$WORK/gate_abi_v2.1" "$WORK/gate_abi_v2"
rm -f "$WORK/gate_abi_v2.2"
chmod 755 "$WORK/gate_abi_v2"

QUAL_BIN_SHA=$(sha256sum "$WORK/abi_v2_qual.bin" | awk '{print $1}')
GATE_BIN_SHA=$(sha256sum "$WORK/gate_abi_v2" | awk '{print $1}')
rec build_2x_determinism core PASS "qual_bin=${QUAL_BIN_SHA} gate_bin=${GATE_BIN_SHA}"
echo "[rm7] 2x deterministic builds PASS (qual=$QUAL_BIN_SHA gate=$GATE_BIN_SHA)"

# 2. Frame abi_v2_qual.om + machine code into native.om ABI v2 wire format and emit all bindings
CODE_LEN=$(wc -c < "$WORK/abi_v2_qual.bin" | tr -d ' ')
CODE_LEN_8=$(printf '%08d' "$CODE_LEN")
{
    cat "$SCRIPT_DIR/abi_v2_qual.om"
    printf '\000%s' "$CODE_LEN_8"
    cat "$WORK/abi_v2_qual.bin"
    printf 'omega-unit abi_v2_qual %s\n' "$OMC_PIN"
} > "$WORK/unit.frame"

for mode in c h api apih apic python rust zig go ident; do
    "$WORK/native" "$mode" < "$WORK/unit.frame" > "$WORK/gen/out.$mode"
done
mv "$WORK/gen/out.c"      "$WORK/gen/omega_native.c"
mv "$WORK/gen/out.h"      "$WORK/gen/omega_native.h"
mv "$WORK/gen/out.api"    "$WORK/gen/omega_api.h"
mv "$WORK/gen/out.apih"   "$WORK/gen/omega_api_decl.h"
mv "$WORK/gen/out.apic"   "$WORK/gen/omega_api_impl.c"
mv "$WORK/gen/out.python" "$WORK/gen/omega_native.py"
mv "$WORK/gen/out.rust"   "$WORK/gen/omega_native.rs"
mv "$WORK/gen/out.zig"    "$WORK/gen/omega_native.zig"
mv "$WORK/gen/out.go"     "$WORK/gen/omega_native.go"
IDENT_LINE=$(cat "$WORK/gen/out.ident")
echo "[rm7] ident=$IDENT_LINE"

# 3. Compile native C libraries: static, shared, BTI static, and FR-7 GNU version-scripted .so
gcc -std=c11 -O2 -Wall -Wextra -Werror -fPIC -c "$WORK/gen/omega_native.c" -o "$WORK/gen/omega_native.o"
ar rcs "$WORK/gen/libomega_native.a" "$WORK/gen/omega_native.o"
gcc -std=c11 -O2 -Wall -Wextra -Werror -shared -fPIC "$WORK/gen/omega_native.o" -o "$WORK/gen/libomega_native.so" -lpthread

gcc -std=c11 -O2 -Wall -Wextra -Werror -mbranch-protection=standard -fPIC -c "$WORK/gen/omega_native.c" -o "$WORK/gen/omega_native_bti.o"
ar rcs "$WORK/gen/libomega_native_bti.a" "$WORK/gen/omega_native_bti.o"

cat > "$WORK/ver/omega2.ver" <<'EOF'
OMEGA_ABI_2.0 {
    global:
        omega2_*;
    local:
        *;
};
EOF
gcc -std=c11 -O2 -Wall -Wextra -Werror -mbranch-protection=standard -shared -fPIC \
    -Wl,-soname,libomega2_qual.so.2 -Wl,--version-script="$WORK/ver/omega2.ver" \
    "$WORK/gen/omega_native_bti.o" -o "$WORK/ver/libomega2_qual.so.2" -lpthread

# 4. C11 + C-BTI exhaustive ABI v2 qualification (all param kinds, statuses 0, 1..14, 32, live SIGUSR1 33, out atomicity)
cat > "$WORK/c/qual_c.c" <<'EOF'
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <inttypes.h>
#include <limits.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "omega_native.h"

static const uint64_t SENTINEL = 0xDEADBEEFCAFEBABEULL;

static volatile sig_atomic_t g_reentry_seen = 0;
static volatile sig_atomic_t g_reentry_status = -1;
static volatile uint64_t g_sig_result = 0xDEADBEEFCAFEBABEULL;
static volatile sig_atomic_t g_spin_started = 0;
static volatile sig_atomic_t g_spin_done = 0;
static pthread_t g_main_tid;

static void on_sigusr1(int sig)
{
    (void)sig;
    uint64_t r = SENTINEL;
    uint32_t st = omega2_q_add(&r, 3u, 4u);
    g_sig_result = r;
    g_reentry_status = (sig_atomic_t)st;
    g_reentry_seen = 1;
}

static void *reentry_sender(void *arg)
{
    (void)arg;
    struct timespec ts = { 0, 5000000L }; /* 5 ms */
    while (!g_spin_started)
        nanosleep(&ts, NULL);
    nanosleep(&ts, NULL);
    for (int i = 0; i < 100 && !g_reentry_seen && !g_spin_done; i++) {
        pthread_kill(g_main_tid, SIGUSR1);
        nanosleep(&ts, NULL);
    }
    return NULL;
}

#define CHECK(cond) do { if (!(cond)) { fprintf(stderr, "FAIL at line %d: %s\n", __LINE__, #cond); return 1; } } while (0)

int main(int argc, char **argv)
{
    const char *tsv_path = (argc > 1) ? argv[1] : NULL;
    FILE *tf = tsv_path ? fopen(tsv_path, "a") : NULL;
    uint64_t r = 0;
    uint32_t st = 0;

    /* Identity check */
    const char *id = omega2_ident_abi_v2_qual();
    CHECK(id != NULL);
    CHECK(strcmp(id, OMEGA2_IDENT_abi_v2_qual) == 0);
    CHECK(strstr(id, "abi=2 profile=OM-2") != NULL);

    /* Status 0 + all parameter classes + all 8 element types */
    r = SENTINEL;
    CHECK(omega2_q_add(&r, 19u, 23u) == OMEGA_OK && r == 42u);

    r = SENTINEL;
    CHECK(omega2_q_sub_signed(&r, (uint64_t)(int64_t)-10, (uint64_t)(int64_t)5) == OMEGA_OK);
    CHECK((int64_t)r == -15);

    /* Unsized view ulong * incl. empty n == 0 with NULL pointer */
    r = SENTINEL;
    CHECK(omega2_q_sum_view(&r, NULL, 0u) == OMEGA_OK && r == 0u);
    uint64_t u64v[4] = { 10u, 20u, 30u, 40u };
    r = SENTINEL;
    CHECK(omega2_q_sum_view(&r, u64v, 4u) == OMEGA_OK && r == 100u);

    /* Unsized edit uint * + scalar */
    uint32_t u32v[3] = { 2u, 5u, 7u };
    r = SENTINEL;
    CHECK(omega2_q_scale_edit(&r, u32v, 3u, 3u) == OMEGA_OK && r == 42u);
    CHECK(u32v[0] == 6u && u32v[1] == 15u && u32v[2] == 21u);

    /* Sized view uchar 8 + sized edit uchar 8 */
    uint8_t s8[8] = { 1, 2, 3, 4, 5, 6, 7, 8 };
    uint8_t d8[8] = { 0 };
    r = SENTINEL;
    CHECK(omega2_q_sized_copy(&r, s8, 8u, d8, 8u) == OMEGA_OK && r == 36u);
    for (int i = 0; i < 8; i++)
        CHECK(d8[i] == (uint8_t)(s8[i] ^ 90u));

    /* All remaining narrow & signed element types: ushort *, short 4, byte 4, int 4 */
    uint16_t a16[3] = { 100u, 200u, 300u };
    int16_t b16[4] = { -10, 20, -30, 40 };
    int8_t c8[4] = { -1, 2, -3, 4 };
    int32_t d32[4] = { 1000, -500, 250, -50 };
    r = SENTINEL;
    CHECK(omega2_q_narrow_types(&r, a16, 3u, b16, 4u, c8, 4u, d32, 4u) == OMEGA_OK);
    CHECK((int64_t)r == 1322);
    CHECK(b16[0] == -9 && b16[1] == 21 && b16[2] == -29 && b16[3] == 41);

    /* Layout edit qhdr (24 bytes) + void return (*result must become 0) */
    uint8_t hdr[24];
    memset(hdr, 0, sizeof hdr);
    hdr[0] = 5u; /* tag = 5 */
    for (int i = 0; i < 8; i++)
        hdr[16 + i] = (uint8_t)(0x40 + i);
    uint8_t msg[3] = { 10u, 20u, 30u };
    r = SENTINEL;
    CHECK(omega2_q_layout_edit(&r, hdr, msg, 3u) == OMEGA_OK && r == 0u);
    uint32_t got_tag = 0;
    uint64_t got_val = 0;
    memcpy(&got_tag, hdr, 4);
    memcpy(&got_val, hdr + 8, 8);
    CHECK(got_tag == 65u && got_val == 3u);

    /* Layout view qhdr + out uchar 16 */
    uint8_t out16[16];
    memset(out16, 0xEE, sizeof out16);
    r = SENTINEL;
    CHECK(omega2_q_layout_out(&r, hdr, out16) == OMEGA_OK && r == 3u);
    for (int i = 0; i < 8; i++)
        CHECK(out16[i] == (uint8_t)(0x40 + i));
    CHECK(out16[8] == 65u && out16[9] == 0u && out16[10] == 0u && out16[11] == 0u);
    CHECK(out16[12] == 0xA5u && out16[13] == 0x5Au && out16[14] == 0u && out16[15] == 0u);

    /* Out overlapping view MUST be allowed */
    uint8_t ov[8] = { 0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80 };
    r = SENTINEL;
    CHECK(omega2_q_out_overlap_view(&r, ov, 8u, ov) == OMEGA_OK && r == 0x240u);
    CHECK(ov[0] == 0xEFu && ov[7] == 0x7Fu);

    /* Two disjoint out buffers (void return -> *result == 0) */
    uint8_t oa[8] = { 0 }, ob[8] = { 0 };
    r = SENTINEL;
    CHECK(omega2_q_two_out(&r, oa, ob) == OMEGA_OK && r == 0u);
    CHECK(oa[0] == 1u && oa[7] == 8u && ob[0] == 17u && ob[7] == 24u);

    if (tf) {
        fprintf(tf, "c_abi_v2_params\tlang\tPASS\tall_22_exports_and_8_element_types\n");
        fprintf(tf, "status_0_ok\tstatus\tPASS\tstatus=0_result_written\n");
    }

    /* Traps 1..14 (every single one must return exact status and leave *result untouched) */
    r = SENTINEL;
    st = omega2_q_trap1_ovf(&r, (uint64_t)INT64_MAX, 1u);
    CHECK(st == 1u && r == SENTINEL);
    if (tf) fprintf(tf, "status_1_ovf\tstatus\tPASS\ttrap=1_signed_overflow\n");

    r = SENTINEL;
    st = omega2_q_trap2_div0(&r, 42u, 0u);
    CHECK(st == 2u && r == SENTINEL);
    if (tf) fprintf(tf, "status_2_div0\tstatus\tPASS\ttrap=2_div_by_zero\n");

    r = SENTINEL;
    st = omega2_q_trap3_bounds(&r, s8, 8u, 8u);
    CHECK(st == 3u && r == SENTINEL);
    if (tf) fprintf(tf, "status_3_bounds\tstatus\tPASS\ttrap=3_index_out_of_bounds\n");

    r = SENTINEL;
    st = omega2_q_trap4_loop(&r, 12u);
    CHECK(st == 4u && r == SENTINEL);
    if (tf) fprintf(tf, "status_4_loop\tstatus\tPASS\ttrap=4_loop_bound_exceeded\n");

    r = SENTINEL;
    st = omega2_q_trap5_cast(&r, 300u);
    CHECK(st == 5u && r == SENTINEL);
    if (tf) fprintf(tf, "status_5_cast\tstatus\tPASS\ttrap=5_narrowing_cast\n");

    r = SENTINEL;
    st = omega2_q_trap_code(&r, 6u);
    CHECK(st == 6u && r == SENTINEL);
    if (tf) fprintf(tf, "status_6_oom\tstatus\tPASS\ttrap=6_oom_stack\n");

    r = SENTINEL;
    st = omega2_q_trap7_shift(&r, 1u, 64u);
    CHECK(st == 7u && r == SENTINEL);
    if (tf) fprintf(tf, "status_7_shift\tstatus\tPASS\ttrap=7_shift_ge_64\n");

    r = SENTINEL;
    st = omega2_q_trap_code(&r, 8u);
    CHECK(st == 8u && r == SENTINEL);
    if (tf) fprintf(tf, "status_8_rt\tstatus\tPASS\ttrap=8_runtime\n");

    r = SENTINEL;
    CHECK(omega2_q_req9(&r, 7u) == OMEGA_OK && r == 8u);
    r = SENTINEL;
    st = omega2_q_req9(&r, 0u);
    CHECK(st == 9u && r == SENTINEL);
    if (tf) fprintf(tf, "status_9_requires\tstatus\tPASS\ttrap=9_rm2_requires_contract\n");

    r = SENTINEL;
    CHECK(omega2_q_ens10(&r, 11u) == OMEGA_OK && r == 11u);
    r = SENTINEL;
    st = omega2_q_ens10(&r, 5u);
    CHECK(st == 10u && r == SENTINEL);
    if (tf) fprintf(tf, "status_10_ensures\tstatus\tPASS\ttrap=10_rm2_ensures_contract\n");

    r = SENTINEL;
    CHECK(omega2_q_inv10(&r, 4u) == OMEGA_OK && r == 4u);
    r = SENTINEL;
    st = omega2_q_inv10(&r, 5u);
    CHECK(st == 10u && r == SENTINEL);
    if (tf) fprintf(tf, "status_10_invariant\tstatus\tPASS\ttrap=10_rm2_loop_invariant\n");

    r = SENTINEL;
    CHECK(omega2_q_trap_code(&r, 11u) == 11u && r == SENTINEL);
    if (tf) fprintf(tf, "status_11_arena\tstatus\tPASS\ttrap=11_arena_full\n");

    r = SENTINEL;
    CHECK(omega2_q_trap_code(&r, 12u) == 12u && r == SENTINEL);
    if (tf) fprintf(tf, "status_12_stale\tstatus\tPASS\ttrap=12_stale_handle\n");

    r = SENTINEL;
    CHECK(omega2_q_trap_code(&r, 13u) == 13u && r == SENTINEL);
    if (tf) fprintf(tf, "status_13_pool\tstatus\tPASS\ttrap=13_pool_full\n");

    r = SENTINEL;
    CHECK(omega2_q_trap_code(&r, 14u) == 14u && r == SENTINEL);
    if (tf) fprintf(tf, "status_14_retired\tstatus\tPASS\ttrap=14_retired\n");

    /* Out-buffer rollback atomicity on trap */
    uint8_t out_guard[8];
    memset(out_guard, 0x5A, sizeof out_guard);
    r = SENTINEL;
    CHECK(omega2_q_out_trap(&r, 1u, out_guard) == 9u && r == SENTINEL);
    for (int i = 0; i < 8; i++)
        CHECK(out_guard[i] == 0x5Au);
    CHECK(omega2_q_out_trap(&r, 0u, out_guard) == OMEGA_OK && r == 42u);
    CHECK(out_guard[0] == 0xABu && out_guard[1] == 0xCDu && out_guard[2] == 0u && out_guard[7] == 0u);
    if (tf) fprintf(tf, "out_atomicity_on_trap\tcontrol\tPASS\tout_untouched_on_trap9_zeroed_on_ok\n");

    /* Status 32 (OMEGA_BAD_ARG): null, misaligned, wrong sized len, overflow, overlap */
    CHECK(omega2_q_add(NULL, 1u, 2u) == OMEGA_BAD_ARG);
    uint8_t unal[32] = { 0 };
    CHECK(omega2_q_add((uint64_t *)(unal + 1), 1u, 2u) == OMEGA_BAD_ARG);
    r = SENTINEL;
    CHECK(omega2_q_sum_view(&r, NULL, 1u) == OMEGA_BAD_ARG && r == SENTINEL);
    CHECK(omega2_q_sum_view(&r, (const uint64_t *)(unal + 1), 1u) == OMEGA_BAD_ARG && r == SENTINEL);
    CHECK(omega2_q_sum_view(&r, u64v, (UINT64_MAX / 8u) + 1u) == OMEGA_BAD_ARG && r == SENTINEL);
    CHECK(omega2_q_sum_view(&r, u64v, ((UINTPTR_MAX - (uintptr_t)u64v) / 8u) + 1u) == OMEGA_BAD_ARG && r == SENTINEL);
    CHECK(omega2_q_sized_copy(&r, s8, 7u, d8, 8u) == OMEGA_BAD_ARG && r == SENTINEL);
    CHECK(omega2_q_sized_copy(&r, s8, 8u, s8, 8u) == OMEGA_BAD_ARG && r == SENTINEL);
    CHECK(omega2_q_sized_copy(&r, s8, 8u, (uint8_t *)&r, 8u) == OMEGA_BAD_ARG && r == SENTINEL);
    CHECK(omega2_q_layout_out(&r, NULL, out16) == OMEGA_BAD_ARG && r == SENTINEL);
    CHECK(omega2_q_layout_out(&r, hdr, (uint8_t *)&r) == OMEGA_BAD_ARG && r == SENTINEL);
    uint8_t ov16[16];
    memset(ov16, 0x33, sizeof ov16);
    CHECK(omega2_q_two_out(&r, ov16, ov16 + 4) == OMEGA_BAD_ARG && r == SENTINEL && ov16[0] == 0x33u);
    if (tf) fprintf(tf, "status_32_bad_arg\tstatus\tPASS\t12_bad_arg_checks_all_32\n");

    /* Status 33 (OMEGA_REENTRY): live SIGUSR1 handler reentering omega2_q_add during q_spin */
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_sigusr1;
    CHECK(sigaction(SIGUSR1, &sa, NULL) == 0);
    g_main_tid = pthread_self();
    pthread_t th;
    CHECK(pthread_create(&th, NULL, reentry_sender, NULL) == 0);
    g_spin_started = 1;
    r = SENTINEL;
    st = omega2_q_spin(&r, 40000u, 10000u);
    g_spin_done = 1;
    CHECK(pthread_join(th, NULL) == 0);
    CHECK(st == OMEGA_OK && r != SENTINEL);
    CHECK(g_reentry_seen == 1 && g_reentry_status == (sig_atomic_t)OMEGA_REENTRY && g_sig_result == SENTINEL);
    /* Verify ombr_active cleared after spin returned */
    r = SENTINEL;
    CHECK(omega2_q_add(&r, 100u, 23u) == OMEGA_OK && r == 123u);
    if (tf) fprintf(tf, "status_33_reentry\tstatus\tPASS\tlive_sigusr1_reentry=33_outer_ok\n");

    if (tf) fclose(tf);
    printf("QUAL_C PASS (ident=%s)\n", id);
    return 0;
}
EOF

gcc -std=c11 -O2 -Wall -Wextra -Werror -I"$WORK/gen" "$WORK/c/qual_c.c" "$WORK/gen/libomega_native.a" -o "$WORK/c/qual_c" -lpthread
"$WORK/c/qual_c" "$RES"

gcc -std=c11 -O2 -Wall -Wextra -Werror -mbranch-protection=standard -I"$WORK/gen" "$WORK/c/qual_c.c" "$WORK/gen/libomega_native_bti.a" -o "$WORK/c/qual_c_bti" -lpthread
"$WORK/c/qual_c_bti"
rec c_bti_abi_v2 lang PASS "mbranch-protection=standard_all_22_exports_and_traps"

# 5. C++17 qualification (omega_native.h + omega_api.h layout static_asserts & inline wrappers)
cat > "$WORK/cpp/qual_cpp.cpp" <<'EOF'
#include <cstdint>
#include <cstdio>
#include <cstring>
#include "omega_native.h"
#include "omega_api.h"

#define CHECK(c) do { if (!(c)) { std::fprintf(stderr, "CPP FAIL line %d: %s\n", __LINE__, #c); return 1; } } while (0)

int main()
{
    static_assert(sizeof(omega_qhdr_t) == OMEGA_QHDR_BYTES, "qhdr size");
    CHECK(std::strcmp(omega2_ident_abi_v2_qual(), OMEGA2_IDENT_abi_v2_qual) == 0);

    /* Direct ABI v2 status checks */
    uint64_t r = 0xCAFEBABEULL;
    CHECK(omega2_q_add(&r, 30u, 12u) == OMEGA_OK && r == 42u);
    r = 0xCAFEBABEULL;
    CHECK(omega2_q_req9(&r, 0u) == 9u && r == 0xCAFEBABEULL);
    CHECK(omega2_q_ens10(&r, 3u) == 10u && r == 0xCAFEBABEULL);
    CHECK(omega2_q_inv10(&r, 5u) == 10u && r == 0xCAFEBABEULL);
    CHECK(omega2_q_add(nullptr, 1u, 2u) == OMEGA_BAD_ARG);

    uint8_t out_guard[8];
    std::memset(out_guard, 0x77, sizeof out_guard);
    CHECK(omega2_q_out_trap(&r, 1u, out_guard) == 9u && out_guard[0] == 0x77u && r == 0xCAFEBABEULL);

    /* Typed omega_api.h wrappers */
    CHECK(q_add(100u, 23u) == 123u);
    omega_qhdr_t hdr{};
    hdr.tag = 7u;
    hdr.val = 10u;
    for (int i = 0; i < 8; i++) hdr.key[i] = static_cast<uint8_t>(0x30 + i);
    uint8_t payload[2] = { 3u, 4u };
    q_layout_edit(&hdr, payload, 2u);
    CHECK(hdr.tag == 14u && hdr.val == 12u);
    uint8_t out16[16]{};
    CHECK(q_layout_out(&hdr, out16) == 12u);
    CHECK(out16[0] == 0x30u && out16[8] == 14u && out16[12] == 0xA5u && out16[13] == 0x5Au);

    std::printf("QUAL_CPP PASS\n");
    return 0;
}
EOF
g++ -std=c++17 -O2 -Wall -Wextra -Werror -I"$WORK/gen" "$WORK/cpp/qual_cpp.cpp" "$WORK/gen/libomega_native.a" -o "$WORK/cpp/qual_cpp" -lpthread
"$WORK/cpp/qual_cpp"
rec cpp_abi_v2 lang PASS "g++17_static_asserts_traps_and_api_wrappers"

# 6. Rust qualification (#![forbid(unsafe_code)] caller crate over isolated -sys FFI crate)
if command -v cargo >/dev/null 2>&1; then
    cp "$WORK/gen/omega_native.rs" "$WORK/rust/abi_v2_sys/src/bindings.rs"
    cat > "$WORK/rust/abi_v2_sys/Cargo.toml" <<'EOF'
[package]
name = "abi_v2_sys"
version = "0.1.0"
edition = "2024"
EOF
    cat > "$WORK/rust/abi_v2_sys/build.rs" <<EOF
fn main() {
    println!("cargo:rustc-link-search=native=$WORK/gen");
    println!("cargo:rustc-link-lib=static=omega_native");
    println!("cargo:rustc-link-lib=pthread");
}
EOF
    cat > "$WORK/rust/abi_v2_sys/src/lib.rs" <<'EOF'
#![allow(non_snake_case, non_upper_case_globals)]
mod bindings;
use std::ffi::CStr;

pub use bindings::{OMEGA2_IDENT_abi_v2_qual, OMEGA_BAD_ARG, OMEGA_OK};

pub fn ident_str() -> &'static str {
    unsafe {
        let p = bindings::omega2_ident_abi_v2_qual() as *const std::ffi::c_char;
        CStr::from_ptr(p).to_str().expect("utf8 ident")
    }
}
pub fn add(a: u64, b: u64) -> (u32, u64) {
    let mut r = 0xDEADBEEFCAFEBABEu64;
    let st = unsafe { bindings::omega2_q_add(&mut r, a, b) };
    (st, r)
}
pub fn bad_arg_null_result() -> u32 {
    unsafe { bindings::omega2_q_add(std::ptr::null_mut(), 1, 2) }
}
pub fn bad_arg_two_out_overlap() -> (u32, u64, u8) {
    let mut r = 0xDEADBEEFCAFEBABEu64;
    let mut buf = [0x33u8; 16];
    let st = unsafe { bindings::omega2_q_two_out(&mut r, buf.as_mut_ptr(), buf.as_mut_ptr().add(4)) };
    (st, r, buf[0])
}
pub fn sum_view(s: &[u64]) -> (u32, u64) {
    let mut r = 0xDEADBEEFCAFEBABEu64;
    let st = unsafe { bindings::omega2_q_sum_view(&mut r, s.as_ptr(), s.len() as u64) };
    (st, r)
}
pub fn scale_edit(s: &mut [u32], fac: u64) -> (u32, u64) {
    let mut r = 0xDEADBEEFCAFEBABEu64;
    let st = unsafe { bindings::omega2_q_scale_edit(&mut r, s.as_mut_ptr(), s.len() as u64, fac) };
    (st, r)
}
pub fn out_trap(fail: u64, out: &mut [u8; 8]) -> (u32, u64) {
    let mut r = 0xDEADBEEFCAFEBABEu64;
    let st = unsafe { bindings::omega2_q_out_trap(&mut r, fail, out.as_mut_ptr()) };
    (st, r)
}
pub fn trap1_ovf(a: i64, b: i64) -> (u32, u64) {
    let mut r = 0xDEADBEEFCAFEBABEu64;
    let st = unsafe { bindings::omega2_q_trap1_ovf(&mut r, a as u64, b as u64) };
    (st, r)
}
pub fn trap2_div0(a: u64, b: u64) -> (u32, u64) {
    let mut r = 0xDEADBEEFCAFEBABEu64;
    let st = unsafe { bindings::omega2_q_trap2_div0(&mut r, a, b) };
    (st, r)
}
pub fn trap3_bounds(d: &[u8], idx: u64) -> (u32, u64) {
    let mut r = 0xDEADBEEFCAFEBABEu64;
    let st = unsafe { bindings::omega2_q_trap3_bounds(&mut r, d.as_ptr(), d.len() as u64, idx) };
    (st, r)
}
pub fn trap4_loop(n: u64) -> (u32, u64) {
    let mut r = 0xDEADBEEFCAFEBABEu64;
    let st = unsafe { bindings::omega2_q_trap4_loop(&mut r, n) };
    (st, r)
}
pub fn trap5_cast(x: u64) -> (u32, u64) {
    let mut r = 0xDEADBEEFCAFEBABEu64;
    let st = unsafe { bindings::omega2_q_trap5_cast(&mut r, x) };
    (st, r)
}
pub fn trap7_shift(x: u64, sh: u64) -> (u32, u64) {
    let mut r = 0xDEADBEEFCAFEBABEu64;
    let st = unsafe { bindings::omega2_q_trap7_shift(&mut r, x, sh) };
    (st, r)
}
pub fn req9(x: u64) -> (u32, u64) {
    let mut r = 0xDEADBEEFCAFEBABEu64;
    let st = unsafe { bindings::omega2_q_req9(&mut r, x) };
    (st, r)
}
pub fn ens10(x: u64) -> (u32, u64) {
    let mut r = 0xDEADBEEFCAFEBABEu64;
    let st = unsafe { bindings::omega2_q_ens10(&mut r, x) };
    (st, r)
}
pub fn inv10(lim: u64) -> (u32, u64) {
    let mut r = 0xDEADBEEFCAFEBABEu64;
    let st = unsafe { bindings::omega2_q_inv10(&mut r, lim) };
    (st, r)
}
pub fn trap_code(c: u64) -> (u32, u64) {
    let mut r = 0xDEADBEEFCAFEBABEu64;
    let st = unsafe { bindings::omega2_q_trap_code(&mut r, c) };
    (st, r)
}
EOF
    cat > "$WORK/rust/abi_v2_caller/Cargo.toml" <<'EOF'
[package]
name = "abi_v2_caller"
version = "0.1.0"
edition = "2024"

[dependencies]
abi_v2_sys = { path = "../abi_v2_sys" }
EOF
    cat > "$WORK/rust/abi_v2_caller/src/main.rs" <<'EOF'
#![forbid(unsafe_code)]

const SENTINEL: u64 = 0xDEADBEEFCAFEBABE;

fn main() {
    assert_eq!(abi_v2_sys::ident_str(), abi_v2_sys::OMEGA2_IDENT_abi_v2_qual);
    assert_eq!(abi_v2_sys::add(19, 23), (abi_v2_sys::OMEGA_OK, 42));
    assert_eq!(abi_v2_sys::sum_view(&[10, 20, 30]), (0, 60));
    let mut v = [2u32, 4, 6];
    assert_eq!(abi_v2_sys::scale_edit(&mut v, 5), (0, 60));
    assert_eq!(v, [10, 20, 30]);

    assert_eq!(abi_v2_sys::trap1_ovf(i64::MAX, 1), (1, SENTINEL));
    assert_eq!(abi_v2_sys::trap2_div0(9, 0), (2, SENTINEL));
    assert_eq!(abi_v2_sys::trap3_bounds(&[1, 2, 3], 3), (3, SENTINEL));
    assert_eq!(abi_v2_sys::trap4_loop(12), (4, SENTINEL));
    assert_eq!(abi_v2_sys::trap5_cast(300), (5, SENTINEL));
    assert_eq!(abi_v2_sys::trap_code(6), (6, SENTINEL));
    assert_eq!(abi_v2_sys::trap7_shift(1, 64), (7, SENTINEL));
    assert_eq!(abi_v2_sys::trap_code(8), (8, SENTINEL));
    assert_eq!(abi_v2_sys::req9(0), (9, SENTINEL));
    assert_eq!(abi_v2_sys::req9(4), (0, 5));
    assert_eq!(abi_v2_sys::ens10(5), (10, SENTINEL));
    assert_eq!(abi_v2_sys::inv10(5), (10, SENTINEL));
    for c in 11u64..=14 {
        assert_eq!(abi_v2_sys::trap_code(c), (c as u32, SENTINEL));
    }

    let mut og = [0x5Au8; 8];
    assert_eq!(abi_v2_sys::out_trap(1, &mut og), (9, SENTINEL));
    assert_eq!(og, [0x5Au8; 8]);
    assert_eq!(abi_v2_sys::out_trap(0, &mut og), (0, 42));
    assert_eq!(&og[..4], &[0xAB, 0xCD, 0, 0]);

    assert_eq!(abi_v2_sys::bad_arg_null_result(), abi_v2_sys::OMEGA_BAD_ARG);
    assert_eq!(abi_v2_sys::bad_arg_two_out_overlap(), (32, SENTINEL, 0x33));
    println!("QUAL_RUST PASS (#![forbid(unsafe_code)])");
}
EOF
    (cd "$WORK/rust/abi_v2_caller" && cargo run --offline --quiet)
    rec rust_forbid_unsafe_abi_v2 lang PASS "rustc_forbid_unsafe_caller_over_sys_all_traps_1_14_and_32"
else
    rec rust_forbid_unsafe_abi_v2 lang NOT_RUN "cargo_absent"
fi

# 7. Zig qualification
if command -v zig >/dev/null 2>&1; then
    cp "$WORK/gen/omega_native.zig" "$WORK/zig/omega_native.zig"
    cat > "$WORK/zig/qual_zig.zig" <<'EOF'
const std = @import("std");
const om = @import("omega_native.zig");

const SENTINEL: u64 = 0xDEADBEEFCAFEBABE;

fn check(ok: bool) void {
    if (!ok) std.process.exit(1);
}

pub fn main() void {
    const id = std.mem.span(om.omega2_ident_abi_v2_qual());
    check(std.mem.eql(u8, id, om.OMEGA2_IDENT_abi_v2_qual));

    var r: u64 = SENTINEL;
    check(om.omega2_q_add(&r, 19, 23) == om.OMEGA_OK and r == 42);

    var arr = [_]u64{ 10, 20, 30 };
    r = SENTINEL;
    check(om.omega2_q_sum_view(&r, &arr, arr.len) == om.OMEGA_OK and r == 60);

    var ed = [_]u32{ 3, 5 };
    r = SENTINEL;
    check(om.omega2_q_scale_edit(&r, &ed, ed.len, 4) == om.OMEGA_OK and r == 32 and ed[0] == 12 and ed[1] == 20);

    r = SENTINEL;
    check(om.omega2_q_trap1_ovf(&r, 9223372036854775807, 1) == 1 and r == SENTINEL);
    check(om.omega2_q_trap2_div0(&r, 9, 0) == 2 and r == SENTINEL);
    var b3 = [_]u8{ 1, 2, 3 };
    check(om.omega2_q_trap3_bounds(&r, &b3, 3, 3) == 3 and r == SENTINEL);
    check(om.omega2_q_trap4_loop(&r, 12) == 4 and r == SENTINEL);
    check(om.omega2_q_trap5_cast(&r, 300) == 5 and r == SENTINEL);
    check(om.omega2_q_trap_code(&r, 6) == 6 and r == SENTINEL);
    check(om.omega2_q_trap7_shift(&r, 1, 64) == 7 and r == SENTINEL);
    check(om.omega2_q_trap_code(&r, 8) == 8 and r == SENTINEL);
    check(om.omega2_q_req9(&r, 0) == 9 and r == SENTINEL);
    check(om.omega2_q_ens10(&r, 5) == 10 and r == SENTINEL);
    check(om.omega2_q_inv10(&r, 5) == 10 and r == SENTINEL);
    for (11..15) |c| {
        check(om.omega2_q_trap_code(&r, c) == @as(u32, @intCast(c)) and r == SENTINEL);
    }

    var og = [_]u8{0x5A} ** 8;
    check(om.omega2_q_out_trap(&r, 1, &og) == 9 and r == SENTINEL and og[0] == 0x5A);
    check(om.omega2_q_out_trap(&r, 0, &og) == 0 and r == 42 and og[0] == 0xAB and og[1] == 0xCD and og[2] == 0);

    check(om.omega2_q_add(null, 1, 2) == om.OMEGA_BAD_ARG);
    var ov = [_]u8{0x33} ** 16;
    check(om.omega2_q_two_out(&r, &ov, ov[4..].ptr) == om.OMEGA_BAD_ARG and ov[0] == 0x33);

    std.debug.print("QUAL_ZIG PASS\n", .{});
}
EOF
    (cd "$WORK/zig" && zig build-exe qual_zig.zig "$WORK/gen/libomega_native.a" -lc -lpthread --cache-dir "$WORK/zig/cache" --global-cache-dir "$WORK/zig/gcache" -femit-bin="$WORK/zig/qual_zig")
    "$WORK/zig/qual_zig"
    rec zig_abi_v2 lang PASS "zig_native_binding_all_traps_1_14_and_32"
else
    rec zig_abi_v2 lang NOT_RUN "zig_absent"
fi

# 8. Python ctypes qualification + tampered-ident ImportError negative control
if command -v python3 >/dev/null 2>&1; then
    cp "$WORK/gen/omega_native.py" "$WORK/py/omega_native.py"
    cp "$WORK/gen/libomega_native.so" "$WORK/py/libomega_native.so"
    cat > "$WORK/py/qual_py.py" <<'EOF'
import ctypes
import omega_native as om

SENTINEL = 0xDEADBEEFCAFEBABE
r = ctypes.c_uint64(SENTINEL)

assert om.omega2_ident_abi_v2_qual() == om.OMEGA2_IDENT_abi_v2_qual
assert om.omega2_q_add(ctypes.byref(r), 19, 23) == om.OMEGA_OK and r.value == 42

arr = (ctypes.c_uint64 * 3)(10, 20, 30)
assert om.omega2_q_sum_view(ctypes.byref(r), arr, 3) == om.OMEGA_OK and r.value == 60

ed = (ctypes.c_uint32 * 2)(3, 5)
assert om.omega2_q_scale_edit(ctypes.byref(r), ed, 2, 4) == om.OMEGA_OK and r.value == 32
assert list(ed) == [12, 20]

def expect_trap(fn, expected, *args):
    rr = ctypes.c_uint64(SENTINEL)
    st = fn(ctypes.byref(rr), *args)
    assert st == expected, f"got {st} expected {expected}"
    assert rr.value == SENTINEL

expect_trap(om.omega2_q_trap1_ovf, 1, (1 << 63) - 1, 1)
expect_trap(om.omega2_q_trap2_div0, 2, 9, 0)
expect_trap(om.omega2_q_trap3_bounds, 3, b"abc", 3, 3)
expect_trap(om.omega2_q_trap4_loop, 4, 12)
expect_trap(om.omega2_q_trap5_cast, 5, 300)
expect_trap(om.omega2_q_trap_code, 6, 6)
expect_trap(om.omega2_q_trap7_shift, 7, 1, 64)
expect_trap(om.omega2_q_trap_code, 8, 8)
expect_trap(om.omega2_q_req9, 9, 0)
expect_trap(om.omega2_q_ens10, 10, 5)
expect_trap(om.omega2_q_inv10, 10, 5)
for c in (11, 12, 13, 14):
    expect_trap(om.omega2_q_trap_code, c, c)

og = (ctypes.c_uint8 * 8)(*([0x5A] * 8))
r = ctypes.c_uint64(SENTINEL)
assert om.omega2_q_out_trap(ctypes.byref(r), 1, og) == 9 and r.value == SENTINEL and list(og) == [0x5A] * 8
assert om.omega2_q_out_trap(ctypes.byref(r), 0, og) == 0 and r.value == 42 and list(og[:4]) == [0xAB, 0xCD, 0, 0]

assert om.omega2_q_add(None, 1, 2) == om.OMEGA_BAD_ARG

# Scalar range enforcement: negative int must raise ValueError / ArgumentError
bad_scalar_caught = False
try:
    om.omega2_q_add(ctypes.byref(r), -1, 2)
except (ValueError, ctypes.ArgumentError):
    bad_scalar_caught = True
assert bad_scalar_caught

print("QUAL_PYTHON PASS")
EOF
    PYTHONPATH="$WORK/py" python3 "$WORK/py/qual_py.py"
    rec python_ctypes_abi_v2 lang PASS "python3_ctypes_ident_traps_1_14_and_32"

    # Negative control: tampered ident in omega_native.py MUST raise ImportError
    sed 's/abi=2 profile=OM-2/abi=2 profile=OM-9/' "$WORK/py/omega_native.py" > "$WORK/py/omega_native_bad.py"
    if PYTHONPATH="$WORK/py" python3 -c '
try:
    import omega_native_bad
except ImportError:
    raise SystemExit(0)
raise SystemExit(1)
'; then
        rec neg_python_ident_mismatch control PASS "tampered_ident_raised_ImportError"
    else
        rec neg_python_ident_mismatch control FAIL "tampered_ident_not_refused"
    fi
else
    rec python_ctypes_abi_v2 lang NOT_RUN "python3_absent"
    rec neg_python_ident_mismatch control NOT_RUN "python3_absent"
fi

# 9. Go (cgo) qualification
if command -v go >/dev/null 2>&1; then
    cp "$WORK/gen/omega_native.go" "$WORK/go/omeganative/omega_native.go"
    cp "$WORK/gen/omega_native.h"  "$WORK/go/omeganative/omega_native.h"
    cp "$WORK/gen/libomega_native.so" "$WORK/go/omeganative/libomega_native.so"
    cat > "$WORK/go/go.mod" <<'EOF'
module omqual

go 1.22
EOF
    cat > "$WORK/go/main.go" <<'EOF'
package main

import (
	"fmt"
	"os"
	"unsafe"

	om "omqual/omeganative"
)

const sentinel uint64 = 0xDEADBEEFCAFEBABE

func check(ok bool, msg string) {
	if !ok {
		fmt.Fprintf(os.Stderr, "GO FAIL: %s\n", msg)
		os.Exit(1)
	}
}

func main() {
	check(om.Omega2_ident_abi_v2_qual() == om.Omega2Ident_abi_v2_qual, "ident")

	var r uint64 = sentinel
	check(om.Omega2_q_add(&r, 19, 23) == om.OmegaOK && r == 42, "q_add")

	u64 := []uint64{10, 20, 30}
	r = sentinel
	check(om.Omega2_q_sum_view(&r, unsafe.Pointer(&u64[0]), uint64(len(u64))) == om.OmegaOK && r == 60, "q_sum_view")

	u32 := []uint32{3, 5}
	r = sentinel
	check(om.Omega2_q_scale_edit(&r, unsafe.Pointer(&u32[0]), uint64(len(u32)), 4) == om.OmegaOK && r == 32 && u32[0] == 12 && u32[1] == 20, "q_scale_edit")

	r = sentinel
	check(om.Omega2_q_trap1_ovf(&r, 9223372036854775807, 1) == 1 && r == sentinel, "trap1")
	check(om.Omega2_q_trap2_div0(&r, 9, 0) == 2 && r == sentinel, "trap2")
	b3 := []byte{1, 2, 3}
	check(om.Omega2_q_trap3_bounds(&r, unsafe.Pointer(&b3[0]), 3, 3) == 3 && r == sentinel, "trap3")
	check(om.Omega2_q_trap4_loop(&r, 12) == 4 && r == sentinel, "trap4")
	check(om.Omega2_q_trap5_cast(&r, 300) == 5 && r == sentinel, "trap5")
	check(om.Omega2_q_trap_code(&r, 6) == 6 && r == sentinel, "trap6")
	check(om.Omega2_q_trap7_shift(&r, 1, 64) == 7 && r == sentinel, "trap7")
	check(om.Omega2_q_trap_code(&r, 8) == 8 && r == sentinel, "trap8")
	check(om.Omega2_q_req9(&r, 0) == 9 && r == sentinel, "req9")
	check(om.Omega2_q_ens10(&r, 5) == 10 && r == sentinel, "ens10")
	check(om.Omega2_q_inv10(&r, 5) == 10 && r == sentinel, "inv10")
	for c := uint64(11); c <= 14; c++ {
		check(om.Omega2_q_trap_code(&r, c) == uint32(c) && r == sentinel, "trap11..14")
	}

	og := [8]byte{0x5A, 0x5A, 0x5A, 0x5A, 0x5A, 0x5A, 0x5A, 0x5A}
	check(om.Omega2_q_out_trap(&r, 1, unsafe.Pointer(&og[0])) == 9 && r == sentinel && og[0] == 0x5A, "out_trap")
	check(om.Omega2_q_out_trap(&r, 0, unsafe.Pointer(&og[0])) == 0 && r == 42 && og[0] == 0xAB && og[1] == 0xCD && og[2] == 0, "out_ok")

	check(om.Omega2_q_add(nil, 1, 2) == om.OmegaBadArg, "bad_arg_nil")
	fmt.Println("QUAL_GO PASS")
}
EOF
    (cd "$WORK/go" && GOCACHE="$WORK/go/gocache" CGO_LDFLAGS="-Wl,-rpath,$WORK/go/omeganative" go build -o "$WORK/go/qual_go" .)
    "$WORK/go/qual_go"
    rec go_cgo_abi_v2 lang PASS "go_cgo_native_binding_all_traps_1_14_and_32"
else
    rec go_cgo_abi_v2 lang NOT_RUN "go_absent"
fi

# 10. Negative control: Link-time ABI version mismatch (v1 omega_q_add / v3 omega3_q_add MUST fail link)
cat > "$WORK/neg/bad_v1_link.c" <<'EOF'
#include <stdint.h>
extern uint32_t omega_q_add(uint64_t *r, uint64_t a, uint64_t b);
int main(void) { uint64_t r = 0; return (int)omega_q_add(&r, 1u, 2u); }
EOF
cat > "$WORK/neg/bad_v3_link.c" <<'EOF'
#include <stdint.h>
extern uint32_t omega3_q_add(uint64_t *r, uint64_t a, uint64_t b);
int main(void) { uint64_t r = 0; return (int)omega3_q_add(&r, 1u, 2u); }
EOF
if ! gcc -std=c11 "$WORK/neg/bad_v1_link.c" "$WORK/gen/libomega_native.a" -o "$WORK/neg/bad_v1" -lpthread 2>"$WORK/neg/v1.err" \
   && ! gcc -std=c11 "$WORK/neg/bad_v3_link.c" "$WORK/gen/libomega_native.a" -o "$WORK/neg/bad_v3" -lpthread 2>"$WORK/neg/v3.err"; then
    rec neg_link_abi_mismatch control PASS "v1_and_v3_symbols_rejected_at_link_time"
else
    rec neg_link_abi_mismatch control FAIL "mismatched_abi_linked_unexpectedly"
fi

# 11. FR-7 Path A: Pure-Omega bridge/shlib/shlib.om ELF64 ET_DYN built with ZERO C/linker + dlopen/dlsym probe
{
    printf 'object\n'
    cat "$REPO_ROOT/bridge/shlib/test.om"
} | "$OMC" > "$WORK/shlib/test.omobj"
"$WORK/shlib_bin" lib "$REPO_ROOT/bridge/shlib/test.tsv" "$WORK/shlib/test.omobj" "$WORK/shlib/libomshlib.so.1"
"$WORK/shlib_bin" call "$REPO_ROOT/bridge/shlib/test.tsv" "$WORK/shlib/probe"
chmod 755 "$WORK/shlib/libomshlib.so.1" "$WORK/shlib/probe"
"$WORK/shlib/probe"
readelf -W -h -S -d --dyn-syms "$WORK/shlib/libomshlib.so.1" > "$WORK/shlib/readelf.txt"
grep -q 'Type:[[:space:]]*DYN' "$WORK/shlib/readelf.txt"
grep -q 'SONAME.*libomshlib.so.1' "$WORK/shlib/readelf.txt"

cat > "$WORK/shlib/dlopen_shlib.c" <<'EOF'
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>

int main(int argc, char **argv)
{
    if (argc < 2) return 2;
    void *h = dlopen(argv[1], RTLD_NOW);
    if (!h) { fprintf(stderr, "dlopen failed: %s\n", dlerror()); return 1; }
    int32_t (*seven_fn)(void) = (int32_t (*)(void))dlsym(h, "omega_shlib_seven");
    int32_t (*add_fn)(int32_t, int32_t) = (int32_t (*)(int32_t, int32_t))dlsym(h, "omega_shlib_add");
    int32_t (*div_fn)(int32_t, int32_t) = (int32_t (*)(int32_t, int32_t))dlsym(h, "omega_shlib_div");
    if (!seven_fn || !add_fn || !div_fn) { fprintf(stderr, "dlsym failed: %s\n", dlerror()); return 1; }
    if (seven_fn() != 7) return 1;
    if (add_fn(19, 23) != 42) return 1;
    if (div_fn(42, 6) != 7) return 1;
    if (div_fn(1, 0) != 999) return 1; /* configured trap-to-value wrapper */
    dlclose(h);
    printf("FR7_SHLIB_DLOPEN PASS\n");
    return 0;
}
EOF
gcc -std=c11 -O2 -Wall -Wextra -Werror "$WORK/shlib/dlopen_shlib.c" -o "$WORK/shlib/dlopen_shlib" -ldl
"$WORK/shlib/dlopen_shlib" "$WORK/shlib/libomshlib.so.1"
rec fr7_shlib_om_dlopen control PASS "pure_om_ET_DYN_readelf_probe_and_dlopen_dlsym_ok"

# 12. FR-7 Path B: GNU symbol-versioned libomega2_qual.so.2 (OMEGA_ABI_2.0) dlvsym PASS + OMEGA_ABI_1.0 NULL refusal
readelf -W --version-info "$WORK/ver/libomega2_qual.so.2" > "$WORK/ver/verinfo.txt"
grep -q 'OMEGA_ABI_2.0' "$WORK/ver/verinfo.txt"

cat > "$WORK/ver/dlvsym_probe.c" <<'EOF'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef uint32_t (*add_fn)(uint64_t *, uint64_t, uint64_t);
typedef uint32_t (*req9_fn)(uint64_t *, uint64_t);
typedef const char *(*ident_fn)(void);

int main(int argc, char **argv)
{
    if (argc < 2) return 2;
    void *h = dlopen(argv[1], RTLD_NOW);
    if (!h) { fprintf(stderr, "dlopen failed: %s\n", dlerror()); return 1; }

    add_fn f_add = (add_fn)dlvsym(h, "omega2_q_add", "OMEGA_ABI_2.0");
    req9_fn f_req = (req9_fn)dlvsym(h, "omega2_q_req9", "OMEGA_ABI_2.0");
    ident_fn f_id = (ident_fn)dlvsym(h, "omega2_ident_abi_v2_qual", "OMEGA_ABI_2.0");
    if (!f_add || !f_req || !f_id) {
        fprintf(stderr, "dlvsym OMEGA_ABI_2.0 failed\n");
        return 1;
    }
    uint64_t r = 0xDEADBEEFULL;
    if (f_add(&r, 19u, 23u) != 0u || r != 42u) return 1;
    r = 0xDEADBEEFULL;
    if (f_req(&r, 0u) != 9u || r != 0xDEADBEEFULL) return 1;
    if (!strstr(f_id(), "abi=2 profile=OM-2")) return 1;

    /* Negative control 1: mismatched ABI version OMEGA_ABI_1.0 MUST return NULL */
    void *bad_v1 = dlvsym(h, "omega2_q_add", "OMEGA_ABI_1.0");
    if (bad_v1 != NULL) {
        fprintf(stderr, "FAIL: OMEGA_ABI_1.0 unexpectedly resolved!\n");
        return 1;
    }
    /* Negative control 2: internal adapter symbol hidden by local:* MUST return NULL */
    if (dlsym(h, "ombr_enter") != NULL) {
        fprintf(stderr, "FAIL: internal symbol ombr_enter leaked!\n");
        return 1;
    }
    dlclose(h);
    printf("FR7_DLVSYM PASS (v2=resolved v1=NULL internal=hidden)\n");
    return 0;
}
EOF
gcc -std=c11 -O2 -Wall -Wextra -Werror "$WORK/ver/dlvsym_probe.c" -o "$WORK/ver/dlvsym_probe" -ldl
"$WORK/ver/dlvsym_probe" "$WORK/ver/libomega2_qual.so.2"
rec fr7_ver_so_dlvsym_v2_pass control PASS "dlvsym_OMEGA_ABI_2_0_resolved_and_executed"
rec fr7_ver_so_dlvsym_v1_refused control PASS "dlvsym_OMEGA_ABI_1_0_NULL_and_ombr_enter_hidden"

# 13. Pure-Omega gate_abi_v2 verifier negative controls (tampered omc exit 69, FAIL row exit 1, missing mandatory row exit 1, duplicate ID exit 1)
cp "$OMC" "$WORK/neg/omc_tampered"
printf 'X' >> "$WORK/neg/omc_tampered"
set +e
"$WORK/gate_abi_v2" "$WORK/neg/omc_tampered" "$OMC_PIN_FILE" "$RES" >/dev/null 2>"$WORK/neg/tamper_omc.err"
RC_OMC=$?
set -e
if [ "$RC_OMC" -ne 69 ]; then
    echo "FAIL: tampered omc returned $RC_OMC (expected 69)" >&2
    exit 1
fi

cp "$RES" "$WORK/neg/res_fail.tsv"
printf 'injected_failure\tcontrol\tFAIL\ttamper_test\n' >> "$WORK/neg/res_fail.tsv"
set +e
"$WORK/gate_abi_v2" "$OMC" "$OMC_PIN_FILE" "$WORK/neg/res_fail.tsv" >/dev/null 2>"$WORK/neg/tamper_fail.err"
RC_FAIL=$?
set -e
if [ "$RC_FAIL" -ne 1 ]; then
    echo "FAIL: injected FAIL row returned $RC_FAIL (expected 1)" >&2
    exit 1
fi

grep -v '^status_9_requires	' "$RES" > "$WORK/neg/res_missing.tsv"
set +e
"$WORK/gate_abi_v2" "$OMC" "$OMC_PIN_FILE" "$WORK/neg/res_missing.tsv" >/dev/null 2>"$WORK/neg/tamper_miss.err"
RC_MISS=$?
set -e
if [ "$RC_MISS" -ne 1 ]; then
    echo "FAIL: missing mandatory row returned $RC_MISS (expected 1)" >&2
    exit 1
fi

cp "$RES" "$WORK/neg/res_dup.tsv"
printf 'status_9_requires\tstatus\tPASS\tdup_test\n' >> "$WORK/neg/res_dup.tsv"
set +e
"$WORK/gate_abi_v2" "$OMC" "$OMC_PIN_FILE" "$WORK/neg/res_dup.tsv" >/dev/null 2>"$WORK/neg/tamper_dup.err"
RC_DUP=$?
set -e
if [ "$RC_DUP" -ne 1 ]; then
    echo "FAIL: duplicate case row returned $RC_DUP (expected 1)" >&2
    exit 1
fi

rec neg_gate_tamper_controls control PASS "omc_tamper=exit69 fail_row=exit1 missing_mand=exit1 dup_case=exit1"

# 14. Final pure-Omega gate verdict on authentic results.tsv
"$WORK/gate_abi_v2" "$OMC" "$OMC_PIN_FILE" "$RES"
