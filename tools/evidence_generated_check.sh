#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# evidence_generated_check.sh: derived numbers in evidence are generated, never typed, and evidence data matches its manifest
# (DRA-485 corrective action). It runs only on evidence directories this change touches, and judges no prose.
#  R1 opt-in: an evidence directory opts in by holding a generated marker in one of its Markdown files. In an opted-in
#     directory each
#       <!-- generated: tools/NAME ARGS -->  ... block ...  <!-- end generated -->
#     must equal the output of tools/NAME ARGS run in that directory, and each
#       <!-- generated-file: FILE tools/NAME ARGS -->
#     requires FILE to equal that output byte for byte. ARGS are an optional leading mode word ([a-z]+) and then files of the
#     directory, so a generator cannot be handed the claim it prints. A generator not at the base ref is listed as
#     AIEN-OBS new_generator. A README of an opted-in directory has at least one marker.
#  R2 manifest: in a touched evidence directory that has a SHA256SUMS, `sha256sum -c SHA256SUMS` passes; in an opted-in one,
#     every file other than Markdown and SHA256SUMS is also listed in it. A directory without SHA256SUMS is not checked.
#  R3 the checker cannot loosen itself: tests/gates/run.sh also runs the base copy when the change edits this script.
# Hand-written prose is judged by the exact-head review, not by this gate; other lanes' evidence directories that neither opt in
# nor carry a manifest pass untouched.
#   usage: tools/evidence_generated_check.sh BASE_REF      check this change
#          tools/evidence_generated_check.sh --self-test   the checker's own controls (end to end, in a scratch git repository)
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


# opted_in DIR: an evidence directory opts in when one of its Markdown files (at HEAD) holds a generated marker.
opted_in() { grep -r -l -i -E --include='*.md' --include='*.markdown' --include='*.MD' '^<!-- generated(-file)?: ' "$1" > /dev/null 2>&1; }

# main BASE: the gate. Prints problems and AIEN-OBS lines; status 0 when clean.
main() {
  BASE="$1"; cd "$ROOT"
  local problems=0 checked=0 markers=0 bare=0 manifests=0 f m out d g x
  while IFS= read -r d; do
    [ -n "$d" ] && [ -d "$d" ] || continue
    if opted_in "$d"; then
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        checked=$((checked + 1))
        if ! out="$(check_file "$f")"; then problems=$((problems + $(printf '%s\n' "$out" | grep -c '^[^ ]'))); printf '%s\n' "$out"; fi
        m="$(grep -c -E '^<!-- generated(-file)?: ' "$f" || true)"; markers=$((markers + m))
        for g in $(grep -o -E '^<!-- generated(-file)?: [^>]*-->' "$f" | grep -o -E 'tools/[A-Za-z0-9_.-]+' | sort -u); do
          git cat-file -e "$BASE:$g" 2> /dev/null || obs new_generator "$g"
        done
        shopt -s nocasematch
        if [[ "$(basename "$f")" =~ ^readme\.(md|markdown)$ ]] && [ "$m" = 0 ]; then
          bare=$((bare + 1)); problems=$((problems + 1)); echo "$f: README of an opted-in evidence directory has no generated block"; fi
        shopt -u nocasematch
      done <<< "$(find "$d" -type f \( -iname '*.md' -o -iname '*.markdown' \) | sort)"
    fi
    [ -f "$d/SHA256SUMS" ] || continue
    manifests=$((manifests + 1))
    if ! out="$(cd "$d" && sha256sum --quiet -c SHA256SUMS 2>&1)"; then problems=$((problems + 1)); echo "$d/SHA256SUMS does not match: $(printf '%s' "$out" | head -3 | tr '\n' ' ')"; fi
    opted_in "$d" || continue   # listing completeness only where the directory opted in
    while IFS= read -r x; do
      [ -n "$x" ] || continue
      awk -v x="$x" '{ f = $0; sub(/^[0-9a-f]+ [ *]/, "", f); if (f == x) found = 1 } END { exit !found }' "$d/SHA256SUMS" ||
        { problems=$((problems + 1)); echo "$d/$x: evidence data file not in SHA256SUMS"; }
    done <<< "$(cd "$d" && find . -type f ! -name SHA256SUMS | sed 's|^\./||' | grep -v -i -E '\.(md|markdown)$' | sort)"
  done <<< "$(git diff --name-only --diff-filter=AMR "$BASE...HEAD" -- evidence/ | awk -F/ 'NF > 2 { print $1 "/" $2 }' | sort -u)"
  obs files_checked "$checked"; obs generated_markers "$markers"; obs evidence_readmes_without_generated "$bare"; obs manifests_checked "$manifests"
  obs generated_mismatches "$problems"
  if [ "$problems" = 0 ]; then
    if [ "$checked" = 0 ] && [ "$manifests" = 0 ]; then echo "evidence-generated: nothing to check (no opted-in evidence directory and no manifest touched)"
    else echo "evidence-generated: $markers generated markers in $checked files of opted-in directories equal their generators; $manifests manifests verify"; fi
  fi
  [ "$problems" = 0 ]
}

