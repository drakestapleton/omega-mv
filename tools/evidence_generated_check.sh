#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# evidence_generated_check.sh: derived facts in evidence and status text are generated, never typed (DRA-485 RCCA).
# For every Markdown file under evidence/ or docs/ that this change adds or modifies (git diff BASE...HEAD), each
#   <!-- generated: tools/NAME ARGS -->            ... block ...   <!-- end generated -->
# is compared with the output of tools/NAME ARGS run in that file's directory, and each
#   <!-- generated-file: FILE tools/NAME ARGS -->
# requires FILE (next to the Markdown file) to equal that output byte for byte. Any difference, a command that
# fails, or a marker without its end line fails the gate. New evidence READMEs without any marker are counted
# and printed as an alarm (AIEN-OBS evidence_readmes_without_generated), not a failure.
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
  obs self_test_failures "$fails"
  [ "$fails" = 0 ]
}

if [ "${1:-}" = "--self-test" ]; then self_test; exit $?; fi
base="${1:?usage: evidence_generated_check.sh BASE_REF | --self-test}"
cd "$ROOT"
self_test > /dev/null || { echo "evidence_generated_check: self-test failed; run --self-test" >&2; exit 1; }
files="$(git diff --name-only --diff-filter=AM "$base...HEAD" -- 'evidence/*.md' 'docs/*.md' 'evidence/**/*.md' 'docs/**/*.md' | sort -u)"
problems=0; checked=0; markers=0; bare=0
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] || continue
  checked=$((checked + 1))
  if ! out="$(check_file "$f")"; then problems=$((problems + $(printf '%s\n' "$out" | grep -c '^[^ ]'))); printf '%s\n' "$out"; fi
  m="$(grep -c -E '^<!-- generated(-file)?: ' "$f" || true)"; markers=$((markers + m))
  case "$f" in evidence/*/README.md)
    if [ "$m" = 0 ] && git diff --name-only --diff-filter=A "$base...HEAD" -- "$f" | grep -q .; then
      bare=$((bare + 1)); echo "alarm: new evidence README with no generated block (derived numbers typed by hand?): $f"; fi ;;
  esac
done <<< "$files"
obs files_checked "$checked"; obs generated_markers "$markers"; obs evidence_readmes_without_generated "$bare"
obs generated_mismatches "$problems"
[ "$problems" = 0 ] && echo "evidence-generated: $markers generated markers in $checked changed files, all equal to their generators"
[ "$problems" = 0 ]
