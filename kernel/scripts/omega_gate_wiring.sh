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
# only if omega-mv's judge can select them. This checks, in seconds, that every gate aienux had (the
# 25 manifests of aienux 1f12818d), the steps omega-mv added (make-test, gate-wiring, spinlock) and
# every step of kernel/tests/gates/run.sh is either wired or listed, never both [ctl:OMEGA-KERNEL-GATE-WIRING/remove-manifest]
# [ctl:OMEGA-KERNEL-GATE-WIRING/kernel-step-added] [ctl:OMEGA-KERNEL-GATE-WIRING/migration-and-manifest] [ctl:OMEGA-KERNEL-GATE-WIRING/make-test-manifest-removed]:
#   - wired: tests/gates/omega-kernel-<step>.gate, read with the judge's manifest grammar (below), names
#     gate OMEGA-KERNEL-<STEP>, runs tests/gates/run.sh with args ["kernel-<step>"], expects exit 0 and
#     verdict PASS, requires only host, qemu, portable or aarch64, and lists inputs that are tracked
#     paths covering every path its kernel runner arm names (below) [ctl:OMEGA-KERNEL-GATE-WIRING/requires-gb10]
#     [ctl:OMEGA-KERNEL-GATE-WIRING/expects-exit-1] [ctl:OMEGA-KERNEL-GATE-WIRING/inputs-readme-only];
#   - listed: a row with a reason in kernel/MIGRATION.md, section "Aienux gates without a manifest".
#
# How the two runners route a step is decided by bash, not by reading their text:
#   - kernel/tests/gates/run.sh: `bash -n`, then its case patterns as bash itself prints them
#     (declare -f of the file as a function body, so indentation, comments and line breaks in the
#     source do not matter), then a dry run of each step: bash runs the file with a DEBUG trap that
#     executes just the `case "$step"` statement and the arm's `need` call and records each other
#     command the arm would start [ctl:OMEGA-KERNEL-GATE-WIRING/kernel-step-indented] [ctl:OMEGA-KERNEL-GATE-WIRING/kernel-step-underscore]. The arm must
#     not be the unknown-step arm, must start with `need` (its tool list is read from it) and its
#     manifest's inputs must cover each tracked path the arm's commands name (a word that is a path
#     under kernel/, or crates/NAME for cargo's -p NAME);
#   - tests/gates/run.sh: each kernel-<step> is run in a scratch copy where kernel/tests/gates/run.sh,
#     kernel/scripts/omega_gate_wiring.sh and make are stubs that record their arguments and then exit
#     0, 1, 3 or 127 or print a NOT_RUN, SKIP, control-report or FAIL-with-NOT_RUN line. The step must
#     reach exactly one stub with the right arguments, and its exit must be what kernel_step promises
#     for each case (0, 1, 3, 3, 3, 3, 3, 3, 0, 0, 1). A gate's tests/gates/controls/<GATE>.controls is
#     probed too: a stub that omits a listed CONTROL line must give exit 1. The `kernel` aggregate must
#     run exactly KERNEL_AGGREGATE, in order.
# It also checks that .aien/always keeps the always-run gates in ALWAYS, each with a manifest, that no
# two manifests under tests/gates/ share a gate name, and that no omega-kernel-*.gate names a step
# the runners do not have [ctl:OMEGA-KERNEL-GATE-WIRING/always-anchor-dropped] [ctl:OMEGA-KERNEL-GATE-WIRING/gate-name-twice] [ctl:OMEGA-KERNEL-GATE-WIRING/orphan-manifest].
# It runs no gate: whether a wired gate passes is that gate's job.
#
# Usage: omega_gate_wiring.sh             check this checkout; exit 0 PASS, 1 FAIL
#        omega_gate_wiring.sh --self-test check this checkout, then: each mutant control below must
#                                         FAIL; each step, run with each tool of its `need` list
#                                         removed from PATH, must exit 3 (NOT_RUN); and omega-mv's
#                                         zero-disk-secrets step must fail on a scratch repository for
#                                         each .env file planted under kernel/
# Each control that does what it must prints "CONTROL OMEGA-KERNEL-GATE-WIRING/<name> FAILED_AS_REQUIRED".
# No `producer | grep -q`: under pipefail grep's early exit can fail the producer (SIGPIPE).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# The gates of aienux 1f12818d (tests/gates/aienos-<step>.gate there; kernel/tests/gates/ here).
AIENUX_GATES="ck-b7b-probe ck-gate-selftest ck-hold-selftest ck-host-tests ck-owner-keys
  ck-qemu-external ck-qemu-gates ck-stage-tests crypto-boundary disk-qemu hw-gates infer-crate
  infer-forward native-argus native-capability native-crypto native-disk native-m5 native-net
  native-sig omega-nvme store-native tcp-corpus verify-all zero-disk-secrets"
# Steps omega-mv added; each must stay wired like the others.
OMEGA_STEPS="make-test gate-wiring spinlock"
# Steps tests/gates/run.sh routes itself (kernel_step), with what the stub must see, and the paths
# their manifests must list.
ROOT_ROUTED="make-test gate-wiring"
root_route() { case "$1" in make-test) echo "make -C kernel/native/kernel test" ;; gate-wiring) echo "wiring --self-test" ;; *) echo "kernel-runner $1" ;; esac; }
root_paths() { case "$1" in make-test) echo "kernel/native/kernel/" ;; gate-wiring) echo "kernel/scripts/omega_gate_wiring.sh kernel/MIGRATION.md .aien/always" ;; esac; }
KERNEL_AGGREGATE="make-test ck-host-tests hw-gates omega-nvme tcp-corpus spinlock"
ALWAYS="OMEGA-EVIDENCE-IMMUTABLE OMEGA-ZERO-DISK-SECRETS OMEGA-KERNEL-CRYPTO-BOUNDARY OMEGA-KERNEL-GATE-WIRING OMEGA-GATE-ANCHOR OMEGA-GATE-CLAIMS"
REQUIRES_OK="host qemu portable aarch64"
# The judge's top-level keys (aien-sovereign-core-mv tools/aien-test/src/manifest.rs, KNOWN).
KNOWN_KEYS="listed outside_inputs target_lock gate manifest_version owner requires depends_on inputs build run prepare expects timeout mutants checks cache exactness tolerance backends fallback cache_scope oracle"

