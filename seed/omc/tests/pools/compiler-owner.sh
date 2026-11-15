#!/bin/sh
# Compiles the compiler source. The historical control refuses its pool
# declaration; this head accepts it. The recording compiler is $OMC.
set -eu
cd "$(dirname "$0")/../../../.."
OMC=${OMC:-seed/out/omc}
"$OMC" < seed/omc/omc.om > /dev/null
