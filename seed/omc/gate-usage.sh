#!/bin/sh
# gate-usage.sh -- the alarm in place of omc's old capacities (Drake 2026-11-11: "Instead of caps to
# prevent something, just put a TEST that will alarm if it passes the threshold"; OMEGESE 9.6).
# The compiler under test is seed/out/omc (OMC overrides it). A unit whose first line is `usage` is
# compiled as usual, and instead of the program omc writes one omc-use record (OMEGESE 9.6):
#   omc-use 1 arena=A top=T waste=W full=F GROUP=N/H ...
# A the arena's 8-byte words (its length now: the arena is a run-time pool that grows, landing 2 of
# docs/RUNTIME-POOLS.md), T the words handed out, W the words left behind when a table moved, F 1 when the
# host refused the arena's growth or its memory ceiling was reached; per group N what the unit asked it to hold and H
# the words it holds; last, ceiling=C, the OMC_MEMORY_MAX in force (0: none), which must parse.
# Units: the largest real units of the stack, composed exactly as their builds compose them: seed/omc/omc.om
# itself, and from sibling checkouts ../omega-mcp (src/UNITS), ../cortex (build.sh SERVER), and
# ../interplane-forge (forged: run.sh units); then the scale units of seed/omc/tests/nocaps/gen.sh.
# Thresholds, for noticing, not for stopping anyone's compile (a real unit never sees them). Since the arena
# grows to fit, T / A is near 50 to 100% by construction, so the words are absolute (the old fractions of the
# 16777216-word static arena, design s7 gate 14):
#   arena    T at most 4194304 words (32 MiB) for a real unit, 12582912 (96 MiB) for a scale unit
#   group    H of any one group at most 2097152 words (16 MiB) for a real unit, 16777216 for a scale unit
#   full     F must be 0
#   time     at most 2 s per real unit, 10 s per scale unit (wall clock, one compile)
#   memory   at most 64 MiB resident per real unit, 256 MiB per scale unit (GNU time %M)
# Past any of them the gate FAILS LOUDLY with the unit, the measure, the number and the threshold.
# A missing sibling checkout is NOT_RUN (status 3 at the end); everything else still runs.
# Mutant control: a compiler built from seed/omc/omc.om whose tables never double (a_need grows a group by 512
# entries each time, `c = add c 512` for `c = shl c 1`) must make this gate fail on a unit: the moved tables'
# words pile up (absolute words and resident memory alarms); its compile time is recorded beside them.
# (The design's first control, arena growth of one page each time, is not one: the arena grows only when a
# group's doubling does not fit and mremap copies nothing, so it costs no time; measured 2026-11-11.)
# Writes build/seed/usage/usage.tsv: unit, arena, top, waste, top%, largest group, its words, seconds, KB.
# Last line: RC=0 when everything passed.
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$R"
S=${OMC:-seed/out/omc}
[ -x "$S" ] || { printf 'FAIL: %s missing; run sh seed/omega-from-seed.sh first\n' "$S" >&2; exit 1; }
command -v /usr/bin/time > /dev/null || { printf 'FAIL: /usr/bin/time (GNU time) is needed for the memory measure\n' >&2; exit 1; }
mkdir -p build/seed/usage
B=$R/$(mktemp -d build/seed/usage/run.XXXXXX)
trap 'rm -rf "$B"' EXIT HUP INT TERM
bad() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
P=$(dirname "$R")
skip=0

# compose the units
mkdir -p $B/real $B/scale
cp seed/omc/omc.om $B/real/omc.om
if [ -f "$P/omega-mcp/src/UNITS" ]; then
  ( cd "$P/omega-mcp" && { printf 'om2\n'; first=1
    while read -r f; do case "$f" in ''|'#'*) continue ;; esac
      if [ $first = 1 ]; then sed 's/^export fn /fn /' "$f" | grep -v '^om2$'; first=0; else cat "$f"; fi
    done < src/UNITS; } ) > $B/real/omega-mcp.om
else say "NOT_RUN omega-mcp: no sibling checkout $P/omega-mcp"; skip=$((skip + 1)); fi
if [ -f "$P/cortex/build.sh" ]; then
  mods=$(sed -n 's/^SERVER="\(.*\)"$/\1/p' "$P/cortex/build.sh")
  [ -n "$mods" ] || bad "cortex: no SERVER= line in $P/cortex/build.sh"
  { echo om2; for m in $mods; do cat "$P/cortex/om/$m.om"; done; } > $B/real/cortex.om
else say "NOT_RUN cortex: no sibling checkout $P/cortex"; skip=$((skip + 1)); fi
if [ -f "$P/interplane-forge/run.sh" ]; then
  sed -n '/^units()/,/^}/p' "$P/interplane-forge/run.sh" > $B/units.sh
  [ -s $B/units.sh ] || bad "forged: no units() in $P/interplane-forge/run.sh"
  # run.sh exports LC_ALL=C. A shell assignment does not reach ls, and en_US then
  # sorts dljson.om before dl.om, so omc stops with error 3 on a name declared in dl.om.
  ( cd "$P/interplane-forge" && export LC_ALL=C && ROOT=$P/interplane-forge && OMV=$R && . $B/units.sh && { printf 'om2\n'; cat $(units); } ) > $B/real/forged.om
else say "NOT_RUN forged: no sibling checkout $P/interplane-forge"; skip=$((skip + 1)); fi
sh seed/omc/tests/nocaps/gen.sh $B/gen
for u in texts100k globals100k fns50k calls100k view100k traps100k longnames20k in64m; do
  mv $B/gen/$u.om $B/scale/$u.om
