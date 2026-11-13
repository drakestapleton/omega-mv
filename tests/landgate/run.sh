#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# tests/landgate/run.sh: TEST INSTRUMENT (shell, never on a product path). The repository-owned landing campaign for a
# change to the seeded compiler line: every step, its command, exit, expected exit, required text and log sha256 go to
# OUT/SUMMARY.log; nothing is retried; a step whose exit or required text differs is a failed record.
# usage: tests/landgate/run.sh BASE OUT     (run from a CLEAN checkout of the head; OUT must not exist)
#   BASE          the Radicle main commit the head sits on (its seed/out/omc is the comparison compiler)
#   OMEGA_BRIDGE  an omega-bridge git checkout holding the om/omega-bridge.lock commit (units, parity, qualify)
#   PHYSICS_DIR   the physics checkout for make test-m15
#   LANDGATE_CORE0_LOCK  optional lock file taken (flock) around the one step pinned to CPU 0 (sched-core0)
# The campaign: seed rebuilt twice to the committed bytes; the full host gate (tests/gates/run.sh seed, which runs the
# pool gate, the compiler-pin admission/consumer checks and every host module); the new-word modules present in the
# head; gate18 and its changed-generator controls; effects; semhash; the full pool gate again with retained work;
# recovered owners; pin checks; units and parity; TLS; profile; m15; a64efi; x86efi; om-units; zero-disk-secrets;
# evidence-immutable; exact bytes of BASE's corpus under BASE's compiler and the head's (samebytes); backend gates;
# orig4 pin; limbo; qualify; the pin grep; the shallow-clone pool gate; the scheduler cases on CPU 0; the judge
# controls of tests/landgate/controls.sh; the readiness, receipt and bundle instrument controls of
# tests/landgate/instruments.sh; the host effect matrix check (where present); the whole-tree merge-residue check of
# tests/landgate/merge-residue.sh; tree clean before and after. The record judge (rec, na, invalid, verdict) is
# tests/landgate/rec.sh.
# Exit 0 only when every record matches ("LANDGATE PASS rc=0"); 1 otherwise; 2 usage or setup.
set -u
BASE=${1:?usage: tests/landgate/run.sh BASE OUT}; OUT=${2:?usage: tests/landgate/run.sh BASE OUT}
F=$(git rev-parse --show-toplevel) || exit 2; cd "$F" || exit 2
H=$(git rev-parse HEAD)
[ ! -e "$OUT" ] || { echo "landgate: refusing to reuse $OUT"; exit 2; }
mkdir -p "$OUT" && L=$(cd "$OUT" && pwd) || exit 2
S=$L/SUMMARY.log; failed=0
BR=${OMEGA_BRIDGE:-}; PHY=${PHYSICS_DIR:-}
git cat-file -e "$BASE^{commit}" 2> /dev/null || { echo "landgate: base $BASE not in this clone" > "$S"; exit 2; }
git merge-base --is-ancestor "$BASE" "$H" || { echo "landgate: base $BASE is not an ancestor of $H" > "$S"; exit 2; }
echo "head $H parent $(git rev-parse HEAD^) base $BASE utc $(date -u +%FT%TZ) instrument tests/landgate/run.sh blob $(git rev-parse HEAD:tests/landgate/run.sh)" > "$S"
. tests/landgate/rec.sh || exit 2
rec tree-clean-before 0 bash -c 'test -z "$(git status --porcelain)"'
cp seed/out/omc "$L/committed-omc"; sha256sum "$L/committed-omc" > "$L/committed-omc.sha256"
rec make-oracles 0 make OUT_DIR=build build/omegese/omegese build/omega_emit/omega_emit build/checker2/checker2
rec seed-rebuild 0 sh seed/omega-from-seed.sh
rec seed-rebuild-equal 0 cmp seed/out/omc "$L/committed-omc"
rec seed-rebuild-second 0 sh seed/omega-from-seed.sh
rec seed-second-equal 0 cmp seed/out/omc "$L/committed-omc"
rec size-history-unchanged 0 git diff --exit-code -- seed/omc/size-history.tsv seed/omc/omc.om seed/out
rec gate-seed 0 env OUT_DIR=build/step-seed tests/gates/run.sh seed
for m in fstatfs execfds container hostpool; do
  if [ -f "seed/host/$m/check.sh" ]; then rec "newword-$m" 0 sh "seed/host/$m/check.sh" seed/out/omc
  else na "newword-$m" "seed/host/$m is not in this head"; fi
