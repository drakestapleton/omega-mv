#!/usr/bin/env bash
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

# tests/gates/run.sh: the one entry point for the local verification gates of omega.
# Every step runs the SAME command as the hosted job it mirrors (.github/workflows/pr-smoke.yml,
# host-suites.yml, host-suites-2.yml, host-suites-3.yml, rx-host.yml, turing-yield.yml,
# evidence-immutable.yml, crumb.yml). Manifests under tests/gates/ name this script plus one
# step word, so no manifest needs shell expansion (ADR 0028 P6).
#
# Pinned sibling sources. The hosted jobs checked out aien-spark/physics at physics.lock,
# aien-dev/aienux at aienos.lock and aien-dev/aienux at
# argus.lock, as physics-src/, aienos-src/ and aienos-argus/ next to the Makefile, and exclude
# them from git status. Here the same commits are materialised as private, read-only checkouts
# under build/pins/ (build/ is gitignored) from the sibling clones, offline. Each invocation
# gets fresh source bytes proven against the locked commit's objects; no gate consumes a shared
# mutable dependency worktree.
set -euo pipefail
# Reviewer 2026-11-15 (P1032): an inherited MAKEFLAGS (e.g. -i/-k) or MAKEFILES (e.g. a file with .IGNORE:) would let a failing gate pass; gates run with a clean make.
unset MAKEFLAGS MFLAGS GNUMAKEFLAGS MAKEFILES
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
python3 tools/uxl/windows_paths.py
step="${1:?usage: tests/gates/run.sh <step>}"

# Every step builds in its own directory. The Spark judge (aien-test) runs a repository's host gates
# at the same moment in one worktree; with one shared build/ a gate links an object another gate's
# compiler is still writing (omega#511: OMEGA-M12 "undefined reference to omega_tern_*" with the
# object on the link line). OUT_DIR is read by the Makefile (?=) and by every make it spawns.
# Each invocation's pins stay in a private random directory under build/pins. The step directory
# name keeps only [A-Za-z0-9_.-] from the step word: "spark:test-r13-host" would put a colon in
# a make target ("multiple target patterns").
step_key="$(printf '%s' "$step" | tr -c 'A-Za-z0-9_.-' '-')"
export OUT_DIR="build/step-$step_key"
mkdir -p "$OUT_DIR" "$ROOT/build/pins"
obs() { printf 'AIEN-OBS %s %s\n' "$1" "$2"; }

PINS="$(mktemp -d "$ROOT/build/pins/$step_key.XXXXXX")"
STEP_MARK=""
cleanup() {
  if [ -n "$STEP_MARK" ]; then rm -f -- "$STEP_MARK"; fi
  case "$PINS" in
    "$ROOT/build/pins/$step_key".*)
      chmod -R u+w -- "$PINS" 2>/dev/null || true
      rm -rf -- "$PINS" ;;
  esac
}
trap cleanup EXIT
NOPHYS="PHYSICS_DIR=/nonexistent PHYSICS_LOCK_CHECK=0"
lock() { awk 'NF && $1 !~ /^#/ {print $1; exit}' "$1"; }

# pin <dir-name> <sibling repo> <sha40>: materialize a fresh detached checkout of <sha40>
# from ../<sibling repo>. pinned_checkout.sh disables replacement objects and grafts, copies
# the commit graph into this invocation's repository, re-hashes commit/tree/blob identities,
# verifies raw worktree bytes and modes, and makes the result read-only before returning it.
pin() {
  local name="$1" repo="$2" sha="$3" dir="$PINS/$1" tree
  if [ ! -d "../$repo/.git" ] && [ ! -f "../$repo/.git" ]; then
    echo "run.sh: ../$repo is missing; the hosted job checks out aien-dev/$repo at $sha" >&2
    exit 3
  fi
  chmod u+w -- "$PINS"
  tree="$(tools/pinned_checkout.sh materialize "../$repo" "$sha" "$dir")"
  chmod a-w -- "$PINS"
  obs "pin_${name//-/_}" "\"$sha\""
  obs "pin_${name//-/_}_tree" "\"$tree\""
}
# Every step that builds against physics takes the commit from physics.lock, never a literal:
# the Makefile's check-physics-lock refuses any other commit, so a literal here goes red on
# the next lock bump (it did for the e95e3ed bump, omega#508, and again for 048e5f5, omega#523).
physics_pin() { pin physics-src physics "$(lock physics.lock)"; export PHYSICS_DIR="$PINS/physics-src"; }
aienos_pin()  { pin aienos-src aienos "$(lock aienos.lock)"; export AIENOS_R7_DIR="$PINS/aienos-src"; export AIENOS_COMMIT="$(lock aienos.lock)"; }
argus_pin()   { pin aienos-argus aienos "$(lock argus.lock)"; export ARGUS_REPO="$PINS/aienos-argus"; }
export OMEGA_CANDIDATE_COMMIT="$(git rev-parse HEAD)"

# receipt <file name or glob> <grep pattern>...: the hosted "Show ... receipt" steps.
# Only receipts written during this step count: a hosted job starts from a fresh checkout, so it
# can only see its own run, while a reused local tree keeps build/qual-runs from earlier runs.
STEP_MARK="$(mktemp /tmp/omega-gate-step.XXXXXX)"
receipt() {
  local r; r="$(find build/qual-runs -name "$1" -type f -newer "$STEP_MARK" | head -n 1)"; shift
  test -n "$r"
  local p; for p in "$@"; do grep -q "$p" "$r"; done
  sha256sum "$r"
}
gates_pass() { grep -E 'TOTAL GATES: [0-9]+ \| PASSED: [0-9]+ \| FAILED: 0' "$1" && ! grep -E 'FAILED: [1-9]' "$1"; }

# speed <make target> <receipt file> <gate word>: a speed test (tests/runtime/rx_quiet_reps.h) that found
# the machine too busy to time, or a leg it claims faster disturbed significantly more often than the
# other leg, ends with `AIEN-OBS not_run_reason "cpu_busy"` (or "leg_skew") and exit 77; make reports
# any failing recipe as 2, so the refusal is read from the test's own receipt for this step: "failures": 0
# and the gate word NOT_RUN, which the test writes only when nothing it judged failed. Then the step goes
# on, so every other check is still judged, and ends NOT_RUN (exit 77) only if nothing else failed, with
# reason leg_skew when any refused receipt says so, else cpu_busy.
# Anything else is the failure it was. A passing run gets the receipt check it always had.
BUSY=0
BUSY_REASON=cpu_busy
speed() {
  local target="$1" file="$2" word="$3" rc=0 r f bad=1
  make "$target" || rc=$?
  if [ "$rc" -eq 0 ]; then
    receipt "$file" '"failures": 0,' '"candidate_bound": true,' "\"$word\": \"PASS\""
    return
  fi
  # Every receipt of that name written during this step must say so; any other one keeps the failure.
  r="$(find build/qual-runs -name "$file" -type f -newer "$STEP_MARK")"
  if [ -n "$r" ]; then
    bad=0
    while IFS= read -r f; do
      grep -q '"failures": 0,' "$f" && grep -q '"candidate_bound": true,' "$f" &&
        grep -q "\"$word\": \"NOT_RUN\"" "$f" || bad=1
      if grep -q '"not_run_reason": "leg_skew"' "$f"; then BUSY_REASON=leg_skew; fi
    done <<< "$r"
  fi
  if [ "$bad" = 0 ]; then
    echo "run.sh: $target: refused to time ($BUSY_REASON; the test's NOT RUN lines say why); not judged, the rest of the step runs" >&2
    printf '%s\n' "$r" | xargs sha256sum
    BUSY=1
    return 0
  fi
  return "$rc"
}

