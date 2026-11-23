#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# fake_recheck.sh -- the stand-in validator of tests/gen_retrieval/genret_parity.sh. genret runs it as
# `<it> --receipts <corpus dir>/receipts <record>...` (an empty environment under the OM genret), so its
# behaviour is chosen by the file <corpus dir>/fake_mode, not by the environment. Without that file it accepts
# every record ("OK <id>" per record, in order), like Agent D's recheck on a valid set. Its sha256 is the pin
# of the parity test's production builds (C and OM), so one file serves every case.
#   refuse         OK for the first record, then "REFUSED <file>: test refusal", exit 1
#   refuse-noline  exit 1, no output          refuse-midline  "xREFUSED y" (not at a line start), exit 1
#   refuse-noeol   "REFUSED last: no newline" without a final newline, exit 1
#   exit3          exit 3                     signal          kill itself with SIGKILL
#   wrongid        "OK wrong-id" per record   fewer           no line for the last record
#   extra          one more "OK extra"        noeol           the last OK line without its newline
#   mutate         accept, then append a byte to the first record
#   delete         accept, then remove the first record
#   race           accept, then create <corpus dir>/../o (the cases' --out), so the final rename finds it
shift
dir=${1%receipts}
shift
m=""
[ -f "${dir}fake_mode" ] && m=$(cat "${dir}fake_mode")
idof() { awk '/^body$/ { exit } /^id / { print substr($0, 4); exit }' "$1"; }
case $m in
refuse) printf 'OK %s\n' "$(idof "$1")"; printf 'REFUSED %s: test refusal\n' "${2##*/}"; exit 1 ;;
refuse-noline) exit 1 ;;
refuse-midline) printf 'xREFUSED y\n'; exit 1 ;;
refuse-noeol) printf 'REFUSED last: no newline'; exit 1 ;;
exit3) exit 3 ;;
signal) kill -9 $$ ;;
wrongid) for f; do printf 'OK wrong-id\n'; done; exit 0 ;;
esac
n=$#
i=0
for f; do
  i=$((i + 1))
  [ "$m" = fewer ] && [ "$i" -eq "$n" ] && break
  if [ "$m" = noeol ] && [ "$i" -eq "$n" ]; then printf 'OK %s' "$(idof "$f")"; else printf 'OK %s\n' "$(idof "$f")"; fi
done
[ "$m" = extra ] && printf 'OK extra\n'
[ "$m" = mutate ] && printf 'x\n' >> "$1"
[ "$m" = delete ] && rm -f "$1"
[ "$m" = race ] && mkdir "${dir}../o"
exit 0
