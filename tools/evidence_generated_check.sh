#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# evidence_generated_check.sh: derived facts in evidence and status text are generated, never typed (DRA-485 RCCA).
# For every Markdown file under evidence/ or docs/ that this change adds or modifies (git diff BASE...HEAD), each
#   <!-- generated: tools/NAME ARGS -->            ... block ...   <!-- end generated -->
# is compared with the output of tools/NAME ARGS run in that file's directory, and each
#   <!-- generated-file: FILE tools/NAME ARGS -->
# requires FILE (next to the Markdown file) to equal that output byte for byte. Any difference, a command that
# fails, or a marker without its end line fails the gate. A changed evidence README without any marker FAILS. Every changed
# Markdown file under evidence/ (whole file) and the added lines of other changed Markdown under docs/ pass the default-deny
# lint below. Every SHA256SUMS in an evidence directory this change touches must verify (sha256sum -c).
#   usage: tools/evidence_generated_check.sh BASE_REF       check this change
#          tools/evidence_generated_check.sh --hash FILE LINE  the typed-ok hash of one line, for a reviewed exemption
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

# Default-deny lint of hand-written text (DRA-485 RCCA 2, after review 6 showed a claim-pattern list fitted to its own controls):
# outside <!-- generated... --> blocks, a line FAILS if, after removing single-token `code` spans, it holds a digit, a status word
# (MET PARTIAL PASS FAIL CHIP_TESTED ...), an approximation sign, or a word of DENY_WORDS (quantifiers, correctness, cause,
# approximation and comparison words). Wrapped text is also checked as joined paragraphs, so a claim split over two lines fails.
# The only exemption is a reviewed line: it carries `<!-- typed-ok HASH: REASON -->` where HASH is the first 12 hex digits of
# the sha256 of the line with the marker removed (`evidence_generated_check.sh --hash FILE LINE` prints it), so any later
# edit of an exempt line fails until it is reviewed again. A table row carries the marker inside its last cell.
DENY_STATUS='(^|[^A-Za-z_])(NOT MET|MET|PARTIAL|PASS|PASSED|FAIL|FAILED|CHIP_TESTED|QUALIFIED|EXERCISED|DONE|OK)([^A-Za-z_]|$)'
DENY_WORDS='(^|[^a-z])(every|all|each|none|whole|full|fully|entire|entirely|correct|correctly|right|wrong|satisfied|satisfies|met|meets|finished|complete|completed|verified|proven|bound|limited|because|due to|comes? from|caused by|explained by|dominated by|floor|roughly|around|about|approx|approximately|nearly|near|almost|up to|at least|at most|above|below|over|under|median|mean|average|best|worst|lowest|highest|fastest|slowest|faster|slower|most|least|quiet|noisy|noise|neutral|wherever|always|never|stable|consistent|established|helps?|loss|losses|wins?|gains?|equal|same|identical|exact|exactly|reproducible|negligible|small|large|high|low|higher|lower|significant|clearly)([^a-z]|$)'
TYPED_OK_RE=' ?<!-- typed-ok ([0-9a-f]{12}): ([^>]*) -->'
# strip_line TEXT: the text the lint judges (marker removed, single-token code spans removed).
strip_line() { printf '%s\n' "$1" | sed -E "s/$TYPED_OK_RE//; s/\`[^\` ]+\`//g"; }
line_hash() { printf '%s' "$(printf '%s\n' "$1" | sed -E "s/$TYPED_OK_RE//")" | sha256sum | cut -c1-12; }
denied() { printf '%s\n' "$1" | grep -E -q -- '[0-9~≈]' || printf '%s\n' "$1" | grep -E -q -- "$DENY_STATUS" || printf '%s\n' "$1" | grep -E -i -q -- "$DENY_WORDS"; }
# lint_text FILE [ADDED]: one output line per problem; ADDED, when given, is a newline list of the line numbers to judge.
lint_text() {
  local f="$1" added="${2:-}" n=0 line=0 l inblock=0 t para="" pstart=0 h
  flush() { if [ -n "$para" ] && denied "$para"; then echo "$f:$pstart: claim split over lines of one paragraph: ${para:0:110}"; n=$((n + 1)); fi; para=""; }
  while IFS= read -r l || [ -n "$l" ]; do
    line=$((line + 1))
    case "$l" in
      "<!-- generated: "*" -->") flush; inblock=1; continue ;;
      "<!-- end generated -->") inblock=0; continue ;;
      "<!-- generated-file: "*" -->") flush; continue ;;
    esac
    [ "$inblock" = 1 ] && continue
    if [ -n "$added" ] && ! printf '%s\n' "$added" | grep -qx "$line"; then flush; continue; fi
    if [ -z "${l//[[:space:]]/}" ]; then flush; continue; fi
    if [[ "$l" =~ $TYPED_OK_RE ]]; then
      h="$(line_hash "$l")"
      if [ "${BASH_REMATCH[1]}" != "$h" ]; then echo "$f:$line: typed-ok hash ${BASH_REMATCH[1]} does not match the line ($h): edited after review"; n=$((n + 1))
      elif [ "${#BASH_REMATCH[2]}" -lt 12 ]; then echo "$f:$line: typed-ok reason shorter than 12 characters"; n=$((n + 1)); fi
      flush; continue
    fi
    t="$(strip_line "$l")"
    if denied "$t"; then echo "$f:$line: hand-typed claim outside a generated block: ${l:0:110}"; n=$((n + 1)); flush; continue; fi
    [ -z "$para" ] && pstart=$line; para="$para $t"
  done < "$f"
  flush
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
  # lint controls: author sentences that DRA-485 reviews 1 to 6 quoted as findings (omega-mv and CUDApp verdict files; quotes
  # of rules and of the issue left out) and the variants review 6 used against the first lint; each must be rejected.
  i=0
  while IFS= read -r sent; do
    [ -n "$sent" ] || continue
    i=$((i + 1)); printf '# t\n%s\n' "$sent" > "$t/ev/lint$i.md"
    if out="$(lint_text "$t/ev/lint$i.md")"; then echo "self-test FAIL: lint control $i accepted: $sent"; fails=$((fails + 1))
    else echo "self-test: lint control $i rejected"; fi
  done <<'CTL'