done
rm -rf $B/gen

# check COMPILER KIND UNIT -> prints the tsv row; returns 1 (with ALARM lines on stderr) past a threshold
check() {
  c=$1; k=$2; f=$3; u=$(basename $f .om)
  if [ $k = real ]; then ta=4194304; tg=2097152; ts=2; tm=65536; else ta=12582912; tg=16777216; ts=10; tm=262144; fi
  { printf 'usage\n'; cat $f; } > $B/w.om
  set +e; "$c" < $B/w.om > $B/w.rec 2> $B/w.err; rc=$?; set -e
  if [ $rc != 0 ]; then
    printf 'ALARM %s: compile refused, status %s: %s\n' $u $rc "$(head -c 600 $B/w.err)" >&2; return 1
  fi
  set +e; /usr/bin/time -f '%e %M' -o $B/t "$c" < $f > /dev/null 2> /dev/null; rc=$?; set -e
  [ $rc = 0 ] || { printf 'ALARM %s: plain compile status %s\n' $u $rc >&2; return 1; }
  awk -v u=$u -v ta=$ta -v tg=$tg -v ts=$ts -v tm=$tm -v tf=$B/t '
    BEGIN { getline tl < tf; split(tl, tt, " "); sec = tt[1]; kb = tt[2] }
    $1 == "omc-use" {
      for (i = 3; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2]; if (i >= 7 && kv[1] != "ceiling") order[++ng] = kv[1] }
      a = v["arena"]; t = v["top"]; bad = 0; big = ""; bw = 0
      if (v["ceiling"] !~ /^[0-9]+$/ || $NF !~ /^ceiling=/) { printf "ALARM %s: the record has no last field ceiling=N (%s)\n", u, $NF > "/dev/stderr"; bad = 1 }
      for (j = 1; j <= ng; j++) { g = order[j]; split(v[g], nh, "/")
        if (nh[2] + 0 > bw) { bw = nh[2] + 0; big = g }
        if (nh[2] + 0 > tg) { printf "ALARM %s: group %s holds %d words; threshold %d words\n", u, g, nh[2], tg > "/dev/stderr"; bad = 1 } }
      if (t + 0 > ta) { printf "ALARM %s: arena top %d words (arena %d words); threshold %d words\n", u, t, a, ta > "/dev/stderr"; bad = 1 }
      if (v["full"] != 0) { printf "ALARM %s: the host refused to grow the arena (full=1)\n", u > "/dev/stderr"; bad = 1 }
      if (sec + 0 > ts) { printf "ALARM %s: compile took %.2f s; threshold %d s\n", u, sec, ts > "/dev/stderr"; bad = 1 }
      if (kb + 0 > tm) { printf "ALARM %s: compile resident %d KB; threshold %d KB\n", u, kb, tm > "/dev/stderr"; bad = 1 }
      printf "%s\t%d\t%d\t%d\t%.2f\t%s\t%d\t%s\t%d\n", u, a, t, v["waste"], 100 * t / a, big, bw, sec, kb
      seen = 1; exit bad }
    END { if (!seen) { printf "ALARM %s: no omc-use record\n", u > "/dev/stderr"; exit 1 } }' $B/w.rec
}

printf 'unit\tarena_words\ttop\twaste\ttop_pct\tlargest_group\tits_words\tseconds\tmax_rss_kb\n' > $B/usage.tsv
for f in $B/real/*.om; do
  check "$S" real $f >> $B/usage.tsv || bad "alarm on $(basename $f .om) (lines above); compiler $(sha256sum "$S" | cut -c1-16)"
  say "PASS $(tail -1 $B/usage.tsv | awk -F'\t' '{ printf "%s: top %s words (arena %s words), largest %s %s words, %s s, %s KB", $1, $3, $2, $6, $7, $8, $9 }')"
done
for f in $B/scale/*.om; do
  check "$S" scale $f >> $B/usage.tsv || bad "alarm on scale unit $(basename $f .om) (lines above)"
  say "PASS scale $(tail -1 $B/usage.tsv | awk -F'\t' '{ printf "%s: top %s words (arena %s words), %s s, %s KB", $1, $3, $2, $8, $9 }')"
done
cp $B/usage.tsv build/seed/usage/usage.tsv

# mutant control: tables that never double (a_need +512 entries each time) must be noticed
grep -cx 'c = shl c 1' seed/omc/omc.om | grep -qx 1 || bad "mutant: the doubling line of a_need does not occur exactly once"
sed 's/^c = shl c 1$/c = add c 512/' seed/omc/omc.om > $B/m.om
"$S" < $B/m.om > $B/m.omc 2> $B/m.err || bad "mutant: does not build ($(cat $B/m.err))"
chmod +x $B/m.omc
caught=""
for f in $B/real/*.om $B/scale/*.om; do k=real; case $f in $B/scale/*) k=scale;; esac
  if ! check $B/m.omc $k $f > $B/m.row 2> $B/m.why; then caught="$(basename $f .om): $(head -2 $B/m.why | tr '\n' ' ')"; break; fi
done
[ -n "$caught" ] || bad "mutant: tables growing by 512 entries passed every unit; the alarm noticed nothing"
say "PASS mutant a_need +512 (never doubling) caught by $caught (row: unit, top words, seconds, KB: $(cut -f1,3,8,9 $B/m.row | tr "\t" " "))"
[ $skip = 0 ] || { say "NOT_RUN $skip sibling units"; exit 3; }
say "RC=0"
