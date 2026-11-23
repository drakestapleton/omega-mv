#!/bin/sh
# seed/helix/strand5_polyglot/cross_x86_ddc.sh -- Strand E ("The Polyglot"):
# Cross-ISA Diverse Double-Compiling (AArch64 <-> x86-64) and True x86-64 Self-Hosting Fixpoint.
#
# Verifies:
#   1. AArch64 omc self-rebuild fixpoint: omc(omc.om) -> omc_a64; omc_a64(omc.om) == omc_a64.
#   2. Cross-compilation to x86-64 Linux ELF using run-time pools (`global a_ar ulong *`, `enlarge`):
#        { printf 'target x86linux\n'; cat seed/omc/omc.om; } | omc_a64 > omc_x86
#      (If OMC_B is set, cross-checks x86-64 emission byte-for-byte across both independent compilers.)
#   3. Negative control: `target x86efi` still refuses run-time pools (`global p ulong *`) with exit 25.
#   4. When qemu-x86_64 is present (e.g. DGX Spark CPU, zero GPU):
#      - Cross-ISA DDC: qemu-x86_64 omc_x86 < seed/omc/omc.om == omc_a64 (BIT-FOR-BIT!)
#      - True x86-64 self-hosting fixpoint: qemu-x86_64 omc_x86 < omc_x86.om == omc_x86 (BIT-FOR-BIT!)
#      - x86-64 run-time pool semantics: enlarge growth (mmap + mremap), n <= len, 2^63 overflow (-22),
#        len, read/write on pool, and out-of-bounds trap 3 (exit 103).
#      When qemu-x86_64 is absent, x86 execution is skipped gracefully with clear status.
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
cd "$R"

OMC=${OMC:-seed/out/omc}
OMC_B=${OMC_B:-}
QEMU_X86_64=${QEMU_X86_64:-qemu-x86_64}
B=${BUILD_DIR:-build/strand5_polyglot/cross_x86_ddc}

bad() { printf 'CROSS_X86_DDC FAIL: %s\n' "$*" >&2; exit 1; }
sha() { sha256sum "$1" | cut -d' ' -f1; }

[ "$(uname -s)" = Linux ] && [ "$(uname -m)" = aarch64 ] || {
  printf 'CROSS_X86_DDC NOT_RUN: requires Linux AArch64 host (got %s %s)\n' "$(uname -s)" "$(uname -m)"
  exit 3
}
[ -x "$OMC" ] || bad "compiler OMC=$OMC not executable"

rm -rf "$B"
mkdir -p "$B"

printf '=== [1/4] AArch64 SELF-REBUILD FIXPOINT ===\n'
"$OMC" < seed/omc/omc.om > "$B/omc_a64_s1" 2> "$B/s1.err" || bad "OMC failed on omc.om: $(cat "$B/s1.err")"
chmod +x "$B/omc_a64_s1"
"$B/omc_a64_s1" < seed/omc/omc.om > "$B/omc_a64" 2> "$B/s2.err" || bad "s1 failed on omc.om: $(cat "$B/s2.err")"
chmod +x "$B/omc_a64"
cmp -s "$B/omc_a64_s1" "$B/omc_a64" || bad "AArch64 fixpoint failed (s1 != s2)"
HA64=$(sha "$B/omc_a64")
printf '  PASS AArch64 omc fixpoint: %s (%s bytes)\n' "$HA64" "$(wc -c < "$B/omc_a64" | tr -d ' ')"

printf '=== [2/4] CROSS-COMPILE target x86linux omc_x86 ===\n'
{ printf 'target x86linux\n'; cat seed/omc/omc.om; } > "$B/omc_x86.om"
"$B/omc_a64" < "$B/omc_x86.om" > "$B/omc_x86" 2> "$B/x86.err" || bad "target x86linux omc compile failed: $(cat "$B/x86.err")"
chmod +x "$B/omc_x86"
HX86=$(sha "$B/omc_x86")

# Check ELF64 LE EM_X86_64 header bytes (0..5 = 7f 45 4c 46 02 01, 18..19 = 3e 00)
hdr=$(od -An -tx1 -N 20 "$B/omc_x86" | tr -s ' \n' ' ' | sed 's/^ //; s/ $//')
case "$hdr" in
  "7f 45 4c 46 02 01 "*" 3e 00") ;;
  *) bad "omc_x86 ELF header is not ELF64 LE x86-64: $hdr" ;;
esac
printf '  PASS x86-64 ELF-64 built: %s (%s bytes)\n' "$HX86" "$(wc -c < "$B/omc_x86" | tr -d ' ')"

if [ -n "$OMC_B" ]; then
  [ -x "$OMC_B" ] || bad "OMC_B=$OMC_B not executable"
  "$OMC_B" < "$B/omc_x86.om" > "$B/omc_x86_B" 2> "$B/x86_B.err" || bad "OMC_B failed on omc_x86.om: $(cat "$B/x86_B.err")"
  cmp -s "$B/omc_x86" "$B/omc_x86_B" || bad "omc_x86 diverged between OMC and OMC_B"
  printf '  PASS OMC vs OMC_B x86-64 output bit-identical\n'
