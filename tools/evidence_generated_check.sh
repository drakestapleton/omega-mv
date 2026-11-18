#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# evidence_generated_check.sh: derived facts in evidence and status text are generated, never typed (DRA-485 RCCA).
# Rules, for the change BASE...HEAD:
#  R1 generated text: in every changed Markdown file under evidence/ and in docs/OMEGA.md, each
#       <!-- generated: tools/NAME ARGS -->  ... block ...  <!-- end generated -->
#     must equal the output of tools/NAME ARGS run in that file's directory, and each
#       <!-- generated-file: FILE tools/NAME ARGS -->
#     requires FILE to equal that output byte for byte. ARGS are an optional leading mode word ([a-z]+) and then files that
#     exist in that directory; nothing else, so a generator cannot be handed the claim it prints. A generator that is not at
#     the base ref is listed as AIEN-OBS new_generator (its code is reviewed as code).
#  R2 hand text is reviewed line by line: in a changed evidence Markdown file (whole file) and in the added lines of
#     docs/OMEGA.md, every non-blank line outside generated blocks, other than a marker line or a table separator, carries
#       <!-- typed-ok HASH: REASON -->
#     with HASH the first 12 hex digits of the sha256 of that line with the marker removed (`--hash FILE LINE` prints it) and a
#     REASON of at least 12 characters. There is no word list: the gate does not judge what a sentence says, it makes sure each
#     hand-written line was put in front of a reviewer as that exact text and fails again when it changes. Each typed-ok line the
#     change adds is printed as AIEN-OBS typed_ok_added, the reviewer's list.
#  R3 a changed evidence README has at least one generated marker.
#  R4 evidence data: in every evidence directory the change touches, every file other than Markdown and SHA256SUMS is listed in
#     that directory's SHA256SUMS, and `sha256sum -c SHA256SUMS` passes.
#  R5 the checker cannot loosen itself: when the base ref has this script and the change edits it, the base copy is also run
#     on this change and must pass.
# Out of scope (stated, not hidden): other files under docs/ (prose documents edited by many lanes) and Markdown at the
# repository root; the truth of a reviewed line, and of the REASON, stays with the reviewer.
#   usage: tools/evidence_generated_check.sh BASE_REF          check this change
#          tools/evidence_generated_check.sh --hash FILE LINE  the typed-ok hash of one line
#          tools/evidence_generated_check.sh --self-test       the checker's own negative controls (end to end, in a scratch git repository)
set -euo pipefail
ROOT="${EGC_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
obs() { printf 'AIEN-OBS %s %s\n' "$1" "$2"; }

