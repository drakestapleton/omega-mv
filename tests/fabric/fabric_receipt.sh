#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Drake Stapleton (AIEN / aien-dev)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# fabric_receipt.sh -- receipt for the Fabric F5-0 exit gate (mk/fabric.mk,
# pure seeded OM-2).
#
#   tests/fabric/fabric_receipt.sh [out-dir]     (default: evidence/F5-0)
#
# Refuses a dirty tree. Runs `make test-fabric` twice from a clean build dir;
# both runs must compile bit-identical pure-OM binaries, pass with zero
# failures and matching check counts, and print identical transcript, state,
# and replay digests. Writes a NEW file named by the SHA-256 of its own bytes.
# Never rewrites an existing receipt. Host-only, loopback only: this receipt
# qualifies nothing physical and no real transport. Shell + coreutils only.
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
cd "$HERE" || exit 2
OUTDIR=${1:-evidence/F5-0}
BUILD_OUT=${OUT_DIR:-build}
FAB_OMC=${FAB_OMC:-seed/out/omc}

if [ -n "$(git status --porcelain)" ]; then
    echo "fabric_receipt: refusing: working tree is dirty (commit first)" >&2
    exit 3
fi
head0=$(git rev-parse HEAD)
tree0=$(git rev-parse 'HEAD^{tree}')
run_id=$(date -u +%Y%m%dT%H%M%SZ)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

run() {   # $1 = label
    rm -rf "$BUILD_OUT/fabric"
    make --no-print-directory OUT_DIR="$BUILD_OUT" FAB_OMC="$FAB_OMC" \
        PHYSICS_DIR=/nonexistent PHYSICS_LOCK_CHECK=0 test-fabric > "$W/$1.log" 2>&1
    local rc=$?
    if [ -f "$BUILD_OUT/fabric/fabric_test" ]; then
        sha256sum "$BUILD_OUT/fabric/fabric_test" | awk '{print $1}' > "$W/$1.bin.sha256"
    fi
    echo $rc
}
rc1=$(run run1)
rc2=$(run run2)
dig() { awk -v k="$2" '$1 == k {print $2}' "$W/$1.log" | tail -n 1; }
is_hex64() { case "$1" in [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) return 0 ;; *) return 1 ;; esac; }

d1=$(dig run1 replay_digest); d2=$(dig run2 replay_digest)
t1=$(dig run1 transcript); t2=$(dig run2 transcript)
sa1=$(dig run1 state_A); sa2=$(dig run2 state_A)
sb1=$(dig run1 state_B); sb2=$(dig run2 state_B)
sc1=$(dig run1 state_C); sc2=$(dig run2 state_C)
v1=$(grep -c '^F5_0_FABRIC_LOOPBACK_PASS$' "$W/run1.log")
v2=$(grep -c '^F5_0_FABRIC_LOOPBACK_PASS$' "$W/run2.log")
f_lines=$(grep -c '^F5_0_FABRIC_LOOPBACK_FAIL$' "$W/run1.log" "$W/run2.log" | awk -F: '{s+=$2} END{print s+0}')
checks1=$(awk '$1 == "checks" {print $2; exit}' "$W/run1.log")
checks2=$(awk '$1 == "checks" {print $2; exit}' "$W/run2.log")
fails1=$(awk '$1 == "checks" {for (i=1;i<=NF;i++) if ($i=="failures") {print $(i+1); exit}}' "$W/run1.log")
fails2=$(awk '$1 == "checks" {for (i=1;i<=NF;i++) if ($i=="failures") {print $(i+1); exit}}' "$W/run2.log")
bin1=$(cat "$W/run1.bin.sha256" 2>/dev/null || true)
bin2=$(cat "$W/run2.bin.sha256" 2>/dev/null || true)
head1=$(git rev-parse HEAD)
dirty1=$(git status --porcelain | grep -v "^?? ${BUILD_OUT}/" || true)

