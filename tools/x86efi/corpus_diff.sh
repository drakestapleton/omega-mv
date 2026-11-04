#!/bin/sh
# corpus_diff.sh NEW_OMC OLD_OMC OUT.tsv [asis|x86linux]
# One TSV line per tracked .om file:
#   path verdict exit_new exit_old sha256_new sha256_old
# verdict:
#   identical: both compilers exit 0 and write the same stdout bytes
#   same-refusal: both exit with the same status in 1..128 and write the same stderr
#   signal: either compiler was killed by a signal (exit 129 or above; 139 is SIGSEGV, which is how
#     a guest segfault under qemu-user reaches the shell). Never counted as a refusal; each such
#     line is also reported on stderr as CORPUS_DIFF_SIGNAL.
#   differ: any other pair
# stdout is hashed even when a compiler refuses (the hash is of the bytes it wrote).
# A compiler that is not a native executable for this machine is NOT_RUN (exit 3).
# CORPUS_DIFF_ALLOW_QEMU=1 runs that pair anyway and records the host on stderr.
# file(1) decides whether a compiler is native; without it the script is NOT_RUN (exit 3).
# No em dash or en dash is used in this file.
set -eu
if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  echo "usage: corpus_diff.sh NEW_OMC OLD_OMC OUT.tsv [asis|x86linux]" >&2
  exit 2
fi
new=$1
old=$2
out=$3
mode=${4:-asis}
case $mode in
  asis|x86linux) ;;
  *) echo "mode must be asis or x86linux" >&2; exit 2 ;;
esac
[ -f "$new" ] && [ -f "$old" ] || { echo "NOT_RUN missing compiler" >&2; exit 3; }
command -v file > /dev/null 2>&1 || { echo "NOT_RUN file(1) not found; it is needed to check that both compilers are native executables" >&2; exit 3; }

root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$root"

native_ok() {
  desc=$(file -b "$1")
  case $(uname -m) in
    aarch64|arm64) echo "$desc" | grep -q 'ARM aarch64' ;;
    x86_64) echo "$desc" | grep -q 'x86-64' ;;
    *) return 1 ;;
  esac
}
if ! native_ok "$new" || ! native_ok "$old"; then
  if [ "${CORPUS_DIFF_ALLOW_QEMU:-}" != 1 ]; then
    echo "NOT_RUN compilers are not native executables for $(uname -m)" >&2
    echo "NOT_RUN host $(uname -sr)" >&2
    file -b "$new" >&2
    file -b "$old" >&2
    exit 3
  fi
  echo "CORPUS_DIFF_QEMU host=$(uname -m) $(uname -sr) mode=$mode" >&2
fi

first_line() {
  awk '
    /^[ \t]*$/ { next }
    /^[ \t]*note([ \t]|$)/ { next }
    { print; exit }
  ' "$1"
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/corpus-diff.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
: > "$out"
n=0
git ls-files '*.om' | while IFS= read -r path; do
  src=$path
  if [ "$mode" = x86linux ]; then
    lead=$(first_line "$path")
    case $lead in
      "target "*) src=$path ;;
      *) { printf '%s\n' 'target x86linux'; cat "$path"; } > "$tmp/src.om"; src=$tmp/src.om ;;
    esac
  fi
  set +e
  "$new" < "$src" > "$tmp/new.out" 2> "$tmp/new.err"
  nr=$?
  "$old" < "$src" > "$tmp/old.out" 2> "$tmp/old.err"
  orc=$?
  set -e
  nh=$(sha256sum "$tmp/new.out" | cut -d ' ' -f 1)
  oh=$(sha256sum "$tmp/old.out" | cut -d ' ' -f 1)
  if [ "$nr" -gt 128 ] || [ "$orc" -gt 128 ]; then
    verdict=signal
    echo "CORPUS_DIFF_SIGNAL $path exit_new=$nr exit_old=$orc" >&2
  elif [ "$nr" -eq 0 ] && [ "$orc" -eq 0 ] && cmp -s "$tmp/new.out" "$tmp/old.out"; then
    verdict=identical
  elif [ "$nr" -ne 0 ] && [ "$orc" -ne 0 ] && [ "$nr" -eq "$orc" ] && cmp -s "$tmp/new.err" "$tmp/old.err"; then
    verdict=same-refusal
  else
    verdict=differ
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$path" "$verdict" "$nr" "$orc" "$nh" "$oh"
  n=$((n + 1))
done > "$out"
echo "CORPUS_DIFF lines=$(wc -l < "$out") mode=$mode out=$out"
sig=$(awk -F '\t' '$2 == "signal"' "$out" | wc -l)
[ "$sig" -eq 0 ] || echo "CORPUS_DIFF_SIGNAL total=$sig (a compiler was killed by a signal; not a refusal)" >&2