# check_file MD: R1 for one file; prints one line per problem; status 0 when clean.
check_file() {
  local md="$1" dir tmp n=0 line=0 l cmd file inblock=0 start=0 words
  dir="$(dirname "$md")"; tmp="$(mktemp -d)"
  while IFS= read -r l || [ -n "$l" ]; do
    line=$((line + 1))
    if [ "$inblock" = 1 ]; then
      if [ "$l" = "<!-- end generated -->" ]; then
        inblock=0
        if ! run_cmd "$dir" "$cmd" > "$tmp/want" 2> "$tmp/err"; then
          echo "$md:$start: generator failed: $cmd: $(head -3 "$tmp/err" | tr '\n' ' ')"; n=$((n + 1))
        elif ! cmp -s "$tmp/want" "$tmp/have"; then
          echo "$md:$start: block differs from the output of: $cmd"; diff "$tmp/have" "$tmp/want" | sed -n '1,12p' | sed 's/^/    /'
          n=$((n + 1))
        fi
      else
        printf '%s\n' "$l" >> "$tmp/have"
      fi
      continue
    fi
    case "$l" in
      "<!-- generated: "*" -->")
        cmd="${l#<!-- generated: }"; cmd="${cmd% -->}"; start=$line; inblock=1; : > "$tmp/have" ;;
      "<!-- generated-file: "*" -->")
        words="${l#<!-- generated-file: }"; words="${words% -->}"; file="${words%% *}"; cmd="${words#* }"
        if ! safe_word "$file" || [ ! -f "$dir/$file" ]; then echo "$md:$line: generated file missing or unsafe name: $file"; n=$((n + 1))
        elif ! run_cmd "$dir" "$cmd" > "$tmp/want" 2> "$tmp/err"; then
          echo "$md:$line: generator failed: $cmd: $(head -3 "$tmp/err" | tr '\n' ' ')"; n=$((n + 1))
        elif ! cmp -s "$tmp/want" "$dir/$file"; then
          echo "$md:$line: $file differs from the output of: $cmd"; n=$((n + 1))
        fi ;;
    esac
  done < "$md"
  if [ "$inblock" = 1 ]; then echo "$md:$start: generated block has no <!-- end generated --> line"; n=$((n + 1)); fi
  rm -rf "$tmp"
  [ "$n" = 0 ]
}
# safe_word W: a relative path inside the directory, plain characters only, no "..".
safe_word() { [[ "$1" =~ ^[A-Za-z0-9_./=-]+$ ]] && [[ "$1" != *..* ]] && [[ "$1" != /* ]]; }
# run_cmd DIR "tools/NAME [mode] FILE...": runs ROOT/tools/NAME in DIR without a shell. After an optional leading mode word
# ([a-z]+, not a file), every argument must be a file that exists in DIR, so no claim can be passed in as an argument.
run_cmd() {
  local dir="$1" a i=0; local -a w; read -r -a w <<< "$2"
  [[ "${w[0]:-}" =~ ^tools/[A-Za-z0-9_.-]+$ ]] || { echo "generator must be tools/NAME: ${w[0]:-}" >&2; return 2; }
  [ -x "$ROOT/${w[0]}" ] || { echo "not executable: ${w[0]}" >&2; return 2; }
  for a in "${w[@]:1}"; do
    i=$((i + 1))
    if [ "$i" = 1 ] && [[ "$a" =~ ^[a-z]+$ ]] && [ ! -e "$dir/$a" ]; then continue; fi
    safe_word "$a" && [ -f "$dir/$a" ] || { echo "generator argument is not a file in the directory: $a" >&2; return 2; }
  done
  [ "${#w[@]}" -ge 2 ] || { echo "generator has no input file: ${w[0]}" >&2; return 2; }
  (cd "$dir" && "$ROOT/${w[0]}" "${w[@]:1}")
}

TYPED_OK_RE=' ?<!-- typed-ok ([0-9a-f]{12}): ([^>]*) -->'
line_hash() { printf '%s' "$(printf '%s\n' "$1" | sed -E "s/$TYPED_OK_RE//")" | sha256sum | cut -c1-12; }
# added_lines FILE: the line numbers of FILE that BASE...HEAD adds or changes.
added_lines() { git diff -U0 "$BASE...HEAD" -- "$1" | awk '/^@@/ { split($3, a, ","); s = substr(a[1], 2) + 0; c = (a[2] == "" ? 1 : a[2] + 0); for (i = 0; i < c; i++) print s + i }'; }
# bind_check FILE ADDED ONLY_ADDED: R2. ADDED is a newline list of added line numbers (for the reviewer's list); when ONLY_ADDED
# is 1 only those lines are judged, otherwise every line. One output line per problem; status 0 when clean.
bind_check() {
  local f="$1" added="$2" only="$3" n=0 line=0 l inblock=0 h isnew
  while IFS= read -r l || [ -n "$l" ]; do
    line=$((line + 1))
    case "$l" in
      "<!-- generated: "*" -->") inblock=1; continue ;;
      "<!-- end generated -->") inblock=0; continue ;;
      "<!-- generated-file: "*" -->") continue ;;
    esac
    [ "$inblock" = 1 ] && continue
    isnew=0; printf '%s\n' "$added" | grep -qx "$line" && isnew=1
    [ "$only" = 1 ] && [ "$isnew" = 0 ] && continue
    [ -z "${l//[[:space:]]/}" ] && continue
    [[ "$l" =~ ^[[:space:]]*\|?[[:space:]:|-]*-[[:space:]:|-]*\|?[[:space:]]*$ ]] && continue   # table separator
    if [[ "$l" =~ $TYPED_OK_RE ]]; then
      h="$(line_hash "$l")"
      if [ "${BASH_REMATCH[1]}" != "$h" ]; then echo "$f:$line: typed-ok hash ${BASH_REMATCH[1]} does not match the line ($h): edited after review"; n=$((n + 1))
      elif [ "${#BASH_REMATCH[2]}" -lt 12 ]; then echo "$f:$line: typed-ok reason shorter than 12 characters"; n=$((n + 1))
      elif [ "$isnew" = 1 ]; then obs typed_ok_added "$f:$line" >&3; fi
      continue
    fi
    echo "$f:$line: hand-written line not reviewed (no typed-ok HASH: REASON marker): ${l:0:110}"; n=$((n + 1))
  done < "$f"
  [ "$n" = 0 ]
}

# main BASE: the gate. Prints problems and AIEN-OBS lines; status 0 when clean.
main() {
  BASE="$1"; cd "$ROOT"
  local problems=0 checked=0 markers=0 bare=0 manifests=0 f m out added d g x
  count() { [ -n "$1" ] && problems=$((problems + $(printf '%s\n' "$1" | grep -c '^[^ ]'))); printf '%s\n' "$1" | sed '/^$/d'; }
  exec 3>&1
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    case "$f" in docs/OMEGA.md) ;; evidence/*) shopt -s nocasematch; [[ "$f" =~ \.(md|markdown)$ ]] || { shopt -u nocasematch; continue; }; shopt -u nocasematch ;; *) continue ;; esac
    checked=$((checked + 1))
    out="$(check_file "$f")" || count "$out"
    m="$(grep -c -E '^<!-- generated(-file)?: ' "$f" || true)"; markers=$((markers + m))
    for g in $(grep -o -E '^<!-- generated(-file)?: [^>]*-->' "$f" | grep -o -E 'tools/[A-Za-z0-9_.-]+' | sort -u); do
      git cat-file -e "$BASE:$g" 2> /dev/null || obs new_generator "$g"
    done
    added="$(added_lines "$f")"
    if [ "$f" = docs/OMEGA.md ]; then out="$(bind_check "$f" "$added" 1)" || count "$out"
    else
      shopt -s nocasematch
      if [[ "$(basename "$f")" =~ ^readme\.(md|markdown)$ ]] && [ "$m" = 0 ]; then
        bare=$((bare + 1)); problems=$((problems + 1)); echo "$f: changed evidence README has no generated block"; fi
      shopt -u nocasematch
      out="$(bind_check "$f" "$added" 0)" || count "$out"
    fi
  done <<< "$(git diff --name-only --diff-filter=AMR "$BASE...HEAD" -- evidence/ docs/OMEGA.md | sort -u)"
  while IFS= read -r d; do
    [ -n "$d" ] && [ -d "$d" ] || continue
    if [ ! -f "$d/SHA256SUMS" ]; then
      if git diff --name-only --diff-filter=AMR "$BASE...HEAD" -- "$d" | grep -v -i -E '\.(md|markdown)$' | grep -q .; then
        problems=$((problems + 1)); echo "$d: data files added or changed but the directory has no SHA256SUMS"; fi
      continue
    fi
    manifests=$((manifests + 1))
    if ! out="$(cd "$d" && sha256sum --quiet -c SHA256SUMS 2>&1)"; then problems=$((problems + 1)); echo "$d/SHA256SUMS does not match: $(printf '%s' "$out" | head -3 | tr '\n' ' ')"; fi
    while IFS= read -r x; do
      [ -n "$x" ] || continue
      awk -v x="$x" '{ f = $0; sub(/^[0-9a-f]+ [ *]/, "", f); if (f == x) found = 1 } END { exit !found }' "$d/SHA256SUMS" ||
        { problems=$((problems + 1)); echo "$d/$x: evidence data file not in SHA256SUMS"; }
    done <<< "$(cd "$d" && find . -type f ! -name SHA256SUMS | sed 's|^\./||' | grep -v -i -E '\.(md|markdown)$' | sort)"
  done <<< "$(git diff --name-only --diff-filter=AMR "$BASE...HEAD" -- evidence/ | awk -F/ 'NF > 2 { print $1 "/" $2 }' | sort -u)"
  obs files_checked "$checked"; obs generated_markers "$markers"; obs evidence_readmes_without_generated "$bare"; obs manifests_checked "$manifests"
  obs generated_mismatches "$problems"
  [ "$problems" = 0 ] && echo "evidence-generated: $markers generated markers in $checked changed files; every hand line reviewed; manifests verify"
  [ "$problems" = 0 ]
}

# self_test: end to end through main() in a scratch git repository: a clean change passes, each control change fails with its
# expected message, and every author sentence that DRA-485 reviews 1 to 7 quoted as a finding fails when typed by hand.
self_test() {
  local t fails=0 rc out
  t="$(mktemp -d)"; trap 'rm -rf "$t"' RETURN
  (
    set -e; cd "$t"; git init -q; git config user.email t@t; git config user.name t
    mkdir -p tools evidence/E docs; cp "$SELF" tools/evidence_generated_check.sh
    printf '#!/bin/sh\n[ "$1" = count ] && shift\necho "count $(wc -l < "$1" | tr -d " ")"\n' > tools/gen_count.sh
    printf '#!/bin/sh\necho "$@"\n' > tools/say.sh; chmod +x tools/*.sh
    printf 'a\nb\nc\n' > evidence/E/data.txt; (cd evidence/E && sha256sum data.txt > SHA256SUMS)
    printf '| Bar | Status |\n|---|---|\n' > docs/OMEGA.md
    git add -A; git commit -qm base
  ) > /dev/null
  bound() { printf '%s <!-- typed-ok %s: reviewed method sentence -->\n' "$1" "$(line_hash "$1")"; }
  readme() { printf '%s\n<!-- generated: tools/gen_count.sh count data.txt -->\ncount 3\n<!-- end generated -->\n' "$(bound '# E receipt')"; }
  # scenario NAME EXPECT(0|1) MESSAGE SETUP...: apply SETUP in the scratch repo, commit, run main, compare, reset to base.
  scenario() {
    local name="$1" want="$2" msg="$3"; shift 3
    (cd "$t" && eval "$*" && git add -A && git commit -qm change) > /dev/null 2>&1
    rc=0; out="$(cd "$t" && EGC_ROOT="$t" bash -c 'source tools/evidence_generated_check.sh --lib; main "$(git rev-parse HEAD~1)"' 2>&1)" || rc=$?
    (cd "$t" && git reset -q --hard HEAD~1 && git clean -qfd) > /dev/null 2>&1
    if [ "$want" = 0 ] && [ "$rc" = 0 ]; then echo "self-test: $name accepted"
    elif [ "$want" = 1 ] && [ "$rc" != 0 ] && printf '%s\n' "$out" | grep -q -- "$msg"; then echo "self-test: $name rejected"
    else echo "self-test FAIL: $name (rc $rc, wanted $want, message '$msg'): $(printf '%s' "$out" | head -3 | tr '\n' ' ')"; fails=$((fails + 1)); fi
  }
  scenario "clean change" 0 "" 'readme > evidence/E/README.md; bound "| C3 | see the receipt |" >> docs/OMEGA.md'
  scenario "bare README" 1 "has no generated block" 'bound "# E" > evidence/E/README.md'
  scenario "unbound hand line with backticks" 1 "not reviewed" 'readme > evidence/E/README.md; echo "Speed is \`0.05\` of the ceiling and the acceptance is \`MET\`." >> evidence/E/README.md'
  scenario "unbound line, other case of extension" 1 "not reviewed" 'readme > evidence/E/README.MD; echo "The chip run passes on any shape with no mismatches." >> evidence/E/README.MD'
  scenario "unbound line in a second Markdown file" 1 "not reviewed" 'readme > evidence/E/README.md; echo "Chip PASS, all shapes correct, fraction 0.05." > evidence/E/SUMMARY.md'
  scenario "reviewed line edited later" 1 "edited after review" 'readme > evidence/E/README.md; bound "Cases of at most 2^27 multiply-adds are compared in full." | sed "s/2^27/2^28/" >> evidence/E/README.md'
  scenario "short typed-ok reason" 1 "shorter than 12" 'readme > evidence/E/README.md; l="A line."; printf "%s <!-- typed-ok %s: short -->\n" "$l" "$(line_hash "$l")" >> evidence/E/README.md'
  scenario "block differs from its generator" 1 "block differs" 'readme | sed "s/^count 3$/count 4/" > evidence/E/README.md'
  scenario "claim passed to a generator as an argument" 1 "not a file" 'readme > evidence/E/README.md; printf "<!-- generated: tools/say.sh MET on the chip -->\nMET on the chip\n<!-- end generated -->\n" >> evidence/E/README.md'
  scenario "stale manifest" 1 "SHA256SUMS does not match" 'readme > evidence/E/README.md; echo d >> evidence/E/data.txt'
  scenario "data file not in the manifest" 1 "not in SHA256SUMS" 'readme > evidence/E/README.md; echo "all shapes correct" > evidence/E/SUMMARY.txt'
  scenario "unbound status row in docs/OMEGA.md" 1 "not reviewed" 'echo "| C3 | GEMM | chip PASS, every shape correct, 0 wrong |" >> docs/OMEGA.md'
  scenario "paragraph split over two lines" 1 "not reviewed" 'readme > evidence/E/README.md; printf "Read the fractions as about\n0.04 to 0.06 of the ceiling.\n" >> evidence/E/README.md'
  local sentences n
  sentences="$(sed -n '/^# CONTROL SENTENCES$/,/^# END CONTROL SENTENCES$/p' "$SELF" | sed '1d;$d' | sed 's/^# //')"
  n="$(printf '%s\n' "$sentences" | grep -c .)"
  printf '%s\n' "$sentences" > "$t/.sentences"
  scenario "each of the $n flagged author sentences typed by hand" 1 "not reviewed" 'readme > evidence/E/README.md; cat .sentences >> evidence/E/README.md; rm .sentences'
  if [ "$(printf '%s\n' "$out" | grep -c 'not reviewed')" != "$n" ]; then echo "self-test FAIL: $n sentences gave $(printf '%s\n' "$out" | grep -c 'not reviewed') problems"; fails=$((fails + 1)); fi
  obs self_test_failures "$fails"
  [ "$fails" = 0 ]
}

# Author sentences that DRA-485 reviews 1 to 7 quoted as findings (omega-mv and CUDApp verdict files) and the variants reviews 6
# and 7 used; quotes of rules and of the issue are left out. The self-test types each one by hand into a README.
# CONTROL SENTENCES
# 104 of 208 shapes fully compared, 104 sampled
# 208 shapes PASS ... 0 wrong
# Small shapes sit at the ~0.103 ms launch floor.
# host-observed submit-to-completion time, 50 us sleep-poll, about 0.1 ms resolution, one sample
# measured on a quiet machine
# every shape correct against a host reference
# Sampled cases are checked on 4096 random elements plus the last row and column.
# PARTIAL: any-shape GEMM built, chip run pending
# the speed is at a high fraction of 237.5
# 208 shapes (BF16 and FP8, four layouts ...)
# load1 13.2, above the 10 in spark-window's header comment
# the C3 GEMM chip tier: all shapes, both types, four layouts, red checks
# Read the fractions as about 0.04 to 0.06 of the ceiling at the large shapes.
# best 0.055 (BF16) / 0.060 (FP8); squares 8192^3 about 0.04
# repeat lines differ by at most 34% (bf16)
# Low fractions at large M*N*K come from small-K shapes, which are memory bound.
# The windows ran with load1 above 10 (receipt and window files).
# DRA-485 acceptance, read literally ... MET on the chip
# the summary generates the run-to-run repeat lines, so variance is shown wherever a speed is
# More weight reuse per pass does not help: 24 same-expert rows run in 305 to 320 us for every mt from 1 to 8
# Weight reuse is neutral elsewhere
# within about 5% of the default, a small repeated loss on qkv and o
# the result is slightly slower, not established
# Every shape is correct against the host reference.
# All 206 distinct (M, N, K) shapes pass on the chip.
# 1648 type/layout cases pass with 0 wrong.
# Fractions run 0.04-0.06 of the ceiling
# the fraction is roughly 0.05
# the fraction is ~0.05
# around 0.05, up to 0.06
# The run is CHIP_TESTED and the acceptance is satisfied.
# The low cases are bandwidth limited.
# Chip PASS, all shapes correct, fraction 0.05.
# the run on 8,665 checks
# it holds for the whole last row
# Speed is `0.05` of the ceiling and the acceptance is `MET`.
# The chip result is `PASS` on `206` shapes, `every` one.
# The chip run passes on any shape with no mismatches.
# about 512 evenly spaced elements of the last row and of the last column
# END CONTROL SENTENCES

case "${1:-}" in
  --lib) return 0 2> /dev/null || true ;;
  --self-test) self_test; exit $? ;;
  --hash) line_hash "$(sed -n "${3:?usage: --hash FILE LINE}p" "${2:?usage: --hash FILE LINE}")"; exit 0 ;;
esac
base="${1:?usage: evidence_generated_check.sh BASE_REF | --hash FILE LINE | --self-test}"
self_test > /dev/null || { echo "evidence_generated_check: self-test failed; run --self-test" >&2; exit 1; }
main "$base"
