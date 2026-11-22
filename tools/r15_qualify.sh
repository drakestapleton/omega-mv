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

# r15_qualify.sh -- the R15 qualification run (spec/r15-performance-proof.md
# §9, §10, §12, §13, §16 C1 item 7).
#
#   tools/r15_qualify.sh [--detach] <host|silicon> [rounds=12] [l1_runs=5] [l2_runs=5]
#   (env: AIENOS_LOCK_REPO or AIENOS_R7_DIR, PHYSICS_DIR repositories holding
#   the pinned commits; CC; R15_OUT_BASE to write a dry run outside evidence/)
#
# Runs, in order: W-EPISODE trials (rounds x RES-4/RES-1/SEQ/RES-1-NODIGEST,
# balanced Latin square), Level 1 (A,C,D,E,G,W0,W1 for RES-1 and SEQ
# interleaved, B for RES-1), Level 2 (RES-1/SEQ interleaved). Every process
# writes its own raw file; a failed process is recorded and NEVER rerun (§10).
# The benchmark and reducer are rebuilt from verified Git archives in a private
# directory. Only digest-bound copies under the run directory are executed.
# Then SHA256SUMS and the reducer. Output: evidence/R15/raw/<run-id>/.
#
# --detach re-launches this script in its own session (setsid nohup), so an
# agent or terminal going away cannot stop a long run; progress is written in
# plain words to <out>/progress.log.
#
# The only machine setting changed is kernel.perf_event_paranoid: 4 -> 1 for
# the run, restored to 4 on every exit path, and the run fails if it does not
# read back 4. No systemd.
set -u
set -o pipefail

if [ "${1:-}" = "--detach" ]; then
    shift
    setsid nohup "$0" "$@" </dev/null >/dev/null 2>&1 &
    disown
    echo "started in the background (pid $!)"
    exit 0
fi

MODE=${1:?host or silicon}
ROUNDS=${2:-12}
L1RUNS=${3:-5}
L2RUNS=${4:-5}
case "$MODE" in host|silicon) ;; *) echo "mode must be host or silicon" >&2; exit 64;; esac

HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE" || exit 1
export GIT_NO_REPLACE_OBJECTS=1 GIT_GRAFT_FILE=/nonexistent/r15-qualify-grafts
COMMIT=$(git rev-parse HEAD) || { echo "r15_qualify: cannot read candidate HEAD" >&2; exit 2; }
INITIAL_STATUS=$(git status --porcelain --untracked-files=no) || { echo "r15_qualify: cannot read initial tree state" >&2; exit 2; }
DIRTY=$([ -z "$INITIAL_STATUS" ] && echo false || echo true)
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)-${COMMIT:0:12}-$MODE
OUT_BASE=${R15_OUT_BASE:-$HERE/evidence/R15/raw}
mkdir -p "$OUT_BASE" || exit 1
OUT=$OUT_BASE/$RUN_ID
mkdir -m 0755 "$OUT" || { echo "r15_qualify: run directory already exists or cannot be created: $OUT" >&2; exit 1; }
LOG=$OUT/progress.log
say() { echo "$(date '+%H:%M:%S') $*" >> "$LOG"; }
jstr() { printf '"%s"' "$(printf '%s' "$1" | tr -d '"\\' | tr '\n' ' ')"; }
sha_file() { sha256sum "$1" | cut -d' ' -f1; }
full_commit() { [[ "$1" =~ ^[0-9a-f]{40}$ ]]; }
plain_path() { [[ "$1" =~ ^[A-Za-z0-9/._+-]+$ ]]; }

BUILD_LOG=$OUT/build.log
: > "$BUILD_LOG"
prepare_fail() {
    say "PREPARATION FAILED: $*"
    echo "r15_qualify: $*" >&2
    exit 2
}
verify_commit() { # <repository> <commit> <label>; prints the root tree id
    local repo=$1 commit=$2 label=$3 got tree line
    full_commit "$commit" || prepare_fail "$label commit is not one full lower-case SHA-1: $commit"
    got=$(git -C "$repo" -c core.commitGraph=false -c core.hooksPath=/dev/null -c core.fsmonitor= \
        rev-parse --verify "$commit^{commit}" 2>/dev/null) || prepare_fail "$label commit $commit is unavailable in $repo"
    [ "$got" = "$commit" ] || prepare_fail "$label resolved to $got, not $commit"
    got=$(git -C "$repo" -c core.commitGraph=false -c core.hooksPath=/dev/null -c core.fsmonitor= \
        cat-file commit "$commit" 2>/dev/null | git hash-object -t commit --stdin 2>/dev/null) || prepare_fail "cannot re-hash $label commit $commit"
    [ "$got" = "$commit" ] || prepare_fail "$label commit object does not hash to $commit"
    # The tree id is the first line of the commit object. A commit-graph must
    # not be able to aim the archive at a different tree than that line.
    line=$(git -C "$repo" -c core.commitGraph=false -c core.hooksPath=/dev/null -c core.fsmonitor= \
        cat-file commit "$commit" | awk 'NR==1 { print; exit }') || prepare_fail "cannot read $label commit $commit"
    tree=${line#tree }
    [ "$line" = "tree $tree" ] && full_commit "$tree" || prepare_fail "$label commit $commit has no literal root tree"
    got=$(git -C "$repo" -c core.commitGraph=false -c core.hooksPath=/dev/null -c core.fsmonitor= \
        cat-file tree "$tree" 2>/dev/null | git hash-object -t tree --stdin 2>/dev/null) || prepare_fail "cannot re-hash $label tree $tree"
    [ "$got" = "$tree" ] || prepare_fail "$label tree object does not hash to $tree"
    git -C "$repo" -c core.commitGraph=false -c core.hooksPath=/dev/null -c core.fsmonitor= \
        fsck --strict --no-dangling "$commit" >> "$BUILD_LOG" 2>&1 || prepare_fail "$label object closure fails git fsck"
    printf '%s\n' "$tree"
}

TMP_BASE=${TMPDIR:-/tmp}
plain_path "$TMP_BASE" || prepare_fail "TMPDIR contains characters outside [A-Za-z0-9/._+-]: $TMP_BASE"
case "$TMP_BASE" in /*) ;; *) prepare_fail "TMPDIR must be absolute: $TMP_BASE";; esac
[ "$TMP_BASE" != / ] || prepare_fail "TMPDIR may not be the filesystem root"
BUILD_WORK=$(mktemp -d "$TMP_BASE/omega-r15-build.XXXXXX") || prepare_fail "cannot create private build directory"
cleanup_build() {
    case "$BUILD_WORK" in
        "$TMP_BASE"/omega-r15-build.*)
            chmod -R u+w "$BUILD_WORK" 2>/dev/null
            rm -rf -- "$BUILD_WORK"
            ;;
        *) echo "r15_qualify: refusing to remove unexpected build path $BUILD_WORK" >&2 ;;
    esac
}
RESTORE_NEEDED=false
on_exit() {
    [ "$RESTORE_NEEDED" != true ] || restore
    cleanup_build
}
trap on_exit EXIT
trap 'say "stopped by a signal"; exit 130' INT TERM HUP

PHYSICS_LOCK=$(git show "$COMMIT:physics.lock" 2>/dev/null | tr -d '[:space:]')
AIENOS_LOCK=$(git show "$COMMIT:aienos.lock" 2>/dev/null | tr -d '[:space:]')
PHYSICS_INPUT=${PHYSICS_DIR:-$HERE/../physics}
PHYSICS_REPO=$(git -C "$PHYSICS_INPUT" rev-parse --show-toplevel 2>/dev/null) || prepare_fail "PHYSICS_DIR must name a Git repository holding $PHYSICS_LOCK"
if [ -n "${AIENOS_LOCK_REPO:-}" ]; then
    AIENOS_INPUT=$AIENOS_LOCK_REPO
elif [ -n "${AIENOS_R7_DIR:-}" ]; then
    AIENOS_INPUT=$AIENOS_R7_DIR
else
    AIENOS_INPUT=$HERE/../aienos-argus-cap
fi
AIENOS_REPO=$(git -C "$AIENOS_INPUT" rev-parse --show-toplevel 2>/dev/null) || prepare_fail "AIENOS source must name a Git repository holding $AIENOS_LOCK"
for path in "$HERE" "$PHYSICS_REPO" "$AIENOS_REPO" "$BUILD_WORK"; do
    plain_path "$path" || prepare_fail "build path contains characters outside [A-Za-z0-9/._+-]: $path"
done

OMEGA_TREE=$(verify_commit "$HERE" "$COMMIT" omega) || exit 2
PHYSICS_TREE=$(verify_commit "$PHYSICS_REPO" "$PHYSICS_LOCK" physics) || exit 2
AIENOS_TREE=$(verify_commit "$AIENOS_REPO" "$AIENOS_LOCK" aienos) || exit 2

CANDIDATE_TAR=$BUILD_WORK/omega.tar
PHYSICS_TAR=$BUILD_WORK/physics.tar
AIENOS_TAR=$BUILD_WORK/aienos-capability.tar
# Archive the tree id taken from the commit object, not a peeled rev-parse.
git -C "$HERE" -c core.commitGraph=false -c core.hooksPath=/dev/null -c core.fsmonitor= \
    archive --format=tar "$OMEGA_TREE" > "$CANDIDATE_TAR" || prepare_fail "cannot archive omega candidate $COMMIT"
git -C "$PHYSICS_REPO" -c core.commitGraph=false -c core.hooksPath=/dev/null -c core.fsmonitor= \
    archive --format=tar "$PHYSICS_TREE" > "$PHYSICS_TAR" || prepare_fail "cannot archive physics commit $PHYSICS_LOCK"
git -C "$AIENOS_REPO" -c core.commitGraph=false -c core.hooksPath=/dev/null -c core.fsmonitor= \
    archive --format=tar "$AIENOS_TREE" native/capability > "$AIENOS_TAR" || prepare_fail "cannot archive aienos capability source at $AIENOS_LOCK"
CANDIDATE_ARCHIVE_SHA=$(sha_file "$CANDIDATE_TAR") || prepare_fail "cannot hash omega candidate archive"
PHYSICS_ARCHIVE_SHA=$(sha_file "$PHYSICS_TAR") || prepare_fail "cannot hash physics archive"
AIENOS_ARCHIVE_SHA=$(sha_file "$AIENOS_TAR") || prepare_fail "cannot hash aienos archive"

CANDIDATE_SRC=$BUILD_WORK/omega
PHYSICS_SRC=$BUILD_WORK/physics
BUILD_OUT=$BUILD_WORK/out
mkdir "$CANDIDATE_SRC" "$PHYSICS_SRC" "$BUILD_OUT" || prepare_fail "cannot create isolated source/build directories"
tar -xf "$CANDIDATE_TAR" -C "$CANDIDATE_SRC" || prepare_fail "cannot extract omega candidate archive"
tar -xf "$PHYSICS_TAR" -C "$PHYSICS_SRC" || prepare_fail "cannot extract physics archive"

CC_NAME=${CC:-gcc}
case "$CC_NAME" in ''|*[!A-Za-z0-9_./+-]*) prepare_fail "CC must be one plain executable name or path";; esac
CC_PATH=$(command -v -- "$CC_NAME" 2>/dev/null) || prepare_fail "compiler $CC_NAME is unavailable"
CC_PATH=$(readlink -f "$CC_PATH") || prepare_fail "cannot resolve compiler $CC_NAME"
MAKE_PATH=$(command -v -- make 2>/dev/null) || prepare_fail "make is unavailable"
MAKE_PATH=$(readlink -f "$MAKE_PATH") || prepare_fail "cannot resolve make"
plain_path "$CC_PATH" || prepare_fail "compiler path contains characters outside [A-Za-z0-9/._+-]: $CC_PATH"
plain_path "$MAKE_PATH" || prepare_fail "make path contains characters outside [A-Za-z0-9/._+-]: $MAKE_PATH"
CC_SHA=$(sha_file "$CC_PATH") || prepare_fail "cannot hash compiler $CC_PATH"
MAKE_SHA=$(sha_file "$MAKE_PATH") || prepare_fail "cannot hash make $MAKE_PATH"
CC_VERSION_ALL=$("$CC_PATH" --version 2>/dev/null) || prepare_fail "cannot read compiler version"
CC_VERSION=${CC_VERSION_ALL%%$'\n'*}
MAKE_VERSION_ALL=$("$MAKE_PATH" --version 2>/dev/null) || prepare_fail "cannot read make version"
MAKE_VERSION=${MAKE_VERSION_ALL%%$'\n'*}
BUILD_COMMAND="env -u build overrides make -C <omega-archive> OUT_DIR=<private> PHYSICS_DIR=<physics-archive> PHYSICS_LOCK_CHECK=0 AIENOS_LOCK_REPO=<verified-repository> CC=$CC_PATH r15-perf-$MODE"
printf 'candidate=%s archive_sha256=%s\nphysics=%s archive_sha256=%s\naienos=%s capability_archive_sha256=%s\ncommand=%s\n' \
    "$COMMIT" "$CANDIDATE_ARCHIVE_SHA" "$PHYSICS_LOCK" "$PHYSICS_ARCHIVE_SHA" \
    "$AIENOS_LOCK" "$AIENOS_ARCHIVE_SHA" "$BUILD_COMMAND" >> "$BUILD_LOG"
if ! env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL -u CC -u CFLAGS -u CPPFLAGS -u LDFLAGS \
        -u CPATH -u C_INCLUDE_PATH -u CPLUS_INCLUDE_PATH -u LIBRARY_PATH \
        -u GCC_EXEC_PREFIX -u COMPILER_PATH -u LD_PRELOAD \
        GIT_NO_REPLACE_OBJECTS=1 GIT_GRAFT_FILE=/nonexistent/r15-qualify-grafts \
        "CC=$CC_PATH" \
        "$MAKE_PATH" -C "$CANDIDATE_SRC" "OUT_DIR=$BUILD_OUT" "PHYSICS_DIR=$PHYSICS_SRC" \
        PHYSICS_LOCK_CHECK=0 "AIENOS_LOCK_REPO=$AIENOS_REPO" "r15-perf-$MODE" \
        >> "$BUILD_LOG" 2>&1; then
    prepare_fail "isolated make r15-perf-$MODE failed (see build.log)"
fi
[ "$(sha_file "$CC_PATH")" = "$CC_SHA" ] || prepare_fail "compiler changed during the isolated build"
[ "$(sha_file "$MAKE_PATH")" = "$MAKE_SHA" ] || prepare_fail "make changed during the isolated build"

BUILT_B=$BUILD_OUT/rx_r15_perf_$MODE
BUILT_BND=$BUILD_OUT/rx_r15_perf_${MODE}_nodigest
BUILT_RED=$BUILD_OUT/r15_reduce
for f in "$BUILT_B" "$BUILT_BND" "$BUILT_RED"; do
    [ -x "$f" ] || prepare_fail "isolated build did not produce executable $f"
done
BIN_DIR=$OUT/bin
mkdir "$BIN_DIR" || prepare_fail "cannot create sealed binary directory"
B=$BIN_DIR/rx_r15_perf_$MODE
BND=$BIN_DIR/rx_r15_perf_${MODE}_nodigest
RED=$BIN_DIR/r15_reduce
cp -- "$BUILT_B" "$B" || prepare_fail "cannot stage trial binary"
cp -- "$BUILT_BND" "$BND" || prepare_fail "cannot stage nodigest binary"
cp -- "$BUILT_RED" "$RED" || prepare_fail "cannot stage reducer"
chmod 0555 "$B" "$BND" "$RED" "$BIN_DIR" || prepare_fail "cannot make staged artifacts read-only"
TRIAL_SHA=$(sha_file "$B") || prepare_fail "cannot hash staged trial binary"
NODIGEST_SHA=$(sha_file "$BND") || prepare_fail "cannot hash staged nodigest binary"
REDUCER_SHA=$(sha_file "$RED") || prepare_fail "cannot hash staged reducer"
[ "$TRIAL_SHA" = "$(sha_file "$BUILT_B")" ] || prepare_fail "staged trial binary differs from isolated build output"
[ "$NODIGEST_SHA" = "$(sha_file "$BUILT_BND")" ] || prepare_fail "staged nodigest binary differs from isolated build output"
[ "$REDUCER_SHA" = "$(sha_file "$BUILT_RED")" ] || prepare_fail "staged reducer differs from isolated build output"
BUILD_LOG_SHA=$(sha_file "$BUILD_LOG") || prepare_fail "cannot hash build log"
{
    printf '{"schema":"AIEN_RX_R15_BUILD_PROVENANCE_V1","candidate_commit":%s,' "$(jstr "$COMMIT")"
    printf '"candidate_archive_sha256":%s,"physics_commit":%s,"physics_archive_sha256":%s,' \
        "$(jstr "$CANDIDATE_ARCHIVE_SHA")" "$(jstr "$PHYSICS_LOCK")" "$(jstr "$PHYSICS_ARCHIVE_SHA")"
    printf '"aienos_commit":%s,"aienos_archive_sha256":%s,"build_command":%s,' \
        "$(jstr "$AIENOS_LOCK")" "$(jstr "$AIENOS_ARCHIVE_SHA")" "$(jstr "$BUILD_COMMAND")"
    printf '"compiler_path":%s,"compiler_sha256":%s,"compiler_version":%s,' \
        "$(jstr "$CC_PATH")" "$(jstr "$CC_SHA")" "$(jstr "$CC_VERSION")"
    printf '"make_path":%s,"make_sha256":%s,"make_version":%s,"build_log_sha256":%s,' \
        "$(jstr "$MAKE_PATH")" "$(jstr "$MAKE_SHA")" "$(jstr "$MAKE_VERSION")" "$(jstr "$BUILD_LOG_SHA")"
    printf '"binaries":{"trial":%s,"nodigest":%s,"reducer":%s}}\n' \
        "$(jstr "$TRIAL_SHA")" "$(jstr "$NODIGEST_SHA")" "$(jstr "$REDUCER_SHA")"
} > "$OUT/build-provenance.json"

# ---- kernel.perf_event_paranoid 4 -> 1 -> 4 (C1 item 7) ---------------------
PARANOID_BEFORE=$(cat /proc/sys/kernel/perf_event_paranoid)
STATE=$CANDIDATE_SRC/tools/r15_machine_state.sh
restore() {
    "$STATE" stop "$OUT" 2>/dev/null
    sudo -n sysctl -q kernel.perf_event_paranoid=4 >/dev/null 2>&1
    PARANOID_RESTORED=$(cat /proc/sys/kernel/perf_event_paranoid)
    echo "$PARANOID_RESTORED" > "$OUT/paranoid-restored.txt"
    if [ "$PARANOID_RESTORED" != 4 ]; then say "WARNING: perf_event_paranoid did not return to 4 (reads $PARANOID_RESTORED)"; fi
}
RESTORE_NEEDED=true
sudo -n sysctl -q kernel.perf_event_paranoid=1 >/dev/null 2>&1
PARANOID_DURING=$(cat /proc/sys/kernel/perf_event_paranoid)

# ---- machine.json (§13) ------------------------------------------------------
midrs=$(for c in /sys/devices/system/cpu/cpu[0-9]*; do
    printf '%s:%s ' "${c##*cpu}" "$(cat "$c/regs/identification/midr_el1" 2>/dev/null)"; done)
govs=$(for c in /sys/devices/system/cpu/cpu[0-9]*; do
    printf '%s:%s:%s ' "${c##*cpu}" "$(cat "$c/cpufreq/scaling_governor" 2>/dev/null)" \
        "$(cat "$c/cpufreq/scaling_cur_freq" 2>/dev/null)"; done)
temps=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | tr '\n' ' ')
spbm_ver=$(cat /sys/module/aien_spbm_readonly/srcversion 2>/dev/null)
top=$(ps -eo pcpu,comm --sort=-pcpu | sed -n 2,11p | awk '{printf "%s:%s ", $2, $1}')
servers=$(ps -eo comm,args | grep -i -E 'astrosage|lm-studio|lmstudio|llama|vllm|ollama' | grep -v grep | awk '{print $1}' | sort -u | tr '\n' ' ')
aienos=$AIENOS_LOCK
physics=$PHYSICS_LOCK
{
    printf '{"run_id":%s,"mode":%s,"candidate_commit":%s,"tree_dirty":%s,' \
        "$(jstr "$RUN_ID")" "$(jstr "$MODE")" "$(jstr "$COMMIT")" "$DIRTY"
    printf '"hostname":%s,"machine_id_sha256":%s,"kernel":%s,' \
        "$(jstr "$(hostname)")" "$(jstr "$(sha256sum /etc/machine-id | cut -d' ' -f1)")" "$(jstr "$(uname -r)")"
    printf '"midr":%s,"governor_freq":%s,"boost":%s,"mem_kb":%s,' \
        "$(jstr "$midrs")" "$(jstr "$govs")" "$(jstr "$(cat /sys/devices/system/cpu/cpufreq/boost 2>/dev/null)")" \
        "$(jstr "$(awk '/MemTotal/{print $2}' /proc/meminfo)")"
    printf '"gpu":%s,"secure_boot":%s,"lockdown":%s,' \
        "$(jstr "$(nvidia-smi --query-gpu=name,pci.bus_id,driver_version,temperature.gpu --format=csv,noheader 2>/dev/null)")" \
        "$(jstr "$(mokutil --sb-state 2>/dev/null)")" "$(jstr "$(cat /sys/kernel/security/lockdown 2>/dev/null)")"
    printf '"perf_event_paranoid":{"original":%s,"qualification":%s,"restored":"see paranoid-restored.txt"},' \
        "$PARANOID_BEFORE" "$PARANOID_DURING"
    printf '"thermal_mc":%s,"spbm_reader_srcversion":%s,"loadavg":%s,"top_cpu":%s,"model_servers":%s,' \
        "$(jstr "$temps")" "$(jstr "$spbm_ver")" "$(jstr "$(cat /proc/loadavg)")" "$(jstr "$top")" "$(jstr "$servers")"
    printf '"aienos_commit":%s,"physics_commit":%s,"compiler":%s,' \
        "$(jstr "$aienos")" "$(jstr "$physics")" \
        "$(jstr "$CC_VERSION")"
    printf '"binaries":{"trial":%s,"nodigest":%s,"reducer":%s},' \
        "$(jstr "$TRIAL_SHA")" "$(jstr "$NODIGEST_SHA")" "$(jstr "$REDUCER_SHA")"
    printf '"reducer_source_sha256":%s,"rounds":%s,"l1_runs":%s,"l2_runs":%s}\n' \
        "$(jstr "$(sha_file "$CANDIDATE_SRC/tools/r15_reduce.om")")" "$ROUNDS" "$L1RUNS" "$L2RUNS"
} > "$OUT/machine.json"
ps -eo pid,pcpu,rss,comm --sort=-pcpu > "$OUT/processes-before.txt"
[ "$PARANOID_DURING" = 1 ] || say "WARNING: could not set perf_event_paranoid to 1 (reads $PARANOID_DURING); memory-traffic counters will be missing"
[ -n "$servers" ] && say "WARNING: a model server looks resident: $servers (spec §9 says nothing heavy may run)"
[ "$DIRTY" = true ] && say "NOTE: the working tree has uncommitted changes, so this run is not candidate-bound"

# ---- instrument preflight (spec §7, §17 C2) ----------------------------------
# Package energy is a mandatory metric (17) and G9's input. If the signed SPBM
# reader is absent or returns invalid samples, the run cannot PASS, so stop
# before consuming an acceptance window. This is BLOCKED_INSTRUMENT, not a
# measured FAIL: no trial runs, no summary and no receipt is written.
# planned run length for the counter-headroom check: the full default run (12/5/5) took 2068 s (CAND-1 window 2),
# 2400 s with margin; scaled by the number of rounds and level runs. Override with R15_PLANNED_RUN_SECONDS.
export R15_PLANNED_RUN_SECONDS=${R15_PLANNED_RUN_SECONDS:-$(( 2400 * (ROUNDS + L1RUNS + L2RUNS) / 22 + 1 ))}
if [ "$MODE" = silicon ]; then
    if ! ENERGY_MSG=$("$STATE" energy-preflight); then
        say "BLOCKED_INSTRUMENT: $ENERGY_MSG"
        printf 'BLOCKED_INSTRUMENT\n%s\n' "$ENERGY_MSG" > "$OUT/instrument-unavailable.txt"
        echo instrument-unavailable > "$OUT/done"
        # the blocked attempt stays on disk as evidence, never deleted; seal it
        ( cd "$OUT" && find . -type f ! -name SHA256SUMS -printf "%P\n" | LC_ALL=C sort | xargs sha256sum > SHA256SUMS )
        exit 4
    fi
    say "$ENERGY_MSG"
fi

# ---- machine physical state (§18 C3, observability only) --------------------
# The preflight stops the run before any trial if the X925 does not sustain
# its clock (the power-limited state seen on 2026-09-28). After that nothing
# stops, drops or reruns a trial; the state is only recorded.
if [ "$MODE" = silicon ]; then
    say "machine-state preflight: 20 s sustained on one X925 core"
    if ! "$STATE" preflight "$OUT"; then
        say "MACHINE-STATE FAILURE: the X925 did not sustain its clock (preflight.txt); stopped before any trial"
        echo machine-state-failure > "$OUT/done"
        exit 3
    fi
    say "machine-state preflight ok: $(grep median "$OUT/preflight.txt")"
fi
"$STATE" start "$OUT"

say "R15 $MODE run $RUN_ID started: $ROUNDS rounds, $L1RUNS Level-1 runs, $L2RUNS Level-2 runs"
FAILED=0
integrity_fail() { # <file> <expected> <phase>
    local file=$1 expected=$2 phase=$3 actual
    actual=$(sha_file "$file" 2>/dev/null)
    say "EXECUTABLE INTEGRITY FAILURE: $(basename "$file") $phase expected $expected got ${actual:-unreadable}"
    printf 'executable=%s\nphase=%s\nexpected_sha256=%s\nactual_sha256=%s\n' \
        "$(basename "$file")" "$phase" "$expected" "${actual:-unreadable}" > "$OUT/executable-integrity-failure.txt"
    exit 5
}
guard_binary() { # <file> <expected> <phase>
    local actual
    actual=$(sha_file "$1" 2>/dev/null) || integrity_fail "$1" "$2" "$3"
    [ "$actual" = "$2" ] || integrity_fail "$1" "$2" "$3"
}
expected_binary() {
    case "$1" in
        "$B") printf '%s\n' "$TRIAL_SHA" ;;
        "$BND") printf '%s\n' "$NODIGEST_SHA" ;;
        "$RED") printf '%s\n' "$REDUCER_SHA" ;;
        *) integrity_fail "$1" unknown "unregistered executable" ;;
    esac
}
one() {   # <label> <file> <binary> <args...>
    local label=$1 file=$2 bin=$3
    shift 3
    local t0=$SECONDS expected
    expected=$(expected_binary "$bin")
    guard_binary "$bin" "$expected" "before $file"
    "$STATE" mark "$OUT" "begin $file"
    "$bin" "$@" "$OUT/$file" >> "$OUT/stderr.log" 2>&1
    local rc=$?
    guard_binary "$bin" "$expected" "after $file"
    "$STATE" mark "$OUT" "end $file exit $rc"
    echo "$file exit $rc seconds $((SECONDS - t0))" >> "$OUT/runs.txt"
    if [ $rc -ne 0 ]; then FAILED=$((FAILED + 1)); say "$label FAILED (exit $rc); recorded, not rerun"; else say "$label ok ($((SECONDS - t0)) s)"; fi
}

# ---- W-EPISODE: balanced Latin square over 4 configurations (§10) ----------
SQ=("0 1 3 2" "1 2 0 3" "2 3 1 0" "3 0 2 1")
NAMES=(RES4 RES1 SEQ ND)
for r in $(seq 1 "$ROUNDS"); do
    for i in ${SQ[$(( (r - 1) % 4 ))]}; do
        c=${NAMES[$i]}
        if [ "$c" = ND ]; then
            one "round $r RES-1-NODIGEST trial" "trial-RES1ND-$(printf %02d "$r").jsonl" "$BND" trial RES1 "$RUN_ID" "$r"
        else
            one "round $r $c trial" "trial-$c-$(printf %02d "$r").jsonl" "$B" trial "$c" "$RUN_ID" "$r"
        fi
    done
done

# ---- Level 1 ------------------------------------------------------------------
for k in $(seq 1 "$L1RUNS"); do
    for m in A C D E G W0 W1; do
        if [ $((k % 2)) = 1 ]; then order="RES1 SEQ"; else order="SEQ RES1"; fi
        for c in $order; do
            one "Level 1 $m $c run $k" "l1-$m-$c-$k.jsonl" "$B" l1 "$m" "$c" "$RUN_ID" "$k"
        done
    done
    one "Level 1 B RES1 run $k" "l1-B-RES1-$k.jsonl" "$B" l1 B RES1 "$RUN_ID" "$k"
done

# ---- Level 2 ------------------------------------------------------------------
for k in $(seq 1 "$L2RUNS"); do
    if [ $((k % 2)) = 1 ]; then order="RES1 SEQ"; else order="SEQ RES1"; fi
    for c in $order; do one "Level 2 $c run $k" "l2-$c-$k.jsonl" "$B" l2 "$c" "$RUN_ID" "$k"; done
done

ps -eo pid,pcpu,rss,comm --sort=-pcpu > "$OUT/processes-after.txt"
restore
RESTORE_NEEDED=false
(cd "$OUT" && sha256sum ./*.jsonl machine.json machine-state.ndjson machine-perf.csv machine-state-marks.txt $([ -f preflight.txt ] && echo preflight.txt) 2>/dev/null | sed 's| \./| |' > SHA256SUMS)
guard_binary "$RED" "$REDUCER_SHA" "before reduction"
"$RED" "$OUT" "$OUT/summary.json" > "$OUT/reduce.log" 2>&1
guard_binary "$RED" "$REDUCER_SHA" "after reduction"

# The final binding is separate from the reducer's raw-input manifest: it is
# written only after every executable use and then sealed with the binaries,
# build log and build provenance in PROVENANCE_SHA256SUMS.
guard_binary "$B" "$TRIAL_SHA" "at final seal"
guard_binary "$BND" "$NODIGEST_SHA" "at final seal"
guard_binary "$RED" "$REDUCER_SHA" "at final seal"
FINAL_HEAD=$(git rev-parse HEAD 2>/dev/null) || FINAL_HEAD=unreadable
if FINAL_STATUS=$(git status --porcelain --untracked-files=no 2>/dev/null); then
    FINAL_DIRTY=$([ -n "$FINAL_STATUS" ] && echo true || echo false)
else
    FINAL_DIRTY=true
fi
HEAD_UNCHANGED=false; [ "$FINAL_HEAD" = "$COMMIT" ] && HEAD_UNCHANGED=true
{
    printf '{"schema":"AIEN_RX_R15_FINAL_STATE_V1","candidate_commit":%s,"final_head":%s,' \
        "$(jstr "$COMMIT")" "$(jstr "$FINAL_HEAD")"
    printf '"tracked_tree_dirty":%s,"head_unchanged":%s,"binaries_unchanged":true,' \
        "$FINAL_DIRTY" "$HEAD_UNCHANGED"
    printf '"binaries":{"trial":%s,"nodigest":%s,"reducer":%s}}\n' \
        "$(jstr "$TRIAL_SHA")" "$(jstr "$NODIGEST_SHA")" "$(jstr "$REDUCER_SHA")"
} > "$OUT/final-state.json"
(cd "$OUT" && sha256sum build.log build-provenance.json final-state.json \
    "bin/$(basename "$B")" "bin/$(basename "$BND")" "bin/$(basename "$RED")" > PROVENANCE_SHA256SUMS) \
    || { say "failed to seal build provenance"; exit 5; }
say "finished: $FAILED process(es) failed; $(grep -c PASS "$OUT/reduce.log") of 16 gates pass (see summary.json)"
tail -1 "$OUT/reduce.log" >> "$LOG"
echo done > "$OUT/done"
