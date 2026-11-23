#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# est_tools_fixtures.sh -- writes the input tree of the est_fit / est_eval differential
# (tests/estimation/est_tools_parity.sh) into <dir>: deterministic synthetic machine-state runs
# (integer Park-Miller generator, no libm), marks files, SHA256SUMS lines, copies of the frozen
# protocol documents and of the run A and run B evidence files the tools identify by digest.
#   tests/estimation/est_tools_fixtures.sh <repo root> <dir>
set -eu
R=${1:?repo root}
D=${2:?fixture dir}
mkdir -p "$D"
cd "$D"
sha() { sha256sum "$1" | cut -c1-64; }

# gen <file> <lines> <seed> <q sd> <r sd> <jitter ns (0: exact 1 s)> [specials]
# specials: comma list of line:kind, kind one of lead (first <line> lines carry no thermal key),
# coast, badv, badt, ovt (t past int64), dup (t of the line before), back (t 5 s earlier),
# gap (3 s), big (70 s); every <k>th line: c<k> (coast) .
gen() {
  awk -v n="$2" -v seed="$3" -v sq="$4" -v sr="$5" -v jit="$6" -v spec="${7:-}" '
    function u() { seed = (seed * 16807) % 2147483647; return seed / 2147483647 }
    function g(   i, s) { s = 0; for (i = 0; i < 12; i++) s += u(); return s - 6 }
    BEGIN {
      ns_ = split(spec, sp, ","); lead = 0; ck = 0
      for (i = 1; i <= ns_; i++) { split(sp[i], kv, ":");
        if (kv[2] == "lead") lead = kv[1] + 0; else if (substr(sp[i], 1, 1) == "c") ck = substr(sp[i], 2) + 0; else kind[kv[1] + 0] = kv[2] }
      s = 1790000000; ns = 1; x = 34000
      for (i = 0; i < n; i++) {
        if (i > 0) { d = 1000000000; if (jit > 0) d += int((u() - 0.5) * 2 * jit)
          k = kind[i]; if (k == "gap") d += 2000000000; if (k == "big") d += 69000000000
          if (k == "dup") d = 0
          ns += d; while (ns >= 1000000000) { ns -= 1000000000; s++ } }
        x += g() * sq
        z = int(x + g() * sr)
        ts = sprintf("%d.%09d", s, ns)
        if (k == "back") ts = sprintf("%d.%09d", s - 5, ns)
        if (k == "badt") ts = "\"bad\""
        if (k == "ovt") ts = "99999999999999999999.5"
        th = sprintf(",\"thermal_mc\":\"%d 33200 \"", z)
        if (k == "badv") th = ",\"thermal_mc\":\"x 33200 \""
        if (i < lead || k == "coast" || (ck > 0 && i % ck == ck - 1)) th = ""
        printf "{\"t\":%s,\"load\":\"%d\"%s}\n", ts, i, th
        k = ""
      }
    }' > "$1"
}
# marks <file> <first t> <pair len s> <gap s> <pairs> [extra lines, printf format]
marks() {
  awk -v t0="$2" -v pl="$3" -v gp="$4" -v n="$5" 'BEGIN {
    t = t0; for (i = 1; i <= n; i++) { printf "%d.000000000 begin trial-%d.jsonl\n", t, i; t += pl
      printf "%d.500000000 end trial-%d.jsonl exit 0\n", t, i; t += gp } }' > "$1"
}
sums() { ( cd "$1" && for f in machine-state.ndjson machine-state-marks.txt; do [ -f "$f" ] && printf '%s  %s\n' "$(sha "$f")" "$f"; done ) > "$1/SHA256SUMS"; }
run() { mkdir -p "$1"; gen "$1/machine-state.ndjson" "$2" "$3" "$4" "$5" "$6" "${7:-}"; }

mkdir -p docs/estimation tmp
for f in EST23_PROTOCOL_V1.md EST23_PROTOCOL_V1_INTERPRETATIONS.md EST23_PROTOCOL_V2.md; do
  cp "$R/docs/estimation/$f" docs/estimation/
done
for id in 20260929T020536Z-ad8e1f2ea4e4-silicon 20260929T025735Z-3e9e53be3358-silicon; do
  mkdir -p "evidence/R15/raw/$id"
  for f in machine-state.ndjson machine-state-marks.txt SHA256SUMS; do cp "$R/evidence/R15/raw/$id/$f" "evidence/R15/raw/$id/"; done
