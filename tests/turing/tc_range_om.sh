#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Drake Stapleton (AIEN / aien-dev)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# tests/turing/tc_range_om.sh: gate glue for the Omega range coder src/turing/tc_range.om (L111).
# POSIX sh, sequencing only (disclosed host glue, as tests/turing/origsel-run.sh): it builds the
# unit with the repository's own seed/out/omc, runs it next to the C reference turing-coder and
# compares bytes and exit codes. Every length number and the bound verdict come from tc_range.om.
#   usage: sh tests/turing/tc_range_om.sh <turing-coder> <out-dir>
# Checks, each printed PASS/FAIL, any FAIL exits 1:
#  1 build; 2 selftest (synthetic round trips, length identity, upper and lower bound, one random
#    flipped payload byte per case detected, exhaustive ub rule check);
#  3 for 2 committed traces x 7 models: Omega encode byte-identical to C, C verifies the Omega
#    file, Omega verifies the C file, Omega decode byte-identical to the TSY1, ideal_ub equal,
#    bound=PASS;
#  4 single-fault inputs: Omega and the C reference refuse with the same CODER_SPEC s.10 name
#    (flipped payload byte, truncated, trailing byte, other TPS1, altered magic, corrupted TPS1,
#    TSY1 of another trace, corrupted TSY1); a refusal after the output exists removes it; an
#    output path naming an input is refused and the input is left intact; usage;
#  4b n = 1152514738907 (cap+1) refuses ARG. The file is a digest-valid 160-byte TPS1, not a
#    terabyte body. A sibling with n = 1 and the same shape refuses FORMAT, so a size-check
#    miss is not counted as the cap. `selftest overflow` raises ALARM 7 on the wrapping sum.
#  4c ofinish: a forced fsync failure (seccomp EIO on fsync/fdatasync; compile-time
#    AUDIT_ARCH_X86_64 / AUDIT_ARCH_AARCH64 and __NR_fsync/__NR_fdatasync) refuses
#    IO (102) and removes the partial output only if rc is 2 and the IO line is
#    present; a SIGSYS or other rc with no file must not PASS. A mutant that
#    clears the open flag before that check leaves the file.
#  5 mutants that must fail: range >> 15 on every real unit (exit 0 and bytes differ from C, or
#    exit 3 from an ALARM; a refusal of every unit is a failed mutant), decoder renorm count
#    doubled (ALARM 1 on verify, the decode still finishes), upper-bound constants, ub rounding,
#    lower-bound constant, ofinish flag-clear order;
#  6 Lean: docs/turing/proofs/TcrBound.lean checks with the pinned toolchain, 10 theorems, no
#    sorry, standard axioms only (lean found as $LEAN, on PATH or in ~/.elan/bin; missing = FAIL).
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TC=$1
OUT=$2
OMC=${OMC:-$ROOT/seed/out/omc}
mkdir -p "$OUT"
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

build() { # build <src.om> <exe>
  { printf 'om2\n'; cat "$ROOT/seed/ng/sha256.om" "$1"; } > "$2.unit.om"
  "$OMC" < "$2.unit.om" > "$2" 2> "$2.err" || return 1
  chmod +x "$2"
}
expect_rc() { # expect_rc <name> <want> <cmd...>
  name=$1; want=$2; shift 2
  "$@" > "$OUT/last.out" 2> "$OUT/last.err"; rc=$?
  if [ "$rc" -eq "$want" ]; then pass "$name (exit $rc: $(head -c 120 "$OUT/last.err"))"
  else fail "$name: exit $rc, want $want"; fi
}

echo "omc sha256 $(sha256sum "$OMC" | cut -d' ' -f1)"
B=$OUT/tcr-om
if build "$ROOT/src/turing/tc_range.om" "$B"; then pass "build"; else fail "build: $(cat "$B.err")"; exit 1; fi

if "$B" selftest > "$OUT/selftest.txt" 2>&1 && grep -q '^selftest=PASS$' "$OUT/selftest.txt"; then
  pass "selftest $(head -n 1 "$OUT/selftest.txt")"
else fail "selftest: $(cat "$OUT/selftest.txt")"; fi

