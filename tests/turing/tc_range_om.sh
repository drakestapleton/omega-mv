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
#  5 mutants that must fail: coder arithmetic (not byte-identical to C), upper-bound constants,
#    ub rounding (exhaustive ub check), lower-bound constant (ALARM exit 3 in each alarm case);
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
sed 's/^lw = add get ST 1 472000000$/lw = add get ST 1 482000000/' "$ROOT/src/turing/tc_range.om" > "$N/mut4.om"
cmp -s "$N/mut4.om" "$ROOT/src/turing/tc_range.om" && fail "mutant 4 did not change the source"
if build "$N/mut4.om" "$N/mut4"; then
  expect_rc "lower-bound mutant (10 bits too high) raises the ALARM" 3 "$N/mut4" encode range "$OUT/u2/s.tps" "$OUT/u2/s.tsy" "$N/m4.tcr"
else fail "mutant 4 build"; fi

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
