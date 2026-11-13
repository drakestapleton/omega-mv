#!/bin/sh
# Python is an independent object test oracle, not a native linker dependency.
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$R"
S=${1:-seed/out/omc}
case "$S" in /*) ;; *) S="$R/$S";; esac
test -x "$S"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
python3 seed/omc/tests/objects/check.py "$S"
for mode in target stack; do
    python3 - "$mode" "$T/mut.om" <<'PY'
from pathlib import Path
import sys
s=Path("seed/omc/omc.om").read_text()
old,new={"target":("objhdr 16 1","objhdr 16 99"),
         "stack":("obj64 a_g 87 i","obj64 0")}[sys.argv[1]]
assert s.count(old)==1
Path(sys.argv[2]).write_text(s.replace(old,new))
PY
    "$S" < "$T/mut.om" > "$T/mut"
    chmod +x "$T/mut"
    rc=0
    python3 seed/omc/tests/objects/check.py "$T/mut" > "$T/$mode.log" 2>&1 || rc=$?
    test "$rc" = 1 || { cat "$T/$mode.log"; echo "FAIL object mutant $mode status=$rc"; exit 1; }
    grep -q "object-$mode-contract" "$T/$mode.log" || { cat "$T/$mode.log"; exit 1; }
    echo "PASS object compiler mutant $mode caught"
done
echo "OBJECTGATE PASS mutants=2"
