#!/bin/sh
# TEST INSTRUMENT. Pool declarations name this file. It compiles each of those
# units alone, then the composition its gate actually builds. Python is the
# measuring instrument; the product sources stay Omega.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../../.." && pwd)
cd "$ROOT"
OMC=${OMC:-seed/out/omc}
exec python3 "$ROOT/seed/omc/tests/pools/compose-owner.py" "$OMC" "$@"
