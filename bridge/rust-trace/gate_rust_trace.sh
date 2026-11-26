#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# bridge/rust-trace/gate_rust_trace.sh
# End-to-end verification runner for the Universal Byte-Traceable Rust FFI Hook.
# Designed to run strictly on DGX Spark (Linux AArch64) with seeded omc, gcc/ar, cargo, and Lean 4.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
RT="$ROOT/bridge/rust-trace"
WORK="${OMEGA_TRACE_WORK_DIR:-$RT/work}"
OMC="${OMEGA_OMC:-$ROOT/seed/out/omc}"
if [ ! -x "$OMC" ] && [ -x "$HOME/canon/omega-mv/seed/out/omc" ]; then
    OMC="$HOME/canon/omega-mv/seed/out/omc"
fi
NATIVE_OM="$ROOT/bridge/omega-bridge/src/native.om"
LEAN_BIN="${OMEGA_LEAN:-$HOME/.elan/bin/lean}"

if [ "$(uname -s)" != "Linux" ] || [ "$(uname -m)" != "aarch64" ]; then
    echo "FAIL: gate_rust_trace.sh must run on Linux aarch64 (DGX Spark)" >&2
    exit 2
fi
if [ ! -x "$OMC" ]; then
    echo "FAIL: seeded omc not found or not executable at $OMC" >&2
    exit 2
fi

mkdir -p "$WORK"

echo "=== [1/7] Lean 4 proof check (TraceBridge.lean) ==="
if [ -x "$LEAN_BIN" ]; then
    LEAN_OUT=$("$LEAN_BIN" "$RT/proof/TraceBridge.lean" 2>&1)
    printf '%s\n' "$LEAN_OUT"
    if printf '%s\n' "$LEAN_OUT" | grep -q "sorryAx"; then
        echo "FAIL: TraceBridge.lean depends on sorryAx" >&2
        exit 1
    fi
else
    echo "FAIL: Lean 4 binary not found at $LEAN_BIN" >&2
    exit 2
fi

echo "=== [2/7] Deterministic pure-Omega builds (om_lock_gen, native, sample_unit) ==="
"$OMC" < "$RT/om_lock_gen.om" > "$WORK/om_lock_gen.1"
"$OMC" < "$RT/om_lock_gen.om" > "$WORK/om_lock_gen.2"
cmp "$WORK/om_lock_gen.1" "$WORK/om_lock_gen.2"
mv -f "$WORK/om_lock_gen.1" "$WORK/om_lock_gen"
rm -f "$WORK/om_lock_gen.2"
chmod 755 "$WORK/om_lock_gen"

"$OMC" < "$NATIVE_OM" > "$WORK/native"
chmod 755 "$WORK/native"

"$OMC" < "$RT/sample_unit.om" > "$WORK/sample_unit.bin.1"
"$OMC" < "$RT/sample_unit.om" > "$WORK/sample_unit.bin.2"
cmp "$WORK/sample_unit.bin.1" "$WORK/sample_unit.bin.2"
mv -f "$WORK/sample_unit.bin.1" "$WORK/sample_unit.bin"
rm -f "$WORK/sample_unit.bin.2"

echo "om_lock_gen=$(wc -c < "$WORK/om_lock_gen")B sample_unit.bin=$(wc -c < "$WORK/sample_unit.bin")B (2x bit-identical)"

echo "=== [3/7] Generate omega-bridge ABI v2 binding & compile ELF object ==="
OMC_SHA=$(sha256sum "$OMC" | awk '{print $1}')
BIN_LEN=$(wc -c < "$WORK/sample_unit.bin")
{
    cat "$RT/sample_unit.om"
    printf '\0%08d' "$BIN_LEN"
    cat "$WORK/sample_unit.bin"
    printf 'omega-unit sample_unit %s\n' "$OMC_SHA"
} > "$WORK/sample_unit.in"

"$WORK/native" c < "$WORK/sample_unit.in" > "$WORK/omega_trace_native.c"
"$WORK/native" h < "$WORK/sample_unit.in" > "$WORK/omega_trace_native.h"
"$WORK/native" rust < "$WORK/sample_unit.in" > "$WORK/omega_trace_native.rs"
gcc -c -O2 -fno-strict-aliasing -fPIC -Wall -Wextra -Werror \
    "$WORK/omega_trace_native.c" -o "$WORK/omega_trace_native.o"