Z=0000000000000000000000000000000000000000000000000000000000000000
C=$ROOT/calibration/experiments/EXP-001/candidates
i=0
for TR in tests/turing/fixtures/ctr1_seed1_crumbs05-07.ctr tests/turing/fixtures/ctr1_seed1_crumbs10-12.ctr; do
  for M in evidence/TURING_YIELD/ty2_candidate.tym uniform:9 $C/B0_uniform.tym $C/B1_order0.tym \
           $C/B2_order1.tym $C/B3_heuristic.tym $C/M_candidate.tym; do
    i=$((i + 1)); D=$OUT/u$i; mkdir -p "$D"
    case $M in uniform:*) MP=$M ;; /*) MP=$M ;; *) MP=$ROOT/$M ;; esac
    if ! "$TC" pstream "$MP" $Z "$ROOT/$TR" "$D/s.tps" "$D/s.tsy" > "$D/pstream.txt" 2>&1; then
      fail "unit $i pstream ($TR $M)"; continue; fi
    "$TC" encode range "$D/s.tps" "$D/s.tsy" "$D/c.tcr" > /dev/null 2>&1 || fail "unit $i C encode"
    if "$B" encode range "$D/s.tps" "$D/s.tsy" "$D/o.tcr" > "$D/enc.txt" 2> "$D/enc.err" \
       && grep -q '^bound=PASS$' "$D/enc.txt" && grep -q '^lower=PASS$' "$D/enc.txt"; then :; else fail "unit $i Omega encode: $(cat "$D/enc.err")"; continue; fi
    cmp -s "$D/o.tcr" "$D/c.tcr" || fail "unit $i Omega bytes differ from C"
    "$TC" verify range "$D/s.tps" "$D/s.tsy" "$D/o.tcr" > /dev/null 2>&1 || fail "unit $i C rejects the Omega file"
    "$B" verify range "$D/s.tps" "$D/s.tsy" "$D/c.tcr" > "$D/ver.txt" 2>&1 || fail "unit $i Omega rejects the C file"
    "$B" decode range "$D/s.tps" "$D/o.tcr" "$D/o.tsy" > /dev/null 2>&1 || fail "unit $i Omega decode"
    cmp -s "$D/o.tsy" "$D/s.tsy" || fail "unit $i decoded TSY1 differs"
    ci=$(sed -n 's/^ideal_ub=//p' "$D/pstream.txt"); oi=$(sed -n 's/^ideal_ub=//p' "$D/enc.txt")
    [ "$ci" = "$oi" ] || fail "unit $i ideal_ub C $ci Omega $oi"
    echo "unit $i n=$(sed -n 's/^count=//p' "$D/enc.txt") ideal_ub=$oi coded_bits=$(sed -n 's/^coded_bits=//p' "$D/enc.txt") slack_ub=$(sed -n 's/^slack_ub=//p' "$D/enc.txt") lower_ub=$(sed -n 's/^lower_ub=//p' "$D/enc.txt") $(basename "$TR") $(basename "$M")"
  done
done
[ "$fails" -eq 0 ] && pass "14 units: byte-identical to C both ways, decode exact, ideal_ub equal, bound=PASS, lower=PASS"

# Refusals (unit 1 files). Each input has one fault; the Omega refusal name must equal the C
# reference's (turing-coder prints TC_E_<NAME>) and both must exit 2.
D=$OUT/u1; N=$OUT/neg; mkdir -p "$N"
same_refusal() { # same_refusal <label> <want NAME> <args after the tool...>
  label=$1; want=$2; shift 2
  "$B" "$@" > "$N/o.out" 2> "$N/o.err"; orc=$?
  "$TC" "$@" > "$N/c.out" 2> "$N/c.err"; crc=$?
  on=$(sed -n 's/^tcr-om: refused -[0-9]* \([A-Z]*\) at .*/\1/p' "$N/o.err")
  cn=$(sed -n 's/.*TC_E_\([A-Z]*\).*/\1/p' "$N/c.err" | head -n 1)
  if [ "$orc" -eq 2 ] && [ "$crc" -eq 2 ] && [ "$on" = "$want" ] && [ "$cn" = "$want" ]; then
    pass "$label: Omega and C both refuse $want"
  else fail "$label: Omega exit $orc '$on', C exit $crc '$cn', want $want"; fi
}
sz=$(wc -c < "$D/o.tcr")
cp "$D/o.tcr" "$N/flip.tcr"; printf '\125' | dd of="$N/flip.tcr" bs=1 seek=$((sz - 3)) conv=notrunc 2> /dev/null
cmp -s "$N/flip.tcr" "$D/o.tcr" && fail "flip control did not change the file"
same_refusal "flipped payload byte (verify)" CORRUPT verify range "$D/s.tps" "$D/s.tsy" "$N/flip.tcr"
head -c $((sz - 1)) "$D/o.tcr" > "$N/trunc.tcr"
same_refusal "truncated file" TRUNC verify range "$D/s.tps" "$D/s.tsy" "$N/trunc.tcr"
{ cat "$D/o.tcr"; printf 'x'; } > "$N/trail.tcr"
same_refusal "trailing byte" TRAIL verify range "$D/s.tps" "$D/s.tsy" "$N/trail.tcr"
same_refusal "other TPS1" BINDING decode range "$OUT/u2/s.tps" "$D/o.tcr" "$N/x.tsy"
cp "$D/o.tcr" "$N/magic.tcr"; printf 'X' | dd of="$N/magic.tcr" bs=1 seek=0 conv=notrunc 2> /dev/null
same_refusal "altered magic" HEADER verify range "$D/s.tps" "$D/s.tsy" "$N/magic.tcr"
cp "$D/s.tps" "$N/bad.tps"; printf '\001' | dd of="$N/bad.tps" bs=1 seek=200 conv=notrunc 2> /dev/null
same_refusal "corrupted TPS1" DIGEST encode range "$N/bad.tps" "$D/s.tsy" "$N/y.tcr"
same_refusal "TSY1 of another trace" COUNT encode range "$D/s.tps" "$OUT/u8/s.tsy" "$N/z.tcr"
cp "$D/s.tsy" "$N/badsym.tsy"; printf '\001' | dd of="$N/badsym.tsy" bs=1 seek=60 conv=notrunc 2> /dev/null
same_refusal "corrupted TSY1" DIGEST verify range "$D/s.tps" "$N/badsym.tsy" "$D/o.tcr"
# A refusal after the output file was created must remove it (decode of the flipped file fails
# its termination check at the end of the stream, after symbols were written).
rm -f "$N/dflip.tsy"
expect_rc "decode refusal after the output was created" 2 "$B" decode range "$D/s.tps" "$N/flip.tcr" "$N/dflip.tsy"
grep -q 'refused -115 CORRUPT' "$OUT/last.err" || fail "decode of the flipped file: not CORRUPT"
[ -e "$N/dflip.tsy" ] && fail "a refused decode left its output file" || pass "refused decode removed its partial output"
# An output path naming an input is refused before anything is truncated.
cp "$D/s.tps" "$N/self.tps"; cp "$D/s.tps" "$N/self.ref"
expect_rc "output path = input refused" 2 "$B" encode range "$N/self.tps" "$D/s.tsy" "$N/self.tps"
grep -q 'refused -101 ARG' "$OUT/last.err" || fail "output = input: not ARG"
cmp -s "$N/self.tps" "$N/self.ref" && pass "input left intact" || fail "the input was changed or removed"
expect_rc "usage" 1 "$B" encode rans "$D/s.tps" "$D/s.tsy" "$N/w.tcr"
grep -q '^lower=PASS$' "$D/enc.txt" || fail "unit 1 has no lower=PASS line"

