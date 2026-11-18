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

# omega_gate_wiring.sh: aienux is folded into omega-mv as kernel/ (Drake 2026-11-17), so its gates run
# only if omega-mv's judge can select them. This checks, statically and in seconds, that every gate
# aienux had (the 25 manifests of aienux 1f12818d) and every step of kernel/tests/gates/run.sh is
# either
#   - wired: tests/gates/omega-kernel-<step>.gate names gate OMEGA-KERNEL-<STEP>, runs
#     tests/gates/run.sh with args ["kernel-<step>"], lists inputs that are all tracked paths, one at
#     least under kernel/; the first arm of tests/gates/run.sh that matches kernel-<step> runs
#     kernel/tests/gates/run.sh, and the first arm there that matches <step> is not the unknown-step
#     arm; or
#   - listed in kernel/MIGRATION.md, section "Aienux gates without a manifest", with a reason;
# never both. It also checks that .aien/always keeps aienux's always-run gates (crypto-boundary as
# OMEGA-KERNEL-CRYPTO-BOUNDARY; zero-disk-secrets as omega-mv's OMEGA-ZERO-DISK-SECRETS) and this
# check itself, and that no omega-kernel-*.gate names a step the kernel runner does not have.
# It runs no gate: whether a wired gate passes is that gate's job.
#
# Usage: omega_gate_wiring.sh             check this checkout; exit 0 PASS, 1 FAIL
#        omega_gate_wiring.sh --self-test check this checkout, then the mutant controls below must
#                                         each FAIL, and omega-mv's zero-disk-secrets step, which
#                                         replaces aienux's, must fail on a scratch repository for
#                                         each .env file planted under kernel/ (the run fails if one
#                                         passes)
# No `producer | grep -q`: under pipefail grep's early exit can fail the producer (SIGPIPE).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# The gates of aienux 1f12818d (tests/gates/aienos-<step>.gate there; kernel/tests/gates/ here).
AIENUX_GATES="ck-b7b-probe ck-gate-selftest ck-hold-selftest ck-host-tests ck-owner-keys
  ck-qemu-external ck-qemu-gates ck-stage-tests crypto-boundary disk-qemu hw-gates infer-crate
  infer-forward native-argus native-capability native-crypto native-disk native-m5 native-net
  native-sig omega-nvme store-native tcp-corpus verify-all zero-disk-secrets"
# Steps of tests/gates/run.sh (omega-mv root) that are not kernel runner steps.
ROOT_ONLY="make-test gate-wiring"
ALWAYS="OMEGA-KERNEL-CRYPTO-BOUNDARY OMEGA-ZERO-DISK-SECRETS OMEGA-KERNEL-GATE-WIRING"