reasons=""
[ "$rc1" = 0 ] && [ "$rc2" = 0 ] || reasons="$reasons make-failed($rc1,$rc2)"
[ "$v1" = 1 ] && [ "$v2" = 1 ] && [ "$f_lines" = 0 ] || reasons="$reasons verdict-line-missing($v1,$v2,fail=$f_lines)"
[ -n "$checks1" ] && [ "$checks1" -gt 0 ] 2>/dev/null && [ "$checks1" = "$checks2" ] || reasons="$reasons checks-missing-or-differs($checks1,$checks2)"
[ "$fails1" = 0 ] && [ "$fails2" = 0 ] || reasons="$reasons nonzero-failures($fails1,$fails2)"
is_hex64 "$d1" && [ "$d1" = "$d2" ] || reasons="$reasons replay-digest-differs"
is_hex64 "$t1" && [ "$t1" = "$t2" ] || reasons="$reasons transcript-differs"
is_hex64 "$sa1" && [ "$sa1" = "$sa2" ] && is_hex64 "$sb1" && [ "$sb1" = "$sb2" ] && is_hex64 "$sc1" && [ "$sc1" = "$sc2" ] || reasons="$reasons state-digests-differ"
is_hex64 "$bin1" && [ "$bin1" = "$bin2" ] || reasons="$reasons binary-digest-differs"
[ "$head0" = "$head1" ] || reasons="$reasons head-moved"
[ -z "$dirty1" ] || reasons="$reasons tree-dirty-after"
verdict=PASS; [ -z "$reasons" ] || verdict=FAIL

log_sha=$(cat "$W/run1.log" "$W/run2.log" | sha256sum | awk '{print $1}')
src_sha=$(cat seed/ng/sha256.om src/runtime/aien_machine_id.om src/fabric/fab_hmac.om src/fabric/fab_loopback.om src/fabric/fabric.om tests/fabric/fabric_test.om mk/fabric.mk | sha256sum | awk '{print $1}')
omc_sha=$(sha256sum "$FAB_OMC" 2>/dev/null | awk '{print $1}')
mkdir -p "$OUTDIR"
cat > "$W/receipt.json" <<JSON
{
  "schema": "omega.f5-0.fabric-loopback.receipt.v2",
  "gate": "F5_0_FABRIC_LOOPBACK",
  "build_mode": "pure-om2",
  "verdict": "$verdict",
  "reasons": "$(echo $reasons)",
  "scope": "host-only, pure seeded OM-2 binary compiled by seed/out/omc, in-process loopback transport, HMAC stand-in authenticator; no real network, no TRUST-1 signature, no hardware qualification",
  "commit": "$head0",
  "tree": "$tree0",
  "run_id": "$run_id",
  "command": "make test-fabric (twice, clean OUT_DIR/fabric each time)",
  "checks_per_binary_run": "${checks1:-null}",
  "failures_per_binary_run": "${fails1:-null}",
  "replay_digest_run1": "${d1:-null}",
  "replay_digest_run2": "${d2:-null}",
  "transcript": "${t1:-null}",
  "state_A": "${sa1:-null}",
  "state_B": "${sb1:-null}",
  "state_C": "${sc1:-null}",
  "binary_sha256_run1": "${bin1:-null}",
  "binary_sha256_run2": "${bin2:-null}",
  "omc_sha256": "${omc_sha:-null}",
  "fabric_sources_sha256": "$src_sha",
  "logs_sha256": "$log_sha",
  "host": "$(uname -srm)"
}
JSON
name=$(sha256sum "$W/receipt.json" | awk '{print $1}')
if [ -e "$OUTDIR/$name.json" ]; then
    echo "fabric_receipt: $OUTDIR/$name.json already exists; not rewritten" >&2
else
    cp "$W/receipt.json" "$OUTDIR/$name.json"
fi
echo "$verdict $OUTDIR/$name.json"
[ "$verdict" = PASS ]