done

# s1: exact 1 s grid, 1300 lines, three trials
run s1 1300 11 60 80 0; marks s1/machine-state-marks.txt 1790000100 40 300 3; sums s1
# s2: jittered, every kind of irregular line, nested begin, stray end, unclosed begin, junk lines
run s2 1500 23 40 120 300000000 "5:lead,c97,200:badv,210:badt,220:ovt,300:dup,301:dup,400:back,500:gap,501:gap,700:big,900:gap,1100:big"
{ echo "junk line"; echo "1790000020.000000000 end stray-1.jsonl exit 0"; echo "1790000050.000000000 begin a.jsonl";
  echo "1790000080.000000000 begin b.jsonl"; echo "1790000090.000000000 end b.jsonl exit 0"; echo "1790000095.000000000 middle x";
  echo "1790000100.000000000 end c.jsonl exit 0"; echo "1790000400.000000000 begin d.jsonl"; echo "1790000450.000000000 end d.jsonl exit 0";
  echo "1790001000.000000000 begin e.jsonl"; } > s2/machine-state-marks.txt; sums s2
# cal1, cal2: two realisations of a local-level process (q sd 50, r sd 60) for a calibrated model
run cal1 1400 101 50 60 0; marks cal1/machine-state-marks.txt 1790000100 200 100 4; sums cal1
run cal2 1400 202 50 60 0; marks cal2/machine-state-marks.txt 1790000100 200 100 4; sums cal2
# rg100: s1's run with one trial whose begin and end are the times of lines 100 and 199, so
# exactly 100 included samples fall in it (both ends inclusive; the in-trial regime gate is n >= 100)
mkdir -p rg100; cp s1/machine-state.ndjson rg100/
printf '1790000100.000000001 begin r.jsonl\n1790000199.000000001 end r.jsonl exit 0\n' > rg100/machine-state-marks.txt; sums rg100
# drift1, drift2: a local linear trend (level sd 50, slope steps sd 1, reading sd 60), on which a
# fitted M1 calibrates and M0 does not, so M1 is selected
drift() {
  mkdir -p "$1"
  awk -v seed="$2" 'function u() { seed = (seed * 16807) % 2147483647; return seed / 2147483647 }
    function g(   i, s) { s = 0; for (i = 0; i < 12; i++) s += u(); return s - 6 }
    BEGIN { s = 1790000000; x = 34000; v = 0
      for (i = 0; i < 1400; i++) { v = v + g(); x += g() * 50 + v
        printf "{\"t\":%d.000000001,\"thermal_mc\":\"%d 33200 \"}\n", s + i, int(x + g() * 60) } }' > "$1/machine-state.ndjson"
  printf '1790000100.000000000 begin a\n1790000300.500000000 end a exit 0\n' > "$1/machine-state-marks.txt"
  sums "$1"
}
drift drift1 999; drift drift2 415
# s3: 40 lines (one sample past burn-in), s4: 20 lines (none), s5: 33 lines (three samples)
run s3 40 31 60 80 0; marks s3/machine-state-marks.txt 1790000005 10 5 1; sums s3
run s4 20 41 60 80 0; marks s4/machine-state-marks.txt 1790000005 10 5 1; sums s4
run s5 33 43 60 80 0; marks s5/machine-state-marks.txt 1790000005 10 5 1; sums s5
# nodata: no line carries a thermal value; flat: a constant reading
run nodata 60 47 60 80 0 "60:lead"; marks nodata/machine-state-marks.txt 1790000005 10 5 1; sums nodata
run flat 400 53 0 0 0; marks flat/machine-state-marks.txt 1790000005 10 5 1; sums flat
# M2 fit runs (path tag -est3b-fit-), the held-out tag, an untagged copy for the SHA256SUMS
# identity, and a C1 copy whose SHA256SUMS line is later spoiled
mkdir -p r-est3b-fit-1
awk 'BEGIN { s = 1790000000; seed = 7; x = 34000
  for (i = 0; i < 1300; i++) { seed = (seed * 16807) % 2147483647; u = seed / 2147483647
    if (u < 0.55) d = 0; else if (u < 0.75) d = 100; else if (u < 0.95) d = -100; else if (u < 0.98) d = 300; else d = -400
    x += d; printf "{\"t\":%d.000000001,\"thermal_mc\":\"%d 33200 \"}\n", s + i, x } }' > r-est3b-fit-1/machine-state.ndjson
