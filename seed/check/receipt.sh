#!/bin/sh
# receipt.sh OUT REC [FILE...] -- compare a gate run's results (OUT, under build/) with the recorded receipt
# (REC, under evidence/). REC is only read: a rerun never writes a recorded receipt (evidence/ is additions
# only, OMEGA-EVIDENCE-IMMUTABLE). Each file in OUT whose name REC also holds is compared byte for byte,
# except *.log (a log carries the run's date and commit). Each FILE, a recorded copy kept outside REC
# (seed/rung4/om4.audit), is compared with OUT/<its name>. Prints one line. Exit 0: all the same;
# 1: some differ; 2: no receipt (REC empty or missing), nothing compared.
set -eu
out=$1; rec=$2; shift 2
if [ -z "$rec" ] || [ ! -d "$rec" ]; then echo "receipt ${rec:-(none)}: none recorded, nothing compared"; exit 2; fi
n=0; d=""
for f in "$out"/*; do
  b=${f##*/}
  case $b in *.log) continue ;; esac
  [ -f "$f" ] && [ -f "$rec/$b" ] || continue
  n=$((n + 1)); cmp -s "$f" "$rec/$b" || d="$d $b"
done
for r in "$@"; do
  n=$((n + 1)); cmp -s "$out/${r##*/}" "$r" || d="$d $r"
done
if [ -z "$d" ]; then echo "receipt $rec: $n files compared, all the same (not rewritten)"; exit 0; fi
echo "receipt $rec: $n files compared, differ (not rewritten):$d"; exit 1