# self_test: end to end through main() in a scratch git repository: clean and unrelated changes pass, each control change fails
# with its expected message.
self_test() {
  local t fails=0 rc out
  t="$(mktemp -d)"; trap 'rm -rf "$t"' RETURN
  (
    set -e; cd "$t"; git init -q; git config user.email t@t; git config user.name t
    mkdir -p tools evidence/E; cp "$SELF" tools/evidence_generated_check.sh
    printf '#!/bin/sh\n[ "$1" = count ] && shift\necho "count $(wc -l < "$1" | tr -d " ")"\n' > tools/gen_count.sh
    printf '#!/bin/sh\necho "$@"\n' > tools/say.sh; chmod +x tools/*.sh
    printf 'a\nb\nc\n' > evidence/E/data.txt; (cd evidence/E && sha256sum data.txt > SHA256SUMS)
    git add -A; git commit -qm base
  ) > /dev/null
  readme() { printf '# E receipt\n<!-- generated: tools/gen_count.sh count data.txt -->\ncount 3\n<!-- end generated -->\n'; }
  # scenario NAME EXPECT(0|1) MESSAGE SETUP...: apply SETUP in the scratch repo, commit, run main, compare, reset to base.
  scenario() {
    local name="$1" want="$2" msg="$3"; shift 3
    (cd "$t" && eval "$*" && git add -A && git commit -qm change) > /dev/null 2>&1
    rc=0; out="$(cd "$t" && EGC_ROOT="$t" bash -c 'source tools/evidence_generated_check.sh --lib; main "$(git rev-parse HEAD~1)"' 2>&1)" || rc=$?
    (cd "$t" && git reset -q --hard HEAD~1 && git clean -qfd) > /dev/null 2>&1
    if [ "$want" = 0 ] && [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q -- "$msg"; then echo "self-test: $name accepted"
    elif [ "$want" = 1 ] && [ "$rc" != 0 ] && printf '%s\n' "$out" | grep -q -- "$msg"; then echo "self-test: $name rejected"
    else echo "self-test FAIL: $name (rc $rc, wanted $want, message '$msg'): $(printf '%s' "$out" | head -3 | tr '\n' ' ')"; fails=$((fails + 1)); fi
  }
  scenario "clean opted-in change" 0 "equal their generators" 'readme > evidence/E/README.md'
  scenario "unrelated evidence directory without markers or manifest" 0 "nothing to check" 'mkdir -p evidence/U; echo "notes, 12 runs, all PASS" > evidence/U/README.md; echo log > evidence/U/run.log'
  scenario "block differs from its generator" 1 "block differs" 'readme | sed "s/^count 3$/count 4/" > evidence/E/README.md'
  scenario "claim passed to a generator as an argument" 1 "not a file" 'readme > evidence/E/README.md; printf "<!-- generated: tools/say.sh MET on the chip -->\nMET on the chip\n<!-- end generated -->\n" >> evidence/E/README.md'
  scenario "stale manifest" 1 "SHA256SUMS does not match" 'echo d >> evidence/E/data.txt'
  scenario "data file not in the manifest of an opted-in directory" 1 "not in SHA256SUMS" 'readme > evidence/E/README.md; echo x > evidence/E/SUMMARY.txt'
  scenario "unlisted note in a manifest directory that did not opt in" 0 "manifests verify" 'echo note > evidence/E/README.txt'
  scenario "README of an opted-in directory without a block" 1 "has no generated block" 'readme > evidence/E/NOTES.md; echo "# E" > evidence/E/README.md'
  scenario "generated file differs" 1 "differs from the output" 'readme > evidence/E/README.md; echo "count 9" > evidence/E/c.txt; echo "<!-- generated-file: c.txt tools/gen_count.sh count data.txt -->" >> evidence/E/README.md; (cd evidence/E && sha256sum data.txt c.txt > SHA256SUMS)'
  obs self_test_failures "$fails"
  [ "$fails" = 0 ]
}

case "${1:-}" in
  --lib) return 0 2> /dev/null || true ;;
  --self-test) self_test; exit $? ;;
esac
base="${1:?usage: evidence_generated_check.sh BASE_REF | --self-test}"
self_test > /dev/null || { echo "evidence_generated_check: self-test failed; run --self-test" >&2; exit 1; }
main "$base"
