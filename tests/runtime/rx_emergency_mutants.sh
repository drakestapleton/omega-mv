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

# R16 G6 operator emergency stop: each guard is load-bearing (pure seeded OM-2).
# Every mutant below removes one guard from a temporary copy of the pure OM-2
# runtime; tests/runtime/rx_emergency.om (compiled with seed/out/omc) must FAIL
# against each one (and PASS against the unmutated copy). A mutant whose pattern
# no longer matches is a failure of this script, never a silent skip.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/rx-estop-mut.XXXXXX")
trap 'rm -rf "$W"' EXIT
OMC=${OMC:-$HERE/seed/out/omc}
[ -x "$OMC" ] || { echo "FAIL missing seeded compiler $OMC"; exit 2; }
SRCS="seed/ng/sha256.om src/runtime/rx_world.om src/runtime/rx_generation.om tests/runtime/rx_emergency.om"

# name|file|perl substitution (applied with -0, must match exactly once)
MUTANTS='M1 caller check ignores the stop|src/runtime/rx_world.om|s/(fn rx_world_caller_check_fn[^\n]*\n  if eq op RW_CALLER_OP_RELEASE\n    ret RW_CALLER_OK\n  end\n  )if ne get rw_w 16 0\n    ret RW_CALLER_ERR_HALTED\n  end/${1}if eq ulong 1 0\n    ret RW_CALLER_ERR_HALTED\n  end/
M2 operator authorize ignores caller secret|src/runtime/rx_world.om|s/(fn rx_world_operator_authorize[^\n]*\n  )if ne rx_world_check_caller subj gen secret RW_CALLER_OK\n    ret RW_ERR_IDENTITY\n  end/${1}if eq ulong 1 0\n    ret RW_ERR_IDENTITY\n  end/
M3 operator authorize ignores control capability|src/runtime/rx_world.om|s/if ne rx_world_validate_cap cap_id cap_gen subj RW_WORLD_RES_CONTROL RW_WORLD_RIGHT_HALT RW_CAP_OK\n    ret RW_ERR_AUTHORITY\n  end/if eq ulong 1 0\n    ret RW_ERR_AUTHORITY\n  end/
M4 duplicate stop not refused|src/runtime/rx_world.om|s/if ne get rw_w 16 0\n    ret RW_HALT_ALREADY\n  end/if eq ulong 1 0\n    ret RW_HALT_ALREADY\n  end/
M5 emergency stop does not latch halted flag|src/runtime/rx_world.om|s/(  put rw_w 22 cid\n  )put rw_w 16 1/${1}put rw_w 16 0/
M6 resume of running world not refused|src/runtime/rx_world.om|s/if eq get rw_w 16 0\n    ret RW_HALT_NOT_STOPPED\n  end/if eq ulong 1 0\n    ret RW_HALT_NOT_STOPPED\n  end/
M7 halt dir accepts dot-dot traversal|src/runtime/rx_world.om|s/(        if eq get path add i 1 46\n          )ret RW_ERR_ARG/${1}ign_dot = ulong 0/
M8 object create allowed under stop|src/runtime/rx_world.om|s/(fn rx_world_create[^\n]*\n  )if ne get rw_w 16 0\n    put rw_w 23 add get rw_w 23 1\n    ret RW_ERR_HALTED\n  end/${1}if eq ulong 1 0\n    ret RW_ERR_HALTED\n  end/
M9 object retire allowed under stop|src/runtime/rx_world.om|s/(fn rx_world_retire[^\n]*\n  )if ne get rw_w 16 0\n    put rw_w 23 add get rw_w 23 1\n    ret RW_ERR_HALTED\n  end/${1}if eq ulong 1 0\n    ret RW_ERR_HALTED\n  end/
M10 outside publication allowed under stop|src/runtime/rx_world.om|s/(fn rx_world_publish_external[^\n]*\n  )if ne get rw_w 16 0\n    put rw_w 23 add get rw_w 23 1\n    ret RW_ERR_HALTED\n  end/${1}if eq ulong 1 0\n    ret RW_ERR_HALTED\n  end/
M11 generation promote ignores held barrier|src/runtime/rx_generation.om|s/(  if lt ci 0\n    ret RX_GEN_ERR_ARG\n  end\n  )if ne get rg_st 5 0\n    ret RX_GEN_ERR_BUSY\n  end/${1}if eq ulong 1 0\n    ret RX_GEN_ERR_BUSY\n  end/'

build_run() { # dir -> exit status of the test
    (cd "$1" && ( echo om2; sed -e '/^om2$/d' -e 's/^export fn /fn /' $SRCS ) | "$OMC" > t && chmod +x t) >"$1/build.log" 2>&1 || { echo "build failed:"; tail -5 "$1/build.log"; return 99; }
    (cd "$1" && timeout 60 ./t) >"$1/run.log" 2>&1
}

copy() { mkdir -p "$1"; (cd "$HERE" && tar -cf - $SRCS) | tar -xf - -C "$1"; }

fails=0
copy "$W/base"
build_run "$W/base"; rc=$?
if [ $rc = 0 ]; then echo "ok   unmutated: PASS"; else echo "FAIL unmutated: exit $rc"; tail -5 "$W/base/run.log"; fails=$((fails + 1)); fi
while IFS='|' read -r name file sub; do
    [ -n "$name" ] || continue
    d="$W/m${name%% *}"
    copy "$d"
    # Count with the same pattern applied globally (s///g returns the number of
    # matches); apply the mutant only when it matches exactly once.
    n=$(perl -0 -e 'my $s = do { local $/; <STDIN> }; my $c = eval "\$s =~ $ARGV[0]g"; die $@ if $@; print $c ? $c + 0 : 0' "$sub" < "$d/$file")
    if [ "$n" != 1 ]; then
        echo "FAIL $name: pattern matched ${n:-?} times (must be 1)"; fails=$((fails + 1)); continue
    fi
    perl -0pi -e "$sub" "$d/$file"
    if cmp -s "$d/$file" "$HERE/$file"; then
        echo "FAIL $name: substitution changed nothing"; fails=$((fails + 1)); continue
    fi
    build_run "$d"; rc=$?
    # Killed means the test ran and at least one check failed; a crash or a
    # timeout without a failed check is not counted as a kill.
    nf=$(grep -c '^\[-\]' "$d/run.log" 2>/dev/null); nf=${nf:-0}
    if [ $rc = 99 ]; then echo "FAIL $name: mutant did not build"; fails=$((fails + 1))
    elif [ $rc != 0 ] && [ "$nf" -gt 0 ]; then echo "ok   $name: killed ($nf checks failed)"
    elif [ $rc != 0 ]; then echo "FAIL $name: exit $rc with no failed check (crash or timeout)"; fails=$((fails + 1))
    else echo "FAIL $name: SURVIVED"; fails=$((fails + 1)); fi
done <<< "$MUTANTS"
if [ $fails = 0 ]; then echo "RX_EMERGENCY_MUTANTS: PASS"; else echo "RX_EMERGENCY_MUTANTS: FAIL ($fails)"; exit 1; fi
