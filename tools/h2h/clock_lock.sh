#!/bin/sh
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

# clock_lock.sh -- hold the GPU clock fixed for the head-to-head timed runs
# (docs/perf/HEAD_TO_HEAD_PROTOCOL.md section 3). Logging the clock shows that
# runs drifted; this stops them drifting, and refuses the run when it cannot.
#
#   clock_lock.sh lock <mhz|max> <out>     nvidia-smi -lgc, then read the clock back
#   clock_lock.sh check <out>              read the clock; exit 4 if it left the lock
#   clock_lock.sh release <out>            nvidia-smi -rgc
#   clock_lock.sh run <mhz|max> <out> -- <command...>
#                                          lock, check, command, check, release
#                                          (release also on INT/TERM/HUP)
#
# Exit: 0 held; 2 usage; 3 the lock was refused or could not be read back
# (BLOCKED_HARDWARE: no timed run is started); 4 the clock left the lock
# (the run is recorded as drifted, never as a timing); else the command's status.
#
# <out> gets clock-lock.txt: one line per event, appended, never rewritten.
# Env: NVSMI (default nvidia-smi), H2H_GPU (index, default 0),
#      H2H_CLOCK_TOL_MHZ (default 10), H2H_SETTLE_S (default 1).
# Needs root for -lgc/-rgc. Opens no GPU context; it only talks to nvidia-smi.
set -u
NVSMI=${NVSMI:-nvidia-smi}
GPU=${H2H_GPU:-0}
TOL=${H2H_CLOCK_TOL_MHZ:-10}
SETTLE=${H2H_SETTLE_S:-1}

usage() { sed -n '17,36p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$OUT/clock-lock.txt"; }
is_int() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# query <field>: one integer for this GPU, or empty when the driver gives
# "[N/A]", "[Not Supported]" or nothing.
query() {
    v=$("$NVSMI" -i "$GPU" --query-gpu="$1" --format=csv,noheader,nounits 2>/dev/null | head -n 1 | tr -d ' ')
    v=${v%%.*}
    if is_int "$v"; then printf '%s\n' "$v"; fi
}

state() {
    printf 'clock_mhz=%s max_mhz=%s power_w=%s temp_c=%s pstate=%s' \
        "$(query clocks.current.graphics)" "$(query clocks.max.graphics)" \
        "$(query power.draw)" "$(query temperature.gpu)" \
        "$("$NVSMI" -i "$GPU" --query-gpu=pstate --format=csv,noheader 2>/dev/null | head -n 1 | tr -d ' ')"
}

do_lock() {
    want=$1
    if [ "$want" = max ]; then want=$(query clocks.max.graphics); fi
    if ! is_int "$want" || [ "$want" -eq 0 ]; then
        log "lock REFUSED reason=no-target-clock $(state)"
        echo "clock_lock: no target clock (give MHz, or the driver must report clocks.max.graphics)" >&2
        return 3
    fi
    log "before $(state)"
    if ! msg=$("$NVSMI" -i "$GPU" -lgc "$want,$want" 2>&1); then
        log "lock REFUSED target_mhz=$want nvidia-smi: $(printf '%s' "$msg" | tr '\n' ' ')"
        echo "clock_lock: nvidia-smi -lgc $want,$want refused: $msg" >&2
        return 3
    fi
    sleep "$SETTLE"
    got=$(query clocks.current.graphics)
    if ! is_int "$got"; then
        "$NVSMI" -i "$GPU" -rgc >/dev/null 2>&1
        log "lock UNVERIFIED target_mhz=$want reason=clock-not-readable (released)"
        echo "clock_lock: lock accepted but the clock cannot be read back; released" >&2
        return 3
    fi
    d=$((got - want)); [ "$d" -lt 0 ] && d=$((-d))
    if [ "$d" -gt "$TOL" ]; then
        "$NVSMI" -i "$GPU" -rgc >/dev/null 2>&1
        log "lock NOT_HELD target_mhz=$want read_mhz=$got tol_mhz=$TOL (released)"
        echo "clock_lock: asked $want MHz, read $got MHz; released" >&2
        return 3
    fi
    printf '%s\n' "$want" >"$OUT/clock-lock.target"
    log "lock LOCKED target_mhz=$want $(state)"
}

do_check() {
    if [ ! -s "$OUT/clock-lock.target" ]; then
        echo "clock_lock: no lock recorded in $OUT" >&2; return 3
    fi
    want=$(cat "$OUT/clock-lock.target")
    got=$(query clocks.current.graphics)
    if ! is_int "$got"; then log "check UNREADABLE target_mhz=$want"; return 4; fi
    d=$((got - want)); [ "$d" -lt 0 ] && d=$((-d))
    if [ "$d" -gt "$TOL" ]; then
        log "check DRIFTED target_mhz=$want $(state)"
        echo "clock_lock: clock left the lock: asked $want MHz, read $got MHz" >&2
        return 4
    fi
    log "check HELD target_mhz=$want $(state)"
}

do_release() {
    if msg=$("$NVSMI" -i "$GPU" -rgc 2>&1); then
        log "release OK $(state)"
    else
        log "release FAILED nvidia-smi: $(printf '%s' "$msg" | tr '\n' ' ')"
        echo "clock_lock: nvidia-smi -rgc failed: $msg" >&2
        return 3
    fi
    rm -f "$OUT/clock-lock.target"
}

cmd=${1:-}
case "$cmd" in
lock)
    [ $# -eq 3 ] || usage
    OUT=$3; mkdir -p "$OUT" || exit 2
    do_lock "$2" ;;
check)
    [ $# -eq 2 ] || usage
    OUT=$2; [ -d "$OUT" ] || usage
    do_check ;;
release)
    [ $# -eq 2 ] || usage
    OUT=$2; mkdir -p "$OUT" || exit 2
    do_release ;;
run)
    [ $# -ge 5 ] && [ "$4" = -- ] || usage
    want=$2; OUT=$3; shift 4
    mkdir -p "$OUT" || exit 2
    do_lock "$want" || exit $?
    # The lock outlives this process, so every way out releases it. The
    # command is not killed here: a signal releases the clock once the
    # command has returned (a GPU run is never cut mid-run).
    released=0
    release_once() { [ "$released" -eq 1 ] || { released=1; do_release; }; }
    trap 'release_once' EXIT
    trap 'release_once; exit 130' INT TERM HUP
    do_check || exit $?
    "$@"; rc=$?
    drift=0; do_check || drift=$?
    release_once || exit 3
    trap - EXIT
    if [ "$drift" -ne 0 ]; then exit "$drift"; fi
    exit "$rc" ;;
*) usage ;;
esac
