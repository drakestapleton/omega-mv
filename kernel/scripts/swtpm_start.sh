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

# swtpm_start.sh: sourced by the TRUST-1 software-TPM tests. swtpm_start DIR starts swtpm with its
# state in DIR/tpm and its log in DIR/swtpm.log on a random TCP port pair of 127.0.0.1 (data PORT,
# control PORT+1), and sets SWTPM_PID, SWTPM_PORT and TPM2TOOLS_TCTI.
#
# A random pair can be in use (another test's swtpm, any other listener): swtpm then exits with
# "Address already in use" and the next pair is tried, up to SWTPM_PORT_TRIES pairs (default 20).
# It returns 0 only once this swtpm process holds the listening sockets of both ports (their
# socket inodes in /proc/net/tcp are among its file descriptors), so a TPM that another process
# serves on a chosen port is never the one the test talks to. It returns 1 on any other failure.
# SWTPM_FIRST_PORT sets the first port tried (for the control, scripts/test_trust1_swtpm_port.sh).

# swtpm_listens PID PORT: PID holds the listening TCP socket of 127.0.0.1:PORT.
swtpm_listens() {
    local inode fd
    inode=$(awk -v a="$(printf '0100007F:%04X' "$2")" -v b="$(printf '7F000001:%04X' "$2")" \
        '($2 == a || $2 == b) && $4 == "0A" {print $10; exit}' /proc/net/tcp 2>/dev/null)
    [[ -n "${inode}" ]] || return 1
    for fd in /proc/"$1"/fd/*; do
        [[ "$(readlink "${fd}" 2>/dev/null)" == "socket:[${inode}]" ]] && return 0
    done
    return 1
}

swtpm_start() {
    local dir=$1 try port i up
    mkdir -p "${dir}/tpm"
    for ((try = 1; try <= ${SWTPM_PORT_TRIES:-20}; try++)); do
        if [[ ${try} -eq 1 && -n "${SWTPM_FIRST_PORT:-}" ]]; then port=${SWTPM_FIRST_PORT}
        else port=$((20000 + RANDOM % 20000)); fi
        swtpm socket --tpm2 --tpmstate dir="${dir}/tpm" \
            --server type=tcp,port="${port}",bindaddr=127.0.0.1 \
            --ctrl type=tcp,port=$((port + 1)),bindaddr=127.0.0.1 \
            --flags not-need-init,startup-clear >"${dir}/swtpm.log" 2>&1 &
        SWTPM_PID=$!
        up=0
        for ((i = 0; i < 100; i++)); do
            kill -0 "${SWTPM_PID}" 2>/dev/null || break
            if swtpm_listens "${SWTPM_PID}" "${port}" && swtpm_listens "${SWTPM_PID}" $((port + 1)); then up=1; break; fi
            sleep 0.05
        done
        if [[ ${up} -eq 1 ]]; then
            SWTPM_PORT=${port}
            export TPM2TOOLS_TCTI="swtpm:host=127.0.0.1,port=${port}"
            return 0
        fi
        kill "${SWTPM_PID}" 2>/dev/null || true
        wait "${SWTPM_PID}" 2>/dev/null || true
        SWTPM_PID=""
        if grep -q "Address already in use" "${dir}/swtpm.log"; then
            echo "swtpm: port ${port} or $((port + 1)) is in use; trying another pair" >&2
            continue
        fi
        echo "swtpm did not listen on ports ${port} and $((port + 1)):" >&2
        cat "${dir}/swtpm.log" >&2
        return 1
    done
    echo "swtpm: ${SWTPM_PORT_TRIES:-20} port pairs in use" >&2
    return 1
}
