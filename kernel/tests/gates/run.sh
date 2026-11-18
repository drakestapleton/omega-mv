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

# tests/gates/run.sh: the one entry point for the local verification gates of aienos.
# Every step runs the SAME command as the hosted job it replaced. #427 removed those workflows
# (ck-kernel.yml, native-suites.yml, crypto-boundary.yml, infer-crate.yml, crumb.yml, ci.yml). The
# only hosted run left is the portable smoke set in the advisory AIEN Checks job
# (aien-verification.yml); the workflow names below say where each command came from.
# Manifests under tests/gates/ name this script plus one step word, so no manifest needs shell
# expansion (ADR 0028 P6).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
step="${1:?usage: tests/gates/run.sh <step>}"
obs() { printf 'AIEN-OBS %s %s\n' "$1" "$2"; }

# The removed hosted jobs kept the quiet flag and the QEMU gate lock in the runner's temp dir,
# never in ~/workspace (ck-kernel.yml, native-suites.yml). Same here.
TMP="$(mktemp -d /tmp/aienos-gate.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
export AIENOS_QUIET_FLAG="$TMP/spark-quiet"
export AIENOS_GATE_LOCK="$TMP/qemu-gate-lock"

# native-suites.yml: make must succeed AND every suite must print its own pass marker, and
# never NOT_RUN. $1 = suite dir, $2 = make targets, $3 = required marker regexes joined by |.
native_suite() {
  local suite="$1" targets="$2" req="$3" log="$TMP/suite.log" found=0
  set -o pipefail
  # native/crypto has no .gitignore for its out/ (the other suites do), so the build output
  # would stay in the tree; the hosted job throws its checkout away. Remove an out/ that this
  # step created, and only when git does not already ignore it. The gate itself is unchanged.
  if [ ! -e "native/$suite/out" ] && ! git check-ignore -q "native/$suite/out"; then
    CLEAN_OUT="$ROOT/native/$suite/out"
    trap 'rm -rf "$TMP" "$CLEAN_OUT"' EXIT
  fi
  # shellcheck disable=SC2086
  make -C "native/$suite" $targets 2>&1 | tee "$log"
  while IFS= read -r m; do
    grep -qE "$m" "$log" || { echo "missing marker: $m"; obs markers_missing 1; exit 1; }
    echo "found: $m"; found=$((found + 1))
  done < <(printf '%s\n' "$req" | tr '|' '\n')
  if grep -q 'NOT_RUN' "$log"; then echo 'NOT_RUN in log'; obs not_run_in_log true; exit 1; fi
  obs markers_found "$found"
  obs not_run_in_log false
}

# One test script inside a step. It counts only when it exits 0 AND prints every required line
# whole (several print NOT_RUN and exit 0, 2 or 3; that is never a pass). Each failure is
# counted in $script_fail so the step runs every script and fails at the end.
# Usage: must_pass NAME LINE_REGEX... -- COMMAND...
script_pass=0
script_fail=0
must_pass() {
  local name="$1" log rc=0 r req=()
  shift
  while [ "$1" != -- ]; do req+=("$1"); shift; done
  shift
  log="$TMP/script-$name.log"
  echo "== $name: $*"
  "$@" 2>&1 | tee "$log" || rc=$?
  if [ "$rc" != 0 ]; then
    echo "script $name: exit $rc, not PASS"; script_fail=$((script_fail + 1)); return 0
  fi
  for r in "${req[@]}"; do
    if ! grep -aqxE -- "$r" "$log"; then
      echo "script $name: no line matching '$r', not PASS"; script_fail=$((script_fail + 1)); return 0
    fi
  done
  echo "script $name: PASS"; script_pass=$((script_pass + 1))
}
scripts_verdict() {
  obs scripts_pass "$script_pass"
  obs scripts_fail "$script_fail"
  [ "$script_fail" = 0 ]
}