# manifest_read FILE: the manifest as "key<TAB>value", "key[]<TAB>item" and "key.child<TAB>value"
# lines, read with the grammar of the judge's parser (aien-sovereign-core-mv
# tools/aien-test/src/manifest.rs at 94979bab4, parse and parse_entries): no CR, tab or BOM, at most
# 16 KiB and 200 lines; blank and #-comment lines skipped; "  - item", "  child: value" and "key: value"
# or "key:" lines, nothing else; duplicate keys, duplicate child keys, a key with two value shapes and
# a key outside the judge's list are errors. A scalar ends at " #"; a value starting with [ must be a
# one-line JSON array of strings, kept as written. Any error prints "ERROR <line>: <why>" and returns 1.
manifest_read() {
  local f="$1"
  [ "$(wc -c < "$f")" -le 16384 ] || { echo "ERROR 0: larger than 16 KiB"; return 1; }
  LC_ALL=C awk -v known=" $KNOWN_KEYS " '
    function bad(m) { print "ERROR " NR ": " m; err = 1; exit 1 }
    function val(s) {
      if (s ~ /^\[/) { if (s !~ /^\[("([^"\\]|\\.)*"(, *"([^"\\]|\\.)*")*)?\]$/) bad("list must be a one-line JSON array of strings"); return s }
      if (s ~ /^"/) { if (s !~ /^"([^"\\]|\\.)*"$/) bad("bad quoted string"); return s }
      i = index(s, " #"); if (i) s = substr(s, 1, i - 1); sub(/ +$/, "", s)
      if (s == "") bad("empty value"); return s
    }
    function key(s,   i, k, r) {
      i = index(s, ":"); if (!i) bad("expected KEY: or an item line")
      k = substr(s, 1, i - 1); r = substr(s, i + 1)
      if (k !~ /^[a-z][a-z0-9_]*$/) bad("invalid key")
      K = k; V = ""; HASV = 0
      if (r == "") return
      if (substr(r, 1, 1) != " ") bad("space required after colon")
      r = substr(r, 2); if (substr(r, 1, 1) == " ") bad("extra space after colon")
      V = val(r); HASV = 1
    }
    NR == 1 && substr($0, 1, 3) == "\357\273\277" { bad("BOM not allowed") }
    /\r/ { bad("CR not allowed") }
    /\t/ { bad("tab not allowed") }
    NR > 200 { bad("longer than 200 lines") }
    {
      raw = $0; sub(/ +$/, "", raw); t = raw; sub(/^ +/, "", t)
      if (t == "" || substr(t, 1, 1) == "#") next
      if (substr(raw, 1, 4) == "  - ") {
        r = substr(raw, 5); if (substr(r, 1, 1) == " ") bad("extra space after dash")
        if (cur == "") bad("item line before any key")
        v = val(r); if (v ~ /^\[/) bad("list item must be a scalar")
        items[cur]++; out[++n] = cur "[]\t" v
      } else if (substr(raw, 1, 2) == "  ") {
        r = substr(raw, 3); if (substr(r, 1, 1) == " ") bad("indentation deeper than two spaces")
        if (cur == "") bad("child line before any key")
        key(r); if (!HASV) bad("child key needs a value")
        if ((cur "." K) in kids) bad("duplicate child key " cur "." K)
        kids[cur "." K] = 1; nk[cur]++; out[++n] = cur "." K "\t" V
      } else if (substr(raw, 1, 1) == " ") {
        bad("one-space indentation")
      } else {
        key(raw)
        if (K in seen) bad("duplicate key " K)
        if (index(known, " " K " ") == 0) bad("unknown key " K)
        seen[K] = 1; cur = K; sc[K] = HASV
        if (HASV) out[++n] = K "\t" V
      }
    }
    END {
      if (err) exit 1
      for (k in seen) if (sc[k] + (items[k] > 0) + (nk[k] > 0) > 1) { print "ERROR 0: key " k " mixes value shapes"; exit 1 }
      for (i = 1; i <= n; i++) print out[i]
    }' "$f"
}
# mget TEXT KEY: the value of KEY ("gate", "run.exec", ...) in manifest_read output; mlist TEXT KEY: its items.
mget() { awk -F '\t' -v k="$2" '$1 == k {print $2; exit}' <<< "$1"; }
mlist() { awk -F '\t' -v k="$2[]" '$1 == k {print $2}' <<< "$1"; }

# case_patterns FILE: "<arm no> <pattern>" for each arm of the top-level `case "$step" in` of FILE,
# as bash parses it. Returns 1 when bash cannot parse FILE or it has no such case.
case_patterns() {
  local body
  bash -n "$1" 2>/dev/null || return 1
  body="$(bash -c 'eval "__wiring_parse() {
$(cat "$1")
}" && declare -f __wiring_parse' _ "$1" 2>/dev/null)" || return 1
  awk 'on == 0 && /^    case "\$step" in *$/ {on = 1; want = 1; next}
       on && /^    esac *$/ {done = 1; exit}
       on && want && /^        [^ ].*\)$/ {lab = substr($0, 9); sub(/\)$/, "", lab); n++
         k = split(lab, p, / \| /); for (i = 1; i <= k; i++) print n, p[i]; want = 0; next}
       on && /^        (;;|;;&|;&)$/ {want = 1}
       END {exit !done}' <<< "$body"
}

