#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# mach_parity.sh -- differential qualification of the pure OM-2 machine lane
# (src/visor/visor_machine.om, run by the omega binary) against the C it replaced
# (src/visor/visor_machine.c, retired), on the same machine graphs and host facts.
#
# Every corpus runs through tests/visor/mach_dump.om (built from the shipped visor.om and
# visor_machine.om) and is compared byte for byte with tests/visor/mach_golden/<corpus>.out:
# view and from_facts return codes, the text and JSON renderings and their exact-size refusals,
# topology validation messages, provenance from host facts, unit names and the Blackwell
# declared-target id. The goldens were generated ONCE from the C at main commit 3f2c70dc5 (with
# omega_blackwell_realize.o linked, as the C omega binary linked it) by the reference-only C
# dumper tests/visor/mach_dump.c (committed once, then removed); tests/visor/mach_golden/MANIFEST
# records the commit, the generator and the sha256 of every corpus and golden. This script needs
# no C compiler.
#
# The `host` corpus reads this machine (visor_machine_host_facts, visor_machine_current): its
# golden is the generating host's (the Spark). It is compared only on a host whose uname -m,
# DMI product name and sorted distinct CPU parts, read here by the shell, equal the golden's
# first line; elsewhere it is reported SKIPPED (no other corpus reads the host).
#
# Corpus commands: see the header of tests/visor/mach_dump.om.
#
# usage: tests/visor/mach_parity.sh [OMC]
#          prints PARITY lines and MACH_PARITY ...; exit 0 iff every compared corpus equals its golden
#        tests/visor/mach_parity.sh --generate <C dumper binary>
#          rewrites the goldens and the MANIFEST body from that binary (keeps the header line)
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GOLD=$ROOT/tests/visor/mach_golden
GEN=""
if [ "${1:-}" = "--generate" ]; then
  GEN=${2:?usage: mach_parity.sh --generate <C dumper binary>}
  case $GEN in /*) ;; *) GEN=$(pwd)/$GEN ;; esac
  OMC=""
else
  OMC=${1:-$ROOT/seed/out/omc}
  case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
fi
W=${MACH_PARITY_WORK:-$(mktemp -d)}
mkdir -p "$W/corpus" "$W/out"
sha() { sha256sum "$1" | cut -d' ' -f1; }

# ---- corpora ----
cd "$ROOT"
C=$W/corpus
rm -f "$C"/*.txt
cp tests/visor/mach_corpus.txt "$C/hand.txt"
printf 'H\nQ\nH\nQ\n' > "$C/host.txt"
# Fields: every scalar field of both canonical graphs at 0, 1, 31, 32, 64, 255, 256, 2^32-1 and
# (64-bit fields) 2^64-1, with and without recomputing the id; unit and cache counts 0..9 and
# 0..8; the topology errors in their check order (issue width, GPR count, GPR width, cache
# level inversion, line size not a power of two).
awk 'BEGIN { split("0 1 31 32 64 255 256 4294967295", vs, " ");
  for (b = 0; b <= 1; b++) for (f = 0; f <= 12; f++) for (k = 1; k <= 8; k++) { if (f == 8 && k > 2) continue; print "B " b; print "F " f " " vs[k]; if (k % 2) print "K"; print "V" }
  for (b = 0; b <= 1; b++) for (f = 9; f <= 10; f++) { print "B " b; print "F " f " 18446744073709551615"; print "K"; print "V" }
  for (b = 0; b <= 1; b++) for (u = 0; u <= 9; u++) { print "B " b; print "F 3 " u; print "K"; print "V" }
  print "B 0"; print "F 3 255"; print "K"; print "V"; print "B 0"; print "F 3 256"; print "K"; print "V"
  for (b = 0; b <= 1; b++) for (c = 0; c <= 8; c++) { print "B " b; print "F 8 " c; print "K"; print "V" }
  print "B 0"; print "F 0 0"; print "F 4 30"; print "F 5 32"; print "C 1 0 0"; print "C 2 3 3"; print "V"
  print "B 0"; print "F 4 30"; print "F 5 32"; print "C 1 0 0"; print "V"
  print "B 0"; print "F 5 32"; print "C 1 0 0"; print "V"
  print "B 0"; print "C 3 0 1"; print "C 2 3 3"; print "V"
  print "B 0"; print "C 2 3 3"; print "V"
  print "B 1"; print "C 1 0 7"; print "C 2 0 2"; print "V" }' > "$C/gen-fields.txt"
# Units and caches: every unit field and type 0..8 and 2^32-1 in each of the 8 slots; every
# cache field, levels 0..9, instruction/data/unified, line sizes 0..130 around the powers of two,
# 2^31, 2^32-1 (both graphs for the first, middle and last slots, the dgx_spark graph for the others).
awk 'BEGIN { split("0 1 2 3 4 5 6 7 8 4294967295", ts, " ");
  for (b = 0; b <= 1; b++) for (u = 0; u <= 7; u++) for (k = 1; k <= 10; k++) { if (b == 1 && k != 10 && u != 7) continue; print "B " b; print "F 3 8"; print "U " u " 0 " ts[k]; print "U " u " 1 " (k * 3); print "U " u " 2 " (u * 1000 + k); print "U " u " 3 4294967295"; print "K"; print "V" }
  for (b = 0; b <= 1; b++) for (c = 0; c <= 7; c++) for (lv = 0; lv <= 9; lv++) { if (c != 0 && c != 3 && c != 7 && lv != 2) continue; print "B " b; print "F 8 8"; print "C " c " 0 " lv; print "C " c " 1 " (lv % 2); print "C " c " 2 " (lv * 65536); print "C " c " 4 " lv; print "C " c " 5 " (lv * 7); print "K"; print "V" }
  nl = split("0 1 2 3 4 5 6 7 8 15 16 17 31 32 33 48 63 64 65 96 127 128 129 130", lns, " "); for (q = 1; q <= nl; q++) { ln = lns[q]; print "B 0"; print "C 0 3 " ln; print "V" }
  print "B 1"; print "C 2 3 2147483648"; print "V"; print "B 1"; print "C 2 3 4294967295"; print "V"
  print "B 0"; print "C 0 2 18446744073709551615"; print "C 3 1 1"; print "C 1 0 2"; print "C 1 1 0"; print "K"; print "V" }' > "$C/gen-units.txt"
# Seals and names: one seal byte changed at each of the 32 positions (no longer the builder
# constant), the flag set and unset; names of 0..63 bytes, with quotes, backslashes, control and
# high bytes (the JSON escapes) and longer than the unit and target name columns.
awk 'BEGIN { for (b = 0; b <= 1; b++) for (i = 0; i < 32; i++) { print "B " b; print "S " i " " (i * 7 + 1); print "F 11 " (i % 2); print "K"; print "V" }
  print "B 0"; for (i = 0; i < 32; i++) print "S " i " 0"; print "K"; print "V"
  for (nl = 0; nl <= 63; nl += 9) { s = "N"; for (i = 0; i < nl; i++) s = s " " (65 + (i % 26)); print "B 1"; print s; print "K"; print "V" }
  print "B 0"; print "N 34 92 1 9 10 13 31 32 127 128 200 255 47 60 62 38"; print "V"
  print "B 0"; s = "N"; for (i = 1; i <= 63; i++) s = s " " i; print s; print "K"; print "V"
  print "B 0"; s = "N"; for (i = 0; i < 70; i++) s = s " " (97 + i % 26); print s; print "K"; print "V" }' > "$C/gen-seals.txt"
# Host facts: uname, DMI product and CPU parts each empty, matching, near-matching, over their
# 31/63/63-byte limits and holding JSON-escaped bytes, through from_facts: every combination for
# an empty, aarch64 and x86_64 uname, the first three of each for the other unames.
awk 'function bytes(s,   i, o) { o = ""; for (i = 1; i <= length(s); i++) o = o " " ord[substr(s, i, 1)]; return o }
BEGIN { for (i = 32; i < 127; i++) ord[sprintf("%c", i)] = i;
  nu = split("|aarch64|x86_64|aarch64 |AARCH64|aarch|aarch64aarch64aarch64aarch64aarch64aa", us, "|");
  nd = split("|NVIDIA DGX Spark|NVIDIA_DGX_Spark|x DGX_Sparky|DGX Spar|dgx spark|Some \"Board\" \\ 1|DGX_SparkDGX_SparkDGX_SparkDGX_SparkDGX_SparkDGX_SparkDGX_SparkDGX_Spark", ds, "|");
  np = split("|0xd4f|0xd85,0xd87|0xd4f,0xd85|0xd4|0xD4F|0xd85,0xd87,0xd0c,0xd40,0xd49,0xd4a,0xd4b,0xd4c,0xd4d,0xd4e,0xd4f,0xd8e", ps, "|");
  for (u = 1; u <= nu; u++) for (d = 1; d <= nd; d++) for (p = 1; p <= np; p++) { if (u > 3 && (d > 3 || p > 3)) continue;
    print "Z"; if (us[u] != "") print "A 0" bytes(us[u]); if (ds[d] != "") print "A 1" bytes(ds[d]); if (ps[p] != "") print "A 2" bytes(ps[p]); print "P" }
  print "Z"; print "A 0 97 97 114 99 104 54 52"; print "A 1 1 9 31 127 200 68 71 88 95 83 112 97 114 107"; print "A 2 34 92"; print "P"
  for (k = 0; k <= 2; k++) { print "Z"; print "A " k " 65 66"; print "A " k " 67"; print "A 0 97 97 114 99 104 54 52"; print "P" } }' > "$C/gen-facts.txt"
# Unit names 0..9, 2^31, 2^32-1; the Blackwell id.
awk 'BEGIN { for (t = 0; t <= 9; t++) print "X " t; print "X 2147483648"; print "X 4294967295"; print "W"; print "W" }' > "$C/gen-names.txt"

# ---- generate mode: write the goldens from the C dumper, keep the MANIFEST header line ----
if [ -n "$GEN" ]; then
  [ -x "$GEN" ] || { echo "MACH_PARITY FAIL $GEN is not an executable C dumper"; exit 2; }
  mkdir -p "$GOLD"
  hdr=$(head -n 1 "$GOLD/MANIFEST" 2>/dev/null | grep '^# generated once ' || true)
  [ -n "$hdr" ] || { echo "MACH_PARITY FAIL write the MANIFEST header line (commit, generator command) first"; exit 2; }
  rm -f "$GOLD"/*.out
  for c in "$C"/*.txt; do
    b=$(basename "$c" .txt)
    "$GEN" < "$c" > "$GOLD/$b.out" || { echo "MACH_PARITY FAIL the C dumper failed on $b"; exit 2; }
    [ -s "$GOLD/$b.out" ] || { echo "MACH_PARITY FAIL empty C output for $b"; exit 2; }
    printf 'corpus %s %s\n' "$b" "$(sha "$c")"
    printf 'golden %s %s\n' "$b" "$(sha "$GOLD/$b.out")"
  done > "$W/MANIFEST.body"
  { printf '%s\n' "$hdr"
    printf '# goldens sha256 (of the corpus and golden lines below) %s\n' "$(sha "$W/MANIFEST.body")"
    cat "$W/MANIFEST.body"; } > "$GOLD/MANIFEST"
  echo "MACH_PARITY generated $(grep -c '^golden ' "$GOLD/MANIFEST") goldens in $GOLD"
  exit 0
fi

# ---- the corpora and goldens must be the ones the MANIFEST records ----
M=$GOLD/MANIFEST
[ -f "$M" ] || { echo "MACH_PARITY FAIL missing $M"; exit 2; }
grep -q '^# generated once from the C at main commit 3f2c70dc5' "$M" \
  || { echo "MACH_PARITY FAIL $M header line does not name the C reference commit"; exit 2; }
grep -v '^#' "$M" > "$W/MANIFEST.body"
[ "$(sed -n 2p "$M")" = "# goldens sha256 (of the corpus and golden lines below) $(sha "$W/MANIFEST.body")" ] \
  || { echo "MACH_PARITY FAIL $M body does not match its recorded sha256"; exit 2; }
bad=0
nc=$(ls "$C"/*.txt | wc -l | tr -d ' ')
[ "$nc" -eq "$(grep -c '^corpus ' "$M")" ] || { echo "MACH_PARITY FAIL $nc corpora built, $(grep -c '^corpus ' "$M") in the MANIFEST"; bad=1; }
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  want=$(awk -v b="$b" '$1 == "corpus" && $2 == b { print $3 }' "$M")
  [ "$want" = "$(sha "$c")" ] || { echo "MACH_PARITY FAIL corpus $b is not the one the goldens were generated from (regenerate: --generate)"; bad=1; }
  want=$(awk -v b="$b" '$1 == "golden" && $2 == b { print $3 }' "$M")
  [ -f "$GOLD/$b.out" ] && [ "$want" = "$(sha "$GOLD/$b.out")" ] || { echo "MACH_PARITY FAIL golden $b.out missing or not the recorded sha256"; bad=1; }
done
[ "$bad" -eq 0 ] || exit 2

# ---- the OM-2 dumper, from the shipped modules (as mk/visor-machine.mk joins them) ----
OMS="src/visor/visor.om src/visor/visor_machine.om tests/visor/mach_dump.om"
(printf 'om2\n'; sed -e '/^om2$/d' -e 's/^export fn /fn /' $OMS) | "$OMC" > "$W/mach_dump_om"
chmod +x "$W/mach_dump_om"

# ---- is this the host the host golden was generated on? (read by the shell, not by OM) ----
hu=$(uname -m)
hd=$(head -n 1 /sys/devices/virtual/dmi/id/product_name 2>/dev/null | sed 's/[ \r]*$//' || true)
hc=$(grep '^CPU part' /proc/cpuinfo 2>/dev/null | sed 's/^[^:]*:[ \t]*//; s/[ \t].*//' | sort -u | paste -sd, - || true)
same_host=0
[ "$(head -n 1 "$GOLD/host.out")" = "L1 H rc=0 u=$hu d=$hd c=$hc" ] && same_host=1
echo "$same_host" > "$W/same_host"

# ---- compare ----
files=0; lines=0; diff=0; skip=0
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  if [ "$b" = host ] && [ "$same_host" -ne 1 ]; then
    skip=$((skip + 1)); echo "PARITY host SKIPPED (this host is not the generating host: u=$hu d=$hd c=$hc)"; continue
  fi
  rc=0
  "$W/mach_dump_om" < "$c" > "$W/out/$b.om" || rc=$?
  n=$(wc -l < "$c" | tr -d ' ')
  files=$((files + 1)); lines=$((lines + n))
  if [ "$rc" -eq 0 ] && cmp -s "$GOLD/$b.out" "$W/out/$b.om"; then
    echo "PARITY $b lines=$n same"
  else
    diff=$((diff + 1))
    echo "PARITY $b lines=$n DIFF exit=$rc"
    diff "$GOLD/$b.out" "$W/out/$b.om" | head -20 || true
  fi
done
echo "MACH_PARITY files=$files lines=$lines diff=$diff skipped=$skip reference=C@3f2c70dc5 (goldens) work=$W"
[ "$diff" -eq 0 ]