done
rec gate18 0 sh seed/omc/gate18.sh
for kw in prlimit:235 execfds:201; do
  w=${kw%%:*}; d=$L/kwctl-$w
  if ! grep -q "$kw" seed/omc/genkw.awk; then na "gate18-changed-generator-$w" "$kw is not in this head's genkw.awk"; continue; fi
  mkdir -p "$d/seed/omc"; cp seed/omc/gate18.sh seed/omc/genkw.awk seed/omc/omc.om "$d/seed/omc/"
  sed -i "s/$kw/$w:1/" "$d/seed/omc/genkw.awk"
  if [ "$(grep -c "$kw" "$d/seed/omc/genkw.awk")" != 0 ] || [ "$(grep -c "$w:1 " "$d/seed/omc/genkw.awk")$(grep -c "$w:1\"" "$d/seed/omc/genkw.awk")" = 00 ]; then
    invalid "gate18-changed-generator-$w" "mutation $kw -> $w:1 not applied exactly"; continue
  fi
  diff seed/omc/genkw.awk "$d/seed/omc/genkw.awk" > "$d/mutation.diff"
  WANT_TEXT="generated keyword packs differ" rec "gate18-changed-generator-$w" 1 sh "$d/seed/omc/gate18.sh"
done
rec effects 0 sh seed/effects/check.sh
rec semhash 0 sh seed/semhash/check.sh
rec pools-full 0 env POOLS_WORKDIR="$L/pools.work" sh seed/omc/gate-pools.sh seed/out/omc
rec recovered-owners 0 sh seed/omc/tests/pools/recovered-owners.sh
rec pins-admission 0 sh seed/omc/tests/pins/admission-check.sh
rec pins-om 0 sh seed/omc/tests/pins/om-check.sh
rec pins-seed 0 sh seed/omc/tests/pins/seed-check.sh
rec pins-orig4 0 sh seed/omc/tests/pins/orig4-check.sh
if [ -n "$BR" ]; then
  rec pins-generator 0 sh seed/omc/tests/pins/generator-check.sh "$BR"
  rec units-check 0 env OMEGA_OMC="$F/seed/out/omc" OMEGA_BRIDGE="$BR" sh om/units.sh --check
