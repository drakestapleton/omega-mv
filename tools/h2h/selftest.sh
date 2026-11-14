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

# selftest.sh -- host-only checks of clock_lock.sh and parity_check.sh against
# a scripted stand-in for nvidia-smi. No GPU, no driver. A PASS here says the
# harness logic is right; it says nothing about what the GB10 driver accepts.
set -u
here=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
fail=0; n=0
ok() { n=$((n + 1)); if [ "$1" = "$2" ]; then echo "ok   $3"; else echo "FAIL $3 (exit $1, want $2)"; fail=1; fi; }
has() { n=$((n + 1)); if grep -q -- "$2" "$1"; then echo "ok   $3"; else echo "FAIL $3 (no '$2' in $1)"; fail=1; fi; }

# Stand-in nvidia-smi. State in $FAKE: "clock" (current MHz), "locked" (0/1),
# "calls" (argument log). FAKE_MODE: ok | refuse (-lgc fails) | na (clock not
# readable) | ignore (-lgc accepted, clock stays floating) | drift (the clock
# moves after the second read while locked).
cat >"$T/nvidia-smi" <<'EOF'
#!/bin/sh
echo "$*" >>"$FAKE/calls"
mode=${FAKE_MODE:-ok}
case "$*" in
*-lgc*)
    [ "$mode" = refuse ] && { echo "Setting locked GPU clocks is not supported for GPU 00000000:01:00.0."; exit 3; }
    f=${*##*-lgc }; f=${f%%,*}
    [ "$mode" = ignore ] || echo "$f" >"$FAKE/clock"
    echo 1 >"$FAKE/locked"; echo 0 >"$FAKE/reads"; echo "GPU clocks set"; exit 0 ;;
*-rgc*) echo 0 >"$FAKE/locked"; echo 900 >"$FAKE/clock"; echo "All done."; exit 0 ;;
*clocks.current.graphics*)
    [ "$mode" = na ] && { echo "[N/A]"; exit 0; }
    r=$(($(cat "$FAKE/reads" 2>/dev/null || echo 0) + 1)); echo "$r" >"$FAKE/reads"
    if [ "$mode" = drift ] && [ "$(cat "$FAKE/locked")" = 1 ] && [ "$r" -gt 2 ]; then echo 1100; else cat "$FAKE/clock"; fi ;;
*clocks.max.graphics*) echo 2400 ;;
*power.draw*) echo 61.50 ;;
*temperature.gpu*) echo 58 ;;
*pstate*) echo P0 ;;
esac
EOF
chmod +x "$T/nvidia-smi"
run() { # run <mode> <name> <args...>: fresh state, returns clock_lock's status
    FAKE="$T/$2"; mkdir -p "$FAKE"; echo 900 >"$FAKE/clock"; echo 0 >"$FAKE/locked"; : >"$FAKE/calls"
    mode=$1; shift 2
    FAKE="$FAKE" FAKE_MODE=$mode NVSMI="$T/nvidia-smi" H2H_SETTLE_S=0 sh "$here/clock_lock.sh" "$@" >"$FAKE/out" 2>&1
}

run ok held run 2000 "$T/held/o" -- sh -c 'exit 0';            ok $? 0 "held: locked run exits 0"
has "$T/held/o/clock-lock.txt" "lock LOCKED target_mhz=2000"   "held: lock recorded"
has "$T/held/o/clock-lock.txt" "release OK"                    "held: released"
ok "$(cat "$T/held/locked")" 0                                 "held: clock unlocked afterwards"
ok "$(grep -c 'check HELD' "$T/held/o/clock-lock.txt")" 2      "held: checked before and after"

run ok max run max "$T/max/o" -- true;                         ok $? 0 "max: target from clocks.max.graphics"
has "$T/max/o/clock-lock.txt" "target_mhz=2400"                "max: 2400 MHz"

run ok status run 2000 "$T/status/o" -- sh -c 'exit 7';        ok $? 7 "command status is passed through"
ok "$(cat "$T/status/locked")" 0                               "command failure still releases"

echo 0 >"$T/ran"
run refuse refuse run 2000 "$T/refuse/o" -- sh -c "echo 1 >$T/ran"; ok $? 3 "refused lock exits 3"
ok "$(cat "$T/ran")" 0                                         "refused lock: command never started"
has "$T/refuse/o/clock-lock.txt" "lock REFUSED"                "refused lock recorded"

