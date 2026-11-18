#!/usr/bin/env bash
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

# gate_claims_lint.sh: OMEGA-GATE-CLAIMS, CA1 of the RCCA of the aienux fold (2026-11-18, kind K1:
# a claim broader than its check). A sentence about gates or checks that uses one of the words
# every, any, all, never, cannot or only has to name a control the gate runs, as [ctl:<GATE-ID>/<name>]
# inside the sentence [ctl:OMEGA-GATE-CLAIMS/uncited-claim].
#
# Text read: the tracked files under kernel/ (except kernel/evidence/, kernel/import/ and
# kernel/vendor/), and the files under tools/ and tests/gates/ that differ from the merge base of
# AIEN_BASE_REF (default origin/main) and HEAD, work tree and untracked files included [ctl:OMEGA-GATE-CLAIMS/tools-changed-file].
#   - *.md, *.txt, README*: the prose; fenced code blocks are skipped, and a heading, a table row
#     and a list item each start a new paragraph;
#   - shell, make, *.gate and *.py: whole-line # comments; consecutive ones form one paragraph
#     [ctl:OMEGA-GATE-CLAIMS/shell-comment-paragraph];
#   - *.c, *.h, *.rs: // comment lines and /* */ blocks [ctl:OMEGA-GATE-CLAIMS/c-block-comment];
#   - *.lean: -- comment lines and /- -/ blocks.
# Not read: *.om, *.toml, *.json, *.tsv, assembly and other kinds of file, comments at the end
# of a code line, and tools/gate-claims-baseline.txt.
# A paragraph is split into sentences at . ! or ? followed by a space or its end. A sentence is a
# claim when it has one of the six words and one of gate, check, control, test, mutant, verdict,
# pass, fail, not_run or refuse (whole words in upper or lower case, with their plural and past forms).
# Citations and gate ids (capitals, digits and _ joined by -, such as OMEGA-KERNEL-VERIFY-ALL) are
# taken out of the sentence before the words are looked for.
#
# A citation is valid when GATE-ID is the gate: of a manifest under tests/gates/, and name is listed
# in tests/gates/controls/GATE-ID.controls [ctl:OMEGA-GATE-CLAIMS/unknown-gate]
# [ctl:OMEGA-GATE-CLAIMS/unlisted-control], or appears in a log passed with --log as the line
# "CONTROL GATE-ID/name FAILED_AS_REQUIRED" [ctl:OMEGA-GATE-CLAIMS/log-citation]. A .controls file
# binds only because tests/gates/run.sh runs that gate's step through step_verdict, which fails the
# step when the run lacks the CONTROL line of a listed name; so a .controls file for a gate whose
# step does not go through step_verdict (OMEGA-KERNEL-* through kernel_step, others by a literal
# "step_verdict GATE-ID" call) is itself refused [ctl:OMEGA-GATE-CLAIMS/unwrapped-gate-controls].
#
# Existing claims: tools/gate-claims-baseline.txt lists, as "path<TAB>sentence", the uncited claims
# this lint found at omega-mv 5cd0af98f (the third review head of the fold). A listed sentence is not
# reported while its file keeps it word for word; an edited sentence is a new claim
# [ctl:OMEGA-GATE-CLAIMS/baseline-edited]. Rows nobody needs any more are counted (baseline_stale).
#
# Usage: gate_claims_lint.sh [--log FILE]...   its planted controls, then this checkout
#        gate_claims_lint.sh --no-controls [--log FILE]...   this checkout, without the controls
#        gate_claims_lint.sh --baseline         print the baseline rows for this checkout
# Exit 0 PASS, 1 FAIL (uncited or invalid citations, or a control that did not fail as required),
# 3 NOT_RUN (not a git checkout, or no base ref) [ctl:OMEGA-GATE-CLAIMS/no-base-not-run].
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF="$ROOT/tools/gate_claims_lint.sh"
BASELINE_FILE=tools/gate-claims-baseline.txt
obs() { printf 'AIEN-OBS %s %s\n' "$1" "$2"; }

mode=full; logs=()
while [ $# -gt 0 ]; do
  case "$1" in
    --log) [ $# -ge 2 ] && [ -r "$2" ] || { echo "usage: $0 [--no-controls|--baseline] [--log FILE]..." >&2; exit 2; }; logs+=("$2"); shift ;;
    --no-controls) mode=lint ;;
    --baseline) mode=baseline ;;
    *) echo "usage: $0 [--no-controls|--baseline] [--log FILE]..." >&2; exit 2 ;;
  esac
  shift
done