# omega_omc: make AIEN_OMC omega-mv's own committed seeded compiler. Aienux is folded into omega-mv
# as kernel/ (Drake 2026-11-17), so the kernel's compiler pin is omega-mv's: seed/out/omc at the
# omega-mv root, whose sha256 is the first field of seed/out/omc.sha256 there (the file the
# omega-mv gates check). AIEN_OMC wins when it has that hash; otherwise seed/out/omc is used when it
# has it. Neither: exit 3, never a pass. native/disk, native/net/tcp and tools/hwgates read the
# same file, so moving omega-mv's compiler moves all three.
OMEGA_ROOT="$(cd "$ROOT/.." && pwd)"
omega_omc() {
  local ps h=""
  ps=$(cut -c1-64 "$OMEGA_ROOT/seed/out/omc.sha256" 2>/dev/null | head -n 1)
  if ! printf '%s\n' "$ps" | grep -qxE '[0-9a-f]{64}'; then
    echo "run.sh: no sha256 in $OMEGA_ROOT/seed/out/omc.sha256 (run from kernel/ inside an omega-mv checkout)" >&2
    obs omc_pinned false
    exit 3
  fi
  if [ -n "${AIEN_OMC:-}" ] && [ -r "$AIEN_OMC" ]; then h=$(sha256sum "$AIEN_OMC" | cut -d' ' -f1); fi
  if [ "$h" != "$ps" ] && [ -r "$OMEGA_ROOT/seed/out/omc" ]; then
    export AIEN_OMC="$OMEGA_ROOT/seed/out/omc"
    h=$(sha256sum "$AIEN_OMC" | cut -d' ' -f1)
  fi
  if [ "$h" != "$ps" ]; then
    echo "run.sh: no omc with sha256 $ps (omega-mv seed/out/omc.sha256; set AIEN_OMC or build seed/out/omc)" >&2
    obs omc_pinned false
    exit 3
  fi
  obs omc_sha256 "\"$ps\""
  obs omc_pinned true
}
# pin_controls: every place the kernel checks a compiler against omega-mv's pin must reach its own
# check and refuse for the right reason (review of aienux 1f12818d finding 12, and of omega-mv
# c9e503afd finding 10: every control tree had no compiler, so a script refused "compiler missing"
# before its compare, and deleting the compare passed). omega_omc runs with AIEN_OMC unset, and each
# script in PIN_SCRIPTS from a copy in a tree, in six states. In every state but missing-compiler the
# tree has a stand-in compiler (a script that records that it ran, then fails):
#   missing, empty, short   pin file absent, empty, not 64 hex digits: refused with "no sha256";
#   missing-compiler        a good pin, no compiler: refused with "no compiler at" or "pinned compiler
#                           missing" (omega_omc: "no omc with sha256");
#   wrong-compiler          a good pin and the stand-in, whose sha256 differs: refused with "compiler pin
#                           mismatch" (omega_omc: "no omc with sha256"), so the compare itself refuses;
#   matching                the pin is the stand-in's sha256: no pin refusal at all (omega_omc accepts),
#                           so the compare accepts an equal digest and refuses only an unequal one.
# A refusing state also needs exit non-zero, no output file and a stand-in that never ran. Output is
# matched with here-strings: with pipefail, `printf | grep -q` fails when grep exits before printf ends.
PIN_SCRIPTS="native/om/lm1b/gate.sh native/omega/allen/build-fw.sh native/omega/allen/build-one.sh
  native/omega/allen/build-local-model.sh scripts/check_local_tools.sh native/disk/tests/omega_nvme_test.sh"