# dry_run FILE STEP: the commands FILE's arm for STEP would start, as "CMD <line> <command>", none
# executed (see the header), and the "NEED <tools>" line its need call prints.
dry_run() {
  ( cd "$(dirname "$1")/../.." && env step="$2" AIENOS_NEED_LIST=1 bash -c '
      __dbg() {
        [ "$__go" = 1 ] && return 0
        case "$BASH_COMMAND" in "source "*) return 0 ;; esac
        if [ "$__in" = 1 ]; then
          printf "CMD %s %s\n" "$1" "$BASH_COMMAND"
          case "$BASH_COMMAND" in "need "*) __c="$BASH_COMMAND"; __go=1; ( eval "$__c" ); __go=0 ;; esac
          return 1
        fi
        case "$BASH_COMMAND" in "case \"\$step\" in"*) __in=1; return 0 ;; esac
        return 1
      }
      __in=0; __go=0; shopt -s extdebug; trap "__dbg \$LINENO" DEBUG
      source "$0" "$step"' "$1" 2>/dev/null )
}

# arm_paths DRYRUN: the tracked paths under kernel/ the arm's commands name, one per line (a
# directory ends in /): each word with a / in it that is a tracked file or directory relative to
# kernel/, and crates/NAME/ for the NAME after cargo's -p. A path that appears just inside a function
# the arm calls is not seen.
arm_paths() {
  local w prev=
  for w in $(sed -n 's/^CMD [0-9]* //p' <<< "$1" | tr -d "\"';()" ); do
    if [ "$prev" = -p ] && grep -qx -- "kernel/crates/$w/Cargo.toml" "$TRACKED"; then echo "kernel/crates/$w/"; fi
    prev="$w"
    case "$w" in ''|-*|*'$'*|*'*'*) continue ;; */*) ;; *) continue ;; esac
    w="${w%/}"
    if grep -qxF -- "kernel/$w" "$TRACKED"; then echo "kernel/$w"
    elif grep -qF -- "kernel/$w/" "$TRACKED" && grep -q "^kernel/$w/" "$TRACKED"; then echo "kernel/$w/"; fi
  done | sort -u
}
# covered INPUTS PATH: an input equal to PATH, or a directory input (ending in /) that holds it.
covered() {
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ "$p" = "$2" ]; then return 0; fi
    case "$p" in */) case "$2" in "$p"*) return 0 ;; esac ;; esac
  done <<< "$1"
  return 1
}

# probe_root CFG STEP: run tests/gates/run.sh of CFG for kernel-STEP (or `kernel` when STEP is
# "kernel") in a scratch tree with stubs, once per mode; prints one FAIL line per wrong result.
PROBE_MODES="pass:0 fail:1 exit3:3 exit127:3 notrun:3 notrun-indented:3 skipped:3 skip-label:3 control-report:0 notrun-midline:0 fail-with-notrun:1"
probe_tree() {  # CFG DIR: a scratch tree with CFG's root runner and controls, and the stubs
  local d="$2" s
  mkdir -p "$d/tests/gates" "$d/kernel/tests/gates" "$d/kernel/scripts" "$d/bin"
  cp "$1/tests/gates/run.sh" "$d/tests/gates/run.sh"
  [ ! -d "$1/tests/gates/controls" ] || cp -r "$1/tests/gates/controls" "$d/tests/gates/"
  for s in kernel/tests/gates/run.sh:kernel-runner kernel/scripts/omega_gate_wiring.sh:wiring bin/make:make; do
    cat > "$d/${s%%:*}" <<STUB
#!/usr/bin/env bash
echo "${s##*:} \$*" >> "\$PROBE_CALLS"
[ -z "\${AIENOS_NEED_LIST:-}" ] || { echo "NEED probe-stub-reached"; exit 3; }
[ "\$PROBE_MODE" = noctl ] || for c in \${PROBE_CTL:-}; do echo "CONTROL \$c FAILED_AS_REQUIRED"; done
case "\$PROBE_MODE" in
  pass|noctl) echo "probe: PASS" ;;
  fail) echo "probe: FAIL"; exit 1 ;;
  exit3) echo "probe: exit 3"; exit 3 ;;
  exit127) echo "probe: a command not found"; exit 127 ;;
  notrun) echo "PROBE_STEP: NOT_RUN (probe)" ;;
  notrun-indented) echo "    AIENOS_PROBE: NOT_RUN (probe)" ;;
  skipped) echo "SKIPPED: probe" ;;
  skip-label) echo "PROBE_STEP: SKIP (probe)" ;;
  control-report) echo "probe control nolean: NOT_RUN exit 3 as required" ;;
  notrun-midline) echo "PROBE: PASS (hardware NOT_RUN)" ;;
  fail-with-notrun) echo "PROBE_STEP: NOT_RUN (probe)"; exit 1 ;;