echo "=== [4/7] Emit EGP3 + OMPK artifacts, generate & verify OMEGA_TRACE.lock ==="
"$WORK/om_lock_gen" emit-artifacts \
    "$RT/sample_unit.om" "$WORK/sample_unit.egp3" "$WORK/sample_unit.ompk"

"$WORK/om_lock_gen" generate \
    "$WORK/OMEGA_TRACE.lock" sample_unit \
    "$RT/sample_unit.om" "$OMC" "$WORK/sample_unit.egp3" \
    "$RT/proof/TraceBridge.lean" "$WORK/sample_unit.ompk" \
    "$WORK/sample_unit.bin" "$WORK/omega_trace_native.c" "$WORK/omega_trace_native.o"

"$WORK/om_lock_gen" verify \
    "$WORK/OMEGA_TRACE.lock" \
    "$RT/sample_unit.om" "$OMC" "$WORK/sample_unit.egp3" \
    "$RT/proof/TraceBridge.lean" "$WORK/sample_unit.ompk" \
    "$WORK/sample_unit.bin" "$WORK/omega_trace_native.c" "$WORK/omega_trace_native.o"

echo "=== [5/7] Verify #![forbid(unsafe_code)] and zero crates.io dependencies ==="
head -n 1 "$RT/crate/src/lib.rs" | grep -qx '#!\[forbid(unsafe_code)\]'
head -n 1 "$RT/crate/build.rs" | grep -qx '#!\[forbid(unsafe_code)\]'
head -n 1 "$RT/crate/tests/trace_parity.rs" | grep -qx '#!\[forbid(unsafe_code)\]'
head -n 1 "$RT/crate/sys/build.rs" | grep -qx '#!\[forbid(unsafe_code)\]'

echo "=== [6/7] Run cargo test --offline (debug & release: safe Rust crate + ABI v2 + traps + runtime tamper) ==="
DO_NOT_TRACK=1 DISABLE_TELEMETRY=1 \
OMEGA_TRACE_WORK_DIR="$WORK" \
OMEGA_OMC="$OMC" \
CARGO_TARGET_DIR="$WORK/target" \
cargo test --offline --manifest-path "$RT/crate/Cargo.toml" -- --nocapture

DO_NOT_TRACK=1 DISABLE_TELEMETRY=1 \
OMEGA_TRACE_WORK_DIR="$WORK" \
OMEGA_OMC="$OMC" \
CARGO_TARGET_DIR="$WORK/target" \
cargo test --release --offline --manifest-path "$RT/crate/Cargo.toml"

echo "=== [7/7] Build-time fail-closed tamper negative controls (5 controls via cargo build) ==="
flip_bit_file() {
    # Flip bit 0 of byte at 0-based offset $2 in file $1 (pure POSIX dd/od/printf, zero python/node).
    f="$1"
    off="$2"
    byte_dec=$(od -An -tu1 -j "$off" -N 1 "$f" | tr -d ' \n\t')
    if [ $((byte_dec % 2)) -eq 0 ]; then
        new_dec=$((byte_dec + 1))
    else
        new_dec=$((byte_dec - 1))
    fi
    new_oct=$(printf '%03o' "$new_dec")
    printf "\\$new_oct" | dd of="$f" bs=1 seek="$off" count=1 conv=notrunc 2>/dev/null
}

