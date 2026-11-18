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

# test_trust1_swtpm_port.sh: control for scripts/swtpm_start.sh, the port choice of the software-TPM
# tests. A decoy swtpm holds a port pair, and scripts/test_trust1_measurement_tools.sh is started on it:
#   1. its data port taken: the test moves to another pair and passes;
#   2. its control port taken: the same;
#   3. one pair allowed (SWTPM_PORT_TRIES=1): the test fails, and does not run on the decoy;
#   4. mutant: swtpm_start.sh taking "the port answers" for "this swtpm listens" (the check before
#      2026-11-18) must run the test against the decoy, which this control sees in the decoy's PCR 7.
# After 1 to 3 the decoy's PCR 7 is unchanged: the test never extended a TPM it did not start.
# Exit 0 PASS, 1 FAIL, 2 tools missing.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tools="${repo_root}/scripts/test_trust1_measurement_tools.sh"

for t in swtpm tpm2_pcrread tpm2_pcrextend tpm2_eventlog xxd; do
    command -v "${t}" >/dev/null || { echo "Error: ${t} not installed" >&2; exit 2; }
done

work="$(mktemp -d)"
DECOY_PID=""
cleanup() {
    [[ -z "${DECOY_PID}" ]] || kill "${DECOY_PID}" 2>/dev/null || true
    rm -rf "${work}"
}
trap cleanup EXIT

fail() { echo "FAIL  $*"; exit 1; }
pass() { echo "PASS  $*"; }

# shellcheck source=swtpm_start.sh
source "${repo_root}/scripts/swtpm_start.sh"
swtpm_start "${work}/decoy" || fail "decoy swtpm did not start"
DECOY_PID=${SWTPM_PID}
dp=${SWTPM_PORT}
decoy_tcti=${TPM2TOOLS_TCTI}
unset TPM2TOOLS_TCTI SWTPM_PID SWTPM_PORT
decoy_pcr7() { TPM2TOOLS_TCTI="${decoy_tcti}" tpm2_pcrread sha256:7; }
before=$(decoy_pcr7) || fail "cannot read the decoy's PCR 7"

run_tools() { # NAME FIRST_PORT [ENV...]: run the self-test with the first port tried set
    local name=$1 first=$2
    shift 2
    set +e
    env SWTPM_FIRST_PORT="${first}" "$@" bash "${tools}" >"${work}/${name}.log" 2>&1
    rc=$?
    set -e
}

run_tools data "${dp}"
[[ ${rc} -eq 0 ]] || { cat "${work}/data.log"; fail "data port in use: exit ${rc}"; }
grep -q "port ${dp} or $((dp + 1)) is in use; trying another pair" "${work}/data.log" ||
    fail "data port in use: no retry line"
pass "data port ${dp} in use: another pair, exit 0"

run_tools ctrl $((dp - 1))
[[ ${rc} -eq 0 ]] || { cat "${work}/ctrl.log"; fail "control port in use: exit ${rc}"; }
grep -q "port $((dp - 1)) or ${dp} is in use; trying another pair" "${work}/ctrl.log" ||
    fail "control port in use: no retry line"
pass "control port ${dp} in use: another pair, exit 0"

run_tools onetry "${dp}" SWTPM_PORT_TRIES=1
[[ ${rc} -ne 0 ]] || fail "one pair allowed, and it is in use: exit 0"
! grep -q "ALL PASS" "${work}/onetry.log" || fail "one pair allowed: the self-test passed"
pass "one pair allowed, in use: exit ${rc}, nothing run"

[[ "$(decoy_pcr7)" == "${before}" ]] || fail "the decoy's PCR 7 changed: a test ran on a TPM it did not start"
pass "decoy PCR 7 unchanged"

# 4. mutant: a scripts folder whose swtpm_start.sh only asks whether the port answers
mut="${work}/mut/scripts"
mkdir -p "${mut}"
for f in "${repo_root}"/scripts/*; do ln -s "${f}" "${mut}/$(basename "${f}")"; done
rm "${mut}/swtpm_start.sh"
sed -e 's/^\( *\)kill -0 "${SWTPM_PID}" 2>\/dev\/null || break$/\1:/' \
    -e 's/if swtpm_listens "${SWTPM_PID}" "${port}" \&\& swtpm_listens "${SWTPM_PID}" $((port + 1)); then/if TPM2TOOLS_TCTI="swtpm:host=127.0.0.1,port=${port}" tpm2_pcrread sha256:0 >\/dev\/null 2>\&1; then/' \
    "${repo_root}/scripts/swtpm_start.sh" >"${mut}/swtpm_start.sh"
cmp -s "${mut}/swtpm_start.sh" "${repo_root}/scripts/swtpm_start.sh" && fail "mutant: sed changed nothing"
grep -q 'tpm2_pcrread sha256:0 >/dev/null 2>&1; then up=1' "${mut}/swtpm_start.sh" || fail "mutant: check not replaced"
set +e
SWTPM_FIRST_PORT="${dp}" bash "${mut}/test_trust1_measurement_tools.sh" >"${work}/mutant.log" 2>&1
set -e
[[ "$(decoy_pcr7)" != "${before}" ]] || fail "mutant: the decoy's PCR 7 did not change, so this control cannot see a test run on a TPM it did not start"
pass "mutant (port answers = ours) ran on the decoy, seen in its PCR 7"

echo "TRUST-1 swtpm port control: ALL PASS"
