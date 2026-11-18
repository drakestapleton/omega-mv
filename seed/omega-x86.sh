#!/bin/sh
# omega-x86.sh -- build the x86-64 Linux omc from the seeded compiler and stop.
# The seed ladder (seed/omega-from-seed.sh) ends in an AArch64 program,
# seed/out/omc. This script has that compiler emit itself for `target x86linux`,
# then makes the x86-64 result prove three things:
#   1. it is what the pinned hash says (seed/out/omc-x86_64.sha256);
#   2. it rebuilds itself to the same bytes, twice (x86 fixpoint);
#   3. asked for the default target, it emits seed/out/omc byte for byte
#      (the compiler's output does not depend on which processor hosts it).
# No C, gcc, as or ld writes a byte of the result. It is not a seed0 chain on
# x86: the first x86 compiler is emitted by the AArch64 one.
#
# Run from the repo root:  sh seed/omega-x86.sh
# Works on an x86-64 or an AArch64 Linux host. The other architecture's
# programs run under a user emulator and every line says which side was
# NATIVE and which was EMULATED:
#   QEMU_A64  (default qemu-aarch64-static, then qemu-aarch64)  on x86-64
#   QEMU_X86  (default qemu-x86_64-static, then qemu-x86_64)    on AArch64
# Exit: 0 all checks agree; 1 a check failed; 3 no emulator for the other side.
# The compiler is left at build/seed/x86/omc-x86_64 (not tracked).
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$R"
B=build/seed/x86
mkdir -p "$B"
SRC=seed/omc/omc.om
PIN=seed/out/omc-x86_64.sha256

bad() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
sha() { sha256sum "$1" | cut -d' ' -f1; }
pick() { for c in "$@"; do if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return 0; fi; done; return 1; }

case "$(uname -m)" in
x86_64|amd64)
    A64=${QEMU_A64:-$(pick qemu-aarch64-static qemu-aarch64 || true)}; X86=
    [ -n "$A64" ] || { echo "BLOCKED: no AArch64 user emulator (set QEMU_A64)" >&2; exit 3; }
    MA=EMULATED; MX=NATIVE ;;
aarch64|arm64)
    X86=${QEMU_X86:-$(pick qemu-x86_64-static qemu-x86_64 || true)}; A64=
    [ -n "$X86" ] || { echo "BLOCKED: no x86-64 user emulator (set QEMU_X86)" >&2; exit 3; }
    MA=NATIVE; MX=EMULATED ;;
*) echo "BLOCKED: host $(uname -m) is neither x86-64 nor AArch64" >&2; exit 3 ;;
esac
printf 'host %s: AArch64 programs %s, x86-64 programs %s\n' "$(uname -m)" "$MA" "$MX"

# 0. The seeded AArch64 compiler is the committed one.
want=$(cut -d' ' -f1 seed/out/omc.sha256)
[ "$(sha seed/out/omc)" = "$want" ] || bad "seed/out/omc is not $want"

# 1. It emits itself for x86-64.
{ printf 'target x86linux\n'; cat "$SRC"; } > "$B/omc-x86.om"
$A64 seed/out/omc < "$B/omc-x86.om" > "$B/stage1" || bad "AArch64 omc refused the x86 build"
chmod +x "$B/stage1"
s1=$(sha "$B/stage1")
printf 'PASS x86 omc emitted by the AArch64 omc (%s), %s bytes\n' "$MA" "$(wc -c < "$B/stage1")"

# 2. The x86 compiler rebuilds itself, twice.
$X86 "$B/stage1" < "$B/omc-x86.om" > "$B/stage2" || bad "x86 omc refused its own source"
chmod +x "$B/stage2"
$X86 "$B/stage2" < "$B/omc-x86.om" > "$B/stage3" || bad "x86 omc stage2 refused its own source"
chmod +x "$B/stage3"
s2=$(sha "$B/stage2"); s3=$(sha "$B/stage3")
[ "$s2" = "$s3" ] || bad "x86 fixpoint: stage2 $s2 != stage3 $s3"
[ "$s1" = "$s2" ] || bad "parents differ: AArch64-built $s1 != x86-built $s2"
printf 'PASS x86 omc fixpoint %s (%s)\n' "$s3" "$MX"

# 3. Hosted on x86, it still emits the AArch64 compiler byte for byte.
$X86 "$B/stage3" < "$SRC" > "$B/a64.from-x86" || bad "x86 omc refused the default-target build"
[ "$(sha "$B/a64.from-x86")" = "$want" ] || bad "x86-hosted omc emits a different AArch64 omc: $(sha "$B/a64.from-x86")"
printf 'PASS x86-hosted omc emits seed/out/omc byte for byte (%s)\n' "$MX"

# 4. One program through the x86 compiler, run on x86: forward calls, exit 7.
{ printf 'target x86linux\n'; cat seed/rung4/tests/r5b_fwd.om; } > "$B/fwd.om"
$X86 "$B/stage3" < "$B/fwd.om" > "$B/fwd.bin" || bad "x86 omc refused r5b_fwd"
chmod +x "$B/fwd.bin"
set +e; $X86 "$B/fwd.bin" >/dev/null; run=$?; set -e
[ "$run" = 7 ] || bad "fwd ran as $run on x86, wanted 7"
printf 'PASS fwd compiled by the x86 omc runs on x86, exit 7 (%s)\n' "$MX"

# 5. The pin. A missing pin is not a pass.
[ -s "$PIN" ] || bad "no pin at $PIN (expected $s3)"
[ "$(cut -d' ' -f1 "$PIN")" = "$s3" ] || bad "pin $(cut -d' ' -f1 "$PIN") != built $s3"
cp "$B/stage3" "$B/omc-x86_64"; chmod +x "$B/omc-x86_64"
printf 'PASS pin %s  %s\n' "$s3" "$B/omc-x86_64"
echo "RC=0"
