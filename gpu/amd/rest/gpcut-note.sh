#!/bin/sh
# TEST INSTRUMENT. CPU only. Builds the AMD rest gate and runs its gpcut
# self-check. Does not open /dev/kfd and does not run the GPU campaign.
set -eu
ROOT=${1:-.}
cd "$ROOT"
OMC=${OMC:-seed/out/omc}
mkdir -p /tmp/omc-b-build
{ printf 'om2\n'; cat seed/ng/sha256.om gpu/amd/rest/gate.om; } | "$OMC" > /tmp/omc-b-build/amd-rest-gate
chmod 700 /tmp/omc-b-build/amd-rest-gate
/tmp/omc-b-build/amd-rest-gate gpcut
echo "GPCUT-NOTE PASS"
