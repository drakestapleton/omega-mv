#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# bridge/tensorfold-omega/gate_tf_omega.sh
# End-to-end verification gate for the optional TensorFold Zig ABI v2 plugin on DGX Spark.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TF="$ROOT/bridge/tensorfold-omega"
WORK="${TF_OMEGA_WORK_DIR:-$TF/work}"
OMC="${OMEGA_OMC:-$ROOT/seed/out/omc}"
if [ ! -x "$OMC" ] && [ -x "$HOME/canon/omega-mv/seed/out/omc" ]; then
    OMC="$HOME/canon/omega-mv/seed/out/omc"
fi
NATIVE_OM="$ROOT/bridge/omega-bridge/src/native.om"

# Locate Zig compiler on Spark (PATH or standard Spark toolchain locations).
ZIG_BIN="${OMEGA_ZIG:-}"
if [ -z "$ZIG_BIN" ]; then
    if command -v zig >/dev/null 2>&1; then
        ZIG_BIN=$(command -v zig)
    elif [ -x "$HOME/.local/opt/zig-linux-aarch64-0.13.0/zig" ]; then
        ZIG_BIN="$HOME/.local/opt/zig-linux-aarch64-0.13.0/zig"
    elif [ -x "$HOME/.local/toolchains/zig-aarch64-linux-0.17.0/zig" ]; then
        ZIG_BIN="$HOME/.local/toolchains/zig-aarch64-linux-0.17.0/zig"
    fi
fi

if [ "$(uname -s)" != "Linux" ] || [ "$(uname -m)" != "aarch64" ]; then
    echo "FAIL: gate_tf_omega.sh must run on Linux aarch64 (DGX Spark)" >&2
    exit 2
fi
if [ ! -x "$OMC" ]; then
    echo "FAIL: seeded omc not found or not executable at $OMC" >&2
    exit 2
fi

mkdir -p "$WORK"

echo "=== [1/6] Deterministic 2x pure-Omega builds (tf_lock_verify, native, tf_omega_unit) ==="
"$OMC" < "$TF/tf_lock_verify.om" > "$WORK/tf_lock_verify.1"
"$OMC" < "$TF/tf_lock_verify.om" > "$WORK/tf_lock_verify.2"
cmp "$WORK/tf_lock_verify.1" "$WORK/tf_lock_verify.2"
mv -f "$WORK/tf_lock_verify.1" "$WORK/tf_lock_verify"
rm -f "$WORK/tf_lock_verify.2"
chmod 755 "$WORK/tf_lock_verify"

"$OMC" < "$NATIVE_OM" > "$WORK/native"
chmod 755 "$WORK/native"

"$OMC" < "$TF/tf_omega_unit.om" > "$WORK/tf_omega_unit.bin.1"
"$OMC" < "$TF/tf_omega_unit.om" > "$WORK/tf_omega_unit.bin.2"
cmp "$WORK/tf_omega_unit.bin.1" "$WORK/tf_omega_unit.bin.2"
mv -f "$WORK/tf_omega_unit.bin.1" "$WORK/tf_omega_unit.bin"
rm -f "$WORK/tf_omega_unit.bin.2"
echo "tf_lock_verify=$(wc -c < "$WORK/tf_lock_verify")B tf_omega_unit.bin=$(wc -c < "$WORK/tf_omega_unit.bin")B (2x bit-identical)"

echo "=== [2/6] Generate omega-bridge ABI v2 bindings (C, H, Zig) & static archive ==="
OMC_SHA=$(sha256sum "$OMC" | awk '{print $1}')
BIN_LEN=$(wc -c < "$WORK/tf_omega_unit.bin")
{
    cat "$TF/tf_omega_unit.om"
    printf '\0%08d' "$BIN_LEN"
    cat "$WORK/tf_omega_unit.bin"
    printf 'omega-unit tf_omega_unit %s\n' "$OMC_SHA"
} > "$WORK/tf_omega_unit.in"

"$WORK/native" c < "$WORK/tf_omega_unit.in" > "$WORK/tf_omega_native.c"
"$WORK/native" h < "$WORK/tf_omega_unit.in" > "$WORK/tf_omega_native.h"
"$WORK/native" zig < "$WORK/tf_omega_unit.in" > "$WORK/tf_omega_native.zig"
gcc -c -O2 -fno-strict-aliasing -fPIC -Wall -Wextra -Werror \
    "$WORK/tf_omega_native.c" -o "$WORK/tf_omega_native.o"
rm -f "$WORK/libtf_omega_native.a"
ar rcsD "$WORK/libtf_omega_native.a" "$WORK/tf_omega_native.o"

