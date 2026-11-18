#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# evidence_generated_check.sh: derived facts in evidence and status text are generated, never typed (DRA-485 RCCA).
# For every Markdown file under evidence/ or docs/ that this change adds or modifies (git diff BASE...HEAD), each
#   <!-- generated: tools/NAME ARGS -->            ... block ...   <!-- end generated -->
# is compared with the output of tools/NAME ARGS run in that file's directory, and each
#   <!-- generated-file: FILE tools/NAME ARGS -->
# requires FILE (next to the Markdown file) to equal that output byte for byte. Any difference, a command that
# fails, or a marker without its end line fails the gate. An added, modified or renamed evidence README without any
# marker FAILS. Text outside generated blocks (every line of a changed evidence README, the added lines of other changed
# Markdown under evidence/ or docs/) FAILS on a typed claim: a percent, a number range or a number after
# about/above/below/over/under/at least/at most/median/best/lowest/highest, a count of shapes/cases/checks/runs/windows/
# triples, MET/NOT MET/PARTIAL, a typed cause (memory bound, because, due to, comes from ...). A line that states a method
# constant or a source may end with `<!-- typed-ok: REASON -->` (REASON at least 12 characters); the marker is the review
# surface. Negative controls are the real sentences of DRA-485 reviews 1 to 5 (see --self-test).
#   usage: tools/evidence_generated_check.sh BASE_REF       check this change
#          tools/evidence_generated_check.sh --self-test     the negative controls of the checker itself
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
obs() { printf 'AIEN-OBS %s %s\n' "$1" "$2"; }

# check_file MD: prints one line per problem, returns the number of problems (0 = clean). Sets MARKERS.
check_file() {
  local md="$1" dir tmp n=0 line=0 l cmd file inblock=0 start=0 words
  dir="$(dirname "$md")"; tmp="$(mktemp -d)"; MARKERS=0
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
        cmd="${l#<!-- generated: }"; cmd="${cmd% -->}"; start=$line; inblock=1; : > "$tmp/have"; MARKERS=$((MARKERS + 1)) ;;
      "<!-- generated-file: "*" -->")
        words="${l#<!-- generated-file: }"; words="${words% -->}"; file="${words%% *}"; cmd="${words#* }"; MARKERS=$((MARKERS + 1))
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
# run_cmd DIR "tools/NAME ARGS": runs ROOT/tools/NAME with ARGS in DIR, without a shell.
run_cmd() {
  local dir="$1" a; local -a w; read -r -a w <<< "$2"
  [[ "${w[0]:-}" =~ ^tools/[A-Za-z0-9_.-]+$ ]] || { echo "generator must be tools/NAME: ${w[0]:-}" >&2; return 2; }
  for a in "${w[@]:1}"; do safe_word "$a" || { echo "unsafe argument: $a" >&2; return 2; }; done
  [ -x "$ROOT/${w[0]}" ] || { echo "not executable: ${w[0]}" >&2; return 2; }
  (cd "$dir" && "$ROOT/${w[0]}" "${w[@]:1}")
}

