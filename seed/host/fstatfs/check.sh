#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# seed/host/fstatfs/check.sh [OMC]: TEST INSTRUMENT (shell) for fstatfs (keyword 215); never a product path.
# Run from anywhere; it works in the repository root. OMC defaults to seed/out/omc.
# 1. fstatfs.cases through the OM-2 conductor: the fixture's 12 checks, refusals (20, 7, 25, 9, 30) and two
#    omc.om mutants (each killed at its named check).
# 2. ORACLE layout: seed/host/fstatfs/oracle.py (Python ctypes ORACLE) derives struct statfs from the kernel
#    headers and measures what the kernel writes; derived and measured sizes must agree and the fixture's dump
#    must be exactly that long.
# 3. ORACLE comparator selftest: a changed stable field, a short or long dump and a changed free count under
#    exact comparison must be refused; a changed free count under volatile comparison accepted.
# 4. ORACLE parity: the fixture's "dump" of a pipe, a memfd, / and /sys/fs/cgroup against raw fstatfs on the
#    same descriptor before and after it, os.fstatvfs and the filesystem magic. pipe and memfd: all bytes equal.
#    / and cgroup2 are shared: stable fields equal, f_bfree/f_bavail/f_ffree printed as snapshots only.
# 5. ORACLE private tmpfs (root through sudo -n, a private mount namespace, size=1m,nr_inodes=64): all bytes
#    equal, f_blocks*f_bsize = 1 MiB, f_files = 64. Without passwordless sudo this row is NOT_RUN.
# Exit 0 PASS, 1 FAIL, 3 NOT_RUN (only the tmpfs row could not run; everything else passed).
set -u
R=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd) || exit 1
cd "$R" || exit 1
OMC=${1:-seed/out/omc}
OMC=$(cd "$(dirname -- "$OMC")" && pwd)/$(basename -- "$OMC")
C=seed/host/fstatfs
B=build/seed/fstatfs
mkdir -p "$B" || exit 1
run=$(mktemp -d "$B/run.XXXXXX") || exit 1
run=$(cd "$run" && pwd)
fail() { echo "FSTATFS FAIL: $*"; exit 1; }
[ -x "$OMC" ] || fail "no compiler $OMC"
pin=$(sha256sum "$OMC" | cut -d' ' -f1)
echo "omc $OMC sha256 $pin scratch $run"
"$OMC" < seed/qualification/om2/gate.om > "$B/gate" 2> "$run/gate-build.err" || fail "gate build: $(cat "$run/gate-build.err")"
chmod +x "$B/gate" || fail "chmod gate"
"$B/gate" "$OMC" "$pin" "$C/fstatfs.cases" "$run/cases" > "$run/cases.log" 2>&1
st=$?
[ "$st" = 0 ] && grep -Eqx 'OM2GATE PASS cases=([0-9]+) pass=\1 fail=0 invalid=0 not_run=0' "$run/cases.log" || { cat "$run/cases.log"; fail "fstatfs.cases exit $st"; }
echo "PASS fstatfs.cases: $(grep '^OM2GATE' "$run/cases.log")"
"$OMC" < "$C/fstatfs.om" > "$run/fstatfs" 2> "$run/build.err" || fail "fixture build: $(cat "$run/build.err")"
chmod +x "$run/fstatfs" || fail "chmod fixture"
python3 "$C/oracle.py" layout > "$run/layout.log" 2>&1 || { cat "$run/layout.log"; fail "layout"; }
size=$(sed -n 's/^LAYOUT PASS size=\([0-9][0-9]*\) .*/\1/p' "$run/layout.log")
[ -n "$size" ] || fail "layout size"
echo "PASS $(tail -1 "$run/layout.log")"
"$run/fstatfs" dump < /dev/null > "$run/dump-null" 2> "$run/dump-null.err" || fail "dump of /dev/null exit $?"
[ "$(wc -c < "$run/dump-null")" = "$size" ] || fail "the fixture dump is $(wc -c < "$run/dump-null") bytes, the kernel struct $size"
echo "PASS the fixture writes exactly the measured $size bytes"
python3 "$C/oracle.py" selftest > "$run/selftest.log" 2>&1 || { cat "$run/selftest.log"; fail "comparator selftest"; }
echo "PASS $(tail -1 "$run/selftest.log")"
for k in pipe memfd root cgroup; do
  python3 "$C/oracle.py" compare $k "$run/fstatfs" > "$run/compare-$k.log" 2>&1 || { cat "$run/compare-$k.log"; fail "compare $k"; }
  echo "PASS $(tail -1 "$run/compare-$k.log")"
  grep '^VOLATILE' "$run/compare-$k.log" || true
done
if ! sudo -n true 2> /dev/null; then
  echo "NOT_RUN tmpfs: no passwordless sudo for the private mount namespace"
  exit 3
fi
sudo -n python3 "$R/$C/oracle.py" tmpfs "$run/fstatfs" > "$run/compare-tmpfs.log" 2>&1 || { cat "$run/compare-tmpfs.log"; fail "compare tmpfs"; }
echo "PASS $(tail -1 "$run/compare-tmpfs.log")"
echo "FSTATFS PASS scratch $run"
