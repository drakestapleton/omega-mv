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

# train_receipt.sh -- receipt for the M22 optimizer substrate + E5 provenance
# tests (mk/train.mk, pure seeded OM-2).
#
#   tests/train/train_receipt.sh [out-dir]     (default: evidence/M22/receipts)
#
# Refuses a dirty tree. Runs `make test-train` twice from a clean build dir;
# both runs must compile bit-identical pure-OM binaries, pass train-purity,
# pass all test_train sub-runs, and print identical replay digests and
# replay dispatch heads. Writes a NEW file named by the SHA-256 of its own
# bytes; never rewrites one.
# Verdict vocabulary: the SUBSTRATE tests PASS or FAIL; M22 itself is always
# NOT QUALIFIED here (no tensor/autodiff integration; waits M20/M21).
# Host-only, single core. Shell + coreutils only.
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
cd "$HERE" || exit 2
OUTDIR=${1:-evidence/M22/receipts}
BUILD_OUT=${OUT_DIR:-build}
TRAIN_OMC=${TRAIN_OMC:-seed/out/omc}

if [ -n "$(git status --porcelain)" ]; then
    echo "train_receipt: refusing: working tree is dirty (commit first)" >&2
    exit 3
fi
head0=$(git rev-parse HEAD)
tree0=$(git rev-parse 'HEAD^{tree}')
run_id=$(date -u +%Y%m%dT%H%M%SZ)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

run() {   # $1 = label
    rm -rf "$BUILD_OUT/train"
    make --no-print-directory OUT_DIR="$BUILD_OUT" TRAIN_OMC="$TRAIN_OMC" \
        PHYSICS_DIR=/nonexistent PHYSICS_LOCK_CHECK=0 test-train > "$W/$1.log" 2>&1
    local rc=$?
    if [ -f "$BUILD_OUT/train/test_train" ]; then
        sha256sum "$BUILD_OUT/train/test_train" | awk '{print $1}' > "$W/$1.bin.sha256"
    fi
    echo $rc
}
rc1=$(run run1)
rc2=$(run run2)
dig_first() { awk -v k="$2" '$1 == k {print $2; exit}' "$W/$1"; }
dig_last() { awk -v k="$2" '$1 == k {print $2}' "$W/$1" | tail -n 1; }
is_hex64() { case "$1" in [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) return 0 ;; *) return 1 ;; esac; }

d1a=$(dig_first run1.log replay_digest); d1b=$(dig_last run1.log replay_digest)
d2a=$(dig_first run2.log replay_digest); d2b=$(dig_last run2.log replay_digest)
h1a=$(dig_first run1.log replay_dispatch_head); h1b=$(dig_last run1.log replay_dispatch_head)
h2a=$(dig_first run2.log replay_dispatch_head); h2b=$(dig_last run2.log replay_dispatch_head)
pass1=$(grep -c '^M22_SUBSTRATE_TESTS_PASS$' "$W/run1.log")
pass2=$(grep -c '^M22_SUBSTRATE_TESTS_PASS$' "$W/run2.log")
fail_lines=$(grep -c '^M22_SUBSTRATE_TESTS_FAIL$' "$W/run1.log" "$W/run2.log" | awk -F: '{s+=$2} END{print s+0}')
both1=$(grep -c '^test-train: pure OM-2 PASS, replay digest equal across runs (' "$W/run1.log")
both2=$(grep -c '^test-train: pure OM-2 PASS, replay digest equal across runs (' "$W/run2.log")
purity1=$(grep -c '^train-purity: src/train is 100% pure seeded OM-2 (0 C/H files)$' "$W/run1.log")
purity2=$(grep -c '^train-purity: src/train is 100% pure seeded OM-2 (0 C/H files)$' "$W/run2.log")
bin1=$(cat "$W/run1.bin.sha256" 2>/dev/null || true)
bin2=$(cat "$W/run2.bin.sha256" 2>/dev/null || true)
head1=$(git rev-parse HEAD)
dirty1=$(git status --porcelain | grep -v "^?? ${BUILD_OUT}/" || true)