# ofinish fsync failure. A small seccomp wrapper makes fsync and fdatasync return EIO.
# The filter is compile-time arch-aware and lives in the generated fail_fsync.c:
#   #if defined(__x86_64__)     AUDIT_ARCH_X86_64
#   #elif defined(__aarch64__)  AUDIT_ARCH_AARCH64
#   #else #error
# and the syscall numbers are __NR_fsync / __NR_fdatasync from <sys/syscall.h>.
# On a native AArch64 host (Spark) that is the process arch and the AArch64
# syscall numbers. On x86_64, qemu-user translates the guest fsync to the host
# syscall, and the x86_64 wrapper catches that. Writes already succeeded, so
# this hits ofinish, not oflush. The open flag must still be set so cleanup
# unlinks the partial output.
# "removed the partial output" PASSes only after rc 2 AND a refused -102 IO
# line AND the file is gone. A SIGSYS (or any other rc) with no file must not
# PASS: that was the vacuous pass in Test Master R-07 when the x86-only filter
# killed the process before the file was created.
ofinish_removed_ok() { # ofinish_removed_ok <rc> <errfile> <outfile>
  [ "$1" -eq 2 ] && grep -q 'refused -102 IO' "$2" && [ ! -e "$3" ]
}
cat > "$N/fail_fsync.c" << 'C'
#define _GNU_SOURCE
#include <errno.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <stddef.h>
#include <stdio.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>
#if defined(__x86_64__)
#define FAIL_FSYNC_AUDIT_ARCH AUDIT_ARCH_X86_64
#elif defined(__aarch64__)
#define FAIL_FSYNC_AUDIT_ARCH AUDIT_ARCH_AARCH64
#else
#error "fail_fsync: only x86_64 and aarch64 are supported"
#endif
static int install(void) {
  struct sock_filter filter[] = {
    BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, arch)),
    BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, FAIL_FSYNC_AUDIT_ARCH, 1, 0),
    BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_KILL_PROCESS),
    BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
    BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_fsync, 0, 1),
    BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (EIO & 0xffff)),
    BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_fdatasync, 0, 1),
    BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (EIO & 0xffff)),
    BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
  };
  struct sock_fprog prog = { .len = (unsigned short)(sizeof filter / sizeof filter[0]), .filter = filter };
  if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0) return -1;
  return (int)syscall(__NR_seccomp, SECCOMP_SET_MODE_FILTER, 0, &prog);
}
int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: fail_fsync CMD [ARGS]\n"); return 127; }
  if (install() != 0) { perror("seccomp"); return 127; }
  execvp(argv[1], argv + 1);
  perror("exec");
  return 127;
}
C
if gcc -O2 -Wall -Werror -o "$OUT/fail_fsync" "$N/fail_fsync.c"; then
  rm -f "$N/fsync.tcr"
  expect_rc "ofinish fsync failure is IO" 2 "$OUT/fail_fsync" "$B" encode range "$D/s.tps" "$D/s.tsy" "$N/fsync.tcr"
  grep -q 'refused -102 IO' "$OUT/last.err" || fail "ofinish fsync failure: not IO ($(head -c 160 "$OUT/last.err"))"
  if ofinish_removed_ok "$rc" "$OUT/last.err" "$N/fsync.tcr"; then
    pass "ofinish fsync failure removed the partial output"
  else
    fail "ofinish fsync failure: rc=$rc file=$([ -e "$N/fsync.tcr" ] && echo present || echo absent) (need rc 2, IO, and no file)"
  fi
  # Vacuous-removal guard: SIGSYS (exit 159) with no output file must not PASS.
  # This is the R-07 shape (exit 159, no file, no IO line).
  rm -f "$N/sigsys.tcr"
  sh -c 'kill -s SYS $$' > "$N/sigsys.out" 2> "$N/sigsys.err"
  src=$?
  if ofinish_removed_ok "$src" "$N/sigsys.err" "$N/sigsys.tcr"; then
    fail "ofinish cleanup PASSed on exit $src with no IO refusal (vacuous removal)"
  else
    pass "SIGSYS or other non-IO exit does not count as ofinish cleanup (exit $src)"
  fi