run_tamper_control() {
    label="$1"
    target_var="$2"
    target_src="$3"
    byte_off="$4"
    expect_code="$5"

    tdir="$WORK/neg_$label"
    rm -rf "$tdir"
    mkdir -p "$tdir"
    cp "$target_src" "$tdir/tampered.bin"
    flip_bit_file "$tdir/tampered.bin" "$byte_off"

    # 1. Verify om_lock_gen rejects with exact exit code.
    set +e
    case "$target_var" in
        OMEGA_TRACE_SRC_OM)
            "$WORK/om_lock_gen" verify "$WORK/OMEGA_TRACE.lock" \
                "$tdir/tampered.bin" "$OMC" "$WORK/sample_unit.egp3" \
                "$RT/proof/TraceBridge.lean" "$WORK/sample_unit.ompk" \
                "$WORK/sample_unit.bin" "$WORK/omega_trace_native.c" "$WORK/omega_trace_native.o" \
                2>"$tdir/ver.err"
            vrc=$?
            ;;
        OMEGA_TRACE_UNIT_OBJ)
            "$WORK/om_lock_gen" verify "$WORK/OMEGA_TRACE.lock" \
                "$RT/sample_unit.om" "$OMC" "$WORK/sample_unit.egp3" \
                "$RT/proof/TraceBridge.lean" "$WORK/sample_unit.ompk" \
                "$WORK/sample_unit.bin" "$WORK/omega_trace_native.c" "$tdir/tampered.bin" \
                2>"$tdir/ver.err"
            vrc=$?
            ;;
        OMEGA_TRACE_EGP3)
            "$WORK/om_lock_gen" verify "$WORK/OMEGA_TRACE.lock" \
                "$RT/sample_unit.om" "$OMC" "$tdir/tampered.bin" \
                "$RT/proof/TraceBridge.lean" "$WORK/sample_unit.ompk" \
                "$WORK/sample_unit.bin" "$WORK/omega_trace_native.c" "$WORK/omega_trace_native.o" \
                2>"$tdir/ver.err"
            vrc=$?
            ;;
        OMEGA_TRACE_LEAN)
            "$WORK/om_lock_gen" verify "$WORK/OMEGA_TRACE.lock" \
                "$RT/sample_unit.om" "$OMC" "$WORK/sample_unit.egp3" \
                "$tdir/tampered.bin" "$WORK/sample_unit.ompk" \
                "$WORK/sample_unit.bin" "$WORK/omega_trace_native.c" "$WORK/omega_trace_native.o" \
                2>"$tdir/ver.err"
            vrc=$?
            ;;
        OMEGA_TRACE_OMPK)
            "$WORK/om_lock_gen" verify "$WORK/OMEGA_TRACE.lock" \
                "$RT/sample_unit.om" "$OMC" "$WORK/sample_unit.egp3" \
                "$RT/proof/TraceBridge.lean" "$tdir/tampered.bin" \
                "$WORK/sample_unit.bin" "$WORK/omega_trace_native.c" "$WORK/omega_trace_native.o" \
                2>"$tdir/ver.err"
            vrc=$?
            ;;
        *)
            echo "FAIL: unknown target_var $target_var" >&2
            exit 2
            ;;
    esac
    set -e
    if [ "$vrc" -ne "$expect_code" ]; then
        echo "FAIL control $label: expected om_lock_gen exit $expect_code, got $vrc" >&2
        cat "$tdir/ver.err" >&2
        exit 1
    fi

    # 2. Verify cargo build --offline fails closed via build.rs!
    set +e
    env DO_NOT_TRACK=1 DISABLE_TELEMETRY=1 \
        OMEGA_TRACE_WORK_DIR="$WORK" \
        OMEGA_OMC="$OMC" \
        "$target_var=$tdir/tampered.bin" \
        CARGO_TARGET_DIR="$tdir/target" \
        cargo build --offline --manifest-path "$RT/crate/Cargo.toml" \
        >"$tdir/cargo.out" 2>"$tdir/cargo.err"
    crc=$?
    set -e
    if [ "$crc" -eq 0 ]; then
        echo "FAIL control $label: cargo build unexpectedly succeeded on 1-bit tamper!" >&2
        exit 1
    fi
    if ! grep -q "FAIL-CLOSED: pure-Omega lock verification refused build (exit $expect_code)" "$tdir/cargo.err"; then
        echo "FAIL control $label: cargo build failed without expected FAIL-CLOSED exit $expect_code message" >&2
        cat "$tdir/cargo.err" >&2
        exit 1
    fi
    echo "CONTROL PASS [$label]: 1-bit tamper caught by om_lock_gen (exit $vrc) AND cargo build.rs (FAIL-CLOSED)"
    rm -rf "$tdir"
}

run_tamper_control "source_om_1bit" "OMEGA_TRACE_SRC_OM" "$RT/sample_unit.om" 12 101
run_tamper_control "binary_obj_1bit" "OMEGA_TRACE_UNIT_OBJ" "$WORK/omega_trace_native.o" 64 106
run_tamper_control "egp3_proof_1bit" "OMEGA_TRACE_EGP3" "$WORK/sample_unit.egp3" 40 103
run_tamper_control "lean_proof_1bit" "OMEGA_TRACE_LEAN" "$RT/proof/TraceBridge.lean" 32 104
run_tamper_control "ompk_semid_1bit" "OMEGA_TRACE_OMPK" "$WORK/sample_unit.ompk" 140 105

echo "=== OMEGA_RUST_TRACE GATE PASS (Lean4 + OM-2 + ABI-v2 + cargo test debug/release + 5 build-time tamper controls) ==="
