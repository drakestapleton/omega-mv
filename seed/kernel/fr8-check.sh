#!/bin/sh
# Host check for the FR-8 kernel words. Compiles the sm_121 encoder and the
# word layer with the seeded omc, then runs the word checks. Opens no device.
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$R"
bin=$(mktemp)
trap 'rm -f "$bin"' EXIT
cat gpu/nvidia/om/encoder/bw_enc_sm121.om seed/kernel/fr8.om seed/kernel/fr8_host.om \
  | nice -n 19 seed/out/omc > "$bin"
chmod 700 "$bin"
"$bin"
echo "FR8 HOST PASS"