run na na run 2000 "$T/na/o" -- sh -c "echo 1 >$T/ran";        ok $? 3 "unreadable clock exits 3"
ok "$(cat "$T/ran")" 0                                         "unreadable clock: command never started"
ok "$(cat "$T/na/locked")" 0                                   "unreadable clock: lock released"

run ignore ignore run 2000 "$T/ignore/o" -- sh -c "echo 1 >$T/ran"; ok $? 3 "lock accepted but not held exits 3"
ok "$(cat "$T/ran")" 0                                         "not held: command never started"
has "$T/ignore/o/clock-lock.txt" "lock NOT_HELD target_mhz=2000 read_mhz=900" "not held recorded"

run drift drift run 2000 "$T/drift/o" -- sh -c 'exit 0';       ok $? 4 "drift during the run exits 4"
has "$T/drift/o/clock-lock.txt" "check DRIFTED"                "drift recorded"
ok "$(cat "$T/drift/locked")" 0                                "drift: lock released"

run ok sig run 2000 "$T/sig/o" -- sh -c 'kill -TERM $PPID; sleep 0.2'; ok $? 130 "TERM exits 130"
ok "$(cat "$T/sig/locked")" 0                                  "TERM: lock released"

run ok usage run 2000 "$T/usage/o" true;                       ok $? 2 "missing -- is a usage error"
ok "$(wc -l <"$T/usage/calls" | tr -d ' ')" 0                  "usage error touches nothing"

# parity_check.sh
decl() { cat >"$1" <<EOF
engine=$2
engine_commit=0123abc
weights_format=$3
weights_sha256=$4
source_checkpoint_sha256=aa11
weights_dtype=$5
activation_dtype=f16
kv_cache_dtype=$6
tokenizer_sha256=bb22
bos=none
chat_template_applied_by=harness
prompt_set_sha256=cc33
prompt_token_counts_sha256=$7
output_tokens=128
sampler=greedy
context_tokens=8192
EOF
}
decl "$T/a.decl" omega safetensors s1 f16 f16 dd44
decl "$T/b.decl" llama.cpp gguf g1 F16 f16 dd44
sh "$here/parity_check.sh" "$T/a.decl" "$T/b.decl" >"$T/p1" 2>&1;  ok $? 0 "parity: same work, case-insensitive"
decl "$T/c.decl" llama.cpp gguf g2 q4_k_m f16 dd44
sh "$here/parity_check.sh" "$T/a.decl" "$T/c.decl" >"$T/p2" 2>&1;  ok $? 1 "parity: Q4_K_M against F16 is different work"
has "$T/p2" "DIFFERENT weights_dtype: f16 | q4_k_m"            "parity: names the differing field"
decl "$T/d.decl" omega safetensors s1 f16 fp8 dd44
sh "$here/parity_check.sh" "$T/d.decl" "$T/b.decl" >"$T/p3" 2>&1;  ok $? 1 "parity: KV cache dtype counts"
decl "$T/e.decl" llama.cpp gguf g1 f16 f16 ee55
sh "$here/parity_check.sh" "$T/a.decl" "$T/e.decl" >"$T/p4" 2>&1;  ok $? 1 "parity: prompt token counts count"
decl "$T/f.decl" llama.cpp gguf g1 f16 default dd44
sh "$here/parity_check.sh" "$T/a.decl" "$T/f.decl" >"$T/p5" 2>&1;  ok $? 3 "parity: 'default' is not a declaration"
grep -v '^bos=' "$T/b.decl" >"$T/g.decl"
sh "$here/parity_check.sh" "$T/a.decl" "$T/g.decl" >"$T/p6" 2>&1;  ok $? 3 "parity: a missing key is incomplete"
sh "$here/parity_check.sh" "$T/a.decl" >"$T/p7" 2>&1;              ok $? 2 "parity: usage"

if [ "$fail" -eq 0 ]; then echo "h2h selftest: PASS ($n checks, host only, scripted nvidia-smi)"; else echo "h2h selftest: FAIL"; fi
exit "$fail"