104 of 208 shapes fully compared, 104 sampled
208 shapes PASS ... 0 wrong
Small shapes sit at the ~0.103 ms launch floor.
host-observed submit-to-completion time, 50 us sleep-poll, about 0.1 ms resolution, one sample
measured on a quiet machine
every shape correct against a host reference
Sampled cases are checked on 4096 random elements plus the last row and column.
PARTIAL: any-shape GEMM built, chip run pending
the speed is at a high fraction of 237.5
208 shapes (BF16 and FP8, four layouts ...)
load1 13.2, above the 10 in spark-window's header comment
the C3 GEMM chip tier: all shapes, both types, four layouts, red checks
Read the fractions as about 0.04 to 0.06 of the ceiling at the large shapes.
best 0.055 (BF16) / 0.060 (FP8); squares 8192^3 about 0.04
repeat lines differ by at most 34% (bf16)
Low fractions at large M*N*K come from small-K shapes, which are memory bound.
The windows ran with load1 above 10 (receipt and window files).
DRA-485 acceptance, read literally ... MET on the chip
the summary generates the run-to-run repeat lines, so variance is shown wherever a speed is
More weight reuse per pass does not help: 24 same-expert rows run in 305 to 320 us for every mt from 1 to 8
Weight reuse is neutral elsewhere
within about 5% of the default, a small repeated loss on qkv and o
the result is slightly slower, not established
Every shape is correct against the host reference.
All 206 distinct (M, N, K) shapes pass on the chip.
1648 type/layout cases pass with 0 wrong.
Fractions run 0.04-0.06 of the ceiling
the fraction is roughly 0.05
the fraction is ~0.05
around 0.05, up to 0.06
The run is CHIP_TESTED and the acceptance is satisfied.
The low cases are bandwidth limited.
| C3 | GEMM | chip PASS, every shape correct, 0 wrong |
Chip PASS, all shapes correct, fraction 0.05.
the run on 8,665 checks
it holds for the whole last row
CTL
  # a claim split over two lines of one paragraph, a hash-bound reviewed line, the same line edited after review, a short reason
  printf '# t\nthe fractions are roughly\nconstant here\n' > "$t/ev/lintsplit.md"
  if out="$(lint_text "$t/ev/lintsplit.md")"; then echo "self-test FAIL: split claim accepted"; fails=$((fails + 1)); else echo "self-test: split claim rejected"; fi
  l='Cases of at most 2^27 multiply-adds are compared in full.'
  printf '# t\n%s <!-- typed-ok %s: method constant of the host reference -->\nThe host model follows the tensor-core steps.\n' "$l" "$(line_hash "$l")" > "$t/ev/lintok.md"
  if out="$(lint_text "$t/ev/lintok.md")"; then echo "self-test: reviewed line and plain method text accepted"; else echo "self-test FAIL: clean text rejected: $out"; fails=$((fails + 1)); fi
  printf '# t\n%s <!-- typed-ok %s: method constant of the host reference -->\n' "Cases of at most 2^28 multiply-adds are compared in full." "$(line_hash "$l")" > "$t/ev/lintedit.md"
  if out="$(lint_text "$t/ev/lintedit.md")"; then echo "self-test FAIL: edited reviewed line accepted"; fails=$((fails + 1)); else echo "self-test: edited reviewed line rejected"; fi
  printf '# t\n%s <!-- typed-ok %s: short -->\n' "$l" "$(line_hash "$l")" > "$t/ev/lintshort.md"
  if out="$(lint_text "$t/ev/lintshort.md")"; then echo "self-test FAIL: short typed-ok reason accepted"; fails=$((fails + 1)); else echo "self-test: short typed-ok reason rejected"; fi
  # manifest: a SHA256SUMS that no longer matches a file is rejected
  printf 'x\n' > "$t/ev/m.txt"; (cd "$t/ev" && sha256sum m.txt > SHA256SUMS); printf 'y\n' > "$t/ev/m.txt"
  if (cd "$t/ev" && sha256sum --quiet -c SHA256SUMS > /dev/null 2>&1); then echo "self-test FAIL: stale manifest accepted"; fails=$((fails + 1)); else echo "self-test: stale manifest rejected"; fi
  printf '# t\ncases: 1648\n' > "$t/ev/nomark.md"
  check_file "$t/ev/nomark.md" > /dev/null || true
  if [ "$MARKERS" = 0 ]; then echo "self-test: README without a generated marker counts as bare"; else echo "self-test FAIL: marker count of bare README"; fails=$((fails + 1)); fi
  obs self_test_failures "$fails"
  [ "$fails" = 0 ]
}

