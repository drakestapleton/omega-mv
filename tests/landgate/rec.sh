# SPDX-License-Identifier: Apache-2.0
# tests/landgate/rec.sh: TEST INSTRUMENT (shell, never on a product path), sourced by tests/landgate/run.sh and by the
# aggregate-judge controls of tests/landgate/controls.sh. The record judge of the landing campaign.
# The caller sets L (the log directory), S (the summary file, its head line already written) and failed=0.
#   rec NAME EXPECTED CMD...   runs CMD once; writes NAME.command and NAME.log and appends the row. A row whose exit
#                              differs from EXPECTED, or whose WANT_TEXT (when set) is not in its log, is a failed record.
#   na NAME REASON             a row that does not apply to this head
#   invalid NAME REASON        a row that could not be set up: a failed record
#   verdict                    appends "failed records: ..." and then "LANDGATE PASS rc=0" or "LANDGATE FAIL"
rec() {
  n=$1; want=$2; shift 2
  printf '%q ' "$@" > "$L/$n.command"
  t0=$(date -u +%FT%TZ)
  "$@" > "$L/$n.log" 2>&1; rc=$?
  tx=; if [ -n "${WANT_TEXT:-}" ]; then if grep -qF -- "$WANT_TEXT" "$L/$n.log"; then tx=" text=found"; else tx=" text=MISSING"; fi; fi
  if [ "$want" = 0 ]; then echo "$n rc=$rc log=$L/$n.log sha256=$(sha256sum < "$L/$n.log" | cut -c1-64) start=$t0$tx" >> "$S"
  else echo "$n control_exit=$rc expected_exit=$want log=$L/$n.log sha256=$(sha256sum < "$L/$n.log" | cut -c1-64) start=$t0$tx" >> "$S"; fi
  [ "$rc" = "$want" ] && [ "$tx" != " text=MISSING" ] || { failed=1; echo "$n" >> "$L/failed.txt"; }  # record predicate
}
na() { echo "$1 NOT_APPLICABLE: $2" >> "$S"; }
invalid() { echo "$1 INVALID: $2" >> "$S"; failed=1; echo "$1" >> "$L/failed.txt"; }
verdict() {
  if [ "$failed" = 0 ]; then echo "failed records: none" >> "$S"; echo "LANDGATE PASS rc=0" >> "$S"
  else echo "failed records: $(tr '\n' ' ' < "$L/failed.txt")" >> "$S"; echo "LANDGATE FAIL" >> "$S"; fi
}