else
  fail "fail_fsync wrapper did not compile"
fi

# Symbol-count cap. Both files are 128-byte headers plus a real trailer (160 bytes). n = 1
# still dies on the body-size check (FORMAT). n = cap+1 dies on the word cap (ARG), which is
# checked first so this does not require a terabyte of records.
python3 - "$N/n1.tps" 1 "$N/ncap.tps" 1152514738907 << 'PY'
import hashlib, struct, sys
def write(path, n):
    hdr = bytearray(128)
    hdr[0:4] = b"TPS1"
    struct.pack_into("<H", hdr, 4, 1)
    hdr[6] = 2
    hdr[7] = 16
    struct.pack_into("<Q", hdr, 12, n)
    struct.pack_into("<I", hdr, 20, 28)
    dig = hashlib.sha256(b"turing.tc.pstream.v1\x00" + bytes(hdr)).digest()
    with open(path, "wb") as f:
        f.write(bytes(hdr) + dig)
write(sys.argv[1], int(sys.argv[2]))
write(sys.argv[3], int(sys.argv[4]))
PY
expect_rc "n = 1 with no records still fails the size check" 2 "$B" encode range "$N/n1.tps" "$N/absent.tsy" "$N/n1.out"
grep -q 'refused -103 FORMAT' "$OUT/last.err" || fail "n = 1 header: not FORMAT ($(head -c 160 "$OUT/last.err"))"
expect_rc "n = cap+1 refused" 2 "$B" encode range "$N/ncap.tps" "$N/absent.tsy" "$N/ncap.out"
grep -q 'refused -101 ARG' "$OUT/last.err" || fail "n = cap+1: not ARG ($(head -c 160 "$OUT/last.err"))"
expect_rc "wrapping micro-bit sum raises the overflow alarm" 3 "$B" selftest overflow
grep -q 'would wrap' "$OUT/last.err" || fail "overflow alarm text missing ($(head -c 160 "$OUT/last.err"))"