# lint_text FILE [ADDED]: prints one line per line outside <!-- generated... --> blocks that matches a claim pattern and
# has no typed-ok marker. ADDED, when given, is a newline list of line numbers; only those lines are checked.
CLAIM_RE='([0-9]+(\.[0-9]+)?[ ]?%|[0-9.]+[ ]+(to|and)[ ]+[0-9.]+|(about|above|below|over|under|at least|at most|median|best|lowest|highest|near)[ ]+[0-9]|[0-9]+[ ]+(distinct |wrong |full |sampled |hand-picked )?(shapes|cases|checks|triples|runs|windows|samples)|(^|[^A-Za-z])(NOT MET|MET|PARTIAL)([^A-Za-z]|$)|memory[- ]bound|compute[- ]bound|launch[- ]bound|because|due to|comes? from|caused by|explained by)'
TYPED_OK_RE='<!-- typed-ok: (.*) -->[[:space:]]*$'
lint_text() {
  local f="$1" added="${2:-}" n=0 line=0 l inblock=0
  while IFS= read -r l || [ -n "$l" ]; do
    line=$((line + 1))
    case "$l" in
      "<!-- generated: "*" -->") inblock=1; continue ;;
      "<!-- end generated -->") inblock=0; continue ;;
      "<!-- generated-file: "*" -->") continue ;;
    esac
    [ "$inblock" = 1 ] && continue
    if [ -n "$added" ] && ! printf '%s\n' "$added" | grep -qx "$line"; then continue; fi
    if [[ "$l" =~ $TYPED_OK_RE ]]; then
      if [ "${#BASH_REMATCH[1]}" -ge 12 ]; then continue; fi
      echo "$f:$line: typed-ok reason shorter than 12 characters"; n=$((n + 1)); continue
    fi
    if printf '%s\n' "$l" | grep -E -i -q -- "$CLAIM_RE"; then
      echo "$f:$line: typed claim outside a generated block: ${l:0:110}"; n=$((n + 1))
    fi
  done < "$f"
  [ "$n" = 0 ]
}

self_test() {
  local t fails=0 out
  t="$(mktemp -d)"; trap 'rm -rf "$t"' RETURN
  mkdir -p "$t/tools" "$t/ev"; cp "${BASH_SOURCE[0]}" "$t/tools/evidence_generated_check.sh"
  printf '#!/bin/sh\necho "count $(wc -l < "$1" | tr -d " ")"\n' > "$t/tools/gen_count.sh"; chmod +x "$t/tools/gen_count.sh"
  printf 'a\nb\nc\n' > "$t/ev/data.txt"; echo "count 3" > "$t/ev/count.txt"
  # case: correct block and file -> clean
  printf 'x\n<!-- generated: tools/gen_count.sh data.txt -->\ncount 3\n<!-- end generated -->\n<!-- generated-file: count.txt tools/gen_count.sh data.txt -->\n' > "$t/ev/ok.md"
  # controls: a typed number that disagrees, a stale file, a missing end, an unsafe command, a failing generator
  printf '<!-- generated: tools/gen_count.sh data.txt -->\ncount 4\n<!-- end generated -->\n' > "$t/ev/typed.md"
  echo "count 2" > "$t/ev/stale.txt"; printf '<!-- generated-file: stale.txt tools/gen_count.sh data.txt -->\n' > "$t/ev/stale.md"
  printf '<!-- generated: tools/gen_count.sh data.txt -->\ncount 3\n' > "$t/ev/noend.md"
  printf '<!-- generated: /bin/sh -c true -->\n<!-- end generated -->\n' > "$t/ev/unsafe.md"
  printf '<!-- generated: tools/gen_count.sh ../outside -->\n<!-- end generated -->\n' > "$t/ev/escape.md"
  printf '<!-- generated: tools/gen_count.sh missing.txt -->\n<!-- end generated -->\n' > "$t/ev/fail.md"
  if out="$(ROOT="$t" check_file "$t/ev/ok.md")"; then echo "self-test: clean file accepted"; else echo "self-test FAIL: clean file rejected: $out"; fails=$((fails + 1)); fi
  for c in typed stale noend unsafe escape fail; do
    if out="$(ROOT="$t" check_file "$t/ev/$c.md")"; then echo "self-test FAIL: control $c accepted"; fails=$((fails + 1))
    else echo "self-test: control $c rejected"; fi
  done
  # lint controls: the actual sentences of DRA-485 reviews 1 to 5 (each must be rejected) and clean method lines
  i=0
  while IFS= read -r sent; do
    i=$((i + 1)); printf '# t\n%s\n' "$sent" > "$t/ev/lint$i.md"
    if out="$(lint_text "$t/ev/lint$i.md")"; then echo "self-test FAIL: lint control $i accepted: $sent"; fails=$((fails + 1))
    else echo "self-test: lint control $i rejected"; fi
  done <<'CTL'
Read the fractions as about 0.04 to 0.06 of the ceiling at the large shapes.
Low fractions at large M*N*K come from small-K shapes, which are memory bound.
The windows ran with load1 above 10 (receipt and window files).
Chip PASS on 999 shapes, 208 shapes in all, speed 0.04 to 0.06.
DRA-485 acceptance MET on the chip.
CTL
  printf '# t\nCases of at most 2^27 multiply-adds are compared in full. <!-- typed-ok: method constant of the host reference -->\nEach case is compared bit for bit with a host model.\n' > "$t/ev/lintok.md"
  if out="$(lint_text "$t/ev/lintok.md")"; then echo "self-test: lint clean text accepted"; else echo "self-test FAIL: lint clean text rejected: $out"; fails=$((fails + 1)); fi
  printf '# t\nCases of at most 2^27 multiply-adds. <!-- typed-ok: short -->\n' > "$t/ev/lintshort.md"
  if out="$(lint_text "$t/ev/lintshort.md")"; then echo "self-test FAIL: short typed-ok reason accepted"; fails=$((fails + 1)); else echo "self-test: short typed-ok reason rejected"; fi
  printf '# t\ncases: 1648\n' > "$t/ev/nomark.md"
  check_file "$t/ev/nomark.md" > /dev/null || true
  if [ "$MARKERS" = 0 ]; then echo "self-test: README without a generated marker counts as bare"; else echo "self-test FAIL: marker count of bare README"; fails=$((fails + 1)); fi
  obs self_test_failures "$fails"
  [ "$fails" = 0 ]
}