# kind PATH: md, hash, c, lean or nothing.
kind() {
  case "${1##*/}" in
    gate-claims-baseline.txt) ;;
    *.md|*.markdown|*.txt|README|README.*) echo md ;;
    *.sh|*.bash|*.mk|Makefile|*.Makefile|GNUmakefile|*.gate|*.py) echo hash ;;
    *.c|*.h|*.rs) echo c ;;
    *.lean) echo lean ;;
  esac
}

# The extractor: for each file (preceded by T=<kind> on the awk command line) prints
# "CLAIM<TAB>path<TAB>line<TAB>sentence" for every claim, the sentence with its whitespace collapsed.
EXTRACT='
function flush(   p, s, off, i, ln, st) {
  if (para == "") return
  p = para; off = 0
  while (p != "") {
    if (match(p, /[.!?]( |$)/)) { s = substr(p, 1, RSTART); p = substr(p, RSTART + RLENGTH) }
    else { s = p; p = "" }
    st = off; off += length(s) + 1
    gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s)
    while (substr(p, 1, 1) == " ") { p = substr(p, 2); off++ }
    if (s == "") continue
    ln = pline[1]; for (i = 1; i <= np; i++) if (poff[i] <= st) ln = pline[i]
    l = s; gsub(/\[ctl:[^]]*\]/, " ", l); gsub(/[A-Z0-9_]+(-[A-Z0-9_]+)+/, " ", l); l = tolower(l)
    if (l ~ /(^|[^a-z0-9_])(every|any|all|never|cannot|only)([^a-z0-9_]|$)/ &&
        l ~ /(^|[^a-z0-9_])(gate|gates|gated|check|checks|checked|control|controls|test|tests|tested|mutant|mutants|verdict|verdicts|pass|passes|passed|fail|fails|failed|not_run|refuse|refuses|refused|refusal)([^a-z0-9_]|$)/)
      printf "CLAIM\t%s\t%d\t%s\n", cur, ln, s
  }
  para = ""; np = 0
}
function add(t) {
  sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
  if (t == "") { flush(); return }
  np++; pline[np] = FNR; poff[np] = length(para) + (para == "" ? 0 : 1)
  para = (para == "" ? t : para " " t)
}
FNR == 1 { flush(); cur = FILENAME; fence = 0; blk = 0 }
T == "md" {
  if ($0 ~ /^[ \t]*(```|~~~)/) { flush(); fence = !fence; next }
  if (fence) next
  if ($0 ~ /^[ \t]*$/) { flush(); next }
  if ($0 ~ /^#+ / || $0 ~ /^[ \t]*\|/) { flush(); add($0); flush(); next }
  if ($0 ~ /^[ \t]*([-*+]|[0-9]+\.) /) flush()
  add($0); next
}
T == "hash" {
  if ($0 ~ /^[ \t]*#/ && $0 !~ /^#!/) { t = $0; sub(/^[ \t]*#+/, "", t); if (t ~ /^[ \t]*([-*]|[0-9]+\.) /) flush(); add(t); if (t ~ /^[ \t]*$/) flush() }
  else flush()
  next
}
T == "c" {
  t = $0
  if (blk) {
    if ((i = index(t, "*/"))) { t = substr(t, 1, i - 1); blk = 0 }
    sub(/^[ \t]*\*+/, "", t); add(t); if (!blk) flush(); next
  }
  if (t ~ /^[ \t]*\/\//) { sub(/^[ \t]*\/\/[\/!]*/, "", t); add(t); next }
  if ((i = index(t, "/*"))) {
    flush(); t = substr(t, i + 2); sub(/^[*!]+/, "", t)
    if ((j = index(t, "*/"))) { add(substr(t, 1, j - 1)); flush() } else { blk = 1; add(t) }
    next
  }
  flush(); next
}
T == "lean" {
  t = $0
  if (blk) {
    if ((i = index(t, "-/"))) { t = substr(t, 1, i - 1); blk = 0 }
    add(t); if (!blk) flush(); next
  }
  if (t ~ /^[ \t]*--/) { sub(/^[ \t]*--+/, "", t); add(t); next }
  if (t ~ /^[ \t]*\/-/) {
    flush(); sub(/^[ \t]*\/-[-!]?/, "", t)
    if ((j = index(t, "-/"))) { add(substr(t, 1, j - 1)); flush() } else { blk = 1; add(t) }
    next
  }
  flush(); next
}
END { flush() }
'

# lint DIR: the lint of the checkout DIR. Prints its findings and the verdict line; returns 0, 1 or 3.
lint() {
  local dir="$1" base mb files args=() f k gates wrapped ctlfile g n uncited=0 bad=0 claims=0 cited=0 stale=0 based=0 out
  cd "$dir" || return 3
  git rev-parse --is-inside-work-tree > /dev/null 2>&1 || { echo "GATE-CLAIMS NOT_RUN: $dir is not a git checkout"; return 3; }
  base="${AIEN_BASE_REF:-origin/main}"
  mb="$(git merge-base "$base" HEAD 2>/dev/null)" || { echo "GATE-CLAIMS NOT_RUN: no merge base of $base and HEAD (set AIEN_BASE_REF)"; return 3; }
  files="$( { git ls-files --cached --others --exclude-standard -- kernel/ | grep -vE '^kernel/(evidence|import|vendor)/'
             git diff --name-only "$mb" -- tools/ tests/gates/
             git ls-files --others --exclude-standard -- tools/ tests/gates/; } | sort -u)"
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    k="$(kind "$f")"; [ -n "$k" ] || continue
    case "$f" in [A-Za-z_]*=*) continue ;; esac
    args+=("T=$k" "$f")
  done <<< "$files"
  # Gates with a manifest; gates whose step goes through step_verdict; their listed controls.
  gates="$(sed -n 's/^gate: *\([A-Za-z0-9_.-]*\) *$/\1/p' tests/gates/*.gate 2>/dev/null | sort -u)"
  wrapped="$( { grep -oE 'step_verdict [A-Za-z0-9_.-]+ ' tests/gates/run.sh 2>/dev/null | awk '{print $2}'
               if grep -qE '^  kernel-\*\) +kernel_step "\$\{step#kernel-\}" ;;$' tests/gates/run.sh 2>/dev/null; then grep -x 'OMEGA-KERNEL-.*' <<< "$gates"; fi; } | grep -v '^step_verdict$' | sort -u)"
  CTL="$(mktemp)"; : > "$CTL"
  for ctlfile in tests/gates/controls/*.controls; do
    [ -e "$ctlfile" ] || continue
    g="${ctlfile##*/}"; g="${g%.controls}"
    if ! grep -qxF -- "$g" <<< "$gates"; then echo "BADCONTROLS $ctlfile: no manifest under tests/gates/ names gate $g"; bad=$((bad + 1)); continue; fi
    if ! grep -qxF -- "$g" <<< "$wrapped"; then echo "BADCONTROLS $ctlfile: tests/gates/run.sh does not run $g through step_verdict, so nothing requires its controls"; bad=$((bad + 1)); continue; fi
    grep -vE '^(#|$)' "$ctlfile" | sed "s|^|$g/|" >> "$CTL"
  done
  for f in "${logs[@]}"; do sed -n 's/^CONTROL \([A-Za-z0-9_.-]*\/[a-z0-9][a-z0-9._-]*\) FAILED_AS_REQUIRED$/\1/p' "$f" | while IFS= read -r n; do
      grep -qxF -- "${n%%/*}" <<< "$gates" && echo "$n"; done >> "$CTL"; done
  out="$(mktemp)"
  if [ ${#args[@]} -gt 0 ]; then LC_ALL=C awk "$EXTRACT" "${args[@]}" > "$out"; else : > "$out"; fi
  if [ "$mode" = baseline ]; then
    awk -F '\t' '$4 !~ /\[ctl:/ {print $2 "\t" $4}' "$out" | sort -u
    rm -f "$out" "$CTL"; return 0
  fi
  local base_rows; base_rows="$(mktemp)"
  [ ! -f "$BASELINE_FILE" ] || grep -v '^#' "$BASELINE_FILE" > "$base_rows"
  local res; res="$(LC_ALL=C awk -F '\t' -v ctl="$CTL" -v brows="$base_rows" -v gates="$(tr '\n' ' ' <<< "$gates")" '
    BEGIN { while ((getline l < ctl) > 0) ok[l] = 1; while ((getline l < brows) > 0) bl[l] = 1
            n = split(gates, g, " "); for (i = 1; i <= n; i++) gate[g[i]] = 1 }
    { claims++; s = $4; nc = 0; badc = 0
      while (match(s, /\[ctl:[A-Za-z0-9_.-]+\/[a-z0-9][a-z0-9._-]*\]/)) {
        c = substr(s, RSTART + 5, RLENGTH - 6); s = substr(s, RSTART + RLENGTH); nc++
        if (c !~ /^[A-Za-z0-9_.-]+\/[a-z0-9][a-z0-9._-]*$/) { print "BADCITE " $2 ":" $3 ": [ctl:" c "] is not [ctl:GATE-ID/name]"; badc++; continue }
        split(c, p, "/")
        if (!(p[1] in gate)) { print "BADCITE " $2 ":" $3 ": [ctl:" c "]: no manifest under tests/gates/ names gate " p[1]; badc++; continue }
        if (!(c in ok)) { print "BADCITE " $2 ":" $3 ": [ctl:" c "]: tests/gates/controls/" p[1] ".controls does not list " p[2] " and no --log reports it"; badc++; continue }
      }
      if (badc) { bad += badc; next }
      if (nc) { cited++; next }
      if (($2 "\t" $4) in bl) { based++; used[$2 "\t" $4] = 1; next }
      print "UNCITED " $2 ":" $3 ": " $4; uncited++
    }
    END { for (k in bl) if (!(k in used)) stale++
          printf "TOTALS %d %d %d %d %d %d\n", claims, cited, based, uncited, bad, stale }' "$out")"
  rm -f "$out" "$CTL" "$base_rows"
  grep -v '^TOTALS ' <<< "$res"
  read -r _ claims cited based n k stale <<< "$(grep '^TOTALS ' <<< "$res")"
  uncited=$n; bad=$((bad + k))
  obs gate_claims_uncited "$uncited"
  obs gate_claims_bad_citations "$bad"
  obs gate_claims_baseline_stale "$stale"
  if [ "$uncited" = 0 ] && [ "$bad" = 0 ]; then
    echo "GATE-CLAIMS PASS files=$(( ${#args[@]} / 2 )) claims=$claims cited=$cited baseline=$based stale_baseline_rows=$stale"; return 0
  fi
  echo "GATE-CLAIMS FAIL uncited=$uncited bad_citations=$bad (cite [ctl:GATE-ID/name], or narrow the sentence to what is checked)"; return 1
}

# self_test: planted controls in a scratch repository: its main branch holds the gate manifests,
# tests/gates/run.sh and tests/gates/controls/ of this checkout, this script, a small baseline and a
# few files; each control plants one change on top and the lint must give the stated result.
self_test() {
  local tmp s killed=0 survived=0 rc
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/gate-claims.XXXXXX")"; s="$tmp/repo"
  mkdir -p "$s/tests/gates" "$s/tools" "$s/kernel/scripts"
  cp "$ROOT"/tests/gates/*.gate "$ROOT/tests/gates/run.sh" "$s/tests/gates/"
  [ ! -d "$ROOT/tests/gates/controls" ] || cp -r "$ROOT/tests/gates/controls" "$s/tests/gates/"
  mkdir -p "$s/tests/gates/controls"
  printf 'listed-control\n' > "$s/tests/gates/controls/OMEGA-GATE-CLAIMS.controls"
  cp "$SELF" "$s/tools/gate_claims_lint.sh"
  printf '# Kernel\n\nEvery gate here passes.\n' > "$s/kernel/README.md"
  printf '#!/bin/sh\n# Every tool here is checked once.\ntrue\n' > "$s/tools/old.sh"
  printf 'kernel/README.md\tEvery gate here passes.\n' > "$s/$BASELINE_FILE"
  git -C "$s" init -q -b main && git -C "$s" add -A && git -C "$s" -c user.name=t -c user.email=t@t commit -qm main || { echo "control setup: cannot build the scratch repository"; rm -rf "$tmp"; return 1; }
  git -C "$s" checkout -q -b work
  # run NAME SNIPPET: reset the scratch work tree to main, apply SNIPPET, lint; sets rc and the log.
  run() {
    git -C "$s" checkout -q -f work && git -C "$s" reset -q --hard main && git -C "$s" clean -qfdx
    (cd "$s" && eval "$2") || { echo "control $1: could not plant"; rc=99; return; }
    rc=0; (cd "$s" && env AIEN_BASE_REF=main bash tools/gate_claims_lint.sh --no-controls "${@:3}") > "$tmp/$1.log" 2>&1 || rc=$?
  }
  ctl() {  # NAME SNIPPET REGEX [ARGS...]: the lint must exit 1 with a line matching REGEX
    run "$1" "$2" "${@:4}"
    if [ "$rc" = 1 ] && grep -qE -- "$3" "$tmp/$1.log"; then killed=$((killed + 1)); echo "CONTROL OMEGA-GATE-CLAIMS/$1 FAILED_AS_REQUIRED"
    else survived=$((survived + 1)); echo "control $1: exit $rc without a line matching '$3'; the lint misses it"; tail -n 3 "$tmp/$1.log"; fi
  }
  pos() {  # NAME SNIPPET [ARGS...]: the lint must pass
    run "$1" "$2" "${@:3}"
    if [ "$rc" = 0 ]; then echo "control $1: PASS as required"
    else survived=$((survived + 1)); echo "control $1: exit $rc, not PASS; the controls above prove nothing"; tail -n 3 "$tmp/$1.log"; fi
  }
  pos clean true
  ctl uncited-claim "printf '\nAny NOT_RUN line fails this gate.\n' >> kernel/README.md" '^UNCITED kernel/README\.md:5: Any NOT_RUN line fails this gate\.$'
  pos cited-claim "printf '\nAny NOT_RUN line fails this gate [ctl:OMEGA-GATE-CLAIMS/listed-control].\n' >> kernel/README.md"
  ctl unknown-gate "printf '\nAny NOT_RUN line fails this gate [ctl:OMEGA-NO-SUCH-GATE/x].\n' >> kernel/README.md" '^BADCITE kernel/README\.md:5: .*no manifest under tests/gates/ names gate OMEGA-NO-SUCH-GATE'
  ctl unlisted-control "printf '\nAny NOT_RUN line fails this gate [ctl:OMEGA-GATE-CLAIMS/not-listed].\n' >> kernel/README.md" 'does not list not-listed'
  ctl shell-comment-paragraph "mkdir -p kernel/scripts; printf '#!/bin/sh\n# This step refuses\n# any input it was not given. Then it stops.\ntrue\n' > kernel/scripts/p.sh" '^UNCITED kernel/scripts/p\.sh:2: This step refuses any input it was not given\.$'
  ctl c-block-comment "mkdir -p kernel/scripts; printf 'int x;\n/*\n * The tests only cover\n * the slow path.\n */\nint y; // all checks pass\n' > kernel/scripts/p.c" '^UNCITED kernel/scripts/p\.c:3: The tests only cover the slow path\.$'
  ctl baseline-edited "sed -i 's/Every gate here passes\./Every gate here passes today./' kernel/README.md" '^UNCITED kernel/README\.md:3: Every gate here passes today\.$'
  ctl tools-changed-file "printf '#!/bin/sh\n# Every tool here is checked twice.\ntrue\n' > tools/old.sh" '^UNCITED tools/old\.sh:2: Every tool here is checked twice\.$'
  ctl last-paragraph-path "printf 'x\n\nEvery gate here is new.' > kernel/A.md; printf 'y\n' > kernel/B.md" '^UNCITED kernel/A\.md:3: Every gate here is new\.$'
  ctl unwrapped-gate-controls "printf 'x\n' > tests/gates/controls/OMEGA-SEED.controls" 'BADCONTROLS tests/gates/controls/OMEGA-SEED\.controls: tests/gates/run\.sh does not run OMEGA-SEED through step_verdict'
  printf 'CONTROL OMEGA-GATE-CLAIMS/from-log FAILED_AS_REQUIRED\n' > "$tmp/ctl.log"
  pos log-citation-accepted "printf '\nAny NOT_RUN line fails this gate [ctl:OMEGA-GATE-CLAIMS/from-log].\n' >> kernel/README.md" --log "$tmp/ctl.log"
  ctl log-citation "printf '\nAny NOT_RUN line fails this gate [ctl:OMEGA-GATE-CLAIMS/from-log].\n' >> kernel/README.md" 'does not list from-log and no --log reports it'
  rc=0; (cd "$s" && env AIEN_BASE_REF=no-such-ref bash tools/gate_claims_lint.sh --no-controls) > "$tmp/nobase.log" 2>&1 || rc=$?
  if [ "$rc" = 3 ] && grep -q '^GATE-CLAIMS NOT_RUN: no merge base' "$tmp/nobase.log"; then killed=$((killed + 1)); echo "CONTROL OMEGA-GATE-CLAIMS/no-base-not-run FAILED_AS_REQUIRED"
  else survived=$((survived + 1)); echo "control no-base-not-run: exit $rc, not 3"; fi
  rm -rf "$tmp"
  echo "gate-claims controls: $killed failed as required, $survived did not"
  [ "$survived" = 0 ]
}

case "$mode" in
  baseline) lint "$ROOT"; exit $? ;;
  lint) lint "$ROOT"; exit $? ;;
esac
st=0; self_test || st=$?
rc=0; lint "$ROOT" || rc=$?
[ "$st" = 0 ] || { echo "GATE-CLAIMS FAIL: a planted control did not fail as required"; exit 1; }
exit "$rc"