reasons=""
[ "$rc1" = 0 ] && [ "$rc2" = 0 ] || reasons="$reasons make-failed($rc1,$rc2)"
[ "$pass1" = 2 ] && [ "$pass2" = 2 ] && [ "$fail_lines" = 0 ] || reasons="$reasons verdict-line-missing($pass1,$pass2,fail=$fail_lines)"
[ "$both1" = 1 ] && [ "$both2" = 1 ] || reasons="$reasons cross-run-replay-missing($both1,$both2)"
[ "$purity1" = 1 ] && [ "$purity2" = 1 ] || reasons="$reasons purity-missing($purity1,$purity2)"
is_hex64 "$d1a" && [ "$d1a" = "$d1b" ] && [ "$d1a" = "$d2a" ] && [ "$d2a" = "$d2b" ] || reasons="$reasons replay-digest-differs"
is_hex64 "$h1a" && [ "$h1a" = "$h1b" ] && [ "$h1a" = "$h2a" ] && [ "$h2a" = "$h2b" ] || reasons="$reasons replay-dispatch-head-differs"
is_hex64 "$bin1" && [ "$bin1" = "$bin2" ] || reasons="$reasons binary-digest-differs"
[ "$head0" = "$head1" ] || reasons="$reasons head-moved"
[ -z "$dirty1" ] || reasons="$reasons tree-dirty-after"
verdict=PASS; [ -z "$reasons" ] || verdict=FAIL

log_sha=$(cat "$W/run1.log" "$W/run2.log" | sha256sum | awk '{print $1}')
src_sha=$(cat src/train/generation.om src/train/sgd_update.om src/train/tg_sha256.om src/train/tg_store.om src/train/tg_sgd.om tests/train/test_train.om mk/train.mk | sha256sum | awk '{print $1}')
omc_sha=$(sha256sum "$TRAIN_OMC" 2>/dev/null | awk '{print $1}')
mkdir -p "$OUTDIR"
cat > "$W/receipt.json" <<JSON
{
  "schema": "omega.m22.train-substrate.receipt.v2",
  "gate": "M22_SUBSTRATE",
  "build_mode": "pure-om2",
  "m22_status": "M22 NOT QUALIFIED: optimizer substrate + SGD path only; no tensor/autodiff integration (waits M20/M21)",
  "substrate_tests_verdict": "$verdict",
  "reasons": "$(echo $reasons)",
  "scope": "host-only, single core, pure seeded OM-2 binary compiled by seed/out/omc; process-crash fault injection (fork + exit at commit points, plus torn/corrupt file and reader-race tests); NOT a power-loss test, NOT a GPU or hardware qualification; SGD with caller-supplied gradients (hand-written quadratic), Adam/AdamW deferred",
  "commit": "$head0",
  "tree": "$tree0",
  "tree_clean": true,
  "run_id": "$run_id",
  "command": "make test-train (twice, clean OUT_DIR/train each time; each make runs train-purity + 2 independent pure OM-2 test_train invocations)",
  "subruns_passed_run1": $pass1,
  "subruns_passed_run2": $pass2,
  "replay_digest_run1": "${d1a:-null}",
  "replay_digest_run2": "${d2a:-null}",
  "replay_dispatch_head_run1": "${h1a:-null}",
  "replay_dispatch_head_run2": "${h2a:-null}",
  "binary_sha256_run1": "${bin1:-null}",
  "binary_sha256_run2": "${bin2:-null}",
  "omc_sha256": "${omc_sha:-null}",
  "train_sources_sha256": "$src_sha",
  "logs_sha256": "$log_sha",
  "host": "$(uname -srm)"
}
JSON
name=$(sha256sum "$W/receipt.json" | awk '{print $1}')
if [ -e "$OUTDIR/$name.json" ]; then
    echo "train_receipt: $OUTDIR/$name.json already exists; not rewritten" >&2
    exit 0
fi
cp "$W/receipt.json" "$OUTDIR/$name.json"
echo "train_receipt: $verdict -> $OUTDIR/$name.json"
[ "$verdict" = PASS ]