# Mutants.
sed 's/^r = shr rg 16$/r = shr rg 15/' "$ROOT/src/turing/tc_range.om" > "$N/mut1.om"
cmp -s "$N/mut1.om" "$ROOT/src/turing/tc_range.om" && fail "mutant 1 did not change the source"
if build "$N/mut1.om" "$N/mut1"; then
  good=0; refused=0; other=0; i=1
  while [ "$i" -le 14 ]; do
    "$N/mut1" encode range "$OUT/u$i/s.tps" "$OUT/u$i/s.tsy" "$N/m1-$i.tcr" > "$N/m1-$i.out" 2> "$N/m1-$i.err"
    rc=$?
    if [ "$rc" -eq 0 ] && [ -f "$N/m1-$i.tcr" ] && ! cmp -s "$N/m1-$i.tcr" "$OUT/u$i/c.tcr"; then
      good=$((good + 1))
    elif [ "$rc" -eq 3 ] && grep -q 'tcr-om: ALARM \(length identity\|length bound\|lower bound\)' "$N/m1-$i.err"; then
      good=$((good + 1))
    elif [ "$rc" -eq 2 ]; then
      refused=$((refused + 1))
    else
      other=$((other + 1))
    fi
    i=$((i + 1))
  done
  if [ "$good" -ge 2 ]; then
    pass "coder mutant (range >> 15) caught on $good units (exit 0 and bytes differ, or exit 3 identity/bound alarm); refusals=$refused other=$other"
  else
    fail "coder mutant: good=$good refused=$refused other=$other (need a real difference or the bound alarm on more than unit 1; a total refusal is not a catch)"
  fi
else fail "mutant 1 build"; fi
# One renorm byte counted twice: the decode still consumes the payload, and ALARM 1 fires
# because shifts + 4 is no longer the payload. A binary that only refuses does not pass.
sed 's/^put DC 5 add get DC 5 1$/put DC 5 add get DC 5 2/' "$ROOT/src/turing/tc_range.om" > "$N/mut5.om"
cmp -s "$N/mut5.om" "$ROOT/src/turing/tc_range.om" && fail "decoder shift mutant did not change the source"
if build "$N/mut5.om" "$N/mut5"; then
  i=1
  while [ "$i" -le 2 ]; do
    expect_rc "decoder shift mutant alarms on unit $i" 3 "$N/mut5" verify range "$OUT/u$i/s.tps" "$OUT/u$i/s.tsy" "$OUT/u$i/c.tcr"
    grep -q 'length identity' "$OUT/last.err" || fail "decoder shift mutant unit $i: not the identity alarm ($(head -c 160 "$OUT/last.err"))"
    i=$((i + 1))
  done
else fail "decoder shift mutant build"; fi
sed 's/umul n 5647 480000000/umul n 0 470000000/' \
  "$ROOT/src/turing/tc_range.om" > "$N/mut2.om"
cmp -s "$N/mut2.om" "$ROOT/src/turing/tc_range.om" && fail "mutant 2 did not change the source"
if build "$N/mut2.om" "$N/mut2"; then
  expect_rc "bound mutant raises the ALARM" 3 "$N/mut2" encode range "$D/s.tps" "$D/s.tsy" "$N/m2.tcr"
else fail "mutant 2 build"; fi
sed 's/^ret shr add mul x 1000000 2147483648 32$/ret shr add mul x 1000000 0 32/' \
  "$ROOT/src/turing/tc_range.om" > "$N/mut3.om"
cmp -s "$N/mut3.om" "$ROOT/src/turing/tc_range.om" && fail "mutant 3 did not change the source"
if build "$N/mut3.om" "$N/mut3"; then
  expect_rc "ub rounding mutant fails the exhaustive ub check" 3 "$N/mut3" selftest