case "$step" in
  # crumb-verify (gate CRUMB-VERIFY) is retired (DRA-97, 2026-11-07). Crumb files were removed
  # (2026-11-08) except two already under evidence/, which stay (additions-only). FOLDERS.md keeps the notes.
  # pr-smoke.yml
  base)
    physics_pin; set -o pipefail
    make test | tee build/base.log
    grep -E 'TOTAL GATES: ([0-9]+) \| PASSED: \1 \| FAILED: 0' build/base.log
    ! grep -qE 'FAILED: [1-9]|\[FAIL\]|\(FAIL\)' build/base.log
    ;;
  gpu-tgemm)          # pr-smoke.yml smoke job, "Training GEMM host proofs" step: physics-src at physics.lock;
                      # budgets and warp simulator, no GPU
    physics_pin; set -o pipefail; mkdir -p build
    make test-gpu-tgemm | tee build/tgemm.log
    test "$(grep -c '^GPU_TGEMM: PASS' build/tgemm.log)" = 2
    ;;
  language)           # pr-smoke.yml and host-suites-3.yml (same command)
    set -o pipefail; mkdir -p build
    make $NOPHYS test-language | tee build/lang.log
    grep -E '^PASS ([0-9]+)/\1$' build/lang.log
    ! grep -q '^FAIL' build/lang.log
    ;;
  numeric-transc)     # pr-smoke.yml and host-suites-3.yml (same command and checks)
    set -o pipefail; mkdir -p build
    make $NOPHYS test-numeric-transc | tee build/transc.log
    test "$(grep -cE '^mutant [0-9]+ killed' build/transc.log)" -eq 10
    grep -qE '^test-numeric-transc: PASS \(all 10 mutants killed\)' build/transc.log
    ! grep -q '^FAIL' build/transc.log
    obs mutants_killed 10
    ;;
  gpu-tern)           # pr-smoke.yml smoke job, KT1 ternary GEMV step: physics-src at physics.lock; host battery
                      # and warp simulator, no chip
    physics_pin; set -o pipefail; mkdir -p build
    make test-gpu-tern | tee build/tern.log
    test "$(grep -cE '^gpu_tern_test: [0-9]+ checks, 0 failed: PASS$' build/tern.log)" -eq 2
    ! grep -q '^FAIL' build/tern.log
    ;;
  # host-suites.yml
  searchtrace)        make $NOPHYS test-searchtrace ;;
  estimation)         for t in test-estimation test-est-tools test-estimation-v3 test-est3c-tools; do make $NOPHYS $t; done ;;
  ans)                make $NOPHYS test-inertial-alignment ;;
  numeric-cpu)        for t in test-numeric-cpu test-numeric-qualify test-e1-combine test-chipwait-campaign test-gpu-wait test-gpu-wait-mutants test-gpu-code-alloc test-mufu-ftz; do make $NOPHYS $t; done ;;
  train)              make $NOPHYS test-train ;;
  compiler)           make $NOPHYS test-compiler-quick; make $NOPHYS test-compiler-full ;;
  one-layer-acceptance) make $NOPHYS test-one-layer-acceptance ;;
  physics0)           make $NOPHYS physics0-test ;;
  chip-tool-selftests) for t in test-m19r-qualify test-gate14-combine test-gate-physics-pin test-window-lane-guard test-unwritten-trap-host test-ldst-host test-dgraph-receipt; do make $NOPHYS $t; done ;;
  # seed compiler (no hosted mirror; Spark only): rebuild from the loader, full qualification, IR oracles required
  seed)               make OUT_DIR=build build/omegese/omegese build/omega_emit/omega_emit build/checker2/checker2
                      sh seed/omega-from-seed.sh
                      # A change that adds, removes or renumbers a host keyword runs `seed/effects/check.sh` inside `tests/gates/run.sh seed`, before that gate's final PASS. The run counts only if it prints the closure line (`host keywords == table`, or `closure: host keywords differ from table`). Exit 3, `NOT_RUN`, or any other exit that does not print that line is not a pass and is not proof the closure was checked. A closure diff is a failing seed gate. A step that exists only in a driver outside this repository does not count.
                      sh seed/effects/check.sh 2>&1 | tee "$OUT_DIR.seed-effects.log"
                      if ! grep -qE '^ok +closure: [0-9]+ host keywords == table$' "$OUT_DIR.seed-effects.log" ||
                         grep -q 'NOT_RUN' "$OUT_DIR.seed-effects.log"; then
                        echo "OMEGA-SEED: effects closure did not pass" >&2
                        exit 1
                      fi
                      sh seed/host/check.sh 2>&1 | tee "$OUT_DIR.seed-check.log"
                      if grep -q "^SKIP" "$OUT_DIR.seed-check.log"; then echo "OMEGA-SEED: a seed gate was skipped" >&2; exit 1; fi
                      # gate5 checks that seed/omc/size-history.tsv ends with a row for this omc; check.sh does not run it
                      sh seed/omc/gate5.sh 2>&1 | tee "$OUT_DIR.seed-gate5.log"
                      grep -q "^PASS native-host qualification" "$OUT_DIR.seed-check.log" || { echo "OMEGA-SEED: native-host qualification did not pass" >&2; exit 1; }
                      tail -1 "$OUT_DIR.seed-gate5.log" | grep -q "^GATE5 PASS" || { echo "OMEGA-SEED: gate5 failed" >&2; exit 1; } ;;
  # AMD gfx942 back end (gpu/amd): the gate is seeded Omega, gpu/amd/gate.om, built with seed/ng/sha256.om by
  # seed/out/omc after that compiler's digest is checked; the gate checks it again before building anything.
  # The expected counts below follow gpu/amd/card.tsv and the unit table in gate.om; a change to either changes
  # them in the same commit, so a truncated card or unit table fails here.
  gpu-amd)
    sha256sum -c --quiet seed/out/omc.sha256 || { echo "OMEGA-GPU-AMD REFUSED: seed/out/omc differs from seed/out/omc.sha256" >&2; exit 69; }
    rm -rf "$OUT_DIR/gate" "$OUT_DIR/work"
    { printf 'om2\n'; cat seed/ng/sha256.om gpu/amd/gate.om; } | seed/out/omc > "$OUT_DIR/gate"
    chmod 700 "$OUT_DIR/gate"
    rc=0; "$OUT_DIR/gate" seed/out/omc "$OUT_DIR/work" > "$OUT_DIR/gate.log" || rc=$?
    cat "$OUT_DIR/gate.log"
    [ "$rc" -eq 0 ] || exit "$rc"
    grep -qx 'OMEGA-GPU-AMD PASS units=15 objects=19 binaries=1 references=1 controls=3 caught=3 hardware=NOT_RUN' "$OUT_DIR/gate.log" ||
      { echo "OMEGA-GPU-AMD FAIL: the summary line does not show the expected units, objects, binaries, references and controls" >&2; exit 1; } ;;
  gpu-amd-rest)
    sha256sum -c --quiet seed/out/omc.sha256 || { echo "OMEGA-GPU-AMD-REST REFUSED: seed/out/omc differs from seed/out/omc.sha256" >&2; exit 69; }
    rm -rf "$OUT_DIR/gate" "$OUT_DIR/work"
    { printf 'om2\n'; cat seed/ng/sha256.om gpu/amd/rest/gate.om; } | seed/out/omc > "$OUT_DIR/gate"
    chmod 700 "$OUT_DIR/gate"
    rc=0; "$OUT_DIR/gate" seed/out/omc "$OUT_DIR/work" > "$OUT_DIR/gate.log" || rc=$?
    cat "$OUT_DIR/gate.log"
    [ "$rc" -eq 0 ] || exit "$rc"
    grep -qx 'OMEGA-GPU-AMD-REST PASS sections=34 objects=34 verdicts=377 not_run=120 writer=19 kfd=103 plan=200 controls=14 caught=14 hardware=NOT_RUN' "$OUT_DIR/gate.log" ||
      { echo "OMEGA-GPU-AMD-REST FAIL: the summary line does not show the expected sections, verdicts, plan rows and controls" >&2; exit 1; } ;;
  # Omega layer units (LAYER/units.tsv; gpu also has gpu/extra-units.tsv): each gate is seeded Omega,
  # LAYER/units-gate.om (gpu/extra-units-gate.om), built with seed/ng/sha256.om by seed/out/omc after that compiler's
  # digest is checked; the gate checks it again. It compiles every unit twice, and runs every unit named in
  # LAYER/units-run.tsv (every *_test unit needs a row): exit 0, empty stderr, last stdout line as recorded, or
  # NOT_RUN with its reason, never counted as a pass. Host only: no row runs a hardware unit.
  # The expected counts follow the tables; a change to a table changes them in the same commit.
  gpu-units|gpu-extra-units|aienux-units|apps-units|bridge-units|core-units|protocol-units|si-units|train-units)
    case "$step" in
      gpu-units)       src=gpu/units-gate.om;       want="OMEGA-GPU-UNITS PASS units=405 runs=0 not_run=0 controls=1 caught=1 hardware=NOT_RUN" ;;
      gpu-extra-units) src=gpu/extra-units-gate.om; want="OMEGA-GPU-EXTRA-UNITS PASS units=22 runs=8 not_run=0 controls=2 caught=2 hardware=NOT_RUN" ;;
      aienux-units)    src=aienux/units-gate.om;    want="OMEGA-AIENUX-UNITS PASS units=78 runs=8 not_run=0 controls=2 caught=2 hardware=NOT_RUN" ;;
      apps-units)      src=apps/units-gate.om;      want="OMEGA-APPS-UNITS PASS units=129 runs=6 not_run=0 controls=2 caught=2 hardware=NOT_RUN" ;;
      bridge-units)    src=bridge/units-gate.om;    want="OMEGA-BRIDGE-UNITS PASS units=176 runs=1 not_run=1 controls=2 caught=2 hardware=NOT_RUN" ;;
      core-units)      src=core/units-gate.om;      want="OMEGA-CORE-UNITS PASS units=51 runs=13 not_run=0 controls=2 caught=2 hardware=NOT_RUN" ;;
      protocol-units)  src=protocol/units-gate.om;  want="OMEGA-PROTOCOL-UNITS PASS units=28 runs=6 not_run=0 controls=2 caught=2 hardware=NOT_RUN" ;;
      si-units)        src=si/units-gate.om;        want="OMEGA-SI-UNITS PASS units=501 runs=10 not_run=0 controls=2 caught=2 hardware=NOT_RUN" ;;
      train-units)     src=train/units-gate.om;     want="OMEGA-TRAIN-UNITS PASS units=78 runs=0 not_run=0 controls=1 caught=1 hardware=NOT_RUN" ;;
    esac
    tag="${want%% *}"
    sha256sum -c --quiet seed/out/omc.sha256 || { echo "$tag REFUSED: seed/out/omc differs from seed/out/omc.sha256" >&2; exit 69; }
    rm -rf "$OUT_DIR/gate" "$OUT_DIR/work"
    { printf 'om2\n'; cat seed/ng/sha256.om "$src"; } | seed/out/omc > "$OUT_DIR/gate"
    chmod 700 "$OUT_DIR/gate"
    rc=0; "$OUT_DIR/gate" seed/out/omc "$OUT_DIR/work" < /dev/null > "$OUT_DIR/gate.log" || rc=$?
    cat "$OUT_DIR/gate.log"
    [ "$rc" -eq 0 ] || exit "$rc"
    grep -qx "$want" "$OUT_DIR/gate.log" ||
      { echo "$tag FAIL: the summary line does not show the expected units, runs, not_run rows and controls" >&2; exit 1; } ;;
  # One slice of the CUDApp merge: new Omega for part of the C decision logic of CUDApp nvrm/ and m16/ (gpu/nvidia/driver/). The gate is seeded Omega,
  # gpu/nvidia/driver/gate.om, composed in the order of gpu/nvidia/driver/parts.txt and built by seed/out/omc after its
  # digest is checked. It recomputes every case the C oracle printed (oracle-cases.tsv) and runs one changed-answer
  # control per case kind. The expected case count is counted from the table. Host only; it opens no device.
  gpu-driver)
    sha256sum -c --quiet seed/out/omc.sha256 || { echo "OMEGA-GPU-DRIVER REFUSED: seed/out/omc differs from seed/out/omc.sha256" >&2; exit 69; }
    rm -f "$OUT_DIR/gate"
    parts=()
    while IFS= read -r p; do parts+=("$p"); done < gpu/nvidia/driver/parts.txt
    cat "${parts[@]}" | seed/out/omc > "$OUT_DIR/gate"
    chmod 700 "$OUT_DIR/gate"
    cases="$(grep -cv -e '^#' -e '^$' gpu/nvidia/driver/oracle-cases.tsv)"
    kinds="$(grep -v -e '^#' -e '^$' gpu/nvidia/driver/oracle-cases.tsv | cut -f1 | sort -u | wc -l)"
    rc=0; "$OUT_DIR/gate" gpu/nvidia/driver/oracle-cases.tsv > "$OUT_DIR/gate.log" || rc=$?
    cat "$OUT_DIR/gate.log"
    [ "$rc" -eq 0 ] || exit "$rc"
    grep -qx "OMEGA-GPU-DRIVER PASS cases=$cases controls=$kinds caught=$kinds hardware=NOT_RUN" "$OUT_DIR/gate.log" ||
      { echo "OMEGA-GPU-DRIVER FAIL: the summary line does not show every case and control of the table" >&2; exit 1; }
    # The sequence gate: client.om (the setup and teardown of nvrm/ and m16/, ported from C) against the command
    # sequences the C oracle recorded (seq-cases.tsv), with two controls for each distinct program.
    rm -f "$OUT_DIR/seqgate"
    parts=()
    while IFS= read -r p; do parts+=("$p"); done < gpu/nvidia/driver/seqparts.txt
    cat "${parts[@]}" | seed/out/omc > "$OUT_DIR/seqgate"
    chmod 700 "$OUT_DIR/seqgate"
    cases="$(grep -cv -e '^#' -e '^$' gpu/nvidia/driver/seq-cases.tsv)"
    progs="$(grep -v -e '^#' -e '^$' gpu/nvidia/driver/seq-cases.tsv | cut -f2 | sort -u | wc -l)"
    # seqgate reads a line into a 65536-byte array fixed at compile time and refuses a longer one; warn at half.
    longest="$(awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }' gpu/nvidia/driver/seq-cases.tsv)"
    [ "$longest" -le 32768 ] ||
      echo "OMEGA-GPU-DRIVER-SEQ ALARM: longest seq-cases.tsv line is $longest bytes, over half of seqgate's 65536-byte line array" >&2
    rc=0; "$OUT_DIR/seqgate" gpu/nvidia/driver/seq-cases.tsv > "$OUT_DIR/seqgate.log" || rc=$?
    tail -n 20 "$OUT_DIR/seqgate.log"
    [ "$rc" -eq 0 ] || exit "$rc"
    grep -qx "OMEGA-GPU-DRIVER-SEQ PASS cases=$cases programs=$progs controls=$((2 * progs)) caught=$((2 * progs)) hardware=NOT_RUN" "$OUT_DIR/seqgate.log" ||
      { echo "OMEGA-GPU-DRIVER-SEQ FAIL: the summary line does not show every case and control of the table" >&2; exit 1; } ;;
  # gpu/runtime/ (one slice of the work on CUDApp src/, the C runtime): the gate is seeded Omega, gpu/runtime/gate.om, built with
  # seed/ng/sha256.om and gpu/runtime/zsha.om by seed/out/omc after that compiler's digest is checked; the gate checks
  # it again. Its counts follow gpu/runtime/checks.tsv and controls.tsv, so the line is matched by its form.
  gpu-runtime)
    sha256sum -c --quiet seed/out/omc.sha256 || { echo "OMEGA-GPU-RUNTIME REFUSED: seed/out/omc differs from seed/out/omc.sha256" >&2; exit 69; }
    rm -rf "$OUT_DIR/gate" "$OUT_DIR/work"
    { printf 'om2\n'; cat seed/ng/sha256.om gpu/runtime/zsha.om gpu/runtime/gate.om; } | seed/out/omc > "$OUT_DIR/gate"
    chmod 700 "$OUT_DIR/gate"
    rc=0; "$OUT_DIR/gate" seed/out/omc "$OUT_DIR/work" > "$OUT_DIR/gate.log" || rc=$?
    cat "$OUT_DIR/gate.log"
    [ "$rc" -eq 0 ] || exit "$rc"
    tail -1 "$OUT_DIR/gate.log" | grep -Eqx 'OMEGA-GPU-RUNTIME PASS checks=[1-9][0-9]* controls=([1-9][0-9]*) caught=\1 hardware=NOT_RUN' ||
      { echo "OMEGA-GPU-RUNTIME FAIL: the summary line is not a PASS with every control caught" >&2; exit 1; } ;;
  gpu-checks)
    # The behaviour checks that replace CUDApp tests/ and tools/ (gpu/nvidia/checks/README.md). The expected
    # counts come from checks.tsv (one row per check, one table control each) and mutants.tsv (one source-mutant
    # control per row), so a row the gate skipped cannot pass unseen.
    sha256sum -c --quiet seed/out/omc.sha256 || { echo "OMEGA-GPU-CHECKS REFUSED: seed/out/omc differs from seed/out/omc.sha256" >&2; exit 69; }
    rm -rf "$OUT_DIR/gate" "$OUT_DIR/work"
    { printf 'om2\n'; cat seed/ng/sha256.om gpu/nvidia/checks/gate.om; } | seed/out/omc > "$OUT_DIR/gate"
    chmod 700 "$OUT_DIR/gate"
    rc=0; "$OUT_DIR/gate" seed/out/omc "$OUT_DIR/work" > "$OUT_DIR/gate.log" || rc=$?
    cat "$OUT_DIR/gate.log"
    [ "$rc" -eq 0 ] || exit "$rc"
    n=$(grep -c '^[A-Za-z0-9_]' gpu/nvidia/checks/checks.tsv)
    m=$(grep -c '^[A-Za-z0-9_]' gpu/nvidia/checks/mutants.tsv)
    c=$((n + m + 1))
    grep -qx "OMEGA-GPU-CHECKS PASS checks=$n controls=$c caught=$c hardware=NOT_RUN" "$OUT_DIR/gate.log" ||
      { echo "OMEGA-GPU-CHECKS FAIL: the summary line does not show $n checks and $c caught controls" >&2; exit 1; } ;;
  # CUDA compatibility bridge (bridge/cuda/, one slice of CUDApp compat/: the compat/cuda profile): seeded Omega only. c0_check.om is the
  # profile checker; fixture.om writes the PTX kernel, the link-only libcuda.so.1 stub and synthetic executables;
  # gate.om replays CUDApp's compat/cuda/test.sh and compares its transcript with bridge/cuda/test-sh-84b524ca.txt.
  # The control rebuilds c0_check with its "missing row" refusal removed; the gate must then fail.
  # With BRIDGE_CUDA_CUDAPP (a CUDApp checkout at 84b524ca) and BRIDGE_CUDA_OLDOMC (omc 2c824805...) set, the gate also
  # runs the old test.sh and gcc builds against the Omega stub, and requires oracle=PASS. Hardware stays NOT_RUN.
  # The check counts in want= are pinned, as gpu-units pins its unit count; a change in gate.om's checks changes them here.
  bridge-cuda)
    sha256sum -c --quiet seed/out/omc.sha256 || { echo "BRIDGE-CUDA REFUSED: seed/out/omc differs from seed/out/omc.sha256" >&2; exit 69; }
    rm -rf "$OUT_DIR"; mkdir -p "$OUT_DIR"
    cat gpu/nvidia/om/cache/digest.om bridge/cuda/c0_check.om | seed/out/omc > "$OUT_DIR/c0_check"
    seed/out/omc < bridge/cuda/fixture.om > "$OUT_DIR/fixture"
    { printf 'om2\n'; cat seed/ng/sha256.om bridge/cuda/gate.om; } | seed/out/omc > "$OUT_DIR/gate"
    sed 's/^rfl 55 l 1$/note rfl 55 l 1/' bridge/cuda/c0_check.om > "$OUT_DIR/mutant.om"
    cmp -s bridge/cuda/c0_check.om "$OUT_DIR/mutant.om" && { echo "BRIDGE-CUDA FAIL: the control mutation did not apply" >&2; exit 1; }
    cat gpu/nvidia/om/cache/digest.om "$OUT_DIR/mutant.om" | seed/out/omc > "$OUT_DIR/c0_mutant"
    chmod 700 "$OUT_DIR/c0_check" "$OUT_DIR/fixture" "$OUT_DIR/gate" "$OUT_DIR/c0_mutant"
    oracle=(); want='checks=27 failed=0 oracle=NOT_RUN'
    if [ -n "${BRIDGE_CUDA_CUDAPP:-}" ] && [ -n "${BRIDGE_CUDA_OLDOMC:-}" ]; then
      oracle=("$BRIDGE_CUDA_CUDAPP" "$BRIDGE_CUDA_OLDOMC" "${BRIDGE_CUDA_CC_AARCH64:-/usr/bin/gcc}" "${BRIDGE_CUDA_CC_X86_64:-/usr/bin/x86_64-linux-gnu-gcc}")
      want='checks=34 failed=0 oracle=PASS'
    fi
    rc=0; "$OUT_DIR/gate" "$ROOT/$OUT_DIR/work" "$ROOT/$OUT_DIR/c0_check" "$ROOT/$OUT_DIR/fixture" "${oracle[@]}" > "$OUT_DIR/gate.log" 2>&1 || rc=$?
    cat "$OUT_DIR/gate.log"
    [ "$rc" -eq 0 ] || exit "$rc"
    tail -1 "$OUT_DIR/gate.log" | grep -qx "BRIDGE-CUDA PASS $want hardware=NOT_RUN" ||
      { echo "BRIDGE-CUDA FAIL: the summary line is not PASS with $want" >&2; exit 1; }
    crc=0; "$OUT_DIR/gate" "$ROOT/$OUT_DIR/control" "$ROOT/$OUT_DIR/c0_mutant" "$ROOT/$OUT_DIR/fixture" > "$OUT_DIR/control.log" 2>&1 || crc=$?
    if [ "$crc" -eq 0 ] || ! tail -1 "$OUT_DIR/control.log" | grep -q '^BRIDGE-CUDA FAIL '; then
      echo "BRIDGE-CUDA FAIL: the mutant c0_check was not caught (rc=$crc)" >&2; exit 1
    fi
    echo "BRIDGE-CUDA CONTROL caught: $(tail -1 "$OUT_DIR/control.log")"
    rm -rf "$OUT_DIR/work" "$OUT_DIR/control" ;;
  # NVML library slice (bridge/nvml/, one slice of CUDApp compat/: compat/nvml): libnvidia-ml.c, nvml.h and
  # libnvidia-ml.map are derived files, listed in bridge/nvml/derived.tsv and never stored here. gate.om (seeded Omega)
  # checks the table and the source digests and compiles the source. With BRIDGE_NVML_TOC set (one or more omega-bridge
  # src/toc.om paths, ':'-separated) it compiles each emitter and requires the pinned output digests; with
  # BRIDGE_NVML_CUDAPP (a CUDApp checkout at 84b524ca) it requires CUDApp's committed files to have them too.
  # Controls: a table with one source digest changed (always); with BRIDGE_NVML_TOC, api.om with one value changed
  # (its digest re-pinned, so only the emitted bytes can catch it) and the first toc.om with one line added.
  bridge-nvml)
    sha256sum -c --quiet seed/out/omc.sha256 || { echo "BRIDGE-NVML REFUSED: seed/out/omc differs from seed/out/omc.sha256" >&2; exit 69; }
    rm -rf "$OUT_DIR"; mkdir -p "$OUT_DIR"
    { printf 'om2\n'; cat seed/ng/sha256.om bridge/nvml/gate.om; } | seed/out/omc > "$OUT_DIR/gate"
    chmod 700 "$OUT_DIR/gate"
    extra=(); emit=NOT_RUN; orc=NOT_RUN; tocs=()
    if [ -n "${BRIDGE_NVML_TOC:-}" ]; then
      IFS=: read -r -a tocs <<< "$BRIDGE_NVML_TOC"
      for t in "${tocs[@]}"; do extra+=("toc=$t"); done; emit=PASS
    fi
    if [ -n "${BRIDGE_NVML_CUDAPP:-}" ]; then extra+=("cudapp=$BRIDGE_NVML_CUDAPP"); orc=PASS; fi
    rc=0; "$OUT_DIR/gate" "$OUT_DIR/work" seed/out/omc bridge/nvml/derived.tsv "${extra[@]}" > "$OUT_DIR/gate.log" 2>&1 || rc=$?
    cat "$OUT_DIR/gate.log"
    [ "$rc" -eq 0 ] || exit "$rc"
    tail -1 "$OUT_DIR/gate.log" | grep -qE "^BRIDGE-NVML PASS checks=[0-9]+ failed=0 emitter=$emit oracle=$orc\$" ||
      { echo "BRIDGE-NVML FAIL: the summary line is not PASS with emitter=$emit oracle=$orc" >&2; exit 1; }
    nvml_control() { # name table [args...]: the gate must report FAIL
      local name="$1" table="$2"; shift 2
      local crc=0; "$OUT_DIR/gate" "$OUT_DIR/c-$name" seed/out/omc "$table" "$@" > "$OUT_DIR/c-$name.log" 2>&1 || crc=$?
      if [ "$crc" -ne 1 ] || ! tail -1 "$OUT_DIR/c-$name.log" | grep -q '^BRIDGE-NVML FAIL '; then
        echo "BRIDGE-NVML FAIL: control $name was not caught (rc=$crc)" >&2; exit 1
      fi
      echo "BRIDGE-NVML CONTROL $name caught: $(grep -m1 '^FAIL ' "$OUT_DIR/c-$name.log" | cut -c1-160) | $(tail -1 "$OUT_DIR/c-$name.log")"
    }
    src=gpu/nvidia/native/nvml/api.om; ssum="$(sha256sum "$src" | cut -d' ' -f1)"
    sed "0,/\t$ssum\t/s//\t0${ssum:1}\t/" bridge/nvml/derived.tsv > "$OUT_DIR/pin.tsv"
    cmp -s bridge/nvml/derived.tsv "$OUT_DIR/pin.tsv" && { echo "BRIDGE-NVML FAIL: the table mutation did not apply" >&2; exit 1; }
    nvml_control pin "$OUT_DIR/pin.tsv"
    if [ "${#tocs[@]}" -gt 0 ]; then
      sed 's/^note cabi value nvmlReturn_t NVML_ERROR_IRQ_ISSUE 11$/note cabi value nvmlReturn_t NVML_ERROR_IRQ_ISSUE 111/' "$src" > "$OUT_DIR/api-mutant.om"
      cmp -s "$src" "$OUT_DIR/api-mutant.om" && { echo "BRIDGE-NVML FAIL: the source mutation did not apply" >&2; exit 1; }
      msum="$(sha256sum "$OUT_DIR/api-mutant.om" | cut -d' ' -f1)"
      sed "s|\t$src\t$ssum\t|\t$OUT_DIR/api-mutant.om\t$msum\t|" bridge/nvml/derived.tsv > "$OUT_DIR/source.tsv"
      nvml_control source "$OUT_DIR/source.tsv" "${extra[@]}"
      { cat "${tocs[0]}"; printf 'note bridge-nvml control: one added line\n'; } > "$OUT_DIR/toc-mutant.om"
      nvml_control toc bridge/nvml/derived.tsv "toc=$OUT_DIR/toc-mutant.om"
    fi
    rm -rf "$OUT_DIR"/work "$OUT_DIR"/c-* ;;
  # Omega-built shared libraries (bridge/shlib): the generator bridge/shlib/shlib.om and the gate
  # bridge/shlib/gate.om, both seeded Omega built by seed/out/omc after its digest is checked; the gate checks it
  # again. Host only: the probes load the libraries through the system's dynamic loader; no device is opened.
  shlib)
    sha256sum -c --quiet seed/out/omc.sha256 || { echo "OMEGA-SHLIB REFUSED: seed/out/omc differs from seed/out/omc.sha256" >&2; exit 69; }
    rm -rf "$OUT_DIR/gate" "$OUT_DIR/shlib" "$OUT_DIR/work"
    mkdir -p "$OUT_DIR"
    { printf 'om2\n'; cat seed/ng/sha256.om bridge/shlib/gate.om; } | seed/out/omc > "$OUT_DIR/gate"
    seed/out/omc < bridge/shlib/shlib.om > "$OUT_DIR/shlib"
    chmod 700 "$OUT_DIR/gate" "$OUT_DIR/shlib"
    rc=0; "$OUT_DIR/gate" seed/out/omc "$OUT_DIR/shlib" "$OUT_DIR/work" > "$OUT_DIR/gate.log" || rc=$?
    cat "$OUT_DIR/gate.log"
    [ "$rc" -eq 0 ] || exit "$rc"
    grep -qx 'OMEGA-SHLIB PASS checks=34 controls=34 caught=34' "$OUT_DIR/gate.log" ||
      { echo "OMEGA-SHLIB FAIL: the summary line does not show the expected checks and controls" >&2; exit 1; } ;;
  # Standalone backend qualification: these execute the current sources, never
  # accept an old receipt, and leave unavailable dependencies nonpassing (exit 3).
  # They are separate from seed so CPU OpenCL is not required by every host check.
  irwasm)
    sh seed/wasm/gate-irwasm.sh 2>&1 | tee "$OUT_DIR/qualification.log"
    if ! grep -q '^PASS IRWASM native parity cases=' "$OUT_DIR/qualification.log" ||
       ! grep -q '^PASS v7 run parity cases=' "$OUT_DIR/qualification.log" ||
       ! grep -q '^PASS v7 OOB traps=.*no-bounds mutant caught' "$OUT_DIR/qualification.log"; then
      echo "FAIL IRWASM incomplete qualification evidence" >&2
      exit 1
    fi
    ;;
  irspirv)
    # CPU OpenCL only. This is not Vulkan or physical GPU qualification.
    sh seed/spirv/gate-irspirv.sh 2>&1 | tee "$OUT_DIR/qualification.log"
    if ! grep -q '^PASS IRSPIRV CPU OpenCL parity cases=' "$OUT_DIR/qualification.log"; then
      echo "FAIL IRSPIRV incomplete qualification evidence" >&2
      exit 1
    fi
    ;;
  # omega-mv#731 ORIG-4 (no hosted mirror; host only): the shadow advisor's glue over the
  # pinned aien-train units (native/orig4/orig4.pin, one aien-train main commit), materialised
  # under build/pins from the sibling clone; every verdict is made by the .om units.
  orig4-shadow)
    train_sha="$(awk '$1 == "unit" && $3 == "aien-train" {print $4; exit}' native/orig4/orig4.pin)"
    pin aien-train-src aien-train "$train_sha"
    set -o pipefail
    OUT="$ROOT/$OUT_DIR/orig4" ORIG4_TRAIN_GIT="$PINS/aien-train-src" \
      sh tests/orig4/run.sh | tee "$OUT_DIR.orig4.log"
    grep -q '^ORIG4_SHADOW_RUN_PASS$' "$OUT_DIR.orig4.log"
    obs shadow_test_checks "$(sed -n 's/.*ORIG4_SHADOW_TEST_PASS checks=\([0-9]*\).*/\1/p' "$OUT_DIR.orig4.log" | head -n 1)"
    obs cost_wall_ms_mlp "$(sed -n 's/^COST_WALL records=780 ms=\([0-9]*\) image=mlp fixture$/\1/p' "$OUT_DIR.orig4.log" | head -n 1)"
    ;;
  # host-suites-2.yml
  visor)              aienos_pin; make $NOPHYS test-visor ;;
  turing)             make $NOPHYS test-turing; make $NOPHYS test-turing-exp001-a test-turing-exp001-coders; make $NOPHYS test-turing-verify-indep; make $NOPHYS test-turing-qcont test-turing-qrecord ;;
  brownian)           make $NOPHYS test-brownian-tps; make $NOPHYS test-brownian-active ;;
  polyglot)           make $NOPHYS test-polyglot-asm; make $NOPHYS test-polyglot-encoder ;;
  algebra)            make $NOPHYS test-algebra test-algebra-asan; make $NOPHYS test-realize; make $NOPHYS test-phase-twin; make $NOPHYS test-ma-digital-bottom ;;
  path)               make $NOPHYS test-path ;;
  crumbline)          make $NOPHYS test-crumbline test-library test-vcstore test-resolve test-vcstore-genesis test-resolve-genesis test-genesis test-genesis-real test-program-ir test-vc-bridge ;;
  runtime)
    physics_pin; aienos_pin
    # host-suites-2.yml sets only PHYSICS_DIR and AIENOS_R7_DIR, and only on the steps that list
    # them; the qualify self-test and the aienos.lock source proof run with neither (the latter
    # checks the default cache, which an inherited AIENOS_R7_DIR override would bypass).
    unset AIENOS_COMMIT OMEGA_CANDIDATE_COMMIT
    make test-r15-instr
    make test-r15-receipt
    make test-r15-preflight test-r15-g15-diag
    make test-r16-inventory
    make test-r16-negative
    make test-r16-surface
    make test-r16-negative-mutants
    env -u PHYSICS_DIR -u AIENOS_R7_DIR make test-r16-qualify-selftest
    env -u PHYSICS_DIR -u AIENOS_R7_DIR make test-aienos-lock-source
    make test-allen
    ;;
  argus)
    physics_pin; aienos_pin; argus_pin
    ARGUS_STREAMS="$(mktemp -d /tmp/argus-streams.XXXXXX)"; export ARGUS_STREAMS
    make test-argus-runtime test-machine-identity-argus
    ;;
  bw-hazard)          # omega-mv#554 scoreboard hazards, then the elementwise host test (DRA-344: RSQ listing,
                      # n=0 refusal, MUFU flush model); host only, no device
    physics_pin; make test-bw-hazard; make test-gpu-elementwise ;;
  numeric2)           make $NOPHYS test-numeric-reduce-cpu test-divsqrt-host ;;
  tensor)             make $NOPHYS test-tensor; make $NOPHYS test-tensor-store; make $NOPHYS test-m20-receipt; make $NOPHYS test-tensor-mutations ;;
  atomf32-probe-host) # host-suites-2.yml gpu-engine job, "f32 global atomic add probe in the warp simulator" step:
                      # physics-src at physics.lock; host, no device (the chip run is by hand)
    physics_pin; make test-atomf32-probe-host ;;
  gpu-decode-graph)   physics_pin; make test-gpu-decode-graph ;;
  gpu-prefill-host)   # omega-mv#1032 (from #456): REQUIRED, first-party prefill host-only tests (3 probes); no device,
                      # no model-shape cases, no OWN-30B build (those run in gpu-prefill-modelshapes)
    physics_pin; set -o pipefail; mkdir -p "$OUT_DIR"
    env -i PATH="$PATH" HOME="$HOME" OUT_DIR="$OUT_DIR" PHYSICS_DIR="$PHYSICS_DIR" make -f Makefile test-gpu-prefill-host-fp | tee "$OUT_DIR/prefill-host.log"
    grep -qx 'test-gpu-prefill-host-fp: PASS (3 first-party prefill tests, host model, no device)' "$OUT_DIR/prefill-host.log"
    ;;
  gpu-prefill-modelshapes) # omega-mv#1032: OPTIONAL lane (requires: operator): model-shape prefill cases + the OWN-30B -Werror build
    physics_pin; set -o pipefail; mkdir -p "$OUT_DIR"
    env -i PATH="$PATH" HOME="$HOME" OUT_DIR="$OUT_DIR" PHYSICS_DIR="$PHYSICS_DIR" make -f Makefile test-gpu-prefill-modelshapes check-own30b-decode-profile | tee "$OUT_DIR/prefill-modelshapes.log"
    grep -qx 'test-gpu-prefill-modelshapes: PASS (5 model-shape prefill tests, host model + warp simulator, no device)' "$OUT_DIR/prefill-modelshapes.log"
    grep -qx 'check-own30b-decode-profile: PASS (compiles with -Werror)' "$OUT_DIR/prefill-modelshapes.log"
    ;;
  # host-suites-3.yml
  numeric-lifecycle)  make $NOPHYS test-numeric-lifecycle ;;
  numeric-transc-digest)
    set -o pipefail; mkdir -p build
    make $NOPHYS test-numeric-transc-digest | tee build/digest.log
    n=$(grep -c 'matches frozen digest' build/digest.log); obs frozen_digests_matched "$n"
    test "$n" -ge 1
    ;;
  gpu-attention)      # host-suites-3.yml gpu-attention (omega#470): physics-src at physics.lock, lock check on;
                      # host-only, sim and sweep tiers, nothing touches a GPU (the Spark has nvdisasm, so the
                      # listing check runs here where the hosted runner printed "skipped")
    physics_pin; set -o pipefail; mkdir -p build
    make -j"$(nproc)" test-gpu-attention | tee build/attn.log
    test "$(grep -cE '^PASS: [0-9]+ checks, 0 failed$' build/attn.log)" -eq 6
    ! grep -qE '^FAIL' build/attn.log
    ;;
  sm121dis)           # L386 bar C6 (docs/OMEGA.md): Omega's own sm_121 disassembler. Host only. Every kernel the
                      # library builds, decoded by build/sm121dis and compared word for word with nvdisasm (the
                      # offline oracle the Spark has), plus the faulty-decoder red check; then ZERO-NVDISASM: the
                      # listing and provenance checks under a decoy nvdisasm and strace, plus its planted-call red check.
    physics_pin; set -o pipefail; mkdir -p build
    make -j"$(nproc)" test-sm121dis | tee build/sm121dis.log
    grep -qE '^kernels: [0-9]+, words: [0-9]+, failed kernels: 0$' build/sm121dis.log
    grep -qE '^red check: the faulty decoder FAILS the comparison' build/sm121dis.log
    make test-zero-nvdisasm | tee build/zero-nvdisasm.log
    grep -qE '^ZERO-NVDISASM: PASS' build/zero-nvdisasm.log
    grep -qE '^red check: the planted nvdisasm calls FAIL the gate' build/zero-nvdisasm.log
    ;;
  gpu-libm-free)      # omega-mv#471: no libm symbol left undefined in libomega_gpu.a (physics-src at physics.lock)
    physics_pin; set -o pipefail; mkdir -p build
    make -j"$(nproc)" test-gpu-libm-free | tee build/libm-free.log
    grep -q '^PASS: libomega_gpu.a is libm-free$' build/libm-free.log
    ;;
  numeric-transc-full) make $NOPHYS test-numeric-transc-full ;;
  m6|m7|m8|m9|m10|m11|m12|m13|m14|m15|m17|m5|m19|m19r-qualify|gate14-combine)
    physics_pin; set -o pipefail; mkdir -p build
    make "test-$step" | tee "build/gate-$step.log"
    gates_pass "build/gate-$step.log"
    ;;
  # rx-host.yml
  rx-host-reference)
    physics_pin; export PHYSICS_COMMIT="$(lock physics.lock)"
    aienos_pin; set -o pipefail; mkdir -p build
    # The hosted job runs these as one make line; the speed test test-action-graph is taken out (speed,
    # above) so a busy machine is a refusal and the targets after it still run, in the same order.
    # All test output also goes to build/rx-host-reference.log, so a step that hits its time limit
    # leaves a record of the test that was running. speed runs in this shell (BUSY), so its output
    # reaches the log through a process substitution, not a pipe.
    make test-r3 test-r7 test-r16-operator-authority-misuse test-r8 test-r9 test-r12 test-rx-emergency | tee build/rx-host-reference.log
    speed test-action-graph rx_action_graph_receipt.json OMEGA_ACTION_GRAPH_IR_PASS > >(tee -a build/rx-host-reference.log)
    make test-state-projection test-capability-query test-capability-graph test-skillroute-compose test-semantic-comm test-cognitive-routing test-sem-incremental test-cortex test-jspace-prod test-composition test-composition-attach-asan test-composition-gate test-fabric test-fabric-living | tee -a build/rx-host-reference.log
    make test-machine-identity | tee -a build/rx-host-reference.log
    make test-effect-cap64 | tee build/effect-cap64.log
    grep -q '^OMEGA_EFFECT_CAP64_PASS$' build/effect-cap64.log
    receipt omega_state_projection_receipt.json '"failures": 0,' '"candidate_bound": true,' '"OMEGA_STATE_PROJECTION_PASS": "PASS"'
    # omega-mv#404 item 2: PASS means the package energy counter (hwmon aien_spbm, found by the
    # same name-prefix test rx_sem_incremental uses) measured the work; HOST_PASS_ENERGY_UNMEASURED
    # means this host has no such counter. The verdict must match this host; PASS_UNBOUND and FAIL
    # never pass. Which one ran is recorded as an observation.
    if grep -qs '^aien_spbm' /sys/class/hwmon/*/name; then inc_verdict=PASS; else inc_verdict=HOST_PASS_ENERGY_UNMEASURED; fi
    receipt omega_incremental_semantics_receipt.json "\"OMEGA_INCREMENTAL_SEMANTICS_PASS\": \"$inc_verdict\"" '"false_hits": 0,'
    obs incremental_semantics_verdict "\"$inc_verdict\""
    receipt rx_capability_query_receipt.json '"failures": 0,' '"candidate_bound": true,' '"OMEGA_CAPABILITY_QUERY_PASS": "PASS"'
    receipt rx_semantic_comm_receipt.json '"failures": 0,' '"candidate_bound": true,' '"OMEGA_SEMANTIC_COMMUNICATION_PASS": "PASS"'
    receipt rx_cognitive_routing_receipt.json '"failures": 0,' '"candidate_bound": true,' '"OMEGA_COGNITIVE_ROUTING_PASS": "PASS"'
    speed test-workflow-fusion rx_workflow_fusion_receipt.json OMEGA_WORKFLOW_FUSION_PASS
    make test-typed-results
    receipt rx_typed_results_receipt.json '"failures": 0,' '"candidate_bound": true,' '"OMEGA_TYPED_RESULT_CONSTRAINTS_PASS": "PASS"'
    make test-costmodel
    receipt rx_aegis_resident_receipt.json '"failures": 0,' '"candidate_bound": true,' '"R8_CONSTITUTIONAL_AEGIS": "PASS"'
    r="$(find build/qual-runs -name rx_heartbeat_receipt.json -type f -newer "$STEP_MARK" | head -n 1)"
    native="$(find build/qual-runs -name rx_native_authority_receipt.json -type f -newer "$STEP_MARK" | head -n 1)"
    generation="$(find build/qual-runs -name rx_generation_barrier_receipt.json -type f -newer "$STEP_MARK" | head -n 1)"
    test -n "$r"; test -n "$native"; test -n "$generation"
    if git diff --quiet && git diff --cached --quiet; then obs tree_cleanliness '"clean"'; else obs tree_cleanliness '"dirty"'; fi
    tools/rx_host_receipts.sh heartbeat "$r"
    tools/rx_host_receipts.sh native "$native" "$OMEGA_CANDIDATE_COMMIT"
    tools/rx_host_receipts.sh generation "$generation" "$OMEGA_CANDIDATE_COMMIT"
    if [ "$BUSY" = 1 ]; then obs not_run_reason "\"$BUSY_REASON\""; exit 77; fi
    ;;
  faculty-arm)
    physics_pin
    aienos_pin; argus_pin; set -o pipefail; mkdir -p build
    make OUT_DIR=build/pid $NOPHYS test-program-id
    make OUT_DIR=build/prz $NOPHYS test-program-realize
    R10_ALLOW_NO_WIN=1 make test-r10
    receipt rx_omega_faculty_receipt.json '"failures": 0,' '"candidate_bound": true,' '"tree_dirty": false,'
    make test-regulate
    make test-r11
    receipt rx_aien_faculty_receipt.json '"failures": 0,' '"candidate_bound": true,' '"tree_dirty": false,'
    make "$OUT_DIR/rx_r13_living_host" "$OUT_DIR/rx_r13_living_testbuild_host"
    make "$OUT_DIR/rx_r14_recovery_host"
    make test-r16-authpath-linkmap | tee build/r16-g3-linkmap-host.log
    grep -qx 'R16-G3 static: R16_G3_LINKMAP=STATIC_PASS mode=host (checks 1-3 of 5 on this build; not the gate)' build/r16-g3-linkmap-host.log
    grep -qx 'R16 gate: R16_G3_AUTHPATH=NOT_RUN (checks 4-5, exec trace and living run, not run in static-only mode)' build/r16-g3-linkmap-host.log
    make test-r16-authpath-linkmap-silicon | tee build/r16-g3-linkmap-silicon.log
    grep -qx 'R16-G3 static: R16_G3_LINKMAP=STATIC_PASS mode=silicon (checks 1-3 of 5 on this build; not the gate)' build/r16-g3-linkmap-silicon.log
    grep -qx 'R16 gate: R16_G3_AUTHPATH=NOT_RUN (checks 4-5, exec trace and living run, not run in static-only mode)' build/r16-g3-linkmap-silicon.log
    make test-prod-hygiene | tee build/prod-hygiene-host.log
    grep -q '^R16 prod: PROD_HYGIENE=PASS mode=host ' build/prod-hygiene-host.log
    R16_PROD_NO_RUN=1 make test-prod-hygiene-silicon | tee build/prod-hygiene-silicon.log
    grep -q '^R16 prod: PROD_HYGIENE=PASS mode=silicon ' build/prod-hygiene-silicon.log
    make test-prod-refuses-test-pieces | tee build/prod-refuses.log
    grep -q '^R16 prod: PROD_REFUSES_TEST_PIECES=PASS ' build/prod-refuses.log
    EMPIRICAL_ALLOW_NO_WIN=1 make test-empirical
    receipt rx_empirical_optimizer_receipt.json '"failures": 0,' '"candidate_bound": true,' '"tree_dirty": false,' '"mismatches": 0,' '"OMEGA_EMPIRICAL_OPTIMIZER_PASS": "\(PASS\|CHAIN_PASS_NO_WIN\)"'
    PLAN_REUSE_NO_ENERGY=1 make test-plan-reuse
    receipt 'rx_plan_reuse_receipt.*.json' '"failures": 0,' '"G3_outcome_and_evidence": "PASS"' '"G4_false_applicability_zero": "PASS"' '"G5_identity": "PASS"'
    make test-rx-deadline-cancel
    make test-i11-wake-merge
    make test-c4-requal
    ;;
  # rx-host.yml chip-only-declared and spark-only targets (SKIP on GitHub, never a pass there)
  chip:*|spark:*)
    t="${step#*:}"
    # Chip and spark steps follow physics.lock like every other step. Makefile check-physics-lock
    # (a prerequisite of omegatool, rx_composition_gate_gpu and libomega_gpu.a) refuses any other
    # physics commit, and omegatool itself now needs the physics API of the lock (nvrm_channel_n,
    # L136 via #614). The former hard-coded physics literal failed every such chip gate on the judge
    # once #614 moved the lock to 048e5f5 (main 18c653b3, 2026-10-25).
    physics_pin
    aienos_pin; argus_pin
    make "$t"
    ;;
  # turing-yield.yml
  turing-yield)       make test-turing-yield test-turing-energy test-turing-range-om ;;
  # evidence-immutable.yml: reviewed evidence is additions-only. Hosted compares the PR base
  # and head; locally the base is origin/main (or AIEN_BASE_REF).
  evidence-immutable)
    base="${AIEN_BASE_REF:-origin/main}"
    obs base_ref "\"$(git rev-parse "$base")\""
    changed="$(git diff --name-status --diff-filter=MDRT "$base...HEAD" -- evidence/)"
    if [ -n "$changed" ]; then
      echo "These existing evidence files would be changed:"; echo "$changed"
      echo "Add a new, content-addressed file instead of rewriting reviewed evidence."
      obs evidence_rewrites "$(printf '%s\n' "$changed" | grep -c .)"
      exit 1
    fi
    obs evidence_rewrites 0
    echo "evidence/: additions only"
    ;;
  zero-disk-secrets)
    echo "Auditing repository for prohibited plaintext secret files..."
    # Inspect every tracked path, including forced additions under generated dirs.
    # NUL records preserve whitespace/newlines; producer failures are not "no hits".
    if ! git ls-files -z > "$OUT_DIR/secret-tracked"; then
      echo "::error::Cannot enumerate tracked paths." >&2; exit 1
    fi
    while IFS= read -r -d '' path; do
      case "${path##*/}" in
        .env*) echo "::error::Tracked plaintext .env path found."
               obs env_files_found true; exit 1 ;;
      esac
    done < "$OUT_DIR/secret-tracked"
    # Also catch untracked working-tree secrets. Only root build output and git
    # metadata are excluded; tracked files in build were already checked above.
    if ! find . \( -path './.git' -o -path './build' \) -prune -o \
        -name '.env*' -print -quit > "$OUT_DIR/secret-untracked"; then
      echo "::error::Cannot complete plaintext secret search." >&2; exit 1
    fi
    if [ -s "$OUT_DIR/secret-untracked" ]; then
      echo "::error::Prohibited plaintext .env file found. Use an approved AIEN SecretProvider."
      obs env_files_found true; exit 1
    fi
    obs env_files_found false
    echo "Zero plaintext .env files verified."
    ;;
  runtime-api)        # omega-mv#594: the Runtime API manifest against the C headers, plus its negative controls.
                      # Host only (gcc for -aux-info), no GPU, no physics checkout.
    make $NOPHYS test-runtime-api ;;
  arboris-gated-silicon)
    sh seed/omega-from-seed.sh
    OMC="$ROOT/seed/out/omc" sh tests/arboris/host.sh "$OUT_DIR"
    for model in gated wide experimental; do
      log="$OUT_DIR/$model-device.log"
      "$OUT_DIR/caproot-issuer" "$OUT_DIR/$model-chip" --arboris-silicon > "$log" || { cat "$log"; exit 1; }
      cat "$log"
      case "$model" in
        gated) halves=40; output=ad8a70b5e2935b7fca819ce4823afea8bef95c56135b6d86e7cf4ada6f16a089 ;;
        experimental) halves=1320; output=21aa98cc216972743626af22a4614ebc7f5e5d8fe3681d8d513d5deaaecf88d6 ;;
        wide) halves=1320; output=ca8052acb8c6306df043531ab6c116c5d8dd69a7e565974338088119f8355e34 ;;
      esac
      grep -Eq '^step_message=4152425354503032[0-9a-f]{352}$' "$log"
      grep -qx "matching_fp16_elements=$halves" "$log"
      grep -qx "kernel_sha256=$(sha256sum "$OUT_DIR/$model.sass" | cut -d' ' -f1)" "$log"
      grep -qx "output_sha256=$output" "$log"
    done
    ;;
  arboris-sparse-silicon)
    sh seed/omega-from-seed.sh
    OMC="$ROOT/seed/out/omc" sh tests/arboris/host.sh "$OUT_DIR"
    for model in sparse small wave persistent hubs; do
      log="$OUT_DIR/arboris-$model.log"
      "$OUT_DIR/caproot-issuer" "$OUT_DIR/$model-chip" --arboris-silicon > "$log" || {
        cat "$log"
        exit 1
      }
      cat "$log"
      case "$model" in
        persistent) words=258; code=persistent.bin; output=125cb0ac528c34014d14a0b99ac75afcf8e21cbd6b3a4845070bd9d5ab638ba4 ;;
        hubs) words=258; code=hubs.bin; output=d1a4e4639301e305a4f7768d14e642153ff5d4b2743bb011009ca9a5358a299b ;;
        sparse) words=200000; code=relax.bin; output=8ded4456ffe03d54cad43b7b7b8d07ff1997919c103dd1b49b61c6782d6e3d19 ;;
        small) words=4096; code=small.bin; output=33dfc6bc867a2bfbe09192038538c209c9b8bc89e16b6cedcaf0e7cf32b1a8f6 ;;
        wave) words=400000; code=wave.bin; output=b2d9f9458d97db2f5415078fbc43ad0256229175bbc28127eeaad941a708dc7a ;;
      esac
      grep -Eq '^step_message=4152425354503032[0-9a-f]{352}$' "$log"
      grep -qx "matching_fp32_words=$words" "$log"
      grep -qx "kernel_sha256=$(sha256sum "$OUT_DIR/$code" | cut -d' ' -f1)" "$log"
      grep -qx "output_sha256=$output" "$log"
    done
    ;;
  arboris)
    sh seed/omega-from-seed.sh > "$OUT_DIR/seed.log" 2>&1
    OMC="$ROOT/seed/out/omc" sh tests/arboris/host.sh "$OUT_DIR"
    ;;
  om-units)           # The C entry points whose algorithm is Omega (om/units.sh): omc born from the seed here,
                      # the generator pinned by om/omega-bridge.lock; regenerated binding, SHA-256 and BLAKE3
                      # byte parity against the C they replaced, and the BLAKE3 mutants. NOT_RUN (3) without tools.
                      # Then the program-mode om/blake3/blake3.om output contract (#726): digest, /dev/full, closed stdout.
    pin omega-bridge omega-bridge "$(lock om/omega-bridge.lock)"
    sh seed/omega-from-seed.sh > build/om-units-seed.log 2>&1 || { tail -3 build/om-units-seed.log; exit 1; }
    export OMEGA_OMC="$ROOT/seed/out/omc" OMEGA_BRIDGE="$PINS/omega-bridge"
    obs omc_sha256 "\"$(sha256sum < "$OMEGA_OMC" | cut -c1-64)\""
    sh om/units.sh --check
    sh om/sha256/parity/run.sh
    sh om/blake3/parity/run.sh
    "$OMEGA_OMC" < om/blake3/blake3.om > build/om-units-blake3 && chmod 700 build/om-units-blake3
    sh om/blake3/test-output.sh build/om-units-blake3
    ;;
  tilelab)            # omega#906: native .om tile planner and streaming (m,s,p) softmax. omc born from the seed
                      # here, then seed/tilelab/gate.sh (expected output, mutants failing for their own reason).
    sh seed/omega-from-seed.sh > build/tilelab-seed.log 2>&1 || { tail -3 build/tilelab-seed.log; exit 1; }
    obs omc_sha256 "\"$(sha256sum < seed/out/omc | cut -c1-64)\""
    sh seed/tilelab/gate.sh
    ;;
  trace)              # omega#608: local trace segment (seed/trace/segment.om), built by the committed seed/out/omc
                      # after its recorded SHA-256 is checked: 71 checks against expected.txt (torn-tail recovery
                      # keeps N-1 records, CRC/length/sequence damage, header refusals, O_EXCL, O_NOFOLLOW) and
                      # 4 source mutants (CRC check, torn tail, alignment, O_EXCL) that must each fail their check.
    sha256sum -c seed/out/omc.sha256
    obs omc_sha256 "\"$(sha256sum < seed/out/omc | cut -c1-64)\""
    sh seed/trace/gate.sh
    ;;
  tracecli)           # omega#610: offline read-only trace CLI (seed/trace/tracecli.om), built by the
                      # committed seed/out/omc after its recorded SHA-256 is checked. Golden stdout and
                      # exit codes, a mode-0000 refusal, and 4 source mutants (partial exit, compare
                      # equality, type filter, read-only open flags) that must each fail their own check.
    sha256sum -c seed/out/omc.sha256
    obs omc_sha256 "\"$(sha256sum < seed/out/omc | cut -c1-64)\""
    sh seed/trace/cli-gate.sh
    ;;
  security758)        # omega#758 (#774): relational comparison suite under seed/qualification/security673/relational,
                      # run by the OM-2 case gate rebuilt from seed/qualification/om2/gate.om with the committed
                      # seed/out/omc (sha checked) and the scanner seed/qualification/om2/leak/leakscan.om. Exits
                      # 0/0/0 for qualification/bindings/consumer, 1 with exactly the two intended FAIL rows for
                      # binding-negative; the L4 secret-dividend scanner PASS is a separate tripwire, not a total.
    sha256sum -c seed/out/omc.sha256
    OMC=seed/out/omc; H="$(cut -c1-64 seed/out/omc.sha256)"
    obs omc_sha256 "\"$H\""
    R=seed/qualification/security673/relational
    sec="$OUT_DIR/security758"; rm -rf "$sec"; mkdir -p "$sec"
    "$OMC" < seed/qualification/om2/gate.om > "$sec/gate.bin"; chmod 700 "$sec/gate.bin"
    obs gate_sha256 "\"$(sha256sum < "$sec/gate.bin" | cut -c1-64)\""
    sec_run() { local rc=0; "$sec/gate.bin" "$OMC" "$H" "$R/$1.cases" "$sec/$1" > "$sec/$1.log" 2>&1 || rc=$?
      tail -1 "$sec/$1.log"; [ "$rc" = "$2" ] || { echo "SECURITY758 FAIL $1.cases exit=$rc expected=$2" >&2; exit 1; }; }
    sec_run qualification 0; sec_run bindings 0; sec_run consumer 0; sec_run binding-negative 1
    grep -qx 'OM2GATE FAIL cases=2 pass=0 fail=2 invalid=0 not_run=0' "$sec/binding-negative.log"
    grep -q '^VERDICT wrong-source-bytes FAIL ' "$sec/binding-negative.log"
    grep -q '^VERDICT wrong-checker-bytes FAIL ' "$sec/binding-negative.log"
    echo "SECURITY758 PASS qualification consumer bindings, binding-negative 2 intended FAIL rows"
    sec_run l4-tripwire 0
    echo "SECURITY758 TRIPWIRE L4-division-gap: scanner still PASSES a secret dividend (known false negative, README L4; not a qualification)"
    ;;
  native)             # omega#663/#664: native .om units built by the committed seed/out/omc after its recorded
                      # SHA-256 is checked. The metadata test must pass and each recorded ECOSYSTEM663 mutant must
                      # exit 1; with native/autodiff664 present, its tape suite (test + 3 compiled mutants) and the
                      # C M21 fixture replay (CPU table, value-exact, mutant-sign control must FAIL) run too.
    sha256sum -c seed/out/omc.sha256
    OMC="$ROOT/seed/out/omc"
    obs omc_sha256 "\"$(sha256sum < "$OMC" | cut -c1-64)\""
    nat="$OUT_DIR/native"; rm -rf "$nat"; mkdir -p "$nat"
    native_build() { "$OMC" < "$1" > "$2" && [ "$(od -An -tx1 -N4 "$2" | tr -d ' ')" = 7f454c46 ] && chmod 700 "$2"; }
    cat native/ecosystem663/metadata.om tests/ecosystem663/metadata-test.om > "$nat/metadata-test.om"
    native_build "$nat/metadata-test.om" "$nat/metadata-test.elf"
    "$nat/metadata-test.elf" > "$nat/metadata-test.stdout"
    grep "^M20_METADATA_V1_PASS checks=" "$nat/metadata-test.stdout"
    for m in evidence/ECOSYSTEM663/mutant-*.om; do
      native_build "$m" "$nat/mutant.elf"
      rc=0; "$nat/mutant.elf" > /dev/null 2>&1 || rc=$?
      [ "$rc" = 1 ] || { echo "run.sh: $m was not rejected (exit $rc, need 1)" >&2; exit 1; }
      echo "mutant $m: exit 1 as required"
    done
    if [ -d native/autodiff664 ]; then
      OMC="$OMC" OUT="$ROOT/$nat/tape" sh tests/autodiff664/run-tape.sh
      make $NOPHYS test-autodiff-fixture FIXTURE=tests/fixtures/autodiff664/adtrain.fix
    fi
    ;;
  trinary)            # T-002 trit/codebook signal tools (tools/trit, tools/codebook), host only, no device. Built by the
                      # committed seed/out/omc after its recorded SHA-256 is checked (the compiler is not retyped here).
                      # Builds both binaries, runs both fixture suites (a SKIP is not a pass), the codebook mutant list,
                      # the regression for the trit mutation driver itself, the trit mutation driver (every mutant applied,
                      # built and killed by test.sh; difftest kills the read-mode ones), the Lean differential of trit.bin
                      # against TritSignal.lean, and the existing Lean proofs (compilation and reported theorem axioms).
                      # Needs python3, perl, strace, lean, cmp and timeout: without them NOT_RUN (exit 3).
    sha256sum -c seed/out/omc.sha256
    OMC="$ROOT/seed/out/omc"; export OMC
    obs omc_sha256 "\"$(sha256sum < "$OMC" | cut -c1-64)\""
    for t in python3 perl lean strace cmp timeout; do
      command -v "$t" >/dev/null 2>&1 || { echo "run.sh: trinary NOT_RUN: $t is not installed" >&2; exit 3; }
    done
    tri=$(mktemp -d "$OUT_DIR/trinary.XXXXXX")
    export TMPDIR="$ROOT/$tri"
    obs lean_version "\"$(lean --version)\""
    obs python_version "\"$(python3 --version)\""
    obs perl_version "\"$(perl -e 'printf "%vd", $^V')\""
    obs strace_version "\"$(strace --version | head -n 1)\""
    B="$tri/codebook" sh tools/codebook/build.sh > "$tri/build-codebook.log"
    B="$tri/trit" sh tools/trit/build.sh > "$tri/build-trit.log"
    obs trit_binary_sha256 "\"$(sha256sum < "$tri/trit/trit" | cut -c1-64)\""
    obs codebook_binary_sha256 "\"$(sha256sum < "$tri/codebook/codebook" | cut -c1-64)\""
    tri_suite() { # name, then the command: its own TOTAL line must show fail=0 skip=0
      local name="$1" rc=0 tot; shift
      "$@" > "$tri/$name.log" 2>&1 || rc=$?
      tot="$(grep -E '^TOTAL pass=[0-9]+ fail=[0-9]+ skip=[0-9]+$' "$tri/$name.log" | tail -n 1 || true)"
      echo "trinary $name: exit $rc, $tot (log $tri/$name.log, sha256 $(sha256sum < "$tri/$name.log" | cut -c1-64))"
      [ "$rc" = 0 ] && [ -n "$tot" ] || { echo "run.sh: trinary $name FAIL (exit $rc)" >&2; tail -n 20 "$tri/$name.log" >&2; exit 1; }
      case "$tot" in *"fail=0 skip=0") ;; *) echo "run.sh: trinary $name: $tot is not fail=0 skip=0" >&2; exit 1 ;; esac
    }
    tri_suite codebook-test env BIN="$ROOT/$tri/codebook/codebook" FIX="$ROOT/$tri/fix-codebook" sh tools/codebook/test.sh
    tri_suite trit-test env BIN="$ROOT/$tri/trit/trit" CBIN="$ROOT/$tri/codebook/codebook" FIX="$ROOT/$tri/fix-trit" sh tools/trit/test.sh
    BIN="$ROOT/$tri/trit/trit" python3 tools/trit/test-daily.py > "$tri/daily.log" 2>&1 || { cat "$tri/daily.log" >&2; exit 1; }
    tail -n 1 "$tri/daily.log"
    COMPOSED="$ROOT/$tri/trit/trit.full.om" python3 tools/trit/mutate-daily.py > "$tri/daily-mutations.log" 2>&1 || { cat "$tri/daily-mutations.log" >&2; exit 1; }
    tail -n 1 "$tri/daily-mutations.log"
    sh tools/codebook/test-mutate.sh > "$tri/codebook-driver.log" 2>&1 || { cat "$tri/codebook-driver.log" >&2; exit 1; }
    tail -n 1 "$tri/codebook-driver.log"
    M="$ROOT/$tri/codebook-mutants" sh tools/codebook/mutate.sh > "$tri/codebook-mutate.log" 2>&1 || { echo "run.sh: trinary codebook mutate FAIL" >&2; tail -n 20 "$tri/codebook-mutate.log" >&2; exit 1; }
    tail -n 1 "$tri/codebook-mutate.log"
    W="$ROOT/$tri/driver-regression" sh tools/trit/test-mutate.sh > "$tri/test-mutate.log" 2>&1 || { echo "run.sh: trinary mutation-driver regression FAIL" >&2; tail -n 20 "$tri/test-mutate.log" >&2; exit 1; }
    tail -n 1 "$tri/test-mutate.log"
    W="$ROOT/$tri/mutants" sh tools/trit/mutate.sh > "$tri/trit-mutate.log" 2>&1 || { echo "run.sh: trinary trit mutate FAIL" >&2; tail -n 25 "$tri/trit-mutate.log" >&2; exit 1; }
    grep -E '^(MUTANTS|mutate.sh: PASS)' "$tri/trit-mutate.log"
    mline="$(grep '^MUTANTS ' "$tri/trit-mutate.log")"; mn="${mline#MUTANTS }"; mn="${mn%% *}"; mk="${mline#*killed-by-test.sh=}"; mk="${mk%% *}"
    [ "$mn" -ge 1 ] && [ "$mk" = "$mn" ] && printf '%s\n' "$mline" | grep -qE 'survived=0 invalid=0 harness-errors=0$' || { echo "run.sh: trinary mutants: killed-by-test.sh=$mk of $mn, or a survivor/invalid/harness error: $mline" >&2; exit 1; }
    BIN="$ROOT/$tri/trit/trit" N=600 SEED=1 W="$ROOT/$tri/diff" sh tools/trit/proof/difftest.sh > "$tri/difftest.log" 2>&1 || { echo "run.sh: trinary difftest FAIL" >&2; tail -n 20 "$tri/difftest.log" >&2; exit 1; }
    grep -E '^DIFF agree=600/600 ' "$tri/difftest.log"
    # CodebookProof.lean prints no axioms itself: check a copy of it with one `#print axioms Codebook.<name>` appended per top-level theorem.
    { cat tools/codebook/proof/CodebookProof.lean; sed -n "s/^theorem \([^ ]*\) .*/#print axioms Codebook.\1/p" tools/codebook/proof/CodebookProof.lean; } > "$tri/CodebookAxioms.lean"
    lean "$tri/CodebookAxioms.lean" > "$tri/lean-codebook.log" 2>&1 || { echo "run.sh: trinary CodebookProof.lean FAIL" >&2; head -n 20 "$tri/lean-codebook.log" >&2; exit 1; }
    ( cd tools/trit/proof && lean TritSignal.lean ) > "$tri/lean-trit.log" 2>&1 || { echo "run.sh: trinary TritSignal.lean FAIL" >&2; head -n 20 "$tri/lean-trit.log" >&2; exit 1; }
    if grep -q 'sorry\|error' "$tri/lean-codebook.log" "$tri/lean-trit.log"; then echo "run.sh: trinary Lean output mentions sorry or error" >&2; exit 1; fi
    cbthm="$(grep -c '^theorem ' tools/codebook/proof/CodebookProof.lean || true)"
    for lf in codebook trit; do
      nax="$(grep -c "depends on axioms\|does not depend on any axioms" "$tri/lean-$lf.log" || true)"
      badax="$(grep "depends on axioms" "$tri/lean-$lf.log" | sed 's/.*\[\(.*\)\]/\1/' | tr ',' '\n' | tr -d ' ' | grep -v '^propext$\|^Classical.choice$\|^Quot.sound$' | sort -u | tr '\n' ' ' || true)"
      [ "$nax" -ge 1 ] && [ -z "$badax" ] || { echo "run.sh: trinary $lf axioms: $nax lines, non-standard '$badax'" >&2; exit 1; }
      echo "trinary lean $lf: $nax axiom lines, standard axioms only"
      [ "$lf" != codebook ] || [ "$nax" = "$cbthm" ] || { echo "run.sh: trinary CodebookProof.lean: $nax axiom lines for $cbthm theorems" >&2; exit 1; }
    done
    find "$tri" -maxdepth 1 -type f -name "*.log" -print0 | sort -z | xargs -0 sha256sum > "$tri/LOGS.sha256"
    cat "$tri/LOGS.sha256"
    echo "TRINARY PASS"
    ;;
  *) echo "run.sh: unknown step '$step'" >&2; exit 2 ;;
esac
