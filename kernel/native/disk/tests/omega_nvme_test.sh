#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Host/disposable-QEMU verification only; no device path argument exists.
set -eu
cd "$(dirname "$0")/../../.."
: "${AIEN_OMC:?set AIEN_OMC to omega-mv's pinned seeded compiler (seed/out/omc)}"
# The pin is omega-mv's own (kernel/ is folded into omega-mv): seed/out/omc.sha256 at its root.
want=$(head -n 1 ../seed/out/omc.sha256 2>/dev/null | cut -c1-64)
printf '%s\n' "$want" | grep -qxE '[0-9a-f]{64}' || { echo 'compiler pin refused: no sha256 in ../seed/out/omc.sha256' >&2; exit 2; }
[ -f "$AIEN_OMC" ] || { echo "compiler pin refused: no compiler at $AIEN_OMC" >&2; exit 2; }
actual=$(sha256sum "$AIEN_OMC")
[ "${actual%% *}" = "$want" ] || { echo 'compiler pin mismatch' >&2; exit 2; }
# A missing tool is NOT_RUN (exit 3), not a FAIL.
cc_tool=${CC:-cc}
for tool in qemu-system-aarch64 "${cc_tool%% *}" pkill; do
 command -v "$tool" > /dev/null 2>&1 || { echo "NOT_RUN omega_nvme: no $tool on PATH"; exit 3; }
