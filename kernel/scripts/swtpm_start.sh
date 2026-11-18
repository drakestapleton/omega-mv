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
# state in DIR/tpm and its log in DIR/swtpm.log on a TCP port pair of 127.0.0.1 (data PORT, control
# PORT+1), and sets SWTPM_PID, SWTPM_PORT and TPM2TOOLS_TCTI.
#
# Ports: the first pair is SWTPM_FIRST_PORT (for the control, scripts/test_trust1_swtpm_port.sh) or a
# random pair in 20000-39999. When swtpm exits with "Address already in use" (another test's swtpm,
# any other listener) the next pair of that range is tried, wrapping around, until each of its 10000
# pairs has been tried once: the port range is the bound, there is no count of tries
# [ctl:OMEGA-KERNEL-VERIFY-ALL/swtpm-busy-25-pairs].
# SWTPM_PORT_TRIES=N, set by a caller's control, stops after N pairs. More than SWTPM_PORT_ALARM
# pairs (default 20) prints one ALARM line on stderr.
# Start-up: there is no time limit. It waits until this swtpm process holds the listening sockets of
# both ports (their socket inodes in /proc/net/tcp are among its file descriptors), or until swtpm
# exits, so a TPM that another process serves on a chosen port is never the one the test talks to
# [ctl:OMEGA-KERNEL-VERIFY-ALL/swtpm-data-port-only].
# Waiting longer than SWTPM_LISTEN_ALARM_S seconds (default 5) prints one ALARM line on stderr; a
# swtpm that never listens is ended by the calling step's timeout. (Before 2026-11-18 there were two
# fixed caps here, 20 pairs and 100 polls of 50 ms; a swtpm that listened after 15 s failed the test:
# review of omega-mv 5cd0af98f, WiringRun finding 8 [ctl:OMEGA-KERNEL-VERIFY-ALL/swtpm-slow-7s].)
#
# Returns 0 when this swtpm listens on both ports, 1 when swtpm exits for any reason other than a
# port in use (no other pair is tried) [ctl:OMEGA-KERNEL-VERIFY-ALL/swtpm-other-error] or every pair allowed is in use.
# swtpm not on PATH: prints "SWTPM: NOT_RUN" and exits the calling script with 3 (a missing tool is
# NOT_RUN, never FAIL) [ctl:OMEGA-KERNEL-VERIFY-ALL/swtpm-absent-not-run].
#
# bash scripts/swtpm_start.sh --self-test runs the controls below with stand-in swtpm programs that
# wrap the real one; exit 0 PASS, 1 FAIL, 3 NOT_RUN (swtpm absent).

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
    local dir=$1 try port off up t0 alarmed pairs=10000
    if ! command -v swtpm >/dev/null 2>&1; then
        echo "SWTPM: NOT_RUN (swtpm is not on PATH)"
        exit 3
    fi
    mkdir -p "${dir}/tpm"
    off=$(( (RANDOM % pairs) * 2 ))
    for ((try = 1; try <= pairs; try++)); do
        if [[ -n "${SWTPM_PORT_TRIES:-}" && ${try} -gt ${SWTPM_PORT_TRIES} ]]; then break; fi
        if [[ ${try} -eq 1 && -n "${SWTPM_FIRST_PORT:-}" ]]; then port=${SWTPM_FIRST_PORT}
        else port=$((20000 + (off + 2 * try) % (2 * pairs))); fi
        if [[ ${try} -eq $(( ${SWTPM_PORT_ALARM:-20} + 1 )) ]]; then
            echo "ALARM swtpm_start: more than ${SWTPM_PORT_ALARM:-20} port pairs in use; still trying" >&2
        fi
        swtpm socket --tpm2 --tpmstate dir="${dir}/tpm" \
            --server type=tcp,port="${port}",bindaddr=127.0.0.1 \
            --ctrl type=tcp,port=$((port + 1)),bindaddr=127.0.0.1 \
            --flags not-need-init,startup-clear >"${dir}/swtpm.log" 2>&1 &
        SWTPM_PID=$!
        up=0; t0=${SECONDS}; alarmed=0
        while kill -0 "${SWTPM_PID}" 2>/dev/null; do
            if swtpm_listens "${SWTPM_PID}" "${port}" && swtpm_listens "${SWTPM_PID}" $((port + 1)); then up=1; break; fi
            if [[ ${alarmed} -eq 0 && $((SECONDS - t0)) -gt ${SWTPM_LISTEN_ALARM_S:-5} ]]; then
                echo "ALARM swtpm_start: swtpm ${SWTPM_PID} not listening on ports ${port} and $((port + 1)) after ${SWTPM_LISTEN_ALARM_S:-5} s; still waiting" >&2
                alarmed=1
            fi
            sleep 0.05
        done
        if [[ ${up} -eq 1 ]]; then
            [[ ${alarmed} -eq 0 ]] || echo "swtpm_start: swtpm ${SWTPM_PID} listened after $((SECONDS - t0)) s" >&2
            SWTPM_PORT=${port}
            export TPM2TOOLS_TCTI="swtpm:host=127.0.0.1,port=${port}"
            return 0
        fi
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
    echo "swtpm: $((try - 1)) port pairs tried, all in use" >&2
    return 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" && "${1:-}" == --self-test ]]; then
    set -uo pipefail
    self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/swtpm_start.sh"
    real=$(command -v swtpm) || { echo "SWTPM_START_SELF_TEST: NOT_RUN (swtpm is not on PATH)"; exit 3; }
    st_tmp=$(mktemp -d "${TMPDIR:-/tmp}/swtpm-start-st.XXXXXX")
    trap 'pkill -f "tpmstate dir=${st_tmp}/" 2>/dev/null; rm -rf "${st_tmp}"' EXIT
    st_fail=0
    ctl() { echo "CONTROL OMEGA-KERNEL-VERIFY-ALL/swtpm-$1 FAILED_AS_REQUIRED"; }
    bad() { echo "FAIL  swtpm-$1: $2"; st_fail=1; }
    # A stand-in swtpm first on PATH: it records each start in CALLS, then acts as MODE says and
    # otherwise execs the real swtpm.
    mkdir -p "${st_tmp}/bin"
    cat > "${st_tmp}/bin/swtpm" <<'STANDIN'
