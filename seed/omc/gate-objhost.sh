#!/bin/sh
# gate-objhost.sh [OMC] -- host effects in native objects (DRA-542; spec/omegese-modules.md, OMEGESE "Native object output").
# Python is an independent test oracle (seed/omc/tests/objhost/check.py), not a build dependency.
# 1. OMC (default seed/out/omc) passes check.py: the object host subset compiles to function-mode code, the
#    rest still refuses, stack records cover host pushes, a linked two-module program does real I/O and
#    matches a single-unit build, and the module driver refuses a chain over 8 MiB only through a push.
# 2. Controls, each built by OMC from a one-line change of seed/omc/omc.om and required to FAIL check.py
#    with its named contract:
#    record  the object stack record drops the transient pushes (osmax), the under-report this gate exists for;
#    device  the device words are let into objects;
#    count   spsub stops counting, so pushes are never charged.
# 3. CTRL (environment, optional): an older compiler that refuses host words in objects must FAIL check.py.
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$R"
S=${1:-seed/out/omc}
case "$S" in /*) ;; *) S="$R/$S";; esac
test -x "$S"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
python3 seed/omc/tests/objhost/check.py "$S" "$T/main"
echo "PASS objhost check $(sha256sum "$S" | cut -d' ' -f1)"
for mode in record device count; do
    python3 - "$mode" "$T/$mode.om" <<'PY'
from pathlib import Path
import sys
s = Path("seed/omc/omc.om").read_text()
old, new = {
    "record": ("a_p 86 sub get curfn 0 1 add get stkbytes 0 get osmax 0", "a_p 86 sub get curfn 0 1 get stkbytes 0"),
    "device": ("\nif and ne get objmode 0 0 and ge c 166 le c 177\nnote d2site 174", "\nif and ne get objmode 0 0 and ge c 166 le c 99\nnote d2site 174"),
    "count": ("put osp 0 add get osp 0 bytes\n", "put osp 0 get osp 0\n"),
}[sys.argv[1]]
assert s.count(old) == 1, sys.argv[1]
Path(sys.argv[2]).write_text(s.replace(old, new))
PY
    "$S" < "$T/$mode.om" > "$T/$mode"
    chmod +x "$T/$mode"
    rc=0
    python3 seed/omc/tests/objhost/check.py "$T/$mode" "$T/out-$mode" > "$T/$mode.log" 2>&1 || rc=$?
    # record: the fopen record drops below 4112; device: mapdrop compiles; count: every save area pops
    # past a zero count, so osbad refuses the first object function that calls a host word (finish, error 9).
    want=$(case $mode in record) echo object-host-stack-record;; device) echo 'mapdrop';; count) echo 'error 9';; esac)
    test "$rc" = 1 || { tail -5 "$T/$mode.log"; echo "FAIL objhost mutant $mode status=$rc"; exit 1; }
    grep -q -e "$want" "$T/$mode.log" || { tail -5 "$T/$mode.log"; echo "FAIL objhost mutant $mode: wrong failure"; exit 1; }
    echo "PASS objhost compiler mutant $mode caught"
done
if [ -n "${CTRL:-}" ]; then
    rc=0
    python3 seed/omc/tests/objhost/check.py "$CTRL" "$T/ctrl" > "$T/ctrl.log" 2>&1 || rc=$?
    test "$rc" = 1 || { echo "FAIL objhost control $CTRL status=$rc"; exit 1; }
    grep -q 'object-code-equals-function-mode\|AssertionError' "$T/ctrl.log" || { tail -5 "$T/ctrl.log"; exit 1; }
    echo "PASS objhost control refused by older compiler $(sha256sum "$CTRL" | cut -d' ' -f1)"
fi
echo "OBJHOSTGATE PASS mutants=3"
