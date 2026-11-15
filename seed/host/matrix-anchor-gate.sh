#!/bin/sh
# TEST INSTRUMENT. Content-window anchors survive a harmless inserted line.
# A line-number citation is refused, which is how the old matrix fails.
set -eu
ROOT=${1:-.}
cd "$ROOT"
BASE=${2:-9cf070151808eeb1e60e5c0dbb4e2ebbc1882c8c}
python3 seed/host/matrix-check.py --probe seed/host/EFFECT-MATRIX.md "$BASE"
