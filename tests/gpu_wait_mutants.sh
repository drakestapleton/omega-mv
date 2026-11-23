#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# gpu_wait_mutants.sh -- negative controls for tests/gpu_wait_parity.sh.
#
# Each mutant is one deliberate fault in the shipped OM-2 wait src/omega_gpu_wait.om (the three
# compile-time mutant constants set to 1, and further one-line faults). It is applied to a copy,
# the OM dumper is rebuilt from that copy, and gpu_wait_parity.sh must report a difference from
# the committed C-reference goldens (tests/gpu_wait_golden, generated from the C at main commit
# 3f2c70dc5). A mutant that does not apply, does not build, or shows no difference fails this
# script.
#
# usage: tests/gpu_wait_mutants.sh [OMC]   env: GPU_WAIT_PARITY_WORK (work dir; default a new one)
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OMC=${1:-$ROOT/seed/out/omc}
case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
W=${GPU_WAIT_PARITY_WORK:-$(mktemp -d)}
case $W in /*) ;; *) W=$(pwd)/$W ;; esac
SRC=$ROOT/src/omega_gpu_wait.om
M=$W/mut
rm -rf "$M"; mkdir -p "$M"

# name|perl substitution on omega_gpu_wait.om (applied with perl -0pi, so \n spans lines)
cat > "$M/list" <<'EOF'
stall-no-reset|s/const OMEGA_GPU_WAIT_MUTANT_STALL_NO_RESET int 0/const OMEGA_GPU_WAIT_MUTANT_STALL_NO_RESET int 1/
progress-extends-hard|s/const OMEGA_GPU_WAIT_MUTANT_PROGRESS_EXTENDS_HARD int 0/const OMEGA_GPU_WAIT_MUTANT_PROGRESS_EXTENDS_HARD int 1/
no-read-barrier|s/const OMEGA_GPU_WAIT_MUTANT_NO_READ_BARRIER int 0/const OMEGA_GPU_WAIT_MUTANT_NO_READ_BARRIER int 1/
fixed-accepts-overshoot|s/ok = eq m expected/ok = ge m expected/
sequence-unsigned|s/ret lt diff uint 0x80000000/ret ge observed target/
sequence-half-open|s/ret lt diff uint 0x80000000/ret le diff uint 0x80000000/
marker2-no-progress|s/if ne m2 get rpt last_marker2\nret true\nend\n//
snap1-no-progress|s/if ne s1 get rpt snap1\nret true\nend\n//
first-never-cleared|s/put st 0 0\nif ge now get dl 3/if ge now get dl 3/
first-change-counts|s/if eq get st 0 0\nput rpt progress_count/if ge get st 0 0\nput rpt progress_count/
no-acquire-barrier|s/gw_barrier uh\nput rpt result OMEGA_GPU_WAIT_PASS/put rpt result OMEGA_GPU_WAIT_PASS/
marker2-ignored|s/m2_ok = eq m2 get cfg marker2_want/m2_ok = true/
valid-ignored|s/if ne get cfg use_valid 0/if ne get cfg use_valid 99/
valid-before-pass|s/if ok\nm2_ok = true/if ne get cfg use_valid 0\nif not gw_hook_valid m\nput rpt result OMEGA_GPU_WAIT_INVALID_STATE\nret 2\nend\nend\nif ok\nm2_ok = true/
abort-ignored|s/if ne get cfg use_abort 0/if ne get cfg use_abort 99/
stall-strict|s/if ge now get dl 3/if gt now get dl 3/
hard-inclusive|s/while lt now get dl 2 bound/while le now get dl 2 bound/
default-total|s/OMEGA_GPU_WAIT_DEFAULT_TOTAL_MS ulong 600000/OMEGA_GPU_WAIT_DEFAULT_TOTAL_MS ulong 600001/
default-progress|s/OMEGA_GPU_WAIT_DEFAULT_PROGRESS_MS ulong 5000/OMEGA_GPU_WAIT_DEFAULT_PROGRESS_MS ulong 4999/
abort-no-elapsed|s/put rpt elapsed_ns sub get dl 5 get dl 4\nret 2/ret 2/
polls-not-counted|s/put rpt polls add get rpt polls ulong 1\n//
timeout-no-elapsed|s/put rpt elapsed_ns sub now get dl 4\nput rpt result OMEGA_GPU_WAIT_TIMEOUT/put rpt result OMEGA_GPU_WAIT_TIMEOUT/
poll-no-elapsed|s/put rpt elapsed_ns sub now get dl 4\n\nif chg/if chg/
no-clock-passes|s/if eq get cfg has_clock 0\nput rpt result OMEGA_GPU_WAIT_INVALID_STATE/if eq get cfg has_clock 0\nput rpt result OMEGA_GPU_WAIT_PASS/
no-word-timeout|s/if eq get cfg has_word 0\nput rpt result OMEGA_GPU_WAIT_INVALID_STATE/if eq get cfg has_word 0\nput rpt result OMEGA_GPU_WAIT_TIMEOUT/
no-word-before-clock|s/dl = new ulong 6 0\ngw_init_dl cfg rpt dl\nif eq get cfg has_word 0\nput rpt result OMEGA_GPU_WAIT_INVALID_STATE\nret false\nend\n/if eq get cfg has_word 0\nput rpt result OMEGA_GPU_WAIT_INVALID_STATE\nret false\nend\ndl = new ulong 6 0\ngw_init_dl cfg rpt dl\n/
lastprog-stale|s/put rpt last_progress_ns now\n//
no-relax|s/gw_relax uh\nret 0/ret 0/
snap1-from-snap0|s/put rpt snap1 get snap 1/put rpt snap1 get snap 0/
expected-not-reported|s/put rpt expected expected\n//
start-not-reported|s/put rpt start_ns start\n//
stall-from-total|s/put dl 3 add start stall_ns/put dl 3 add start total_ns/
EOF

n=0; killed=0; bad=0
while IFS='|' read -r name expr; do
  [ -n "$name" ] || continue
  n=$((n + 1))
  T=$M/t$n
  mkdir -p "$T"
  cp "$SRC" "$T/omega_gpu_wait.om"
  perl -0pi -e "$expr" "$T/omega_gpu_wait.om"
  if cmp -s "$SRC" "$T/omega_gpu_wait.om"; then
    echo "MUTANT $n $name NOT-APPLIED $expr"; bad=$((bad + 1)); continue
  fi
  if ! (printf 'om2\n'; sed '/^om2$/d' "$T/omega_gpu_wait.om" "$ROOT/tests/gpu_wait_dump.om") | "$OMC" > /dev/null 2> "$T/omc.err"; then
    echo "MUTANT $n $name NO-BUILD $(head -1 "$T/omc.err") $expr"; bad=$((bad + 1)); continue
  fi
  if GPU_WAIT_OM_SRC=$T/omega_gpu_wait.om GPU_WAIT_PARITY_WORK=$T/w sh "$ROOT/tests/gpu_wait_parity.sh" "$OMC" > "$T/parity.out" 2>&1; then
    bad=$((bad + 1)); echo "MUTANT $n $name SURVIVED $expr"
  elif grep -q '^GPU_WAIT_PARITY files=' "$T/parity.out"; then
    killed=$((killed + 1)); echo "MUTANT $n $name KILLED by $(grep '^PARITY .* DIFF' "$T/parity.out" | cut -d' ' -f2 | tr '\n' ' ')"
  else
    bad=$((bad + 1)); echo "MUTANT $n $name ERROR (parity did not run): $(tail -1 "$T/parity.out")"
  fi
  rm -rf "$T/w"
done < "$M/list"
echo "GPU_WAIT_PARITY_MUTANTS run=$n killed=$killed bad=$bad"
[ "$bad" -eq 0 ]