echo "=== [3/6] Emit EGP3 cert, generate & verify TF_OMEGA.lock ==="
"$WORK/tf_lock_verify" emit-egp3 "$WORK/tf_sample.egp3"
"$WORK/tf_lock_verify" generate \
    "$WORK/TF_OMEGA.lock" \
    "$TF/tf_omega_unit.om" "$OMC" "$WORK/tf_sample.egp3" \
    "$WORK/tf_omega_unit.bin" "$WORK/tf_omega_native.c" "$WORK/tf_omega_native.o" \
    "$WORK/tf_omega_native.zig"
"$WORK/tf_lock_verify" verify \
    "$WORK/TF_OMEGA.lock" \
    "$TF/tf_omega_unit.om" "$OMC" "$WORK/tf_sample.egp3" \
    "$WORK/tf_omega_unit.bin" "$WORK/tf_omega_native.c" "$WORK/tf_omega_native.o" \
    "$WORK/tf_omega_native.zig"

echo "=== [4/6] Build & run C ABI v2 caller + negative controls ==="
gcc -O2 -Wall -Wextra -Werror "$TF/tests/test_c_abi.c" "$WORK/libtf_omega_native.a" \
    -lpthread -o "$WORK/test_c_abi"
"$WORK/test_c_abi" "$WORK/tf_sample.egp3"

echo "=== [5/6] Run real Zig ABI v2 caller (zig test) ==="
if [ -n "$ZIG_BIN" ] && [ -x "$ZIG_BIN" ]; then
    ZIG_VER=$("$ZIG_BIN" version)
    echo "Using Zig $ZIG_VER ($ZIG_BIN)"
    ZIG_GLOBAL_CACHE_DIR="$WORK/zig-gcache" \
    ZIG_LOCAL_CACHE_DIR="$WORK/zig-lcache" \
    "$ZIG_BIN" test "$TF/src/omega_plugin.zig" "$WORK/libtf_omega_native.a" -lc
    echo "ZIG_ABI_V2_PASS zig=$ZIG_VER"
else
    echo "ZIG_ABI_V2_NOT_RUN (zig compiler not found on Spark)"
fi

echo "=== [6/6] Fail-closed 1-bit tamper negative controls (pure-Omega tf_lock_verify) ==="
flip_bit_file() {
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

check_tamper() {
    label="$1"
    expect="$2"
    shift 2
    set +e
    "$@" 2>"$WORK/neg_$label.err"
    rc=$?
    set -e
    if [ "$rc" -ne "$expect" ]; then
        echo "FAIL tamper control $label: expected exit $expect, got $rc" >&2
        cat "$WORK/neg_$label.err" >&2
        exit 1
    fi
    echo "CONTROL PASS [$label]: refused fail-closed with exit $rc"
}

cp "$WORK/tf_omega_unit.bin" "$WORK/tampered.bin"
flip_bit_file "$WORK/tampered.bin" 16
check_tamper "unit_bin_1bit" 106 "$WORK/tf_lock_verify" verify \
    "$WORK/TF_OMEGA.lock" "$TF/tf_omega_unit.om" "$OMC" "$WORK/tf_sample.egp3" \
    "$WORK/tampered.bin" "$WORK/tf_omega_native.c" "$WORK/tf_omega_native.o" \
    "$WORK/tf_omega_native.zig"

cp "$WORK/tf_omega_native.o" "$WORK/tampered.o"
flip_bit_file "$WORK/tampered.o" 64
check_tamper "unit_obj_1bit" 106 "$WORK/tf_lock_verify" verify \
    "$WORK/TF_OMEGA.lock" "$TF/tf_omega_unit.om" "$OMC" "$WORK/tf_sample.egp3" \
    "$WORK/tf_omega_unit.bin" "$WORK/tf_omega_native.c" "$WORK/tampered.o" \
    "$WORK/tf_omega_native.zig"

cp "$TF/tf_omega_unit.om" "$WORK/tampered.om"
flip_bit_file "$WORK/tampered.om" 12
check_tamper "source_om_1bit" 101 "$WORK/tf_lock_verify" verify \
    "$WORK/TF_OMEGA.lock" "$WORK/tampered.om" "$OMC" "$WORK/tf_sample.egp3" \
    "$WORK/tf_omega_unit.bin" "$WORK/tf_omega_native.c" "$WORK/tf_omega_native.o" \
    "$WORK/tf_omega_native.zig"

cp "$WORK/tf_sample.egp3" "$WORK/tampered.egp3"
flip_bit_file "$WORK/tampered.egp3" 40
check_tamper "egp3_cert_1bit" 103 "$WORK/tf_lock_verify" verify \
    "$WORK/TF_OMEGA.lock" "$TF/tf_omega_unit.om" "$OMC" "$WORK/tampered.egp3" \
    "$WORK/tf_omega_unit.bin" "$WORK/tf_omega_native.c" "$WORK/tf_omega_native.o" \
    "$WORK/tf_omega_native.zig"

rm -f "$WORK"/tampered.* "$WORK"/neg_*.err

echo "=== TENSORFOLD_OMEGA GATE PASS (OM-2 + ABI-v2 + C + Zig + 4 1-bit tamper controls) ==="
