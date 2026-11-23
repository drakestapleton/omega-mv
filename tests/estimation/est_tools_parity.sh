#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# est_tools_parity.sh -- differential qualification of the pure OM-2 est_fit and est_eval
# (tools/estimation/est_fit.om, tools/estimation/est_eval.om) against the C tools they replaced
# (tools/estimation/est_fit.c, tools/estimation/est_eval.c, retired at main commit 3f2c70dc5).
#
# The cases of tests/estimation/est_tools_cases.txt run in order, in one fixture tree written by
# tests/estimation/est_tools_fixtures.sh, against three OM builds composed exactly as
# mk/estimation_tools.mk composes them ($(ESTT_OM_LIB), passed in EST_OM_LIB, then the main):
#   fit   est_fit.om
#   eval  est_eval.om after a toolid.om with commit "parity-commit", EE_TOOL_DIRTY 0, EE_TEST_BUILD 0
#         (the production build; the mk rule writes the same three lines with the HEAD commit)
#   evalt est_eval.om after the toolid_t.om of the mk rule ("test-build", 1, 1)
# Every case's exit code, stdout, stderr and every file it writes under out/<group>.<case>/ are compared
# byte for byte with tests/estimation/est_tools_golden/<group>.out, generated ONCE from the C at
# main commit 3f2c70dc5 (tests/estimation/est_tools_golden/MANIFEST: commit, generator commands,
# blobs and sha256 of the C sources, sha256 of every corpus and golden). Two normalisations, both
# applied to C and OM alike: a receipt's "eval_binary_sha256" (the SHA-256 of /proc/self/exe,
# which differs between any two builds) reads "BIN", and a 64-hex digest on stdout that is the
# raw SHA-256 of a .json file the case wrote reads "RECEIPT(<file>)" (so the printed digest must
# still be that receipt's real digest). Stream files are compared by SHA-256. No C compiler.
#
# usage: EST_OM_LIB="<the ESTT_OM_LIB list>" tests/estimation/est_tools_parity.sh [OMC]
#          prints PARITY lines and EST_TOOLS_PARITY ...; exit 0 iff every group equals its golden
#        tests/estimation/est_tools_parity.sh --generate <C est_fit> <C est_eval> <C est_eval_t>
#          rewrites the goldens and the MANIFEST body from those C binaries (keeps the header)
#        tests/estimation/est_tools_parity.sh --run <est_fit> <est_eval> <est_eval_t> <outdir>
#          runs the cases with the given binaries, writes <outdir>/<group>.out (mutants, coverage);
#          with EST_STOP_GOLD=<golden dir> it stops at the first case that leaves the golden and
#          names it in <outdir>/.stop
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GOLD=$ROOT/tests/estimation/est_tools_golden
CASES=$ROOT/tests/estimation/est_tools_cases.txt
W=${EST_PARITY_WORK:-$(mktemp -d)}
mkdir -p "$W"
sha() { sha256sum "$1" | cut -c1-64; }
abs() { case $1 in /*) echo "$1" ;; *) echo "$(pwd)/$1" ;; esac; }

# run_cases <fit> <eval> <evalt> <outdir>: fresh fixtures, every case in order
run_cases() {
  _fit=$1; _ev=$2; _evt=$3; _o=$4
  FX=$_o.fx
  rm -rf "$FX" "$_o"; mkdir -p "$_o"
  sh "$ROOT/tests/estimation/est_tools_fixtures.sh" "$ROOT" "$FX" > /dev/null
  A=evidence/R15/raw/20260929T020536Z-ad8e1f2ea4e4-silicon
  B=evidence/R15/raw/20260929T025735Z-3e9e53be3358-silicon
  grep -v '^#' "$CASES" | while IFS='|' read -r grp name tool envs args; do
    [ -n "$grp" ] || continue
    g=$_o/$grp.out
    mkdir -p "$FX/out/$grp.$name"
    case $tool in fit) bin=$_fit ;; eval) bin=$_ev ;; evalt) bin=$_evt ;; sh) bin="" ;; *) echo "bad tool $tool" >&2; exit 2 ;; esac
    rc=0
    if [ -z "$bin" ]; then
      (cd "$FX" && sh -c "$args") > "$_o/.so" 2> "$_o/.se" || rc=$?
    else
      (cd "$FX" && eval "env -i PATH=\"\$PATH\" TMPDIR=\"\$FX/tmp\" $envs \"\$bin\" $args") > "$_o/.so" 2> "$_o/.se" || rc=$?
    fi
    {
      echo "== $name exit=$rc"
      if [ -n "$bin" ]; then
        cp "$_o/.so" "$_o/.so2"
        for f in $(cd "$FX" && find "out/$grp.$name" -type f -name '*.json' | sort); do
          h=$(sha "$FX/$f")
          sed "s|$h|RECEIPT($f)|g" "$_o/.so2" > "$_o/.so3"; mv "$_o/.so3" "$_o/.so2"
        done
        echo "-- stdout"; cat "$_o/.so2"
        echo "-- stderr"; cat "$_o/.se"
      fi
      for f in $(cd "$FX" && find "out/$grp.$name" -type f | sort); do
        case $f in
          *.stream) echo "-- file $f sha256 $(sha "$FX/$f")" ;;
          *.json) echo "-- file $f"; sed -E 's/"eval_binary_sha256": "[0-9a-f]{64}"/"eval_binary_sha256": "BIN"/' "$FX/$f" ;;
          *) echo "-- file $f"; cat "$FX/$f" ;;
        esac
      done
    } >> "$g"
    # mutant runs stop at the first case whose output leaves the golden
    if [ -n "${EST_STOP_GOLD:-}" ] && ! head -c "$(wc -c < "$g")" "$EST_STOP_GOLD/$grp.out" | cmp -s - "$g"; then
      echo "$grp.$name" > "$_o/.stop"; break
    fi
  done
  rm -f "$_o/.so" "$_o/.so2" "$_o/.se"
}

case ${1:-} in
--run)
  run_cases "$(abs "$2")" "$(abs "$3")" "$(abs "$4")" "$5"; exit 0 ;;
--generate)
  CF=$(abs "${2:?C est_fit}"); CE=$(abs "${3:?C est_eval}"); CT=$(abs "${4:?C est_eval_t}")
  hdr=$(head -n 1 "$GOLD/MANIFEST" 2>/dev/null | grep '^# generated once ' || true)
  [ -n "$hdr" ] || { echo "EST_TOOLS_PARITY FAIL write the MANIFEST header line (commit, generator command) first"; exit 2; }
  run_cases "$CF" "$CE" "$CT" "$W/c"
  rm -f "$GOLD"/*.out
  cp "$W/c"/*.out "$GOLD/"
  { printf 'corpus cases %s\n' "$(sha "$CASES")"
    printf 'corpus fixtures %s\n' "$(sha "$ROOT/tests/estimation/est_tools_fixtures.sh")"
    printf 'corpus fixture-tree %s\n' "$(cd "$W/c.fx" && find . -path ./out -prune -o -path ./tmp -prune -o -type f -print | sort | xargs sha256sum | sha256sum | cut -c1-64)"
    for g in "$GOLD"/*.out; do printf 'golden %s %s\n' "$(basename "$g" .out)" "$(sha "$g")"; done; } > "$W/MANIFEST.body"
  { printf '%s\n' "$hdr"
    printf '# goldens sha256 (of the corpus and golden lines below) %s\n' "$(sha "$W/MANIFEST.body")"
    cat "$W/MANIFEST.body"; } > "$GOLD/MANIFEST"
  echo "EST_TOOLS_PARITY generated $(grep -c '^golden ' "$GOLD/MANIFEST") goldens in $GOLD"
  exit 0 ;;
esac

OMC=$(abs "${1:-$ROOT/seed/out/omc}")
LIB=${EST_OM_LIB:?set EST_OM_LIB to the ESTT_OM_LIB list of mk/estimation_tools.mk}
M=$GOLD/MANIFEST
[ -f "$M" ] || { echo "EST_TOOLS_PARITY FAIL missing $M"; exit 2; }
grep -q '^# generated once from the C at main commit 3f2c70dc5' "$M" \
  || { echo "EST_TOOLS_PARITY FAIL $M header line does not name the C reference commit"; exit 2; }
grep -v '^#' "$M" > "$W/MANIFEST.body"
[ "$(sed -n 2p "$M")" = "# goldens sha256 (of the corpus and golden lines below) $(sha "$W/MANIFEST.body")" ] \
  || { echo "EST_TOOLS_PARITY FAIL $M body does not match its recorded sha256"; exit 2; }
bad=0
[ "$(awk '$2 == "cases" { print $3 }' "$M")" = "$(sha "$CASES")" ] || { echo "EST_TOOLS_PARITY FAIL the cases are not the ones the goldens were generated from"; bad=1; }
[ "$(awk '$2 == "fixtures" { print $3 }' "$M")" = "$(sha "$ROOT/tests/estimation/est_tools_fixtures.sh")" ] || { echo "EST_TOOLS_PARITY FAIL the fixture generator is not the one the goldens were generated from"; bad=1; }
for g in $(awk '$1 == "golden" { print $2 }' "$M"); do
  [ -f "$GOLD/$g.out" ] && [ "$(awk -v g="$g" '$1 == "golden" && $2 == g { print $3 }' "$M")" = "$(sha "$GOLD/$g.out")" ] \
    || { echo "EST_TOOLS_PARITY FAIL golden $g.out missing or not the recorded sha256"; bad=1; }
done
[ "$(ls "$GOLD"/*.out | wc -l | tr -d ' ')" -eq "$(grep -c '^golden ' "$M")" ] || { echo "EST_TOOLS_PARITY FAIL a golden file the MANIFEST does not list"; bad=1; }
[ "$bad" -eq 0 ] || exit 2

# ---- the OM-2 tools, composed as mk/estimation_tools.mk composes them ----
cd "$ROOT"
mkdir -p "$W/om"
printf 'text t_ee_tool_commit "%s"\nconst EE_TOOL_DIRTY ulong %s\nconst EE_TEST_BUILD ulong 0\n' parity-commit 0 > "$W/om/toolid.om"
printf 'text t_ee_tool_commit "test-build"\nconst EE_TOOL_DIRTY ulong 1\nconst EE_TEST_BUILD ulong 1\n' > "$W/om/toolid_t.om"
# shellcheck disable=SC2086
cat $LIB tools/estimation/est_fit.om | "$OMC" > "$W/om/est_fit"
# shellcheck disable=SC2086
cat $LIB "$W/om/toolid.om" tools/estimation/est_eval.om | "$OMC" > "$W/om/est_eval"
# shellcheck disable=SC2086
cat $LIB "$W/om/toolid_t.om" tools/estimation/est_eval.om | "$OMC" > "$W/om/est_eval_t"
chmod +x "$W/om/est_fit" "$W/om/est_eval" "$W/om/est_eval_t"
run_cases "$W/om/est_fit" "$W/om/est_eval" "$W/om/est_eval_t" "$W/o"
nfx=$(cd "$W/o.fx" && find . -path ./out -prune -o -path ./tmp -prune -o -type f -print | sort | xargs sha256sum | sha256sum | cut -c1-64)
[ "$(awk '$2 == "fixture-tree" { print $3 }' "$M")" = "$nfx" ] || { echo "EST_TOOLS_PARITY FAIL the fixture tree written here is not the one the goldens were generated from"; exit 2; }

files=0; cases=0; diff=0
for g in $(awk '$1 == "golden" { print $2 }' "$M"); do
  n=$(grep -c '^== ' "$GOLD/$g.out")
  files=$((files + 1)); cases=$((cases + n))
  if cmp -s "$GOLD/$g.out" "$W/o/$g.out"; then
    echo "PARITY $g cases=$n same"
  else
    diff=$((diff + 1))
    echo "PARITY $g cases=$n DIFF"
    diff "$GOLD/$g.out" "$W/o/$g.out" | head -20 || true
  fi
done
echo "EST_TOOLS_PARITY groups=$files cases=$cases diff=$diff reference=C@3f2c70dc5 (goldens) work=$W"
[ "$diff" -eq 0 ]