esac
exit 0
STUB
    chmod +x "$d/${s%%:*}"
  done
  git -C "$d" init -q && git -C "$d" add -A && git -C "$d" -c user.name=t -c user.email=t@t commit -qm probe
}
probe_run() {  # DIR STEPWORD MODE: sets prc and pcalls
  : > "$1/CALLS"; prc=0
  (cd "$1" && env PATH="$1/bin:$PATH" PROBE_CALLS="$1/CALLS" PROBE_MODE="$3" PROBE_CTL="${PROBE_CTL:-}" AIEN_BASE_REF="${PROBE_BASE:-HEAD}" bash tests/gates/run.sh "$2") > "$1/out" 2>&1 || prc=$?
  pcalls="$(cat "$1/CALLS")"
}
probe_root() {
  local cfg="$1" s="$2" d mode want gate ctl PROBE_CTL=
  d="$(mktemp -d "${TMPDIR:-/tmp}/gate-wiring-probe.XXXXXX")"; probe_tree "$cfg" "$d"
  # The controls the step's gate lists: the stub prints their CONTROL lines (except in mode noctl).
  gate="OMEGA-KERNEL-${s^^}"; ctl="$d/tests/gates/controls/$gate.controls"
  [ ! -f "$ctl" ] || PROBE_CTL="$(grep -vE '^(#|$)' "$ctl" | sed "s|^|$gate/|" | tr '\n' ' ')"
  if [ "$s" = kernel ]; then
    PROBE_CTL="$(for ctl in "$d"/tests/gates/controls/*.controls; do [ -e "$ctl" ] || continue
      gate="${ctl##*/}"; gate="${gate%.controls}"; grep -vE '^(#|$)' "$ctl" | sed "s|^|$gate/|"; done | tr '\n' ' ')"
    probe_run "$d" kernel pass
    want="$(for k in $KERNEL_AGGREGATE; do root_route "$k"; done)"
    [ "$prc" = 0 ] && [ "$pcalls" = "$want" ] || fail "kernel: the aggregate runs '$(printf '%s' "$pcalls" | paste -sd, -)' (exit $prc), not $KERNEL_AGGREGATE"
    probe_run "$d" kernel fail
    [ "$prc" = 1 ] || fail "kernel: the aggregate exits $prc when every step fails, not 1"
    rm -rf "$d"; return
  fi
  for mode in $PROBE_MODES; do
    probe_run "$d" "kernel-$s" "${mode%%:*}"
    if [ "$pcalls" != "$(root_route "$s")" ]; then
      fail "$s: tests/gates/run.sh kernel-$s ran '$(printf '%s' "$pcalls" | paste -sd, -)', not '$(root_route "$s")' (stub mode ${mode%%:*})"; break
    fi
    [ "$prc" = "${mode##*:}" ] || fail "$s: tests/gates/run.sh kernel-$s exits $prc when its runner gives '${mode%%:*}', not ${mode##*:}"
  done
  # A base without kernel/ (an empty-tree commit), or a ref that does not exist: NOT_RUN, the stub not reached.
  for b in "$(git -C "$d" -c user.name=t -c user.email=t@t commit-tree "$(git -C "$d" hash-object -t tree /dev/null)" -m empty)" no-such-ref; do
    PROBE_BASE="$b" probe_run "$d" "kernel-$s" pass
    [ "$prc" = 3 ] && [ -z "$pcalls" ] || fail "$s: tests/gates/run.sh kernel-$s exits $prc with base '$b' (no kernel/), not 3 before running"
  done
  if [ -f "$ctl" ]; then
    probe_run "$d" "kernel-$s" noctl
    [ "$prc" = 1 ] || fail "$s: tests/gates/run.sh kernel-$s exits $prc when the controls in tests/gates/controls/$gate.controls do not report, not 1"
  fi
  rm -rf "$d"
}