done
out=${OMEGA_NVME_EVIDENCE:-$(mktemp -d /tmp/omega-nvme-evidence-XXXXXX)}
mkdir -p "$out"
case "$out" in /*) ;; *) echo 'evidence directory must be absolute' >&2; exit 2;; esac
# Controls that must print an ALARM line keep their logs here, apart from $out, whose logs must have
# none.
ctl=$(mktemp -d "${TMPDIR:-/tmp}/omega-nvme-controls-XXXXXX")
mkdir -p "$ctl/silent"
# A run that does not end in PASS after the runner is built keeps its evidence: the gate deletes its
# temporary directory, so $out and $ctl are copied to a new directory named on stderr. (A failure
# before that, such as a compile error, has nothing but its stderr.)
keep=0
silent=
# Kill the silent-peer runner and its QEMU stand-in when it still runs.
stop_silent() {
 [ -n "$silent" ] && kill -0 "$silent" 2>/dev/null || return 0
 ss=$(cat "$ctl/silent/silent.pid" 2>/dev/null) || ss=
 [ -z "$ss" ] || { pkill -KILL -P "$ss" || true; kill -KILL "$ss" 2>/dev/null || true; }
 wait "$silent" 2>/dev/null || true
}
on_exit() {
 st=$?
 trap - EXIT
 stop_silent
 if [ "$st" != 0 ] && [ "$keep" = 1 ]; then
  kept=$(mktemp -d "${TMPDIR:-/tmp}/omega-nvme-kept-XXXXXX") &&
   cp -a "$out" "$kept/evidence" && cp -a "$ctl" "$kept/controls" &&
   echo "Evidence kept (exit $st): $kept" >&2
 fi
 rm -rf "$ctl"
 exit "$st"
}
trap on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
GATE=OMEGA-KERNEL-OMEGA-NVME
# The controls this script runs; finish refuses a run whose controls.txt lacks one of them.
CONTROLS='mutant-cid mutant-sqid mutant-status mutant-sqhead mutant-reopen mutant-opcode
 mutant-retention mutant-budget1 mutant-nowait mutant-budget255 mutant-budget257 mutant-cwait51
 mutant-rwait501 mutant-qemu-max-waits qemu-killed qemu-stopped qemu-mute qemu-not-listening
 candidate-mute alarm-printed-counted alarm-planted-host-err alarm-planted-qemu-err
 alarm-planted-control-qemu-killed-log alarm-planted-control-qemu-killed-err
 alarm-planted-mutant-cid-log alarm-planted-mutant-cid-err alarm-planted-extra-log'
base=native/disk
compose() { cat "$base/omega_nvme.om" "$base/omega_nvme_transport.om" "$1"; }
compile() { nice -n 15 "$AIEN_OMC" < "$1" > "$2"; chmod +x "$2"; }
compose "$base/omega_nvme_main.om" > "$out/read.om"
compile "$out/read.om" "$out/read"
compose "$base/tests/omega_nvme_probe.om" > "$out/probe.om"
compile "$out/probe.om" "$out/probe"
compose "$base/tests/omega_nvme_adminwrap.om" > "$out/adminwrap.om"
compile "$out/adminwrap.om" "$out/adminwrap"
compose "$base/tests/omega_nvme_failstop.om" > "$out/failstop.om"
compile "$out/failstop.om" "$out/failstop"
$cc_tool -std=c11 -O2 -Wall -Wextra -Werror -Wno-unused-function \
 "$base/tests/omega_nvme_runner.c" "$base/disk_nvme.c" "$base/disk.c" -o "$out/runner"
$cc_tool -std=c11 -O2 -Wall -Wextra -Werror "$base/tests/omega_nvme_fakepeer.c" -o "$out/fakepeer"
mkdir -p "$out/fakebin"
cp "$out/fakepeer" "$out/fakebin/qemu-system-aarch64"
keep=1

# run_logged DIR NAME CMD...: stdout to DIR/NAME.log, stderr to DIR/NAME.err, exit status to
# DIR/NAME.rc and $rc. For DIR = $out, ALARM lines also go to this script's stderr as they come.
run_logged() {
 rl_dir=$1; rl_name=$2; shift 2
 : >> "$rl_dir/$rl_name.log"; : >> "$rl_dir/$rl_name.err"
 { rl_rc=0; "$@" 2>&1 >> "$rl_dir/$rl_name.log" || rl_rc=$?; echo "$rl_rc" > "$rl_dir/$rl_name.rc"; } |
  while IFS= read -r rl_line || [ -n "$rl_line" ]; do
   printf '%s\n' "$rl_line" >> "$rl_dir/$rl_name.err"
   case $rl_dir:$rl_line in "$out":ALARM*) printf '%s\n' "$rl_line" >&2 ;; esac
  done
 rc=$(cat "$rl_dir/$rl_name.rc")
}
# has_line PREFIX FILE...: some line of the files starts with PREFIX (a fixed string).
has_line() { hl_p=$1; shift; cat "$@" | awk -v p="$hl_p" 'index($0, p) == 1 {f = 1} END {exit !f}'; }
control_line() { echo "CONTROL $GATE/$1 FAILED_AS_REQUIRED" | tee -a "$out/controls.txt"; }
not_run() { cat "$1" >&2; echo "NOT_RUN omega_nvme: $2 exit 3"; exit 3; }
# case_run LOG ARGS...: one runner case that must PASS (exit 0).
case_run() {
 cr_log=$1; shift
 run_logged "$out" "$cr_log" nice -n 15 "$out/runner" "$@"
 [ "$rc" != 0 ] || return 0
 [ "$rc" != 3 ] || not_run "$out/$cr_log.err" "case $*"
 cat "$out/$cr_log.err" >&2; echo "FAIL case $* exit $rc" >&2; exit 1
}
# expect_fail DIR NAME RC LINE CMD...: the run must exit RC and print a line starting with LINE.
expect_fail() {
 ef_dir=$1; ef_name=$2; ef_rc=$3; ef_line=$4; shift 4
 run_logged "$ef_dir" "$ef_name" "$@"
 [ "$rc" != 3 ] || not_run "$ef_dir/$ef_name.err" "$ef_name"
 if [ "$rc" != "$ef_rc" ] || ! has_line "$ef_line" "$ef_dir/$ef_name.log" "$ef_dir/$ef_name.err"; then
  cat "$ef_dir/$ef_name.log" "$ef_dir/$ef_name.err" >&2
  echo "FAIL $ef_name: exit $rc (required $ef_rc) or no line starting '$ef_line'" >&2; exit 1
 fi
}
# alarm_count DIR: ALARM lines in the run logs (*.log, *.err) of DIR.
alarm_count() { cat "$1"/*.log "$1"/*.err 2>/dev/null | grep -c '^ALARM' || true; }
# finish DIR: refuse ALARM lines in DIR's run logs and missing controls, then print the PASS line.
finish() {
 fa=$(alarm_count "$1")
 if [ "$fa" != 0 ]; then grep -H '^ALARM' "$1"/*.log "$1"/*.err >&2 || true; echo "FAIL $fa ALARM lines in $1" >&2; return 1; fi
 for fc in $CONTROLS; do
  grep -qxF "CONTROL $GATE/$fc FAILED_AS_REQUIRED" "$1/controls.txt" 2>/dev/null ||
   { echo "FAIL control $fc did not run" >&2; return 1; }
 done
 fn=$(cat "$1/host.log" "$1/qemu.log" | grep -c '^PASS case=' || true)
 printf 'PASS Omega NVMe host + QEMU + guard, budget and wait mutants + QEMU death control; cases=%s alarms=%s; physical NOT_RUN\n' "$fn" "$fa"
}
: > "$out/controls.txt"

# The C model holds every command and the ready bit in the slow case for half the engine's waits
# (omega_nvme_runner.c SLOW_HOLD_WAITS); the timeout cases must use the engine's budget exactly.
for c in healthy slow singlepage lba4k dstrd serial firmware approval nsid extent range before prp zero metadata format nsze sqes cqes cap stride readytimeout readycfs status; do
 case_run host "$out/read" "$c"
done
case_run host "$out/adminwrap" adminwrap
for c in cid sqid sqhead phase timeout cfs; do
 case_run host "$out/failstop" "$c"
done
for c in opcode0 opcode1 opcode8 opcode9 opcode128 opcode132 adminformat; do
 case_run host "$out/probe" "$c"
done

# Mutants: disposable copies of the composed sources, never source edits or candidate artifacts.
# Each must fail its case with the named exit and reason line.
mutant_awk() {
 awk "$3" "$out/$2.om" > "$out/mutant-$1.om" || { echo "FAIL mutant $1: its source line was not found exactly" >&2; exit 1; }
 compile "$out/mutant-$1.om" "$out/mutant-$1"
}
mutant() {
 mu_name=$1; mu_rc=$2; mu_line=$3; shift 3
 expect_fail "$out" "mutant-$mu_name" "$mu_rc" "$mu_line" nice -n 15 "$out/runner" "$out/mutant-$mu_name" "$@"
 control_line "mutant-$mu_name"
}
for spec in 'cid|if ne and dw3 65535 cid|cid|read' \
 'sqid|if ne shr dw2 16 q|sqid|read' \
 'status|if ne and shr dw3 17 2047 0|status|read' \
 'sqhead|if ne and dw2 65535 get tail q|sqhead|read'; do
 name=${spec%%|*}; rest=${spec#*|}; guard=${rest%%|*}; rest=${rest#*|}; case_name=${rest%%|*}; source=${rest#*|}
 # Remove exactly the named three-line refusal block.
 mutant_awk "$name" "$source" "BEGIN {skip=0;hits=0} \$0==\"$guard\" {skip=3;hits++} skip>0 {skip--;next} {print} END {if(hits!=1)exit 2}"
 # The guard gone, the engine accepts the bad completion: result 0, not the refusal.
 mutant "$name" 1 "FAIL case=$case_name transport=C-model result=0 " "$case_name"
done
mutant_awk reopen failstop 'BEGIN {skip=0;hits=0} $0=="if gt get st 0 0" {skip=3;hits++} skip>0 {skip--;next} {print} END {if(hits!=1)exit 2}'
mutant reopen 1 'FAIL timeout: uncertain DMA is not zeroed/reset/reopened' timeout
mutant_awk opcode probe 'BEGIN {skip=0;hits=0} $0=="if not ok" {skip=3;hits++} skip>0 {skip--;next} {print} END {if(hits!=1)exit 2}'
mutant opcode 1 'FAIL opcode1: NO WRITE OPCODE REACHABLE' opcode1
# Retention: delete only the in-flight ownership marker.
mutant_awk retention read '$0=="put st 1 1" {hits++;next} {print} END {if(hits!=1)exit 2}'
mutant retention 1 'FAIL timeout: timeout/correlation DMA retention' timeout
# Wait budget. Both 256-poll loops cut to 1 poll, or both transport waits deleted: timeout on the
# slow case (result 12). Both loops at 255 or 257 polls: the timeout cases see the budget is not
# 256. A completion wait of 51 us or a ready wait of 501 us: the wait lengths are not the engine's.
mutant_awk budget1 read '$0=="for i ulong 256" {print "for i ulong 1"; hits++; next} {print} END {if(hits!=2)exit 2}'
mutant budget1 1 'FAIL case=slow transport=C-model result=12 ' slow
mutant_awk nowait read '$0=="transport_wait 1000" || $0=="transport_wait 100" {hits++; next} {print} END {if(hits!=2)exit 2}'
mutant nowait 1 'FAIL case=slow transport=C-model result=12 ' slow
mutant_awk budget255 read '$0=="for i ulong 256" {print "for i ulong 255"; hits++; next} {print} END {if(hits!=2)exit 2}'
mutant budget255 1 'FAIL timeout: timeout case: the longest wait loop took 255 waits, 25500 us;' timeout
mutant_awk budget257 read '$0=="for i ulong 256" {print "for i ulong 257"; hits++; next} {print} END {if(hits!=2)exit 2}'
mutant budget257 2 'FAIL readytimeout: ENGINE_OVER_BUDGET 257 waits in one loop' readytimeout
mutant_awk cwait51 read '$0=="transport_wait 100" {print "transport_wait 51"; hits++; next} {print} END {if(hits!=1)exit 2}'
mutant cwait51 1 'FAIL slow: slow case: wait loops took 128 to 251 waits,' slow
mutant_awk rwait501 read '$0=="transport_wait 1000" {print "transport_wait 501"; hits++; next} {print} END {if(hits!=1)exit 2}'
mutant rwait501 1 'FAIL readytimeout: timeout case: the longest wait loop took 256 waits, 128256 us;' readytimeout

# QEMU. Firmware identity is intentionally pinned; a different QEMU version refuses.
qemu-system-aarch64 --version > "$out/qemu-version.txt"
# A runnable peer that never answers is ended only by the runner's 30 s ALARM; it runs beside the
# QEMU cases, logged in $ctl/silent; its output goes to files only, so a failing step does not wait
# for it. The runner's pid goes to silent.pid (sh, env and nice exec it).
( run_logged "$ctl/silent" silent sh -c 'echo $$ > "$1"; shift; exec "$@"' sh "$ctl/silent/silent.pid" \
  env OMEGA_NVME_FAKE=trickle PATH="$out/fakebin:$PATH" nice -n 15 "$out/runner" "$out/read" healthy qemu ) > /dev/null 2>&1 &
silent=$!
for c in healthy serial firmware approval nsid extent range before prp zero; do
 case_run qemu "$out/read" "$c" qemu
done
# QEMU_MAX_WAITS: nine waits after each SQ doorbell make a wait loop longer than the runner's 8.
mutant_awk qemu-max-waits read '{print} $0=="ring q 0 get tail q" {for (i = 0; i < 9; i++) print "transport_wait 100"; hits++} END {if(hits!=1)exit 2}'
mutant qemu-max-waits 1 'FAIL healthy: QEMU: a wait loop used ' healthy qemu
# A dead QEMU ends the run with exit 2 and QEMU_DEAD, no ALARM (it is in $out, whose logs have none).
expect_fail "$out" control-qemu-killed 2 'FAIL qemukill: QEMU_DEAD ' nice -n 15 "$out/runner" "$out/read" qemukill qemu
control_line qemu-killed
# A live peer that does not answer: exit 2, its reason on a FAIL line and on an ALARM line.
peer_control() {
 pc_name=$1; pc_line=$2; shift 2
 expect_fail "$ctl" "control-$pc_name" 2 "$pc_line" "$@"
 has_line "ALARM${pc_line#FAIL}" "$ctl/control-$pc_name.err" ||
  { cat "$ctl/control-$pc_name.err" >&2; echo "FAIL control-$pc_name: no line starting 'ALARM${pc_line#FAIL}'" >&2; exit 1; }
 control_line "$pc_name"
}
peer_control qemu-stopped 'FAIL qemustop: QEMU_STOPPED ' nice -n 15 "$out/runner" "$out/read" qemustop qemu
peer_control qemu-mute 'FAIL healthy: QEMU_MUTE ' \
 env OMEGA_NVME_FAKE=mute PATH="$out/fakebin:$PATH" nice -n 15 "$out/runner" "$out/read" healthy qemu
peer_control qemu-not-listening 'FAIL healthy: QEMU_NOT_LISTENING ' \
 env OMEGA_NVME_FAKE=nolisten PATH="$out/fakebin:$PATH" nice -n 15 "$out/runner" "$out/read" healthy qemu
peer_control candidate-mute 'FAIL healthy: CANDIDATE_MUTE ' \
 env OMEGA_NVME_FAKE=mute nice -n 15 "$out/runner" "$out/fakepeer" healthy
# The runnable silent peer: one ALARM line, then PEER_SILENT and exit 2. A second ALARM line means the
# runner went on after its ALARM: it is killed (with its QEMU stand-in) and the control fails.
while kill -0 "$silent" 2>/dev/null; do
 if [ "$(grep -c '^ALARM' "$ctl/silent/silent.err" || true)" -gt 1 ]; then
  stop_silent
  cat "$ctl/silent/silent.err" >&2; echo "FAIL silent-peer control: the runner went on after its ALARM line" >&2; exit 1
 fi
 sleep 1
done
wait "$silent" || true
rc=$(cat "$ctl/silent/silent.rc" 2>/dev/null || echo none)
if [ "$rc" != 2 ] || ! has_line 'ALARM healthy: ' "$ctl/silent/silent.err" || ! has_line 'FAIL healthy: PEER_SILENT ' "$ctl/silent/silent.err"; then
 cat "$ctl/silent/silent.log" "$ctl/silent/silent.err" >&2; echo "FAIL silent-peer control: exit $rc, no ALARM line and PEER_SILENT" >&2; exit 1
fi
if (finish "$ctl/silent") > "$ctl/silent/finish.out" 2>&1 || ! has_line 'FAIL 1 ALARM lines' "$ctl/silent/finish.out" || has_line 'PASS Omega' "$ctl/silent/finish.out"; then
 cat "$ctl/silent/finish.out" >&2; echo "FAIL silent-peer control: finish did not refuse its ALARM line" >&2; exit 1
fi
control_line alarm-printed-counted
# One ALARM line planted in a copy of this run's logs, in each kind of log, and in a log name no
# run writes: finish must refuse each copy.
for f in host.err qemu.err control-qemu-killed.log control-qemu-killed.err mutant-cid.log mutant-cid.err extra.log; do
 d=$ctl/planted-$f; mkdir -p "$d"
 cp "$out"/*.log "$out"/*.err "$out/controls.txt" "$d/"
 echo "ALARM planted: one line in $f" >> "$d/$f"
 if (finish "$d") > "$d/finish.out" 2>&1 || ! has_line 'FAIL 1 ALARM lines' "$d/finish.out" || has_line 'PASS Omega' "$d/finish.out"; then
  cat "$d/finish.out" >&2; echo "FAIL planted ALARM in $f was not refused" >&2; exit 1
 fi
 control_line "alarm-planted-$(printf '%s' "${f%.*}-${f##*.}")"
done
sha256sum "$AIEN_OMC" "$base/omega_nvme.om" "$base/omega_nvme_transport.om" "$base/omega_nvme_main.om" \
 "$base/tests/omega_nvme_runner.c" "$base/tests/omega_nvme_fakepeer.c" "$out/read" > "$out/sha256.txt"
finish "$out" > "$out/result.txt" || exit 1
cat "$out/result.txt"
printf 'Evidence: %s\n' "$out"