fi

printf '=== [3/4] NEGATIVE CONTROL: target x86efi REFUSES RUN-TIME POOLS (exit 25) ===\n'
cat > "$B/efi_pool.om" <<'EOF'
target x86efi
global p ulong *
fn main to int
ret 0
end
EOF
set +e
"$B/omc_a64" < "$B/efi_pool.om" > "$B/efi_pool.efi" 2> "$B/efi_pool.err"
erc=$?
set -e
[ "$erc" -eq 25 ] || bad "expected target x86efi pool refusal exit 25, got $erc"
printf '  PASS target x86efi refused global pool with exit 25\n'

printf '=== [4/4] CROSS-ISA DDC & x86-64 SELF-HOSTING UNDER %s ===\n' "$QEMU_X86_64"
if ! command -v "$QEMU_X86_64" >/dev/null 2>&1; then
  printf 'CROSS_X86_DDC SKIP_QEMU: %s not found; cross-compile verified (a64=%s x86=%s)\n' \
    "$QEMU_X86_64" "$HA64" "$HX86"
  exit 0
fi

# 4a. Cross-ISA DDC: x86-64 omc compiles AArch64 omc -> bit-identical to AArch64-built omc!
"$QEMU_X86_64" "$B/omc_x86" < seed/omc/omc.om > "$B/omc_from_x86" 2> "$B/ddc.err" || \
  bad "qemu-x86_64 omc_x86 failed compiling AArch64 omc.om: $(cat "$B/ddc.err")"
cmp -s "$B/omc_from_x86" "$B/omc_a64" || bad "Cross-ISA DDC mismatch: x86_64(omc.om) != aarch64(omc.om)"
printf '  PASS Cross-ISA DDC: x86_64(omc.om) == aarch64(omc.om) (%s)\n' "$HA64"

# 4b. True x86-64 self-hosting fixpoint: x86-64 omc compiles itself -> bit-identical!
"$QEMU_X86_64" "$B/omc_x86" < "$B/omc_x86.om" > "$B/omc_x86_2" 2> "$B/x86_s2.err" || \
  bad "qemu-x86_64 omc_x86 failed self-hosting x86linux omc: $(cat "$B/x86_s2.err")"
cmp -s "$B/omc_x86" "$B/omc_x86_2" || bad "x86-64 self-hosting fixpoint mismatch (omc_x86 != omc_x86_2)"
printf '  PASS x86-64 self-hosting fixpoint: omc_x86(omc_x86.om) == omc_x86 (%s)\n' "$HX86"

# 4c. x86-64 run-time pool semantics (enlarge mmap/mremap, n<=len, overflow -22, read/write, trap 3)
cat > "$B/pool_ok.om" <<'EOF'
target x86linux
global p ulong *
global b uchar *
fn main to int
if ne len p 0
ret 1
end
r = enlarge p 10
if ne r 0
ret 2
end
if ne len p 10
ret 3
end
put p 0 111
put p 9 999
r = enlarge p 5
if ne r 0
ret 4
end
if ne len p 10
ret 5
end
r = enlarge p 1152921504606846976
if ne r -22
ret 6
end
if ne len p 10
ret 7
end
r = enlarge p 2000
if ne r 0
ret 8
end
if ne len p 2000
ret 9
end
if or ne get p 0 111 ne get p 9 999
ret 10
end
if ne get p 1999 0
ret 11
end
put p 1999 424242
if ne get p 1999 424242
ret 12
end
r = enlarge b 16
if ne r 0
ret 13
end
k = read 0 b 0 4
if ne k 4
ret 14
end
k = write 1 b 0 4
if ne k 4
ret 15
end
ret 0
end
EOF
"$B/omc_a64" < "$B/pool_ok.om" > "$B/pool_ok" && chmod +x "$B/pool_ok"
out=$(printf 'OMX8' | "$QEMU_X86_64" "$B/pool_ok") || bad "x86 pool_ok exited non-zero"
[ "$out" = "OMX8" ] || bad "x86 pool_ok read/write output '$out' != 'OMX8'"

cat > "$B/pool_oob.om" <<'EOF'
target x86linux
global p ulong *
fn main to int
r = enlarge p 8
if ne r 0
ret 1
end
v = get p 8
ret int and v 255
end
EOF
"$B/omc_a64" < "$B/pool_oob.om" > "$B/pool_oob" && chmod +x "$B/pool_oob"
set +e
"$QEMU_X86_64" "$B/pool_oob"
oob_rc=$?
set -e
[ "$oob_rc" -eq 103 ] || bad "x86 pool OOB expected trap 3 (exit 103), got $oob_rc"
printf '  PASS x86-64 run-time pools (mmap/mremap/n<=len/overflow -22/read+write/OOB trap 103)\n'

printf '\nCROSS_X86_DDC PASS a64=%s x86=%s ddc=EXACT self_host=EXACT pools=PASS\n' "$HA64" "$HX86"
