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
#  1 build; 2 selftest (synthetic round trips, identity, bound, corruption detection);
#  3 for 2 committed traces x 7 models: Omega encode byte-identical to C, C verifies the Omega
#    file, Omega verifies the C file, Omega decode byte-identical to the TSY1, bound=PASS;
#  4 refusals with the CODER_SPEC s.10 code: flipped payload byte, truncated, trailing byte,
#    other TPS1 (BINDING), altered magic (HEADER), corrupted TPS1 (DIGEST), wrong count (COUNT
#    via a TSY1 of another length), usage;
#  5 mutants that must fail: a coder arithmetic mutant (not byte-identical to C), a bound
#    mutant (the ALARM path, exit 3, is live) and a ub rounding mutant (exhaustive ub check).
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
       && grep -q '^bound=PASS$' "$D/enc.txt"; then :; else fail "unit $i Omega encode: $(cat "$D/enc.err")"; continue; fi
    cmp -s "$D/o.tcr" "$D/c.tcr" || fail "unit $i Omega bytes differ from C"
    "$TC" verify range "$D/s.tps" "$D/s.tsy" "$D/o.tcr" > /dev/null 2>&1 || fail "unit $i C rejects the Omega file"
    "$B" verify range "$D/s.tps" "$D/s.tsy" "$D/c.tcr" > "$D/ver.txt" 2>&1 || fail "unit $i Omega rejects the C file"
    "$B" decode range "$D/s.tps" "$D/o.tcr" "$D/o.tsy" > /dev/null 2>&1 || fail "unit $i Omega decode"
    cmp -s "$D/o.tsy" "$D/s.tsy" || fail "unit $i decoded TSY1 differs"
    ci=$(sed -n 's/^ideal_ub=//p' "$D/pstream.txt"); oi=$(sed -n 's/^ideal_ub=//p' "$D/enc.txt")
    [ "$ci" = "$oi" ] || fail "unit $i ideal_ub C $ci Omega $oi"
    echo "unit $i n=$(sed -n 's/^count=//p' "$D/enc.txt") ideal_ub=$oi coded_bits=$(sed -n 's/^coded_bits=//p' "$D/enc.txt") slack_ub=$(sed -n 's/^slack_ub=//p' "$D/enc.txt") $(basename "$TR") $(basename "$M")"
  done
done
[ "$fails" -eq 0 ] && pass "14 units: byte-identical to C both ways, decode exact, ideal_ub equal, bound=PASS"

# Refusals (unit 1 files).
D=$OUT/u1; N=$OUT/neg; mkdir -p "$N"
sz=$(wc -c < "$D/o.tcr")
cp "$D/o.tcr" "$N/flip.tcr"; printf '\125' | dd of="$N/flip.tcr" bs=1 seek=$((sz - 3)) conv=notrunc 2> /dev/null
cmp -s "$N/flip.tcr" "$D/o.tcr" && fail "flip control did not change the file"
expect_rc "flipped payload byte refused" 2 "$B" verify range "$D/s.tps" "$D/s.tsy" "$N/flip.tcr"
head -c $((sz - 1)) "$D/o.tcr" > "$N/trunc.tcr"
expect_rc "truncated file refused" 2 "$B" verify range "$D/s.tps" "$D/s.tsy" "$N/trunc.tcr"
grep -q 'refused -113 TRUNC' "$OUT/last.err" || fail "truncated: not TRUNC"
{ cat "$D/o.tcr"; printf 'x'; } > "$N/trail.tcr"
expect_rc "trailing byte refused" 2 "$B" verify range "$D/s.tps" "$D/s.tsy" "$N/trail.tcr"
grep -q 'refused -114 TRAIL' "$OUT/last.err" || fail "trailing: not TRAIL"
expect_rc "other TPS1 refused" 2 "$B" decode range "$OUT/u2/s.tps" "$D/o.tcr" "$N/x.tsy"
grep -q 'refused -112 BINDING' "$OUT/last.err" || fail "other TPS1: not BINDING"
[ -e "$N/x.tsy" ] && fail "a refused decode left its output file"
cp "$D/o.tcr" "$N/magic.tcr"; printf 'X' | dd of="$N/magic.tcr" bs=1 seek=0 conv=notrunc 2> /dev/null
expect_rc "altered magic refused" 2 "$B" verify range "$D/s.tps" "$D/s.tsy" "$N/magic.tcr"
grep -q 'refused -111 HEADER' "$OUT/last.err" || fail "magic: not HEADER"
cp "$D/s.tps" "$N/bad.tps"; printf '\001' | dd of="$N/bad.tps" bs=1 seek=200 conv=notrunc 2> /dev/null
expect_rc "corrupted TPS1 refused" 2 "$B" encode range "$N/bad.tps" "$D/s.tsy" "$N/y.tcr"
grep -q 'refused -104 DIGEST' "$OUT/last.err" || fail "corrupted TPS1: not DIGEST"
[ -e "$N/y.tcr" ] && fail "a refused encode left its output file"
expect_rc "TSY1 of another trace refused" 2 "$B" encode range "$D/s.tps" "$OUT/u8/s.tsy" "$N/z.tcr"
expect_rc "usage" 1 "$B" encode rans "$D/s.tps" "$D/s.tsy" "$N/w.tcr"

# Mutants.
sed 's/^r = shr rg 16$/r = shr rg 15/' "$ROOT/src/turing/tc_range.om" > "$N/mut1.om"
cmp -s "$N/mut1.om" "$ROOT/src/turing/tc_range.om" && fail "mutant 1 did not change the source"
if build "$N/mut1.om" "$N/mut1"; then
  "$N/mut1" encode range "$D/s.tps" "$D/s.tsy" "$N/m1.tcr" > /dev/null 2>&1
  if [ -e "$N/m1.tcr" ] && cmp -s "$N/m1.tcr" "$D/c.tcr"; then fail "coder mutant still byte-identical"
  else pass "coder mutant (range >> 15) caught: output differs from C or refused"; fi
else fail "mutant 1 build"; fi
sed 's/^bnd = add add get ST 1 mul n 5647 480000000$/bnd = add add get ST 1 mul n 0 470000000/' \
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

if [ "$fails" -eq 0 ]; then echo "TC-RANGE-OM PASS"; exit 0; fi
echo "TC-RANGE-OM FAIL ($fails)"; exit 1
