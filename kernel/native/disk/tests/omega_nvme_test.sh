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
out=${OMEGA_NVME_EVIDENCE:-$(mktemp -d /tmp/omega-nvme-evidence-XXXXXX)}
mkdir -p "$out"
case "$out" in /*) ;; *) echo 'evidence directory must be absolute' >&2; exit 2;; esac
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
${CC:-cc} -std=c11 -O2 -Wall -Wextra -Werror -Wno-unused-function \
 "$base/tests/omega_nvme_runner.c" "$base/disk_nvme.c" "$base/disk.c" -o "$out/runner"
# Every runner's stderr (FAIL detail, ALARM lines) goes to a .err log beside its .log; a case that
# fails prints its stderr and ends the script, and any ALARM line in a passing run fails it below.
: > "$out/host.log"; : > "$out/host.err"
case_run() {
 log=$1; shift
 nice -n 15 "$out/runner" "$@" >> "$out/$log.log" 2>> "$out/$log.err" || {
  rc=$?; cat "$out/$log.err" >&2; echo "FAIL case $* exit $rc" >&2; exit 1; }
}
# slow: the C model holds every command and the ready bit for 128 of the engine's 256 waits
# (omega_nvme_runner.c SLOW_CMD_US, SLOW_READY_US), so the engine's wait budget is exercised.
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
# Remove exactly the named three-line refusal block in disposable sources.
# These are verification mutants, never source edits or candidate artifacts.
mutate() {
 awk -v target="$1" 'BEGIN {skip=0;hits=0} $0==target {skip=3;hits++} skip>0 {skip--;next} {print} END {if(hits!=1)exit 2}' "$2" > "$3"
}
: > "$out/mutants.log"
for spec in 'cid|if ne and dw3 65535 cid|cid|read' \
 'sqid|if ne shr dw2 16 q|sqid|read' \
 'status|if ne and shr dw3 17 2047 0|status|read' \
 'sqhead|if ne and dw2 65535 get tail q|sqhead|read' \
 'reopen|if gt get st 0 0|timeout|failstop' \
 'opcode|if not ok|opcode1|probe'; do
 name=${spec%%|*}; rest=${spec#*|}; guard=${rest%%|*}; rest=${rest#*|}; case_name=${rest%%|*}; source=${rest#*|}
 mutate "$guard" "$out/$source.om" "$out/mutant-$name.om"
 compile "$out/mutant-$name.om" "$out/mutant-$name"
 if nice -n 15 "$out/runner" "$out/mutant-$name" "$case_name" > "$out/mutant-$name.log" 2>&1; then
  echo "FAIL mutant survived $name" >&2; exit 1
 fi
 echo "PASS killed guard-removal mutant $name (baseline case passed)" >> "$out/mutants.log"
done
# Retention negative control: delete only the in-flight ownership marker.
awk '$0=="put st 1 1" {hits++;next} {print} END {if(hits!=1)exit 2}' "$out/read.om" > "$out/mutant-retention.om"
compile "$out/mutant-retention.om" "$out/mutant-retention"
if nice -n 15 "$out/runner" "$out/mutant-retention" timeout > "$out/mutant-retention.log" 2>&1; then
 echo 'FAIL retention mutant survived' >&2; exit 1
fi
echo 'PASS killed retention guard-removal mutant' >> "$out/mutants.log"
# Wait-budget mutants: both 256-poll loops cut to 1 poll, and both transport waits deleted. Each
# must time out on the slow case (result 12), and the unmutated engine passes it (above).
budget_mutant() {
 name=$1; prog=$2
 awk "$prog" "$out/read.om" > "$out/mutant-$name.om"
 compile "$out/mutant-$name.om" "$out/mutant-$name"
 if nice -n 15 "$out/runner" "$out/mutant-$name" slow > "$out/mutant-$name.log" 2>&1; then
  echo "FAIL $name mutant survived the slow case" >&2; exit 1
 fi
 grep -q '^FAIL case=slow transport=C-model result=12 ' "$out/mutant-$name.log" ||
  { cat "$out/mutant-$name.log" >&2; echo "FAIL $name mutant did not die by timeout (result 12)" >&2; exit 1; }
 echo "PASS killed $name mutant on the slow case (result 12)" >> "$out/mutants.log"
}
budget_mutant budget1 '$0=="for i ulong 256" {print "for i ulong 1"; hits++; next} {print} END {if(hits!=2)exit 2}'
budget_mutant nowait '$0=="transport_wait 1000" || $0=="transport_wait 100" {hits++; next} {print} END {if(hits!=2)exit 2}'
: > "$out/qemu.log"; : > "$out/qemu.err"
# Firmware identity is intentionally pinned; a different QEMU version refuses.
qemu-system-aarch64 --version > "$out/qemu-version.txt"
for c in healthy serial firmware approval nsid extent range before prp zero; do
 case_run qemu "$out/read" "$c" qemu
done
# QEMU death control: the runner SIGKILLs QEMU at the 20th RPC and waits for it to go idle; it must
# see QEMU_DEAD and exit 2 at once. timeout bounds only this control (a hang is exit 124, a FAIL).
rc=0; timeout 300 nice -n 15 "$out/runner" "$out/read" qemukill qemu > "$out/control-qemukill.log" 2>&1 || rc=$?
if [ "$rc" != 2 ] || ! grep -q '^FAIL qemukill: QEMU_DEAD ' "$out/control-qemukill.log"; then
 cat "$out/control-qemukill.log" >&2; echo "FAIL QEMU death control: exit $rc, QEMU_DEAD not reported" >&2; exit 1
fi
echo "PASS QEMU death control: killed QEMU ended the run, exit 2 (QEMU_DEAD)" >> "$out/mutants.log"
alarms=$(cat "$out/host.err" "$out/qemu.err" | grep -c '^ALARM' || true)
[ "$alarms" = 0 ] || { grep '^ALARM' "$out/host.err" "$out/qemu.err" >&2; echo "FAIL $alarms ALARM lines" >&2; exit 1; }
cases=$(grep -c '^PASS case=' "$out/host.log" "$out/qemu.log" | awk -F: '{s += $2} END {print s}')
sha256sum "$AIEN_OMC" "$base/omega_nvme.om" "$base/omega_nvme_transport.om" \
 "$base/omega_nvme_main.om" "$base/tests/omega_nvme_runner.c" "$out/read" > "$out/sha256.txt"
printf 'PASS Omega NVMe host + QEMU + guard, budget and wait mutants + QEMU death control; cases=%s alarms=0; physical NOT_RUN\n' "$cases" | tee "$out/result.txt"
printf 'Evidence: %s\n' "$out"