marks r-est3b-fit-1/machine-state-marks.txt 1790000100 40 300 3; sums r-est3b-fit-1
mkdir -p r-est3b-fit-2; cp r-est3b-fit-1/machine-state.ndjson r-est3b-fit-1/machine-state-marks.txt r-est3b-fit-1/SHA256SUMS r-est3b-fit-2/
mkdir -p r-est3b-heldout-1
awk 'BEGIN { s = 1790000000; seed = 9; x = 34000
  for (i = 0; i < 1250; i++) { seed = (seed * 16807) % 2147483647; u = seed / 2147483647
    if (u < 0.55) d = 0; else if (u < 0.75) d = 100; else if (u < 0.95) d = -100; else if (u < 0.98) d = 300; else d = -400
    x += d; printf "{\"t\":%d.000000001,\"thermal_mc\":\"%d 33200 \"}\n", s + i, x } }' > r-est3b-heldout-1/machine-state.ndjson
marks r-est3b-heldout-1/machine-state-marks.txt 1790000100 40 300 3; sums r-est3b-heldout-1
mkdir -p c2copy; cp r-est3b-heldout-1/machine-state.ndjson r-est3b-heldout-1/machine-state-marks.txt r-est3b-heldout-1/SHA256SUMS c2copy/
# a recorded run B stand-in for the test build (directory names the test run id synthB)
mkdir -p rb-synthB-1; cp cal2/machine-state.ndjson cal2/machine-state-marks.txt cal2/SHA256SUMS rb-synthB-1/
# run B identity: by path component, and by an innocent directory's SHA256SUMS digest
mkdir -p x-3e9e53be3358-y; cp s1/machine-state.ndjson s1/machine-state-marks.txt s1/SHA256SUMS x-3e9e53be3358-y/
mkdir -p sumsb; cp s1/machine-state.ndjson s1/machine-state-marks.txt sumsb/
B=evidence/R15/raw/20260929T025735Z-3e9e53be3358-silicon
printf '%s  machine-state.ndjson\n%s  machine-state-marks.txt\n' "$(sha $B/machine-state.ndjson)" "$(sha $B/machine-state-marks.txt)" > sumsb/SHA256SUMS
# load refusals: no SHA256SUMS, a wrong digest, a marks file with no SHA256SUMS line
mkdir -p nosums badsum nomarksum; cp s1/machine-state.ndjson s1/machine-state-marks.txt nosums/
cp s1/machine-state.ndjson s1/machine-state-marks.txt badsum/; printf '%064d  machine-state.ndjson\n%064d  machine-state-marks.txt\n' 0 0 > badsum/SHA256SUMS
cp s1/machine-state.ndjson s1/machine-state-marks.txt nomarksum/; printf '%s  machine-state.ndjson\n' "$(sha s1/machine-state.ndjson)" > nomarksum/SHA256SUMS
# marks capacity: 600 pairs; 513 nested begins; 512 pairs and an unclosed begin; exactly 512 pairs
mkdir -p mm1 mm2 mm3 mm4
for d in mm1 mm2 mm3 mm4; do cp s1/machine-state.ndjson $d/; done
marks mm1/machine-state-marks.txt 1790000000 1 1 600
awk 'BEGIN { for (i = 0; i < 514; i++) printf "%d.000000000 begin t-%d.jsonl\n", 1790000000 + i, i }' > mm2/machine-state-marks.txt
{ marks /dev/stdout 1790000000 1 1 512; echo "1790002000.000000000 begin last.jsonl"; } > mm3/machine-state-marks.txt
marks mm4/machine-state-marks.txt 1790000000 1 1 512
for d in mm1 mm2 mm3 mm4; do sums $d; done
# parameter files written by hand: malformed, off the grid, and a v2 file naming a missing v1 file
mkdir -p hand
printf 'est_params_v1\nnot a parameter file\n' > hand/bad.txt
printf 'est_params_v1\nprotocol_commit f96dc97\nfit_run_path s1/machine-state.ndjson\nfit_file_sha256 %s\nfit_lines 1300\nM0 q 123 r 100 loglik -1\nM1 q 100 r 100 loglik -1\n' "$(sha s1/machine-state.ndjson)" > hand/offgrid.txt
echo ok > hand/plain.txt