pin_controls() {
  local c d s out rc sh_ args n=0 want owant
  for c in missing empty short missing-compiler wrong-compiler matching; do
    d="$TMP/pin-control-$c"; mkdir -p "$d/seed/out"
    if [ "$c" != missing-compiler ]; then
      printf '#!/bin/sh\necho ran >> "%s/RAN"\nexit 97\n' "$d" > "$d/seed/out/omc"; chmod +x "$d/seed/out/omc"
    fi
    case "$c" in
      missing) want='compiler pin refused: no sha256'; owant='no sha256 in' ;;
      empty) : > "$d/seed/out/omc.sha256"; want='compiler pin refused: no sha256'; owant='no sha256 in' ;;
      short) printf 'abc  seed/out/omc\n' > "$d/seed/out/omc.sha256"; want='compiler pin refused: no sha256'; owant='no sha256 in' ;;
      missing-compiler) cp "$OMEGA_ROOT/seed/out/omc.sha256" "$d/seed/out/omc.sha256"
        want='no compiler at|pinned compiler missing'; owant='no omc with sha256' ;;
      wrong-compiler) cp "$OMEGA_ROOT/seed/out/omc.sha256" "$d/seed/out/omc.sha256"
        want='compiler pin mismatch'; owant='no omc with sha256' ;;
      matching) (cd "$d" && sha256sum seed/out/omc > seed/out/omc.sha256); want=; owant= ;;
    esac
    rc=0; out=$(OMEGA_ROOT="$d"; unset AIEN_OMC; omega_omc 2>&1) || rc=$?
    if [ -n "$owant" ]; then
      if [ "$rc" != 3 ] || grep -q 'omc_pinned true' <<< "$out" || ! grep -q "$owant" <<< "$out"; then
        printf '%s\n' "$out"; echo "pin control $c: omega_omc exit $rc, not refused with '$owant'" >&2; exit 1
      fi
    elif [ "$rc" != 0 ] || ! grep -q 'omc_pinned true' <<< "$out"; then
      printf '%s\n' "$out"; echo "pin control $c: omega_omc exit $rc, refused a compiler equal to the pin" >&2; exit 1
    fi
    n=$((n + 1))
    for s in $PIN_SCRIPTS; do
      rm -rf "$d/RAN" "$d/out.efi" "$d/out.bin" "$d/out.tools"
      mkdir -p "$d/kernel/$(dirname "$s")"; cp "$s" "$d/kernel/$s"
      case "$s" in
        */build-fw.sh) args="$d/out.efi" ;;
        */build-one.sh) args="$d/kernel/none.om $d/out.bin" ;;
        */build-local-model.sh) args="$d/train $d/out.efi" ;;
        *) args= ;;
      esac
      case "$(head -n 1 "$s")" in *bash*) sh_=bash ;; *) sh_=sh ;; esac
      # shellcheck disable=SC2086
      rc=0; out=$(cd "$d" && env -u OMEGA_COMPILER -u OMC -u OMEGA_SOURCE AIEN_OMC="$d/seed/out/omc" \
        MODEL="$d/no-model" LOCAL_TOOLS_OUT="$d/out.tools" OMEGA_NVME_EVIDENCE="$d/nvme-evidence" "$sh_" "$d/kernel/$s" $args 2>&1) || rc=$?
      if [ -n "$want" ]; then
        if [ "$rc" != 0 ] && grep -qE "$want" <<< "$out" && [ ! -e "$d/RAN" ] &&
          [ ! -e "$d/out.efi" ] && [ ! -e "$d/out.bin" ] && [ ! -e "$d/out.tools" ]; then
          n=$((n + 1))
        else
          printf '%s\n' "$out"; [ -e "$d/RAN" ] && echo "(the stand-in compiler ran)"
          echo "pin control $c: $s exit $rc, not refused with '$want' before running the compiler" >&2; exit 1
        fi
      elif grep -qE 'compiler pin|pinned compiler missing|no compiler at|digest differs' <<< "$out"; then
        printf '%s\n' "$out"; echo "pin control $c: $s refused a compiler equal to the pin" >&2; exit 1
      else
        n=$((n + 1))
      fi
    done
  done
  # OMEGA_SOURCE (scripts/check_local_tools.sh) names where the compiler is, never the pin: a
  # compiler with its own matching omc.sha256 beside it, with none, or reached by a symlink must be
  # refused (review of omega-mv c9e503afd, finding 12).
  for c in own-pin no-pin symlink; do
    d="$TMP/pin-control-source-$c"; mkdir -p "$d/kernel/scripts" "$d/seed/out" "$d/src/seed/out"
    cp "$OMEGA_ROOT/seed/out/omc.sha256" "$d/seed/out/omc.sha256"
    cp scripts/check_local_tools.sh "$d/kernel/scripts/check_local_tools.sh"
    printf '#!/bin/sh\ncat\n' > "$d/fake-omc"; chmod +x "$d/fake-omc"
    case "$c" in symlink) ln -s "$d/fake-omc" "$d/src/seed/out/omc" ;; *) cp "$d/fake-omc" "$d/src/seed/out/omc" ;; esac
    [ "$c" = no-pin ] || (cd "$d/src" && sha256sum seed/out/omc > seed/out/omc.sha256)
    rc=0; out=$(cd "$d" && env -u OMEGA_COMPILER -u OMC -u AIEN_OMC OMEGA_SOURCE="$d/src" LOCAL_TOOLS_OUT="$d/out.tools" \
      bash "$d/kernel/scripts/check_local_tools.sh" 2>&1) || rc=$?
    if [ "$rc" != 0 ] && grep -q 'compiler pin refused' <<< "$out" && [ ! -e "$d/out.tools" ]; then
      n=$((n + 1))
    else
      printf '%s\n' "$out"; echo "pin control source-$c: check_local_tools.sh exit $rc, ran the compiler OMEGA_SOURCE named" >&2; exit 1
    fi
  done
  echo "pin controls: $n results as required (omega_omc and $(echo $PIN_SCRIPTS | wc -w) scripts in 6 pin states, 3 OMEGA_SOURCE states)"
  obs pin_controls_refused "$n"
}