# arms FILE: one line per top-level arm of the `case "$step" in` block: "<arm no> <pattern>",
# then the arm body is read by arm_body.
arms() {
  awk '/^case "\$step" in/ {on=1; next} on && /^esac/ {exit}
       on && /^  [^ #][^)]*\)/ { n++; lab=$0; sub(/^  /, "", lab); sub(/\).*/, "", lab);
         k=split(lab, p, "|"); for (i=1;i<=k;i++) print n, p[i] }' "$1"
}
# arm_body FILE N: the text of arm N, from its label line to the line that ends it with ;;.
arm_body() {
  awk -v want="$2" '/^case "\$step" in/ {on=1; next} on && /^esac/ {exit}
       on && /^  [^ #][^)]*\)/ { n++ } on && n==want { print; if ($0 ~ /;;[[:space:]]*(#.*)?$/) exit }' "$1"
}
# first_arm ARMS WORD: from the output of arms, the number and pattern of the first arm whose
# pattern matches WORD.
first_arm() {
  local n pat
  while read -r n pat; do
    # shellcheck disable=SC2053
    if [[ $2 == $pat ]]; then echo "$n $pat"; return 0; fi
  done <<< "$1"
  return 1
}
# field TEXT KEY: the value of the first uncommented "KEY: value" line of a manifest's text.
field() {
  local l
  while IFS= read -r l; do
    if [[ $l =~ ^[[:space:]]*$2:[[:space:]]*(.*)$ ]]; then printf '%s' "${BASH_REMATCH[1]}"; return; fi
  done <<< "$1"
}
# inputs_of TEXT: the entries of a manifest's inputs: list.
inputs_of() {
  local l on=0
  while IFS= read -r l; do
    if [[ $l == inputs: ]]; then on=1
    elif [ "$on" = 1 ] && [[ $l == "  - "* ]]; then printf '%s\n' "${l#  - }"
    elif [ "$on" = 1 ] && [[ $l =~ ^[^\ ] ]]; then return
    fi
  done <<< "$1"
}

# check CFG TREE: CFG holds the files under test (tests/gates/*.gate, tests/gates/run.sh,
# kernel/tests/gates/run.sh, kernel/MIGRATION.md, .aien/always); TREE is the checkout whose tracked
# paths the inputs must name. Prints one FAIL line per problem and the totals; returns 1 on any FAIL.
check() {
  local cfg="$1" tree="$2" fails=0 wired=0 listed=0 s m n pat body p up exempt steps tracked wanted
  local root_rs="$cfg/tests/gates/run.sh" kern_rs="$cfg/kernel/tests/gates/run.sh" mig="$cfg/kernel/MIGRATION.md"
  local root_arms kern_arms mt
  fail() { echo "FAIL $*"; fails=$((fails + 1)); }
  tracked="$TRACKED"; wanted="$(mktemp)"
  [ -s "$root_rs" ] || fail "no tests/gates/run.sh"
  [ -s "$kern_rs" ] || fail "no kernel/tests/gates/run.sh"
  # MIGRATION.md rows: | `step` | ... | reason |
  exempt="$(awk '/^##+ / {on = ($0 ~ /^#+ Aienux gates without a manifest$/)} on && /^\| `[a-z0-9-]+` \|/ {
      line=$0; s=line; sub(/^\| `/, "", s); sub(/`.*/, "", s); r=line; sub(/[[:space:]]*\|[[:space:]]*$/, "", r); sub(/.*\|[[:space:]]*/, "", r);
      if (r != "" && r != "-") print s; else print s " NO-REASON" }' "$mig" 2>/dev/null)"
  while read -r s m; do [ -n "$s" ] && [ "$m" = NO-REASON ] && fail "MIGRATION.md lists $s without a reason"; done <<< "$exempt"
  exempt="$(printf '%s\n' "$exempt" | awk '{print $1}')"
  root_arms="$(arms "$root_rs")"; kern_arms="$(arms "$kern_rs")"
  # Steps: aienux's 25 plus every kernel runner arm pattern that is a plain word.
  steps="$(printf '%s\n' $AIENUX_GATES; awk '$2 ~ /^[a-z0-9-]+$/ {print $2}' <<< "$kern_arms")"
  steps="$(printf '%s\n' "$steps" | sort -u)"
  for s in $steps; do
    if read -r n pat < <(first_arm "$kern_arms" "$s") && [ "$pat" != '*' ]; then :; else
      fail "$s: kernel/tests/gates/run.sh has no step $s (only its unknown-step arm matches)"
    fi
    m="$cfg/tests/gates/omega-kernel-$s.gate"
    if grep -qx -- "$s" <<< "$exempt"; then
      if [ -e "$m" ]; then fail "$s: both wired (tests/gates/omega-kernel-$s.gate) and listed in MIGRATION.md"; else listed=$((listed + 1)); fi
      continue
    fi
    if [ ! -f "$m" ]; then fail "$s: no tests/gates/omega-kernel-$s.gate and no MIGRATION.md row"; continue; fi
    up="${s^^}"; mt="$(<"$m")"
    [ "$(field "$mt" gate)" = "OMEGA-KERNEL-$up" ] || fail "$s: manifest gate is '$(field "$mt" gate)', not OMEGA-KERNEL-$up"
    [ "$(field "$mt" exec)" = "tests/gates/run.sh" ] || fail "$s: manifest exec is '$(field "$mt" exec)', not tests/gates/run.sh"
    [ "$(field "$mt" args)" = "[\"kernel-$s\"]" ] || fail "$s: manifest args are '$(field "$mt" args)', not [\"kernel-$s\"]"
    n=0; local inkern=0
    while IFS= read -r p; do
      n=$((n + 1))
      case "$p" in kernel/*) inkern=1 ;; esac
      printf '%s\t%s\n' "$s" "$p" >> "$wanted"
    done < <(inputs_of "$mt")
    [ "$n" -gt 0 ] || fail "$s: manifest lists no inputs"
    [ "$inkern" = 1 ] || fail "$s: manifest lists no input under kernel/"
    if read -r n pat < <(first_arm "$root_arms" "kernel-$s"); then
      body="$(arm_body "$root_rs" "$n")"
      grep -q 'kernel/tests/gates/run\.sh' <<< "$body" \
        || fail "$s: the first arm of tests/gates/run.sh matching kernel-$s ('$pat') does not run kernel/tests/gates/run.sh"
    else
      fail "$s: no arm of tests/gates/run.sh matches kernel-$s"
    fi
    wired=$((wired + 1))
  done
  # Every input names a tracked file, or (ending in /) a directory holding one: one pass.
  while IFS= read -r p; do fail "$p"; done < <(awk -F '\t' '
      NR == FNR { f[$0] = 1; n = split($0, c, "/"); d = ""; for (i = 1; i < n; i++) { d = d c[i] "/"; f[d] = 1 } next }
      !($2 in f) { print $1 ": input " $2 " is no tracked " ($2 ~ /\/$/ ? "directory" : "file") }' "$tracked" "$wanted")
  # This check's own wiring.
  m="$cfg/tests/gates/omega-kernel-gate-wiring.gate"
  mt="$(cat "$m" 2>/dev/null)"
  if [ -f "$m" ] && [ "$(field "$mt" gate)" = OMEGA-KERNEL-GATE-WIRING ] && [ "$(field "$mt" exec)" = tests/gates/run.sh ] \
     && [ "$(field "$mt" args)" = '["kernel-gate-wiring"]' ]; then :; else fail "gate-wiring: tests/gates/omega-kernel-gate-wiring.gate missing or not wired"; fi
  if read -r n pat < <(first_arm "$root_arms" kernel-gate-wiring); then
    grep -q 'kernel/scripts/omega_gate_wiring\.sh' <<< "$(arm_body "$root_rs" "$n")" \
      || fail "gate-wiring: the first arm of tests/gates/run.sh matching kernel-gate-wiring ('$pat') does not run kernel/scripts/omega_gate_wiring.sh"
  else fail "gate-wiring: no arm of tests/gates/run.sh matches kernel-gate-wiring"; fi
  # No manifest for a step nobody runs.
  for m in "$cfg"/tests/gates/omega-kernel-*.gate; do
    [ -e "$m" ] || continue
    s="${m##*/omega-kernel-}"; s="${s%.gate}"
    grep -qx -- "$s" <<< "$(printf '%s\n' $steps $ROOT_ONLY)" || fail "tests/gates/omega-kernel-$s.gate names no step of kernel/tests/gates/run.sh"
  done
  # Always-run gates.
  for p in $ALWAYS; do
    grep -qx -- "$p" "$cfg/.aien/always" 2>/dev/null || fail ".aien/always does not list $p"
    grep -lx -- "gate: $p" "$cfg"/tests/gates/*.gate > /dev/null 2>&1 || fail ".aien/always gate $p has no manifest"
  done
  rm -f "$wanted"
  echo "OMEGA-KERNEL-GATE-WIRING: steps=$(printf '%s\n' $steps | wc -l) wired=$wired listed=$listed always=$(printf '%s\n' $ALWAYS | wc -l) fail=$fails"
  [ "$fails" = 0 ]
}

# copy_cfg DIR: the files check reads, copied from this checkout.
copy_cfg() {
  mkdir -p "$1/tests/gates" "$1/kernel/tests/gates" "$1/.aien"
  cp "$ROOT"/tests/gates/*.gate "$ROOT/tests/gates/run.sh" "$1/tests/gates/"
  cp "$ROOT/kernel/tests/gates/run.sh" "$1/kernel/tests/gates/"
  cp "$ROOT/kernel/MIGRATION.md" "$1/kernel/"
  cp "$ROOT/.aien/always" "$1/.aien/"
}

self_test() {
  local tmp d name rc killed=0 survived=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/gate-wiring.XXXXXX")"
  # mutant NAME SHELL-SNIPPET REGEX: the snippet runs in a fresh copy; check must then FAIL with a
  # FAIL line matching REGEX (the failure the mutant was made for, not some other one).
  mutant() {
    d="$tmp/$1"; copy_cfg "$d"
    (c="$d"; cd "$d" && eval "$2") || { echo "control $1: could not build the mutant"; survived=$((survived + 1)); return; }
    rc=0; check "$d" "$ROOT" > "$d.log" 2>&1 || rc=$?
    if [ "$rc" != 0 ] && grep -qE -- "^FAIL .*$3" "$d.log"; then
      killed=$((killed + 1)); echo "control $1: FAIL as required ($(grep -m1 -E -- "^FAIL .*$3" "$d.log"))"
    else
      survived=$((survived + 1)); echo "control $1: exit $rc without a FAIL line matching '$3'; the check misses it"
      grep '^FAIL ' "$d.log" | head -n 3
    fi
  }
  M=tests/gates/omega-kernel-native-crypto.gate
  mutant remove-manifest          "rm $M" 'native-crypto: no tests/gates/omega-kernel-native-crypto\.gate'
  mutant remove-always-gate       "rm tests/gates/omega-kernel-crypto-boundary.gate" 'crypto-boundary: no tests/gates/omega-kernel-crypto-boundary\.gate'
  mutant rename-manifest          "mv $M $M.disabled" 'native-crypto: no tests/gates/omega-kernel-native-crypto\.gate'
  mutant args-other-step          "sed -i 's/kernel-native-crypto/kernel-native-sig/' $M" 'native-crypto: manifest args'
  mutant args-commented           "sed -i 's/^  args:/#  args:/' $M" 'native-crypto: manifest args'
  mutant gate-name                "sed -i 's/^gate: .*/gate: OMEGA-KERNEL-NATIVECRYPTO/' $M" 'native-crypto: manifest gate'
  mutant exec-bypass-root         "sed -i 's#exec: tests/gates/run.sh#exec: kernel/tests/gates/run.sh#' $M" 'native-crypto: manifest exec'
  mutant input-unprefixed         "sed -i 's#^  - kernel/native/crypto/#  - native/crypto/#' $M" 'native-crypto: input native/crypto/ is no tracked'
  mutant inputs-none-in-kernel    "sed -i '/^  - kernel\\//d' $M" 'native-crypto: manifest lists no input under kernel/'
  mutant root-arm-shadows         "awk '{print} /^case \"\\\$step\" in/ {print \"  kernel-native-crypto) echo skipped ;;\"}' tests/gates/run.sh > x && mv x tests/gates/run.sh" 'native-crypto: the first arm of tests/gates/run\.sh'
  mutant root-arm-removed         "sed -i '/^  kernel-\\*)/d' tests/gates/run.sh" 'native-crypto: the first arm of tests/gates/run\.sh'
  mutant kernel-step-removed      "sed -i 's/^  native-crypto)/  native-crypto-old)/' kernel/tests/gates/run.sh" 'native-crypto: kernel/tests/gates/run\.sh has no step'
  mutant kernel-step-added        "awk '{print} /^case \"\\\$step\" in/ {print \"  brand-new-gate) true ;;\"}' kernel/tests/gates/run.sh > x && mv x kernel/tests/gates/run.sh" 'brand-new-gate: no tests/gates/omega-kernel-brand-new-gate\.gate'
  mutant always-dropped           "sed -i '/^OMEGA-KERNEL-CRYPTO-BOUNDARY\$/d' .aien/always" 'always does not list OMEGA-KERNEL-CRYPTO-BOUNDARY'
  mutant migration-row-dropped    "sed -i '/^| \`zero-disk-secrets\` |/d' kernel/MIGRATION.md" 'zero-disk-secrets: no tests/gates/omega-kernel-zero-disk-secrets\.gate'
  mutant migration-and-manifest   "sed -i '/^| \`zero-disk-secrets\` |/p; s/^| \`zero-disk-secrets\` |/| \`native-crypto\` |/' kernel/MIGRATION.md" 'native-crypto: both wired'
  mutant migration-no-reason      "sed -i 's/^\\(| \`zero-disk-secrets\` |.*|\\) [^|]*|\$/\\1 - |/' kernel/MIGRATION.md" 'MIGRATION\.md lists zero-disk-secrets without a reason'
  mutant wiring-manifest-removed  "rm tests/gates/omega-kernel-gate-wiring.gate" 'gate-wiring: tests/gates/omega-kernel-gate-wiring\.gate missing'
  mutant orphan-manifest          "cp $M tests/gates/omega-kernel-nonesuch.gate" 'omega-kernel-nonesuch\.gate names no step'
  # Aienux's AIENOS-ZERO-DISK-SECRETS is replaced by omega-mv's zero-disk-secrets step
  # (kernel/MIGRATION.md). That step, run on a scratch repository holding only tests/gates/run.sh
  # and kernel/README.md, must pass; with a .env file planted under kernel/ it must fail: where
  # aienux's check looked (untracked at the top of kernel/, tracked in a suite) and where it did
  # not (deeper than its -maxdepth 4, under vendor/ and target/, which it skipped).
  secret_run() {  # NAME [PLANT [track]]: sets rc, log in $tmp/secret-NAME.log
    d="$tmp/secret-$1"; mkdir -p "$d/tests/gates" "$d/kernel"
    cp "$ROOT/tests/gates/run.sh" "$d/tests/gates/"; echo kernel > "$d/kernel/README.md"
    git -C "$d" init -q && git -C "$d" add -A && git -C "$d" -c user.name=t -c user.email=t@t commit -qm base
    if [ -n "${2:-}" ]; then
      mkdir -p "$d/$(dirname "$2")"; echo 'TOKEN=planted-by-gate-wiring-control' > "$d/$2"
      [ "${3:-}" != track ] || { git -C "$d" add -f -- "$2" && git -C "$d" -c user.name=t -c user.email=t@t commit -qm plant; }
    fi
    rc=0; (cd "$d" && bash tests/gates/run.sh zero-disk-secrets) > "$d.log" 2>&1 || rc=$?
  }
  secret_run clean
  if [ "$rc" = 0 ] && grep -qx 'AIEN-OBS env_files_found false' "$tmp/secret-clean.log"; then
    echo "control secret-clean: zero-disk-secrets exit 0 on the scratch repository without a plant"
  else
    survived=$((survived + 1)); echo "control secret-clean: exit $rc without a plant; the secret controls below prove nothing"
  fi
  for name in untracked:kernel/.env tracked:kernel/native/crypto/.env.local deep:kernel/a/b/c/d/e/.env \
              vendor:kernel/vendor/x/.env target:kernel/target/.env.production; do
    secret_run "${name%%:*}" "${name#*:}" "$( [ "${name%%:*}" = tracked ] && echo track )"
    if [ "$rc" = 1 ] && grep -qx 'AIEN-OBS env_files_found true' "$tmp/secret-${name%%:*}.log"; then
      killed=$((killed + 1)); echo "control secret-${name%%:*} (${name#*:}): zero-disk-secrets FAIL as required"
    else
      survived=$((survived + 1)); echo "control secret-${name%%:*} (${name#*:}): zero-disk-secrets exit $rc; the planted file was missed"
    fi
  done
  rm -rf "$tmp"
  echo "gate-wiring controls: $killed failed as required, $survived passed"
  [ "$survived" = 0 ]
}

mode="${1:-}"
case "$mode" in
  ""|--self-test) ;;
  *) echo "usage: $0 [--self-test]" >&2; exit 2 ;;
esac
# The tracked paths of this checkout, listed once: every manifest input must name one.
TRACKED="$(mktemp)"; trap 'rm -f "$TRACKED"' EXIT
git -C "$ROOT" ls-files > "$TRACKED" || { echo "OMEGA-KERNEL-GATE-WIRING: FAIL cannot list the tracked files"; exit 1; }
rc=0; check "$ROOT" "$ROOT" || rc=$?
if [ "$mode" = --self-test ]; then
  st=0; self_test || st=$?
  [ "$st" = 0 ] || { echo "OMEGA-KERNEL-GATE-WIRING SELF-TEST: FAIL"; exit 1; }
  echo "OMEGA-KERNEL-GATE-WIRING SELF-TEST: PASS"
fi
[ "$rc" = 0 ] || { echo "OMEGA-KERNEL-GATE-WIRING: FAIL"; exit 1; }
echo "OMEGA-KERNEL-GATE-WIRING: PASS"