# check CFG: CFG holds the files under test (tests/gates/*.gate, tests/gates/controls/,
# tests/gates/run.sh, kernel/tests/gates/run.sh, kernel/MIGRATION.md, .aien/always); the inputs must
# name tracked paths of this checkout ($TRACKED). WIRING_STEP=<step> limits the dry runs and probes to that
# step (the self-test's mutants); WIRING_STEP=none skips them. Prints one FAIL line per problem and the
# totals; returns 1 on any FAIL.
check() {
  local cfg="$1" fails=0 wired=0 listed=0 s m p mt exempt steps pats unk unk_first first dr up ins r t dup
  local root_rs="$cfg/tests/gates/run.sh" kern_rs="$cfg/kernel/tests/gates/run.sh" mig="$cfg/kernel/MIGRATION.md"
  fail() { echo "FAIL $*"; fails=$((fails + 1)); }
  one_step() { [ -z "${WIRING_STEP:-}" ] || [ "$WIRING_STEP" = "$1" ]; }
  [ -s "$root_rs" ] && bash -n "$root_rs" 2>/dev/null || fail "tests/gates/run.sh missing or not valid bash"
  # MIGRATION.md rows: | `step` | ... | reason |. A row this reader skips (no backticks, another
  # section) leaves its step unlisted, which then fails as unwired: the reader fails closed.
  exempt="$(awk '/^##+ / {on = ($0 ~ /^#+ Aienux gates without a manifest$/)} on && /^\| `[a-z0-9-]+` \|/ {
      line=$0; s=line; sub(/^\| `/, "", s); sub(/`.*/, "", s); r=line; sub(/[[:space:]]*\|[[:space:]]*$/, "", r); sub(/.*\|[[:space:]]*/, "", r);
      if (r != "" && r != "-") print s; else print s " NO-REASON" }' "$mig" 2>/dev/null)"
  while read -r s m; do [ -n "$s" ] && [ "$m" = NO-REASON ] && fail "MIGRATION.md lists $s without a reason"; done <<< "$exempt"
  exempt="$(printf '%s\n' "$exempt" | awk '{print $1}')"
  # Steps: aienux's 25, omega-mv's own, and every kernel runner arm whose pattern bash reads as a
  # plain word (no * ? [ or other glob character).
  if ! pats="$(case_patterns "$kern_rs")"; then fail "kernel/tests/gates/run.sh: bash cannot parse it, or it has no case \"\$step\" in"; pats=; fi
  steps="$(printf '%s\n' $AIENUX_GATES $OMEGA_STEPS; awk '$2 !~ /[][*?!@+|\\$"'"'"'`]/ {print $2}' <<< "$pats")"
  steps="$(printf '%s\n' "$steps" | grep . | sort -u)"
  if [ "${WIRING_STEP:-}" != none ]; then
    unk="$(dry_run "$kern_rs" __no_such_step__)"; unk_first="$(awk '/^CMD / {print $2; exit}' <<< "$unk")"
  fi
  for s in $steps; do
    dr=
    if ! grep -qx -- "$s" <<< "$(printf '%s\n' $ROOT_ROUTED)" && [ "${WIRING_STEP:-}" != none ] && one_step "$s"; then
      dr="$(dry_run "$kern_rs" "$s")"; first="$(grep -m1 '^CMD ' <<< "$dr")"
      if [ -z "$first" ] || [ "$(awk '{print $2}' <<< "$first")" = "$unk_first" ]; then
        fail "$s: kernel/tests/gates/run.sh has no step $s (only its unknown-step arm runs)"
      elif [[ $first != "CMD "*" need "* ]]; then
        fail "$s: the first command of its arm in kernel/tests/gates/run.sh is '${first#CMD * }', not need TOOL..."
      elif ! grep -q '^NEED ' <<< "$dr"; then
        fail "$s: its need call printed no tool list"
      fi
    fi
    m="$cfg/tests/gates/omega-kernel-$s.gate"
    if grep -qx -- "$s" <<< "$exempt"; then
      if [ -e "$m" ]; then fail "$s: both wired (tests/gates/omega-kernel-$s.gate) and listed in MIGRATION.md"; else listed=$((listed + 1)); fi
      continue
    fi
    if [ ! -f "$m" ]; then fail "$s: no tests/gates/omega-kernel-$s.gate and no MIGRATION.md row"; continue; fi
    up="${s^^}"
    if ! mt="$(manifest_read "$m")"; then fail "$s: tests/gates/omega-kernel-$s.gate: the judge's grammar refuses it ($(tail -n 1 <<< "$mt"))"; continue; fi
    [ "$(mget "$mt" gate)" = "OMEGA-KERNEL-$up" ] || fail "$s: manifest gate is '$(mget "$mt" gate)', not OMEGA-KERNEL-$up"
    [ "$(mget "$mt" run.exec)" = "tests/gates/run.sh" ] || fail "$s: manifest exec is '$(mget "$mt" run.exec)', not tests/gates/run.sh"
    [ "$(mget "$mt" run.args)" = "[\"kernel-$s\"]" ] || fail "$s: manifest args are '$(mget "$mt" run.args)', not [\"kernel-$s\"]"
    [ "$(mget "$mt" expects.exit)" = 0 ] || fail "$s: manifest expects exit '$(mget "$mt" expects.exit)', not 0"
    [ "$(mget "$mt" expects.verdict)" = PASS ] || fail "$s: manifest expects verdict '$(mget "$mt" expects.verdict)', not PASS"
    [ "$(mget "$mt" manifest_version)" = 2 ] || fail "$s: manifest_version is '$(mget "$mt" manifest_version)', not 2"
    [[ $(mget "$mt" timeout) =~ ^[1-9][0-9]*(ms|s|m|h)$ ]] || fail "$s: manifest timeout '$(mget "$mt" timeout)' is not a duration the judge reads"
    r="$(mlist "$mt" requires)"
    [ -n "$r" ] || fail "$s: manifest lists no requires"
    for t in $r; do grep -qx -- "$t" <<< "$(printf '%s\n' $REQUIRES_OK)" || fail "$s: manifest requires '$t'; a kernel gate may require only: $REQUIRES_OK"; done
    ins="$(mlist "$mt" inputs)"
    [ -n "$ins" ] || fail "$s: manifest lists no inputs"
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      if [[ $p == */ ]]; then grep -q -- "^${p//./\\.}" "$TRACKED" || fail "$s: input $p is no tracked directory"
      else grep -qxF -- "$p" "$TRACKED" || fail "$s: input $p is no tracked file"; fi
    done <<< "$ins"
    for p in tests/gates/run.sh "tests/gates/omega-kernel-$s.gate" $(root_paths "$s") $( [ -n "$(root_paths "$s")" ] || echo kernel/tests/gates/run.sh ) \
             $( [ -z "$dr" ] || arm_paths "$dr" ); do
      covered "$ins" "$p" || fail "$s: manifest inputs do not cover $p, which its step runs"
    done
    if one_step "$s" && [ "${WIRING_STEP:-}" != none ]; then probe_root "$cfg" "$s"; fi
    wired=$((wired + 1))
  done
  if [ -z "${WIRING_STEP:-}" ] || [ "$WIRING_STEP" = kernel ]; then probe_root "$cfg" kernel; fi
  # No manifest for a step nobody runs; no gate name twice.
  for m in "$cfg"/tests/gates/omega-kernel-*.gate; do
    [ -e "$m" ] || continue
    s="${m##*/omega-kernel-}"; s="${s%.gate}"
    grep -qx -- "$s" <<< "$steps" || fail "tests/gates/omega-kernel-$s.gate names no step of the kernel runners"
  done
  dup="$(for m in "$cfg"/tests/gates/*.gate; do mt="$(manifest_read "$m" 2>/dev/null)" && mget "$mt" gate; done | sort | uniq -d)"
  for p in $dup; do fail "gate $p is named by more than one manifest under tests/gates/"; done
  # Always-run gates.
  for p in $ALWAYS; do
    grep -qx -- "$p" "$cfg/.aien/always" 2>/dev/null || fail ".aien/always does not list $p"
    grep -lx -- "gate: $p" "$cfg"/tests/gates/*.gate > /dev/null 2>&1 || fail ".aien/always gate $p has no manifest"
  done
  echo "OMEGA-KERNEL-GATE-WIRING: steps=$(printf '%s\n' $steps | wc -l) wired=$wired listed=$listed always=$(printf '%s\n' $ALWAYS | wc -l) fail=$fails"
  [ "$fails" = 0 ]
}

# copy_cfg DIR: the files check reads, copied from this checkout.
copy_cfg() {
  mkdir -p "$1/tests/gates" "$1/kernel/tests/gates" "$1/.aien"
  cp "$ROOT"/tests/gates/*.gate "$ROOT/tests/gates/run.sh" "$1/tests/gates/"
  [ ! -d "$ROOT/tests/gates/controls" ] || cp -r "$ROOT/tests/gates/controls" "$1/tests/gates/"
  cp "$ROOT/kernel/tests/gates/run.sh" "$1/kernel/tests/gates/"
  cp "$ROOT/kernel/MIGRATION.md" "$1/kernel/"
  cp "$ROOT/.aien/always" "$1/.aien/"
}

self_test() {
  local tmp d name rc killed=0 survived=0 s t tools farm line
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/gate-wiring.XXXXXX")"
  ctl_ok() { killed=$((killed + 1)); echo "CONTROL OMEGA-KERNEL-GATE-WIRING/$1 FAILED_AS_REQUIRED"; }
  # mutant NAME STEP SHELL-SNIPPET REGEX: the snippet runs in a fresh copy; check (limited to STEP)
  # must then FAIL with a FAIL line matching REGEX (the failure the mutant was made for).
  mutant() {
    d="$tmp/$1"; copy_cfg "$d"
    (c="$d"; cd "$d" && eval "$3") || { echo "control $1: could not build the mutant"; survived=$((survived + 1)); return; }
    rc=0; WIRING_STEP="$2" check "$d" > "$d.log" 2>&1 || rc=$?
    if [ "$rc" != 0 ] && grep -qE -- "^FAIL .*$4" "$d.log"; then ctl_ok "$1"
    else
      survived=$((survived + 1)); echo "control $1: exit $rc without a FAIL line matching '$4'; the check misses it"
      grep '^FAIL ' "$d.log" | head -n 3
    fi
  }
  M=tests/gates/omega-kernel-native-crypto.gate; S=tests/gates/omega-kernel-native-sig.gate
  RR=tests/gates/run.sh; KR=kernel/tests/gates/run.sh
  ins_after_case() { awk -v l="$2" '{print} /^case "\$step" in/ && !d {print l; d=1}' "$1" > x && mv x "$1"; }
  mutant remove-manifest          none "rm $M" 'native-crypto: no tests/gates/omega-kernel-native-crypto\.gate'
  mutant remove-always-gate       none "rm tests/gates/omega-kernel-crypto-boundary.gate" 'crypto-boundary: no tests/gates/omega-kernel-crypto-boundary\.gate'
  mutant rename-manifest          none "mv $M $M.disabled" 'native-crypto: no tests/gates/omega-kernel-native-crypto\.gate'
  mutant make-test-manifest-removed none "rm tests/gates/omega-kernel-make-test.gate" 'make-test: no tests/gates/omega-kernel-make-test\.gate'
  mutant spinlock-removed         none "rm tests/gates/omega-kernel-spinlock.gate; sed -i 's/^  spinlock)/  spinlock-gone)/' $KR" 'spinlock: no tests/gates/omega-kernel-spinlock\.gate'
  mutant args-other-step          none "sed -i 's/kernel-native-crypto/kernel-native-sig/' $M" 'native-crypto: manifest args'
  mutant args-commented           none "sed -i 's/^  args:/#  args:/' $M" 'native-crypto: manifest args'
  mutant gate-name                none "sed -i 's/^gate: .*/gate: OMEGA-KERNEL-NATIVECRYPTO/' $M" 'native-crypto: manifest gate'
  mutant exec-bypass-root         none "sed -i 's#exec: tests/gates/run.sh#exec: kernel/tests/gates/run.sh#' $M" 'native-crypto: manifest exec'
  mutant exec-duplicate           none "sed -i '/^  args:/a\\  exec: /usr/bin/true' $M" 'native-crypto: .*duplicate child key run\.exec'
  mutant exec-decoy-notes         none "sed -i 's/^run:/notes:\\n  exec: tests\\/gates\\/run.sh\\nrun:/' $M" 'native-crypto: .*unknown key notes'
  mutant requires-gb10            none "sed -i '/^requires:/a\\  - gb10' $M" "native-crypto: manifest requires 'gb10'"
  mutant requires-operator        none "sed -i '/^requires:/a\\  - operator' $M" "native-crypto: manifest requires 'operator'"
  mutant requires-unknown         none "sed -i '/^requires:/a\\  - unknown' $M" "native-crypto: manifest requires 'unknown'"
  mutant expects-exit-1           none "sed -i 's/^  exit: 0/  exit: 1/' $M" "native-crypto: manifest expects exit '1'"
  mutant expects-not-run          none "sed -i 's/^  verdict: PASS/  verdict: NOT_RUN/' $M" "native-crypto: manifest expects verdict 'NOT_RUN'"
  mutant manifest-tab             none "sed -i 's/^  args:/\\targs:/' $M" 'native-crypto: .*tab not allowed'
  mutant manifest-crlf            none "sed -i 's/\$/\\r/' $M" 'native-crypto: .*CR not allowed'
  mutant manifest-deep-indent     none "sed -i 's/^  args:/   args:/' $M" 'native-crypto: .*indentation deeper'
  mutant gate-name-twice          none "sed 's#^  args: .*#  args: []#; s#^  exec: .*#  exec: /usr/bin/true#' $M > tests/gates/omega-decoy.gate" 'gate OMEGA-KERNEL-NATIVE-CRYPTO is named by more than one manifest'
  mutant input-unprefixed         none "sed -i 's#^  - kernel/native/crypto/#  - native/crypto/#' $M" 'native-crypto: input native/crypto/ is no tracked'
  mutant inputs-readme-only       native-sig "awk '/^inputs:/{print; print \"  - kernel/README.md\"; skip=1; next} skip && /^  - /{next} {skip=0; print}' $S > x && mv x $S" 'native-sig: manifest inputs do not cover kernel/native/sig/'
  mutant root-arm-shadows         native-crypto "ins_after_case $RR '  kernel-native-crypto) echo skipped ;;'" "native-crypto: tests/gates/run\\.sh kernel-native-crypto ran ''"
  mutant root-arm-shadow-indented native-sig "ins_after_case $RR '    kernel-native-sig) echo skipped ;;'" "native-sig: tests/gates/run\\.sh kernel-native-sig ran ''"
  mutant root-arm-shadow-comment  native-sig "ins_after_case $RR '  kernel-native-sig) true  # bash kernel/tests/gates/run.sh native-sig
    ;;'" "native-sig: tests/gates/run\\.sh kernel-native-sig ran ''"
  mutant root-arm-or-true         native-sig "sed -i 's#^  kernel-\\*)  *kernel_step \"\${step\#kernel-}\" ;;#  kernel-*) (kernel_step \"\${step\#kernel-}\") || true ;;#' $RR" 'native-sig: tests/gates/run\.sh kernel-native-sig exits 0 when its runner gives .fail., not 1'
  mutant root-arm-no-wrapper      native-sig "sed -i 's#^  kernel-\\*)  *kernel_step \"\${step\#kernel-}\" ;;#  kernel-*) bash kernel/tests/gates/run.sh \"\${step\#kernel-}\" ;;#' $RR" 'native-sig: tests/gates/run\.sh kernel-native-sig exits 0 when its runner gives .notrun., not 3'
  mutant wrapper-127-pass         native-sig "sed -i 's/if \\[ \"\$rc\" = 127 \\] || \\[ \"\$rc\" = 3 \\]; then/if [ \"\$rc\" = 3 ]; then/' $RR" 'native-sig: .* exits 127 when its runner gives .exit127., not 3'
  mutant wrapper-controls-ignored native-crypto "mkdir -p tests/gates/controls; echo planted > tests/gates/controls/OMEGA-KERNEL-NATIVE-CRYPTO.controls; sed -i 's/^  if \\[ -f \"\$ctl\" \\]; then/  if false; then/' $RR" 'native-crypto: .* exits 0 when the controls in tests/gates/controls/OMEGA-KERNEL-NATIVE-CRYPTO\.controls do not report'
  mutant wrapper-verdict-ignored  native-sig "sed -i \"s/^KERNEL_VERDICT_RE=.*/KERNEL_VERDICT_RE='^NEVER-MATCHES\\\$'/\" $RR" 'native-sig: .* exits 0 when its runner gives .notrun., not 3'
  mutant wrapper-skip-ignored     native-sig "sed -i '/^KERNEL_VERDICT_RE=/ s/(NOT_RUN|SKIP)/(NOT_RUN)/; /^KERNEL_VERDICT_RE=/ s/(NOT_RUN|SKIP|SKIPPED)/(NOT_RUN)/' $RR" 'native-sig: .* exits 0 when its runner gives .skip(ped|-label)., not 3'
  mutant wrapper-any-not-run-word native-sig "sed -i \"s/^KERNEL_VERDICT_RE=.*/KERNEL_VERDICT_RE='(NOT_RUN|SKIP)'/\" $RR" 'native-sig: .* exits 3 when its runner gives .(control-report|notrun-midline)., not 0'
  mutant base-without-kernel      native-sig "sed -i 's/git cat-file -e \"\$kc:kernel\"/true/' $RR" "native-sig: .* with base '[0-9a-f]+' \\(no kernel/\\), not 3"
  mutant root-arm-removed         native-crypto "sed -i '/^  kernel-\\*)/d' $RR" "native-crypto: tests/gates/run\\.sh kernel-native-crypto ran ''"
  mutant aggregate-step-dropped   kernel "sed -i 's/^    for s in make-test ck-host-tests hw-gates omega-nvme tcp-corpus spinlock; do/    for s in make-test ck-host-tests hw-gates omega-nvme tcp-corpus; do/' $RR" 'kernel: the aggregate runs'
  mutant kernel-step-removed      native-crypto "sed -i 's/^  native-crypto)/  native-crypto-old)/' $KR" 'native-crypto: kernel/tests/gates/run\.sh has no step'
  mutant kernel-step-indented     native-crypto "sed -i 's/^  native-crypto)  */      native-crypto) echo shadow; exit 0; /' $KR" "native-crypto: the first command of its arm .* is 'echo shadow'"
  mutant kernel-step-no-need      native-crypto "sed -i 's/^  native-crypto)     need make \"\$(cc_word)\"; /  native-crypto)     /' $KR" 'native-crypto: the first command of its arm .* is .native_suite'
  mutant kernel-step-added        none "ins_after_case $KR '  brand-new-gate) true ;;'" 'brand-new-gate: no tests/gates/omega-kernel-brand-new-gate\.gate'
  mutant kernel-step-underscore   none "ins_after_case $KR '  native_new) need make; true ;;'" 'native_new: no tests/gates/omega-kernel-native_new\.gate'
  mutant kernel-runner-syntax     none "echo 'case \$x in' >> $KR" 'kernel/tests/gates/run\.sh: bash cannot parse it'
  mutant always-dropped           none "sed -i '/^OMEGA-KERNEL-CRYPTO-BOUNDARY\$/d' .aien/always" 'always does not list OMEGA-KERNEL-CRYPTO-BOUNDARY'
  mutant always-anchor-dropped    none "sed -i '/^OMEGA-GATE-ANCHOR\$/d' .aien/always" 'always does not list OMEGA-GATE-ANCHOR'
  mutant always-claims-dropped    none "sed -i '/^OMEGA-GATE-CLAIMS\$/d' .aien/always" 'always does not list OMEGA-GATE-CLAIMS'
  mutant migration-row-dropped    none "sed -i '/^| \`zero-disk-secrets\` |/d' kernel/MIGRATION.md" 'zero-disk-secrets: no tests/gates/omega-kernel-zero-disk-secrets\.gate'
  mutant migration-row-no-backticks none "sed -i 's/^| \`zero-disk-secrets\` |/| zero-disk-secrets |/' kernel/MIGRATION.md" 'zero-disk-secrets: no tests/gates/omega-kernel-zero-disk-secrets\.gate'
  mutant migration-and-manifest   none "sed -i '/^| \`zero-disk-secrets\` |/p; s/^| \`zero-disk-secrets\` |/| \`native-crypto\` |/' kernel/MIGRATION.md" 'native-crypto: both wired'
  mutant migration-no-reason      none "sed -i 's/^\\(| \`zero-disk-secrets\` |.*|\\) [^|]*|\$/\\1 - |/' kernel/MIGRATION.md" 'MIGRATION\.md lists zero-disk-secrets without a reason'
  mutant wiring-manifest-removed  none "rm tests/gates/omega-kernel-gate-wiring.gate" 'gate-wiring: no tests/gates/omega-kernel-gate-wiring\.gate'
  mutant orphan-manifest          none "cp $M tests/gates/omega-kernel-nonesuch.gate" 'omega-kernel-nonesuch\.gate names no step'
  # Missing tools (CA3): each step, run for real through tests/gates/run.sh with each tool of its
  # need list removed from PATH, must exit 3 with its NOT_RUN line, before it runs anything else
  # ([ctl:OMEGA-KERNEL-GATE-WIRING/no-cargo-crypto-boundary] is one of these controls).
  for s in $(printf '%s\n' $AIENUX_GATES $OMEGA_STEPS $(case_patterns "$ROOT/kernel/tests/gates/run.sh" | awk '$2 ~ /^[a-z0-9_-]+$/ {print $2}') | sort -u); do
    if grep -qx -- "$s" <<< "$(printf '%s\n' $ROOT_ROUTED)"; then
      d="$tmp/need-$s"; probe_tree "$ROOT" "$d"
      tools="$(cd "$d" && env AIENOS_NEED_LIST=1 AIEN_BASE_REF=HEAD PATH="$d/bin:$PATH" PROBE_CALLS=/dev/null PROBE_MODE=pass bash tests/gates/run.sh "kernel-$s" 2>/dev/null \
        | sed -n 's/^NEED //p' | grep -v '^probe-stub-reached$' | tr '\n' ' ')"
    else
      tools="git $(dry_run "$ROOT/kernel/tests/gates/run.sh" "$s" | sed -n 's/^NEED //p')"
    fi
    if [ -z "${tools// /}" ] || { [ "$tools" = "git " ] && ! grep -qx -- "$s" <<< "$(printf '%s\n' $ROOT_ROUTED)"; }; then
      survived=$((survived + 1)); echo "control need-$s: step $s declares no tools (no need call before it runs)"; continue
    fi
    for t in $tools; do
      farm="$tmp/farm-$t"
      if [ ! -d "$farm" ]; then
        mkdir -p "$farm"
        local IFS=:; for line in $PATH; do IFS=$' \t\n'
          for p in "$line"/*; do
            [ -x "$p" ] && [ ! -d "$p" ] || continue
            [ "${p##*/}" != "$t" ] && [ ! -e "$farm/${p##*/}" ] && [ ! -L "$farm/${p##*/}" ] && ln -s "$p" "$farm/${p##*/}"
          done
        done; IFS=$' \t\n'
      fi
      rc=0; (cd "$ROOT" && env PATH="$farm" AIEN_BASE_REF=HEAD bash tests/gates/run.sh "kernel-$s") > "$tmp/need-$s-$t.log" 2>&1 || rc=$?
      if [ "$rc" = 3 ] && grep -qE "^(kernel-)?$s: NOT_RUN \\($t is not on PATH\\)" "$tmp/need-$s-$t.log"; then ctl_ok "no-$t-$s"
      else survived=$((survived + 1)); echo "control no-$t-$s: tests/gates/run.sh kernel-$s without $t exits $rc, not 3 with its NOT_RUN line"; tail -n 3 "$tmp/need-$s-$t.log"; fi
    done
  done
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
      ctl_ok "secret-${name%%:*}"
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
rc=0; check "$ROOT" || rc=$?
if [ "$mode" = --self-test ]; then
  st=0; self_test || st=$?
  [ "$st" = 0 ] || { echo "OMEGA-KERNEL-GATE-WIRING SELF-TEST: FAIL"; exit 1; }
  echo "OMEGA-KERNEL-GATE-WIRING SELF-TEST: PASS"
fi
[ "$rc" = 0 ] || { echo "OMEGA-KERNEL-GATE-WIRING: FAIL"; exit 1; }
echo "OMEGA-KERNEL-GATE-WIRING: PASS"