if [ "${1:-}" = "--self-test" ]; then self_test; exit $?; fi
if [ "${1:-}" = "--hash" ]; then line_hash "$(sed -n "${3:?usage: --hash FILE LINE}p" "${2:?usage: --hash FILE LINE}")"; exit 0; fi
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
    evidence/*)
      case "$f" in */README.md)
        if [ "$m" = 0 ]; then bare=$((bare + 1)); problems=$((problems + 1)); echo "$f: changed evidence README has no generated block (derived numbers typed by hand)"; fi ;;
      esac
      if ! out="$(lint_text "$f")"; then problems=$((problems + $(printf '%s\n' "$out" | grep -c '^[^ ]'))); printf '%s\n' "$out"; fi ;;
    *)
      added="$(git diff -U0 "$base...HEAD" -- "$f" | awk '/^@@/ { split($3, a, ","); s = substr(a[1], 2) + 0; c = (a[2] == "" ? 1 : a[2] + 0); for (i = 0; i < c; i++) print s + i }')"
      if [ -n "$added" ] && ! out="$(lint_text "$f" "$added")"; then problems=$((problems + $(printf '%s\n' "$out" | grep -c '^[^ ]'))); printf '%s\n' "$out"; fi ;;
  esac
done <<< "$files"
manifests=0
for d in $(git diff --name-only --diff-filter=AMR "$base...HEAD" -- evidence/ | awk -F/ 'NF > 2 { print $1 "/" $2 }' | sort -u); do
  [ -f "$d/SHA256SUMS" ] || continue
  manifests=$((manifests + 1))
  if ! bad="$(cd "$d" && sha256sum --quiet -c SHA256SUMS 2>&1)"; then problems=$((problems + 1)); echo "$d/SHA256SUMS does not match: $bad" | head -5; fi
done
obs manifests_checked "$manifests"
obs files_checked "$checked"; obs generated_markers "$markers"; obs evidence_readmes_without_generated "$bare"
obs generated_mismatches "$problems"
[ "$problems" = 0 ] && echo "evidence-generated: $markers generated markers in $checked changed files, all equal to their generators"
[ "$problems" = 0 ]