else fail "mutant 3 build"; fi
sed 's/^lw = uadd get ST 1 472000000$/lw = uadd get ST 1 482000000/' "$ROOT/src/turing/tc_range.om" > "$N/mut4.om"
cmp -s "$N/mut4.om" "$ROOT/src/turing/tc_range.om" && fail "mutant 4 did not change the source"
if build "$N/mut4.om" "$N/mut4"; then
  expect_rc "lower-bound mutant (10 bits too high) raises the ALARM" 3 "$N/mut4" encode range "$OUT/u2/s.tps" "$OUT/u2/s.tsy" "$N/m4.tcr"
else fail "mutant 4 build"; fi
# Old ofinish order: clear OS[4] after fclose, then refuse. The fsync-failure case must
# leave the output (cleanup sees the flag already clear). A binary that still unlinks
# does not catch the bug.
python3 - "$ROOT/src/turing/tc_range.om" "$N/mut6.om" << 'PY'
import sys
src = open(sys.argv[1]).read()
old = """fn ofinish to void
note Flush, fsync and close. Refuse IO (102) on fsync or fclose failure before clearing
note OS[4], so cleanup still unlinks the partial output. After a successful close,
note zero OS[0] so the stale descriptor is not reused by a later fclose.
oflush
f = int get OS 0
k = fsync f
z = fclose f
if lt k 0
refuse 102 0
end
if lt z 0
refuse 102 0
end
put OS 0 0
put OS 4 0
end
"""
new = """fn ofinish to void
oflush
f = int get OS 0
k = fsync f
z = fclose f
put OS 4 0
if lt k 0
refuse 102 0
end
end
"""
if old not in src:
    sys.stderr.write("ofinish block not found for the old-order mutant\n")
    sys.exit(1)
open(sys.argv[2], "w").write(src.replace(old, new, 1))
PY
cmp -s "$N/mut6.om" "$ROOT/src/turing/tc_range.om" && fail "ofinish old-order mutant did not change the source"
if [ -x "$OUT/fail_fsync" ] && build "$N/mut6.om" "$N/mut6"; then
  rm -f "$N/mut6.tcr"
  "$OUT/fail_fsync" "$N/mut6" encode range "$D/s.tps" "$D/s.tsy" "$N/mut6.tcr" > "$OUT/last.out" 2> "$OUT/last.err"
  rc=$?
  if [ "$rc" -eq 2 ] && grep -q 'refused -102 IO' "$OUT/last.err" && [ -e "$N/mut6.tcr" ]; then
    pass "ofinish old-order mutant leaves the output on fsync failure (exit 2 IO)"
  else
    fail "ofinish old-order mutant: exit $rc, file exists=$([ -e "$N/mut6.tcr" ] && echo yes || echo no) ($(head -c 160 "$OUT/last.err"))"
  fi
else fail "ofinish old-order mutant build or fail_fsync missing"; fi

# Lean: the bound's proof must still check, with no sorry and only the standard axioms.
# docs/turing/proofs/lean-toolchain pins the toolchain; elan's `lean` picks it from that folder.
LEAN=${LEAN:-$(command -v lean || echo "$HOME/.elan/bin/lean")}
if [ -x "$LEAN" ] || command -v "$LEAN" > /dev/null 2>&1; then
  ( cd "$ROOT/docs/turing/proofs" && "$LEAN" TcrBound.lean ) > "$OUT/lean.txt" 2>&1; lrc=$?
  nax=$(grep -c "depends on axioms\|does not depend on any axioms" "$OUT/lean.txt")
  badax=$(grep "depends on axioms" "$OUT/lean.txt" | sed 's/.*\[\(.*\)\]/\1/' | tr ',' '\n' | tr -d ' ' |
          grep -v '^propext$\|^Classical.choice$\|^Quot.sound$' | sort -u | tr '\n' ' ')
  if [ "$lrc" -eq 0 ] && [ "$nax" -eq 10 ] && [ -z "$badax" ] && ! grep -q "sorry" "$OUT/lean.txt"; then
    pass "lean TcrBound.lean ($(cat "$ROOT/docs/turing/proofs/lean-toolchain")): 10 theorems, standard axioms only"
  else fail "lean: exit $lrc, $nax axiom lines, other axioms '$badax': $(head -c 400 "$OUT/lean.txt")"; fi
else fail "lean not found (set LEAN): the proof of the bound cannot be checked"; fi

if [ "$fails" -eq 0 ]; then echo "TC-RANGE-OM PASS"; exit 0; fi
echo "TC-RANGE-OM FAIL ($fails)"; exit 1