#!/usr/bin/env bash
echo start >> "${ST_CALLS}"
n=$(wc -l < "${ST_CALLS}")
case "${ST_MODE}" in
    other) echo "swtpm: Could not open the TPM state (stand-in)" >&2; exit 1 ;;
    busy) if [[ ${n} -le 25 ]]; then echo "swtpm: Could not open TCP socket: Address already in use" >&2; exit 1; fi ;;
    slow) sleep 7 ;;
    dataonly) args=(); prev=
        for a in "$@"; do
            if [[ ${prev} == --ctrl ]]; then p=${a#*port=}; p=${p%%,*}; a="type=tcp,port=$((p + 2)),bindaddr=127.0.0.1"; fi
            args+=("${a}"); prev=${a}
        done
        set -- "${args[@]}" ;;
esac
exec "${ST_REAL}" "$@"
STANDIN
    chmod +x "${st_tmp}/bin/swtpm"
    # run NAME MODE [ENV...]: swtpm_start in its own shell; rc, its output in NAME.out, starts in NAME.calls.
    run() {
        local name=$1 mode=$2; shift 2
        : > "${st_tmp}/${name}.calls"
        rc=0
        env PATH="${st_tmp}/bin:${PATH}" ST_REAL="${real}" ST_MODE="${mode}" ST_CALLS="${st_tmp}/${name}.calls" "$@" \
            bash -c 'source "$1"; swtpm_start "$2"; r=$?; [[ -z "${SWTPM_PID:-}" ]] || kill "${SWTPM_PID}"; exit "${r}"' \
            _ "${self}" "${st_tmp}/${name}" > "${st_tmp}/${name}.out" 2>&1 || rc=$?
        calls=$(wc -l < "${st_tmp}/${name}.calls")
    }
    # 1. swtpm fails for another reason than a port in use: refused at once, no other pair tried
    #    (kills the mutant "any swtpm failure counts as a port in use") [ctl:OMEGA-KERNEL-VERIFY-ALL/swtpm-other-error].
    run other other
    if [[ ${rc} == 1 && ${calls} == 1 ]] && ! grep -q 'trying another pair' "${st_tmp}/other.out"; then ctl other-error
    else bad other-error "exit ${rc}, ${calls} starts"; fi
    # 2. 25 pairs in use: no cap of 20; started on the 26th, with one ALARM line.
    run busy busy
    if [[ ${rc} == 0 && ${calls} == 26 ]] && [[ $(grep -c '^ALARM swtpm_start: more than 20 port pairs' "${st_tmp}/busy.out") == 1 ]]; then ctl busy-25-pairs
    else bad busy-25-pairs "exit ${rc}, ${calls} starts"; cat "${st_tmp}/busy.out"; fi
    # 3. swtpm listens after 7 s: no fixed wait (the old one was 5 s); passes with one ALARM line.
    run slow slow
    if [[ ${rc} == 0 && ${calls} == 1 ]] && grep -q '^ALARM swtpm_start: swtpm .* not listening' "${st_tmp}/slow.out"; then ctl slow-7s
    else bad slow-7s "exit ${rc}, ${calls} starts"; cat "${st_tmp}/slow.out"; fi
    # 4. this swtpm serves the data port but its control port elsewhere: not accepted; it is still
    #    waiting when its ALARM line comes (kills the mutant "only the data port checked")
    #    [ctl:OMEGA-KERNEL-VERIFY-ALL/swtpm-data-port-only].
    : > "${st_tmp}/dataonly.calls"
    env PATH="${st_tmp}/bin:${PATH}" ST_REAL="${real}" ST_MODE=dataonly ST_CALLS="${st_tmp}/dataonly.calls" SWTPM_LISTEN_ALARM_S=1 \
        bash -c 'source "$1"; swtpm_start "$2" && echo "ACCEPTED ${SWTPM_PORT}"' _ "${self}" "${st_tmp}/dataonly" > "${st_tmp}/dataonly.out" 2>&1 &
    dpid=$!
    until grep -q '^ALARM swtpm_start' "${st_tmp}/dataonly.out" || ! kill -0 "${dpid}" 2>/dev/null; do sleep 0.2; done
    if kill -0 "${dpid}" 2>/dev/null && ! grep -q ACCEPTED "${st_tmp}/dataonly.out"; then ctl data-port-only
    else bad data-port-only "returned: $(cat "${st_tmp}/dataonly.out")"; fi
    kill "${dpid}" 2>/dev/null; pkill -f "tpmstate dir=${st_tmp}/dataonly/" 2>/dev/null; wait "${dpid}" 2>/dev/null
    # 5. swtpm not on PATH: NOT_RUN and the calling script exits 3.
    mkdir -p "${st_tmp}/nobin"
    for t in bash mkdir awk readlink sleep cat grep wc env; do ln -s "$(command -v "${t}")" "${st_tmp}/nobin/${t}"; done
    rc=0; env PATH="${st_tmp}/nobin" bash -c 'source "$1"; swtpm_start "$2"; echo reached' _ "${self}" "${st_tmp}/absent" \
        > "${st_tmp}/absent.out" 2>&1 || rc=$?
    if [[ ${rc} == 3 ]] && grep -qx 'SWTPM: NOT_RUN (swtpm is not on PATH)' "${st_tmp}/absent.out" && ! grep -qx reached "${st_tmp}/absent.out"; then ctl absent-not-run
    else bad absent-not-run "exit ${rc}: $(cat "${st_tmp}/absent.out")"; fi
    if [[ ${st_fail} == 0 ]]; then echo "SWTPM_START_SELF_TEST: PASS (5 controls)"; exit 0; fi
    echo "SWTPM_START_SELF_TEST: FAIL"; exit 1
fi