else invalid pins-generator "OMEGA_BRIDGE unset"; invalid units-check "OMEGA_BRIDGE unset"; fi
for d in aarch64 evidence gpumath receipt; do rec "parity-$d" 0 env OMEGA_OMC="$F/seed/out/omc" ${BR:+OMEGA_BRIDGE="$BR"} sh "om/$d/parity/run.sh"; done
rec parity-codec 0 env OMEGA_OMC="$F/seed/out/omc" sh om/codec/parity/run.sh --mutants
for t in ec ecdh rsa rev x509; do rec "tls-$t" 0 sh "om/tls/test/$t/run.sh" "$F/seed/out/omc"; done
rec profile-check 0 bash -c 'mkdir -p build/seed && seed/out/omc < seed/profile/check.om > build/seed/profile-check && chmod +x build/seed/profile-check && build/seed/profile-check'
if [ -n "$PHY" ]; then rec m15 0 make PHYSICS_DIR="$PHY" test-m15; else invalid m15 "PHYSICS_DIR unset"; fi
rec a64efi 0 env TMPDIR=/tmp sh tests/a64efi/run.sh
rec x86efi 0 env TMPDIR=/tmp sh tests/x86efi/run.sh
rec om-units 0 env OUT_DIR=build/step-om-units tests/gates/run.sh om-units
rec zero-disk-secrets 0 env OUT_DIR=build/step-zds tests/gates/run.sh zero-disk-secrets
git update-ref refs/remotes/origin/main "$BASE"
rec evidence-immutable 0 env AIEN_BASE_REF=origin/main OUT_DIR=build/step-ei tests/gates/run.sh evidence-immutable
git show "$BASE:seed/out/omc" > "$L/base-omc" && chmod 555 "$L/base-omc"
rec samebytes-base-corpus 0 bash tests/landgate/samebytes.sh "$L/base-omc" "$F/seed/out/omc" "$L/samebytes" "$F@$BASE"
rec gate-irequiv 0 env OMC="$F/seed/out/omc" sh seed/equiv/gate-irequiv.sh
rec gate-json 0 env OMC="$F/seed/out/omc" sh seed/json/tests/gate-json.sh
rec gate-irwasm 0 env OMC="$F/seed/out/omc" sh seed/wasm/gate-irwasm.sh
rec orig4-compiler-pin 0 sh tests/orig4/run.sh --check-compiler-pin
rec tls-limbo 0 sh om/tls/test/x509/limbo.sh "$F/seed/out/omc"
if [ -n "$BR" ]; then rec qualify-abi-sha 0 python3 seed/qualification/om2/current/qualify.py --bridge "$BR" --output "$L/qualify-out"; fi
rec pin-grep 0 bash tests/landgate/pin-grep.sh "$BASE"
git clone -q --depth 1 "file://$F" "$L/shallow" 2> /dev/null
WANT_TEXT="NOT_RUN gate-pools: shallow clone" rec pools-shallow 3 bash -c 'cd "$1" && test "$(git rev-parse HEAD)" = "$2" && test "$(git rev-parse --is-shallow-repository)" = true && exec sh seed/omc/gate-pools.sh seed/out/omc' sh "$L/shallow" "$H"
core0() { if [ -n "${LANDGATE_CORE0_LOCK:-}" ]; then flock "$LANDGATE_CORE0_LOCK" taskset -c 0 "$@"; else taskset -c 0 "$@"; fi; }
WANT_TEXT="OM2GATE PASS" rec sched-core0 0 core0 bash -c 'set -e; mkdir -p build/seed/c0 build/seed/sched-caller; seed/out/omc < seed/qualification/om2/gate.om > build/seed/c0/gate; chmod +x build/seed/c0/gate; seed/out/omc < seed/host/affinity/caller-conductor.om > build/seed/sched-caller/conductor; chmod +x build/seed/sched-caller/conductor; echo "mask $(taskset -cp $$)"; exec build/seed/c0/gate seed/out/omc "$(cut -c1-64 seed/out/omc.sha256)" seed/host/affinity/sched.cases "$1"' sh "$L/sched-core0.scratch"
if [ -f seed/host/matrix-check.py ]; then rec matrix-check 0 python3 seed/host/matrix-check.py seed/host/EFFECT-MATRIX.md "$BASE"; else na matrix-check "seed/host/EFFECT-MATRIX.md is not in this head"; fi
WANT_TEXT="LANDGATE-CONTROLS PASS" rec judge-controls 0 bash tests/landgate/controls.sh "$BASE" "$L/controls"
WANT_TEXT="LANDGATE-INSTRUMENTS PASS" rec instrument-controls 0 bash tests/landgate/instruments.sh "$L/instruments"
WANT_TEXT="MERGE-RESIDUE PASS" rec merge-residue 0 bash tests/landgate/merge-residue.sh
rec tree-clean-after 0 bash -c 'test -z "$(git status --porcelain)"'
[ "$(git rev-parse HEAD)" = "$H" ] || invalid head-moved "HEAD is no longer $H"
verdict
cat "$S"
[ "$failed" = 0 ]