if [ "${1:-}" = "--self-test" ]; then self_test; exit $?; fi
base="${1:?usage: evidence_generated_check.sh BASE_REF | --self-test}"
cd "$ROOT"
self_test > /dev/null || { echo "evidence_generated_check: self-test failed; run --self-test" >&2; exit 1; }
files="$(git diff --name-only --diff-filter=AMR "$base...HEAD" -- 'evidence/*.md' 'docs/*.md' 'evidence/**/*.md' 'docs/**/*.md' | sort -u)"
problems=0; checked=0; markers=0; bare=0
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] || continue
  checked=$((checked + 1))
  if ! out="$(check_file "$f")"; then problems=$((problems + $(printf '%s\n' "$out" | grep -c '^[^ ]'))); printf '%s\n' "$out"; fi
  m="$(grep -c -E '^<!-- generated(-file)?: ' "$f" || true)"; markers=$((markers + m))
  case "$f" in
    evidence/*/README.md)
      if [ "$m" = 0 ]; then bare=$((bare + 1)); problems=$((problems + 1)); echo "$f: changed evidence README has no generated block (derived numbers typed by hand)"; fi
      if ! out="$(lint_text "$f")"; then problems=$((problems + $(printf '%s\n' "$out" | grep -c '^[^ ]'))); printf '%s\n' "$out"; fi ;;
    *)
      added="$(git diff -U0 "$base...HEAD" -- "$f" | awk '/^@@/ { split($3, a, ","); s = substr(a[1], 2) + 0; c = (a[2] == "" ? 1 : a[2] + 0); for (i = 0; i < c; i++) print s + i }')"
      if [ -n "$added" ] && ! out="$(lint_text "$f" "$added")"; then problems=$((problems + $(printf '%s\n' "$out" | grep -c '^[^ ]'))); printf '%s\n' "$out"; fi ;;
  esac
done <<< "$files"
obs files_checked "$checked"; obs generated_markers "$markers"; obs evidence_readmes_without_generated "$bare"
obs generated_mismatches "$problems"
[ "$problems" = 0 ] && echo "evidence-generated: $markers generated markers in $checked changed files, all equal to their generators"
[ "$problems" = 0 ]
