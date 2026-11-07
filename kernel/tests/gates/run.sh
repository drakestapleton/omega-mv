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

# The seeded Omega compiler native/disk pins (omega-mv 397e6704, sha256 bcfa5828...). AIEN_OMC
# wins when it has the pinned hash; otherwise the committed compiler at the pin is taken from
# the sibling checkout ../omega-mv (as crumb-verify takes its tool from ../aien-architecture).
# Neither available: exit 3, never a pass.
OMC_PIN_COMMIT=397e67040fb74853c6814097fe02ae4e1ebd6f66
OMC_PIN_SHA256=bcfa582892afca8f65e551fe56867d918d86e84540c7381be8fa9ef18d0cf0f6
pinned_omc() {
  local h=""
  if [ -n "${AIEN_OMC:-}" ] && [ -r "$AIEN_OMC" ]; then h=$(sha256sum "$AIEN_OMC" | cut -d' ' -f1); fi
  if [ "$h" != "$OMC_PIN_SHA256" ]; then
    if [ -d ../omega-mv ] && git -C ../omega-mv show "$OMC_PIN_COMMIT:seed/out/omc" > "$TMP/omc" 2>/dev/null; then
      chmod +x "$TMP/omc"; export AIEN_OMC="$TMP/omc"
      h=$(sha256sum "$AIEN_OMC" | cut -d' ' -f1)
    fi
  fi
  if [ "$h" != "$OMC_PIN_SHA256" ]; then
    echo "run.sh: no omc with sha256 $OMC_PIN_SHA256 (set AIEN_OMC, or check out aien-dev/omega-mv beside this tree)" >&2
    obs omc_pinned false
    exit 3
  fi
  obs omc_pinned true
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
  # Hardware-gate register (docs/HARDWARE_GATES.md): fixtures, checker mutants, the register and
  # two planted-bad copies. Needs the seeded compiler pinned by native/disk (omc bcfa5828).
  hw-gates)
    pinned_omc
    sh tools/hwgates/gate.sh
    ;;
  # Bounded read-only NVMe protocol in seeded Omega (#472): 37 host cases, 7 guard mutants,
  # 10 disposable-QEMU cases. Physical NVMe stays NOT_RUN.
  omega-nvme)
    pinned_omc
    must_pass omega_nvme 'PASS Omega NVMe host \+ QEMU \+ guard mutants; physical NOT_RUN' \
      -- env OMEGA_NVME_EVIDENCE="$TMP/omega-nvme" sh native/disk/tests/omega_nvme_test.sh
    scripts_verdict
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