case "$step" in
  # crumb-verify (gate CRUMB-VERIFY) is retired (DRA-97, 2026-11-07): Crumbs are off the active
  # workflow, so no gate checks crumb freshness. The .crumb files and crumb.lock stay as history.
  # ck-kernel.yml, host steps (ubuntu-24.04-arm there, AArch64 here)
  ck-host-tests)
    make -C native/kernel test sanitize
    bash scripts/ck_swap_disk_bound_test.sh
    bash scripts/ck_imac_lab_services_test.sh
    bash scripts/check_local_model.sh --self-test
    # Host-only kernel regressions (no QEMU machine, no model server, no network beyond loopback
    # and a private namespace). ck_courier_udp_frame needs sudo -n for unshare --net.
    must_pass fat_boot 'AIENOS_FAT_BOOT: PASS' -- bash scripts/ck_fat_boot_test.sh
    must_pass allen_memory 'AIENOS_ALLEN_MEMORY: PASS' -- bash scripts/ck_allen_memory_test.sh
    must_pass allen_canvas 'AIENOS_ALLEN_CANVAS: PASS' -- bash scripts/ck_allen_canvas_test.sh
    must_pass allen_code 'AIENOS_ALLEN_CODE: PASS' -- bash scripts/ck_allen_code_test.sh
    must_pass allen_ui 'AIENOS_ALLEN_UI: PASS' -- bash scripts/ck_allen_ui_test.sh
    must_pass boot_show 'AIENOS_BOOT_SHOW: PASS' -- bash scripts/ck_boot_show_test.sh
    must_pass courier_udp_frame 'COURIER_FRAMES: PASS .*' \
      'COURIER_FRAME_ACK_CONTROL: PASS withholding GOT triggers real LINE retransmission' \
      -- env -u KEEP_LOGS bash scripts/ck_courier_udp_frame_test.sh
    must_pass courier_udp 'AIENOS_COURIER_UDP: PASS' -- env -u ALLEN_MODEL bash scripts/ck_courier_udp_test.sh
    must_pass imac_bsdp 'AIENOS_IMAC_BSDP: PASS' -- bash scripts/ck_imac_bsdp_test.sh
    must_pass imac_report 'AIENOS_IMAC_REPORT: PASS' -- bash scripts/ck_imac_report_test.sh
    must_pass imac_security 'AIENOS_IMAC_SECURITY: PASS' -- bash scripts/ck_imac_security_test.sh
    must_pass setup_wizard 'AIENOS_SETUP_WIZARD: PASS' -- bash scripts/ck_setup_wizard_test.sh
    must_pass sky 'AIENOS_SKY: PASS' -- bash scripts/ck_sky_test.sh
    must_pass sky_sharpness 'AIENOS_SKY_SHARPNESS: PASS' -- bash scripts/ck_sky_sharpness_test.sh
    must_pass virtio_av 'AIENOS_VIRTIO_AV: PASS' -- bash scripts/ck_virtio_av_test.sh
    must_pass mind_phases 'AIENOS_MIND_PHASES: PASS' -- sh scripts/ck_mind_phases_test.sh "$TMP/mind-phases"
    scripts_verdict
    ;;
  ck-stage-tests)     make -C native/kernel stage-test stage-sanitize ;;
  ck-gate-selftest)   bash scripts/ck_gates.sh --self-test ;;
  ck-hold-selftest)   bash scripts/gate_hold_selftest.sh ;;
  ck-owner-keys)      bash scripts/ck_owner_keys_check.sh ;;
  # ck-kernel.yml, QEMU TCG gates: every gate with a C implementation except FPU and INFER
  ck-qemu-gates)
    mkdir -p "$TMP/ck-receipt"
    set +e
    bash scripts/ck_gates.sh --out "$TMP/ck-receipt" | tee "$TMP/ck-gates.txt"
    rc=${PIPESTATUS[0]}
    set -e
    echo "ck_gates.sh exit ${rc}"
    [ "${rc}" = 0 ] || exit 1
    required=$(sed -n "/^CK_GATE_TABLE='/,/^'/p" scripts/ck_gates.sh | awk -F'|' 'NF==3 && $2!="missing" && $1!="FPU" && $1!="INFER" {print $1}')
    [ -n "${required}" ] || { echo "could not read the gate table"; exit 1; }
    fail=0; n=0
    for g in ${required}; do
      if grep -q "^AIENOS_CK_${g}: PASS" "$TMP/ck-gates.txt"; then echo "required gate ${g}: PASS"; n=$((n + 1))
      else echo "required gate ${g}: not PASS"; fail=1; fi
    done
    obs required_gates_pass "$n"
    # Self-contained QEMU tests of the iMac kernel: no model server (allen_code replays its
    # recorded replies), no hardware; gpu_bench's BARs are RAM stand-ins. Each takes the gate lock.
    must_pass allen_memory_qemu 'AIENOS_ALLEN_MEMORY_QEMU: PASS' -- bash scripts/qemu_ck_allen_memory_test.sh
    must_pass imac_bootdisk 'AIENOS_IMAC_BOOTDISK: PASS' -- bash scripts/qemu_ck_imac_bootdisk_test.sh
    must_pass imac_swap 'AIENOS_IMAC_SWAP: PASS' -- bash scripts/qemu_ck_imac_swap_test.sh
    must_pass imac_kernel 'AIENOS_IMAC_KERNEL: PASS' -- env AIENOS_IMAC_DMAR=0 bash scripts/qemu_ck_imac_kernel_test.sh
    must_pass imac_keyboard 'AIENOS_IMAC_KEYBOARD: PASS' -- bash scripts/qemu_ck_imac_keyboard_test.sh
    must_pass boot_show_qemu 'AIENOS_CK_BOOT_SHOW: PASS' -- bash scripts/qemu_ck_boot_show_test.sh aarch64 tcg
    must_pass gpu_bench 'AIENOS_GPU_BENCH: PASS' -- bash scripts/qemu_ck_gpu_bench_test.sh
    must_pass local_tools 'LOCAL_TOOLS: PASS cpu=qemu64' 'LOCAL_TOOLS: PASS cpu=max' \
      -- env LOCAL_TOOLS_OUT="$TMP/local-tools" bash scripts/qemu_ck_local_tools_test.sh
    must_pass allen_code_qemu 'AIENOS_ALLEN_CODE_QEMU: PASS' -- env ALLEN_CODE_LIVE=0 bash scripts/qemu_ck_allen_code_test.sh
    scripts_verdict || fail=1
    exit ${fail}
    ;;
  # Not hosted: QEMU tests that need outside inputs. A missing input is a FAIL, never a pass.
  #   ALLEN_MODEL            host:port of an OpenAI-shape model server answering /health
  #                          (allen_courier, allen_wizard); no default, so the shared server
  #                          is only ever used when the operator names it
  #   LOCAL_MODEL_WEIGHTS    pinned stories15M.bin (local_model checks its sha256)
  #   LOCAL_MODEL_TOKENIZER  pinned tokenizer.bin
  ck-qemu-external)
    missing=0
    for v in ALLEN_MODEL LOCAL_MODEL_WEIGHTS LOCAL_MODEL_TOKENIZER; do
      if [ -z "${!v:-}" ]; then echo "::error::ck-qemu-external needs $v" >&2; missing=$((missing + 1)); fi
    done
    for v in LOCAL_MODEL_WEIGHTS LOCAL_MODEL_TOKENIZER; do
      if [ -n "${!v:-}" ] && [ ! -r "${!v}" ]; then echo "::error::$v=${!v} is not a readable file" >&2; missing=$((missing + 1)); fi
    done
    obs inputs_missing "$missing"
    [ "$missing" = 0 ] || exit 1
    must_pass allen_courier 'AIENOS_ALLEN_COURIER: PASS' -- bash scripts/qemu_ck_allen_courier_test.sh
    must_pass allen_wizard 'AIENOS_ALLEN_WIZARD: PASS' -- bash scripts/qemu_ck_allen_wizard_test.sh
    must_pass local_model 'LOCAL_MODEL: PASS cpu=qemu64' 'LOCAL_MODEL: PASS cpu=max' \
      -- env -u LOCAL_MODEL_CPUS LOCAL_MODEL_OUT="$TMP/local-model" bash scripts/qemu_ck_local_model_test.sh
    scripts_verdict
    ;;
  ck-b7b-probe)
    bash scripts/qemu_ck_b7b_probe_test.sh --self-test
    bash scripts/qemu_ck_b7b_probe_test.sh
    bash scripts/qemu_ck_b7b_probe_test.sh --positive
    # #469 SMMU stream-ownership fault check: real out-of-window NVMe DMA must raise an event
    # with the decoded SID/address, the canary page stays intact, the recovery read succeeds.
    bash scripts/qemu_ck_b7b_probe_test.sh --events
    ;;
  # Hardware-gate register (docs/HARDWARE_GATES.md): fixtures, checker mutants, the register, its
  # receipts, a size alarm and planted-bad copies. Needs omega-mv's pinned seed/out/omc.
  hw-gates)
    pin_controls
    omega_omc
    sh tools/hwgates/gate.sh
    ;;
  # Bounded read-only NVMe protocol in seeded Omega (#472): host cases (with the slow case that holds
  # every command for half the engine's wait budget), guard mutants, the budget-cut and no-wait
  # mutants, disposable-QEMU cases and the killed-QEMU control; 48 cases, no ALARM line (an ALARM
  # fails the test). Physical NVMe stays NOT_RUN.
  omega-nvme)
    pin_controls
    omega_omc
    must_pass omega_nvme 'PASS Omega NVMe host \+ QEMU \+ guard, budget and wait mutants \+ QEMU death control; cases=48 alarms=0; physical NOT_RUN' \
      -- env OMEGA_NVME_EVIDENCE="$TMP/omega-nvme" sh native/disk/tests/omega_nvme_test.sh
    scripts_verdict
    ;;
  # Native TCP stack in seeded Omega (L232): native/net/tcp/gate.sh corpus mode (the hosted hostile
  # corpus, its exact-state cases and its mutants), built with omega-mv's pinned seed/out/omc. FUZZ is
  # set here to the pinned 2000000 frames (gate.sh refuses less), so the caller's environment cannot
  # lower it. PASS needs its TCP_CORPUS_GATE PASS line with fuzz=2000000, nonzero counts, killed equal
  # to mutants and gen_killed + survivors equal to generated; gate.sh exit 3 is NOT_RUN (exit 3 here),
  # never a pass. No QEMU; the QEMU profiles stay in gate.sh.
  tcp-corpus)
    pin_controls
    omega_omc
    rc=0; env FUZZ=2000000 sh native/net/tcp/gate.sh corpus "$AIEN_OMC" "$TMP/tcp" 2>&1 | tee "$TMP/tcp-corpus.log" || rc=$?
    if [ "$rc" = 3 ]; then echo "tcp-corpus: NOT_RUN (native/net/tcp/gate.sh exit 3)"; obs tcp_corpus_not_run true; exit 3; fi
    [ "$rc" = 0 ] || { echo "tcp-corpus: native/net/tcp/gate.sh exit $rc, not PASS"; exit 1; }
    line=$(grep -E '^TCP_CORPUS_GATE PASS checks=[1-9][0-9]* fuzz=2000000 groups=[1-9][0-9]* mutants=[1-9][0-9]* killed=[1-9][0-9]* generated=[0-9]+ gen_killed=[0-9]+ survivors=[0-9]+ controls=[1-9][0-9]*$' "$TMP/tcp-corpus.log" | tail -n 1 || true)
    [ -n "$line" ] || { echo "tcp-corpus: no 'TCP_CORPUS_GATE PASS checks= fuzz=2000000 groups= mutants= killed= generated= gen_killed= survivors= controls=' line, not PASS"; exit 1; }
    field() { local v="${line#* $1=}"; printf '%s\n' "${v%% *}"; }
    mutants=$(field mutants); killed=$(field killed); generated=$(field generated)
    gen_killed=$(field gen_killed); survivors=$(field survivors)
    [ "$killed" = "$mutants" ] || { echo "tcp-corpus: killed=$killed of mutants=$mutants, not PASS"; exit 1; }
    [ $((gen_killed + survivors)) = "$generated" ] || { echo "tcp-corpus: gen_killed=$gen_killed + survivors=$survivors != generated=$generated, not PASS"; exit 1; }
    obs tcp_corpus_fuzz 2000000
    obs tcp_corpus_groups "$(field groups)"
    obs tcp_corpus_mutants "$mutants"
    obs tcp_corpus_killed "$killed"
    echo "tcp-corpus: PASS ($line)"
    ;;
  # DRA-556 spinlock (core/spinlock.h): the compiled order of both lock forms and of every lock site
  # of core/pipe.c, with its dump mutants (make spinlock-asm-check: $(CROSS)gcc and $(CROSS)objdump for
  # aarch64, $(X86_CROSS)gcc and $(X86_CROSS)objdump for x86-64, default x86_64-linux-gnu-), and the Lean
  # model proofs/TicketLock.lean checked by proofs/check.sh (syntax allowlist, compile, leanchecker
  # kernel replay, axioms of every constant, pinned constants and statements), with its bad-proof
  # controls (make ticketlock-proof). lean is the elan toolchain proofs/lean-toolchain names; a shell
  # started by ssh has no ~/.elan/bin on PATH, so when lean is not on PATH this step adds
  # ${ELAN_HOME:-$HOME/.elan}/bin. No cross compiler, no lean, or a lean other than the pinned one:
  # NOT_RUN, exit 3, never a pass. The NOT_RUN paths are controls here too.
  spinlock)
    spin_fail=0; spin_notrun=0
    if ! command -v lean > /dev/null; then
      elan_bin="${ELAN_HOME:-$HOME/.elan}/bin"
      if [ -x "$elan_bin/lean" ]; then export PATH="$elan_bin:$PATH"; echo "spinlock: lean not on PATH, using $elan_bin"; fi
    fi
    spin_part() {  # spin_part NAME MAKE-TARGET PASS-LINE...: one target, counted as PASS, FAIL or NOT_RUN
      local name="$1" target="$2" r rc=0 log="$TMP/spin-$1.log"
      shift 2
      make -C native/kernel "$target" 2>&1 | tee "$log" || rc=$?
      if grep -qE '^CK_[A-Z_]+: NOT_RUN' "$log" && ! grep -qE '^CK_[A-Z_]+: (PASS|FAIL)$' "$log"; then
        echo "spinlock $name: NOT_RUN"; spin_notrun=$((spin_notrun + 1)); return 0
      fi
      [ "$rc" = 0 ] || { echo "spinlock $name: make $target exit $rc, not PASS"; spin_fail=$((spin_fail + 1)); return 0; }
      for r in "$@"; do
        grep -qx "$r" "$log" || { echo "spinlock $name: no line '$r', not PASS"; spin_fail=$((spin_fail + 1)); return 0; }
      done
      echo "spinlock $name: PASS"
    }
    spin_part asm spinlock-asm-check 'CK_SPINLOCK_ASM: PASS' 'CK_SPINLOCK_ASM_SELFTEST: PASS'
    spin_part proof ticketlock-proof 'CK_TICKETLOCK_PROOF: PASS' \
      'CK_TICKETLOCK_PROOF_SELFTEST: PASS (12 controls, 5 also with the syntax rule off)'
    # Controls of the NOT_RUN paths: no lean, a lean other than the pinned one, no x86 compiler.
    mkdir -p "$TMP/nolean" "$TMP/oldlean"
    for t in dirname realpath sed; do ln -sf "$(command -v "$t")" "$TMP/nolean/$t"; done
    printf '#!/bin/sh\necho "Lean (version 0.0.1, control)"\n' > "$TMP/oldlean/lean"; chmod +x "$TMP/oldlean/lean"
    for c in nolean:"$TMP/nolean" oldlean:"$TMP/oldlean:$TMP/nolean"; do
      rc=0; env PATH="${c#*:}" "$BASH" native/kernel/proofs/check.sh native/kernel/proofs/TicketLock.lean > "$TMP/spin-${c%%:*}.log" 2>&1 || rc=$?
      if [ "$rc" = 3 ] && grep -qE '^CK_TICKETLOCK_PROOF: NOT_RUN \(.+\)$' "$TMP/spin-${c%%:*}.log"; then
        echo "spinlock control ${c%%:*}: NOT_RUN exit 3 as required"
      else
        cat "$TMP/spin-${c%%:*}.log"; echo "spinlock control ${c%%:*}: exit $rc, not NOT_RUN"; spin_fail=$((spin_fail + 1))
      fi
    done
    rc=0; make -C native/kernel OUT="$TMP/spin-noxcc" X86_CROSS=/nonexistent/ spinlock-asm-check > "$TMP/spin-noxcc.log" 2>&1 || rc=$?
    if [ "$rc" != 0 ] && grep -qx 'CK_SPINLOCK_ASM: NOT_RUN (/nonexistent/gcc not installed)' "$TMP/spin-noxcc.log"; then
      echo "spinlock control no-x86-compiler: NOT_RUN as required"
    else
      cat "$TMP/spin-noxcc.log"; echo "spinlock control no-x86-compiler: exit $rc, not NOT_RUN"; spin_fail=$((spin_fail + 1))
    fi
    obs spinlock_failed "$spin_fail"
    obs spinlock_not_run "$spin_notrun"
    [ "$spin_fail" = 0 ] || { echo "AIENOS_SPINLOCK: FAIL"; exit 1; }
    [ "$spin_notrun" = 0 ] || { echo "AIENOS_SPINLOCK: NOT_RUN"; exit 3; }
    echo "AIENOS_SPINLOCK: PASS"
    ;;
  # native-suites.yml matrix
  native-net)        native_suite net "test sanitize mutants" 'AIENOS_NET_SECURE_TESTS: PASS|NET_SANITIZE: PASS|NET_SECURE_MUTANTS: [0-9]+/[0-9]+ killed' ;;
  native-sig)        native_suite sig "test sanitize mutants" 'AIENOS_SIG_NATIVE: PASS|AIENOS_SIG_MUTANTS: PASS' ;;
  native-crypto)     native_suite crypto "test sanitize mutants" 'AIENOS_CRYPTO_NATIVE: PASS|AIENOS_CRYPTO_MUTANTS: PASS' ;;
  native-m5)         native_suite m5 "test sanitize mutants" 'M5_NATIVE: PASS|M5_NATIVE_MUTANTS: PASS' ;;
  native-disk)       native_suite disk "test sanitize mutants" 'AIENOS_DISK_NATIVE: PASS|AIENOS_DISK_SANITIZE: PASS|AIENOS_DISK_MUTANTS: PASS' ;;
  native-argus)      native_suite argus "test sanitize" 'GATE CONTAIN_TEST PASS|GATE CONTAIN_DETERMINISM PASS' ;;
  native-capability) native_suite capability "mutants" 'AIENOS_CAP_MUTANTS: PASS' ;;
  disk-qemu)
    set -o pipefail
    bash scripts/qemu_native_nvme_test.sh 2>&1 | tee "$TMP/qemu.log"
    # The script exits 0 on NOT_RUN; only an explicit PASS counts.
    grep -qx 'AIENOS_STORE_NVME_QEMU: PASS' "$TMP/qemu.log"
    ;;
  # crypto-boundary.yml (one job, four commands)
  crypto-boundary)
    cargo test --locked --offline -p aienos-crypto
    cargo test --locked --offline -p aienos-kernel crypto::
    cargo clippy --locked --offline -p aienos-crypto --all-targets -- -D warnings
    cargo check --locked --offline -p aienos-kernel --target aarch64-unknown-none --no-default-features
    ;;
  # infer-crate.yml (one job: fmt, clippy, test, no_std build)
  infer-crate)
    export AIENOS_MODEL="${AIENOS_MODEL:-/nonexistent/no-model.gguf}"  # hosted runner has no model file; forward tests SKIP
    test -f crates/aienos-infer/Cargo.toml
    cargo fmt -p aienos-infer --check
    cargo clippy -p aienos-infer --all-targets -- -D warnings
    cargo test -p aienos-infer
    cargo build -p aienos-infer --target aarch64-unknown-none
    ;;
  # Not hosted (the hosted runner has no model file): the real Llama forward comparisons in
  # crates/aienos-infer/tests/forward.rs, release build. The sandbox finds the model at
  # $HOME/models (aien-run-exec bind-mounts the operator's ~/models read-only there).
  # A missing model or any SKIPPED line is a FAIL, never a silent pass.
  infer-forward)
    model="${AIENOS_MODEL:-$HOME/models/aien-mail/Llama-3.2-1B-Instruct-Q4_K_M.gguf}"
    if [ ! -f "$model" ]; then
      echo "::error::model file $model not present; infer-forward needs the real model" >&2
      obs model_present false
      exit 1
    fi
    obs model_present true
    export AIENOS_MODEL="$model"
    set -o pipefail
    cargo test --release -p aienos-infer --test forward 2>&1 | tee "$TMP/forward.log"
    if grep -q 'SKIPPED' "$TMP/forward.log"; then
      echo "::error::forward tests printed SKIPPED" >&2
      obs skipped_in_log true
      exit 1
    fi
    obs skipped_in_log false
    ;;
  # ci.yml (disabled on GitHub since the CK workflow took over): the suites it still names
  store-native)      make -C native/store test mutants ;;
  verify-all)
    export AIENOS_MODEL="${AIENOS_MODEL:-/nonexistent/no-model.gguf}"  # hosted parity: the debug workspace sweep skips forward tests (they run in infer-forward)
    bash scripts/verify_all.sh
    ;;
  zero-disk-secrets)
    echo "Auditing repository for prohibited plaintext secret files..."
    if find . -maxdepth 4 -name ".env*" -not -path "*/.git/*" -not -path "*/target/*" -not -path "*/vendor/*" | grep -q .; then
      echo "::error::Prohibited plaintext .env file found. Use an approved AIEN SecretProvider."
      obs env_files_found true
      exit 1
    fi
    obs env_files_found false
    echo "Zero plaintext .env files verified."
    ;;
  *)
    echo "run.sh: unknown step '$step'" >&2
    exit 2
    ;;
esac
