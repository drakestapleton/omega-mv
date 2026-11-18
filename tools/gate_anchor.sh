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

# tools/gate_anchor.sh: OMEGA-GATE-ANCHOR (tests/gates/run.sh gate-anchor, always-run). The paths in
# tools/gate-anchors.txt are gate-integrity files: gate scripts, pins, count pins, control lists and
# allowlists that a gate trusts and that the same commit could rewrite. A head that changes one is
# BLOCKED_OPERATOR: the operator run that writes the landing receipt reviews each changed file, lists
# it in the receipt and sets AIEN_GATE_ANCHOR_ACK to exactly those paths. A worker does not set it.
#   tools/gate_anchor.sh                      (no arguments; AIEN_BASE_REF, default origin/main)
# B is the merge base of AIEN_BASE_REF and HEAD. The anchors are the entries of tools/gate-anchors.txt
# at the base ref, at B and at HEAD (their union), plus tools/gate_anchor.sh and tools/gate-anchors.txt
# themselves; an entry ending in '/' stands for the paths under that folder. One line
# GATE-ANCHOR CHANGED <path> is printed for each anchor path that
#  - differs between B and HEAD in content, mode or type, or exists at one of them only (an add, a
#    delete; a rename is both) [ctl:OMEGA-GATE-ANCHOR/edited] [ctl:OMEGA-GATE-ANCHOR/deleted]
#    [ctl:OMEGA-GATE-ANCHOR/renamed-out] [ctl:OMEGA-GATE-ANCHOR/mode-changed]
#    [ctl:OMEGA-GATE-ANCHOR/type-changed] [ctl:OMEGA-GATE-ANCHOR/added-in-folder];
#  - is staged differently from HEAD, or whose work-tree copy differs from HEAD in raw bytes (hashed
#    with no filters), executable bit or type, or is an untracked file under an anchor folder that
#    .gitignore does not ignore [ctl:OMEGA-GATE-ANCHOR/staged] [ctl:OMEGA-GATE-ANCHOR/worktree-edit]
#    [ctl:OMEGA-GATE-ANCHOR/worktree-mode] [ctl:OMEGA-GATE-ANCHOR/untracked-in-folder].
# An entry dropped from the list at HEAD is still read from the base ref and B
# [ctl:OMEGA-GATE-ANCHOR/list-entry-dropped] [ctl:OMEGA-GATE-ANCHOR/list-deleted].
# Not read: ignored files, changes the base ref made after B (they are the base's, not this head's
# [ctl:OMEGA-GATE-ANCHOR/base-advanced]), and paths that no list names.
# Exit 0: no anchor changed, or AIEN_GATE_ANCHOR_ACK (paths separated by white space) is exactly the
# changed set [ctl:OMEGA-GATE-ANCHOR/ack-subset] [ctl:OMEGA-GATE-ANCHOR/ack-superset]
# [ctl:OMEGA-GATE-ANCHOR/ack-without-change]. Exit 1: GATE-ANCHOR BLOCKED_OPERATOR (changed and not
# acknowledged) or GATE-ANCHOR FAIL (a control failed, a list entry is malformed). Exit 3:
# GATE-ANCHOR NOT_RUN (not a git work tree, a shallow clone, no base ref) [ctl:OMEGA-GATE-ANCHOR/no-git]
# [ctl:OMEGA-GATE-ANCHOR/shallow] [ctl:OMEGA-GATE-ANCHOR/no-base]. NOT_RUN is not a pass.
# Base copy: when the base ref holds a tools/gate_anchor.sh with other bytes than this file, that copy
# runs first (its own controls included) and the exit is the worse of the two, 1 over 3 over 0, so a
# head that weakens the check below this script's first statements still meets the base's check
# [ctl:OMEGA-GATE-ANCHOR/head-copy-weakened]. A head that edits those first statements is caught only
# when the caller runs the base ref's copy itself:
#   git show "$AIEN_BASE_REF:tools/gate_anchor.sh" > "$tmp/ga.sh" && bash "$tmp/ga.sh"
# The environment does not point the check at another repository: every GIT_* variable except
# GIT_CEILING_DIRECTORIES is cleared, and replace refs and grafts are ignored
# [ctl:OMEGA-GATE-ANCHOR/git-dir-knob] [ctl:OMEGA-GATE-ANCHOR/replace-ref].
# AIEN_GATE_ANCHOR_CONTROL_RUN=1 is how the controls run this script inside a throwaway repository: it
# skips the controls and turns a would-be PASS into NOT_RUN [ctl:OMEGA-GATE-ANCHOR/control-run-never-passes].
set -u
GATE=OMEGA-GATE-ANCHOR
ME=tools/gate_anchor.sh
LIST=tools/gate-anchors.txt
SELF=$(realpath -e -- "${BASH_SOURCE[0]}") || { echo "GATE-ANCHOR NOT_RUN: cannot resolve the path of this script"; exit 3; }
# Every control, by name; each must run and give its expected exit (asserted, not only printed).
CONTROLS="untouched base-advanced edited deleted renamed-out mode-changed type-changed added-in-folder
list-entry-dropped list-deleted script-edited bad-entry staged worktree-edit worktree-mode
untracked-in-folder ack-exact ack-subset ack-superset ack-without-change git-dir-knob replace-ref
shallow no-git no-base head-copy-weakened control-run-never-passes"

obs() { printf 'AIEN-OBS %s %s\n' "$1" "$2"; }
clear_git_env() {
  local v
  for v in $(compgen -e); do
    case $v in GIT_CEILING_DIRECTORIES) ;; GIT_*) unset "$v" ;; esac
  done
  export GIT_NO_REPLACE_OBJECTS=1 GIT_GRAFT_FILE=/nonexistent/gate-anchor-grafts
}
gq() { git --literal-pathspecs -c core.quotePath=false "$@"; }
g() { git -c user.name=gateanchor -c user.email=gateanchor@invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null -c init.defaultBranch=main -c advice.detachedHead=false "$@"; }
# worst RC...: 1 over 3 over 0 (any other exit counts as 1)
worst() {
  local w=0 x
  for x in "$@"; do case $x in 0) ;; 3) [ "$w" = 0 ] && w=3 ;; *) w=1 ;; esac; done
  echo "$w"
}
# chg PATH HOW: record one change (NUL-separated, so any path survives)
chg() { printf '%s\0%s\0' "$1" "$2" >> "$T/chg"; }
# rawlog FILE WHERE: record the changes of a `git diff-* -z --raw` output
rawlog() {
  local meta p m1 m2 s1 s2 st how
  while IFS= read -r -d '' meta && IFS= read -r -d '' p; do
    read -r m1 m2 s1 s2 st <<< "${meta#:}"
    case $st in
      A) how=added ;;
      D) how=deleted ;;
      T) how="type $m1 -> $m2" ;;
      M) how=""; [ "$s1" = "$s2" ] || how=content; [ "$m1" = "$m2" ] || how="${how:+$how, }mode $m1 -> $m2" ;;
      *) how="status $st" ;;
    esac
    chg "$p" "$2: $how"
  done < "$1"
}

# anchorcheck: the check, run inside the work tree to check. Prints one GATE-ANCHOR CHANGED line per
# changed anchor path and a verdict line; returns 0, 1 or 3.
anchorcheck() { # BODY
  local top base bc mb c e bad=0 ent meta p mode type id n ackset chgset
  local -a ents=()
  local -A how=()
  clear_git_env
  top=$(git rev-parse --show-toplevel 2> /dev/null) || { echo "GATE-ANCHOR NOT_RUN: $PWD is not in a git work tree, so there is no base to compare with"; return 3; }
  cd "$top" || return 3
  if [ "$(git rev-parse --is-shallow-repository 2> /dev/null)" != false ]; then
    echo "GATE-ANCHOR NOT_RUN: shallow clone: the merge base may be missing (fetch the full history)"; return 3
  fi
  base=${AIEN_BASE_REF:-origin/main}
  bc=$(git rev-parse --verify -q "$base^{commit}") || { echo "GATE-ANCHOR NOT_RUN: base ref '$base' is not a commit here (set AIEN_BASE_REF to the branch this head lands on)"; return 3; }
  mb=$(git merge-base "$bc" HEAD) || { echo "GATE-ANCHOR FAIL: HEAD shares no history with $base"; return 1; }
  obs base_ref "\"$bc\""; obs merge_base "\"$mb\""
  # the anchors: this script, the list, and the list's entries at the base ref, at B and at HEAD
  { printf '%s\n' "$ME" "$LIST"
    for c in "$bc" "$mb" HEAD; do
      if git cat-file -e "$c:$LIST" 2> /dev/null; then git cat-file blob "$c:$LIST"; echo; fi
    done
  } > "$T/raw"
  : > "$T/ents"
  while IFS= read -r e || [ -n "$e" ]; do
    case $e in '' | '#'*) continue ;; esac
    case $e in
      *[[:space:]]* | /* | ./* | ../* | */./* | */../* | */. | */.. | . | .. | *//*)
        echo "GATE-ANCHOR FAIL: $LIST entry '$e' is not a plain relative path (no white space, no '.', '..' or '//' component)"; bad=1; continue ;;
    esac
    printf '%s\n' "$e" >> "$T/ents"
  done < "$T/raw"
  sort -u "$T/ents" -o "$T/ents"
  mapfile -t ents < "$T/ents"
  obs anchor_entries "${#ents[@]}"
  : > "$T/chg"
  # B against HEAD, and the index against HEAD
  gq diff-tree -z -r --no-renames --no-abbrev --raw "$mb" HEAD -- "${ents[@]}" > "$T/net" || { echo "GATE-ANCHOR FAIL: git diff-tree $mb HEAD failed"; return 1; }
  rawlog "$T/net" "against the merge base"
  gq diff-index -z --cached --no-renames --no-abbrev --raw HEAD -- "${ents[@]}" > "$T/idx" || { echo "GATE-ANCHOR FAIL: git diff-index failed"; return 1; }
  rawlog "$T/idx" "staged"
  # the work tree against HEAD: type, executable bit and raw bytes
  gq ls-tree -r -z HEAD -- "${ents[@]}" > "$T/tree" || { echo "GATE-ANCHOR FAIL: git ls-tree HEAD failed"; return 1; }
  : > "$T/reg"; : > "$T/ids"
  while IFS= read -r -d '' ent; do
    meta=${ent%%$'\t'*}; p=${ent#*$'\t'}
    read -r mode type id <<< "$meta"
    case $p in *$'\n'* | *$'\t'*) echo "GATE-ANCHOR FAIL: an anchor path holds a newline or a tab: $(printf '%q' "$p")"; bad=1; continue ;; esac
    case $mode in
      120000)
        if [ ! -L "$p" ] || [ "$(printf '%s' "$(readlink -- "$p")" | git hash-object --stdin)" != "$id" ]; then
          chg "$p" "work tree: not the symlink HEAD has"
        fi ;;
      100644 | 100755)
        if [ -L "$p" ] || [ ! -f "$p" ]; then chg "$p" "work tree: missing or not a regular file"
        elif { [ "$mode" = 100755 ] && [ ! -x "$p" ]; } || { [ "$mode" = 100644 ] && [ -x "$p" ]; }; then
          chg "$p" "work tree: executable bit differs from HEAD's $mode"
        else printf '%s\n' "$p" >> "$T/reg"; printf '%s\n' "$id" >> "$T/ids"; fi ;;
      *) chg "$p" "HEAD has mode $mode (not a file or symlink)" ;;
    esac
  done < "$T/tree"
  if [ -s "$T/reg" ]; then
    if git hash-object --no-filters --stdin-paths < "$T/reg" > "$T/got"; then
      while IFS=$'\t' read -r id c p; do
        [ "$id" = "$c" ] || chg "$p" "work tree: raw bytes $c, HEAD $id"
      done < <(paste "$T/ids" "$T/got" "$T/reg")
    else echo "GATE-ANCHOR FAIL: cannot hash the anchor files in the work tree"; bad=1; fi
  fi
  gq ls-files -z --others --exclude-standard -- "${ents[@]}" > "$T/untracked" || { echo "GATE-ANCHOR FAIL: git ls-files --others failed"; return 1; }
  while IFS= read -r -d '' p; do chg "$p" "untracked in the work tree"; done < "$T/untracked"
  # one line per changed path, with how it changed
  while IFS= read -r -d '' p && IFS= read -r -d '' e; do
    case $p in *$'\n'*) echo "GATE-ANCHOR FAIL: a changed anchor path holds a newline: $(printf '%q' "$p")"; bad=1; continue ;; esac
    how[$p]="${how[$p]:+${how[$p]}; }$e"
  done < "$T/chg"
  n=${#how[@]}
  chgset=""
  if [ "$n" -gt 0 ]; then
    chgset=$(printf '%s\n' "${!how[@]}" | LC_ALL=C sort -u)
    while IFS= read -r p; do printf 'GATE-ANCHOR CHANGED %s\n  (%s)\n' "$p" "${how[$p]}"; done <<< "$chgset"
  fi
  obs gate_anchor_changed "$n"
  ackset=$(printf '%s' "${AIEN_GATE_ANCHOR_ACK:-}" | tr -s '[:space:]' '\n' | grep . | LC_ALL=C sort -u)
  [ "$bad" = 0 ] || return 1
  if [ "$n" = 0 ] && [ -z "$ackset" ]; then return 0; fi
  if [ "$ackset" = "$chgset" ]; then
    echo "GATE-ANCHOR ACKNOWLEDGED changed=$n: AIEN_GATE_ANCHOR_ACK names exactly the changed set"; return 0
  fi
  if [ -z "$ackset" ]; then
    echo "GATE-ANCHOR BLOCKED_OPERATOR changed=$n: gate-integrity files changed against $base; the operator run reviews them, lists them in the landing receipt and sets AIEN_GATE_ANCHOR_ACK to exactly these paths"
  else
    echo "GATE-ANCHOR BLOCKED_OPERATOR changed=$n: AIEN_GATE_ANCHOR_ACK is not the changed set (acknowledged, not changed: $(LC_ALL=C comm -23 <(echo "$ackset") <(echo "$chgset") | tr '\n' ' '); changed, not acknowledged: $(LC_ALL=C comm -13 <(echo "$ackset") <(echo "$chgset") | tr '\n' ' '))"
  fi
  return 1
}

# controls: each copies a throwaway repository (a base holding the list, an anchored file, an anchored
# folder, a free file and this script; then one commit on the free file), makes one change, and runs
# the check there. ctl runs anchorcheck in this process; sctl runs the copy's tools/gate_anchor.sh.
# A control that must fail prints CONTROL OMEGA-GATE-ANCHOR/<name> FAILED_AS_REQUIRED when it does.
controls() {
  local C=$T/ctl
  mkdir -p "$C/proto" || return 1
  ( cd "$C/proto" && clear_git_env && g init -q &&
    mkdir -p gates pins/sub tools && printf '#!/bin/sh\necho gate\n' > gates/g.sh && chmod +x gates/g.sh &&
    printf 'pin a\n' > pins/a.pin && printf 'pin b\n' > pins/sub/b.pin && printf 'free\n' > free.txt &&
    printf '# anchors\ngates/g.sh\npins/\n' > tools/gate-anchors.txt && cp "$SELF" tools/gate_anchor.sh &&
    g add -A && g commit -qm base && g update-ref refs/remotes/origin/main HEAD &&
    echo more >> free.txt && g commit -qam work
  ) > "$C/proto.log" 2>&1 || { echo "FAIL controls: cannot build the throwaway repository: $(tr '\n' ' ' < "$C/proto.log")"; return 1; }
  : > "$C/keys"
  local E='echo x >> gates/g.sh && g commit -qam e' E2='echo x >> gates/g.sh && echo y >> pins/a.pin && g commit -qam e'
  ctl untouched 0 '' ':'
  ctl base-advanced 0 '' 'g checkout -q -b adv origin/main && echo x >> gates/g.sh && g commit -qam adv && g update-ref refs/remotes/origin/main HEAD && g checkout -q main'
  ctl edited 1 'GATE-ANCHOR CHANGED gates/g.sh' "$E"
  ctl deleted 1 'GATE-ANCHOR CHANGED pins/a.pin' 'g rm -q pins/a.pin && g commit -qm d'
  ctl renamed-out 1 'GATE-ANCHOR CHANGED gates/g.sh' 'g mv gates/g.sh g.sh && g commit -qm r'
  ctl mode-changed 1 'GATE-ANCHOR CHANGED gates/g.sh' 'chmod -x gates/g.sh && g add -A && g commit -qm m'
  ctl type-changed 1 'GATE-ANCHOR CHANGED pins/a.pin' 'rm pins/a.pin && ln -s sub/b.pin pins/a.pin && g add -A && g commit -qm t'
  ctl added-in-folder 1 'GATE-ANCHOR CHANGED pins/sub/new.pin' 'echo n > pins/sub/new.pin && g add -A && g commit -qm a'
  ctl list-entry-dropped 1 'GATE-ANCHOR CHANGED pins/a.pin' 'sed -i "/^pins\//d" tools/gate-anchors.txt && echo x >> pins/a.pin && g commit -qam l'
  ctl list-deleted 1 'GATE-ANCHOR CHANGED gates/g.sh' 'g rm -q tools/gate-anchors.txt && echo x >> gates/g.sh && g commit -qam l'
  ctl script-edited 1 'GATE-ANCHOR CHANGED tools/gate_anchor.sh' 'echo "# x" >> tools/gate_anchor.sh && g commit -qam s'
  ctl bad-entry 1 'is not a plain relative path' 'echo "../outside" >> tools/gate-anchors.txt && g commit -qam b' 'export AIEN_GATE_ANCHOR_ACK=tools/gate-anchors.txt'
  ctl staged 1 'GATE-ANCHOR CHANGED gates/g.sh' 'echo x >> gates/g.sh && g add gates/g.sh'
  ctl worktree-edit 1 'GATE-ANCHOR CHANGED gates/g.sh' 'echo x >> gates/g.sh'
  ctl worktree-mode 1 'GATE-ANCHOR CHANGED gates/g.sh' 'chmod -x gates/g.sh'
  ctl untracked-in-folder 1 'GATE-ANCHOR CHANGED pins/extra.pin' 'echo x > pins/extra.pin'
  ctl ack-exact 0 'GATE-ANCHOR ACKNOWLEDGED changed=2' "$E2" 'export AIEN_GATE_ANCHOR_ACK="pins/a.pin gates/g.sh"'
  ctl ack-subset 1 'changed, not acknowledged: pins/a.pin' "$E2" 'export AIEN_GATE_ANCHOR_ACK=gates/g.sh'
  ctl ack-superset 1 'acknowledged, not changed: pins/a.pin' "$E" 'export AIEN_GATE_ANCHOR_ACK="gates/g.sh pins/a.pin"'
  ctl ack-without-change 1 'acknowledged, not changed: gates/g.sh' ':' 'export AIEN_GATE_ANCHOR_ACK=gates/g.sh'
  ctl git-dir-knob 1 'GATE-ANCHOR CHANGED gates/g.sh' "$E" 'export GIT_DIR=$C/proto/.git GIT_WORK_TREE=$C/proto'
  ctl replace-ref 1 'GATE-ANCHOR CHANGED gates/g.sh' "b=\$(g rev-parse HEAD) && $E && g replace HEAD \"\$b\""
  ctl shallow 3 'GATE-ANCHOR NOT_RUN: shallow' 'cd .. && rm -rf shallow && g clone -q --depth 1 "file://$C/proto" shallow && cd shallow && g update-ref refs/remotes/origin/main HEAD' '' shallow
  ctl no-git 3 'GATE-ANCHOR NOT_RUN' 'cd .. && rm -rf no-git && mkdir no-git && g -C "$C/proto" archive HEAD | tar -x -C no-git' 'export GIT_CEILING_DIRECTORIES=$C' no-git
  ctl no-base 3 'GATE-ANCHOR NOT_RUN: base ref' ':' 'export AIEN_BASE_REF=refs/heads/no-such-base'
  # the copy's own check is weakened (its anchorcheck returns 0 at once): the base ref's copy still runs
  sctl head-copy-weakened 1 'GATE-ANCHOR CHANGED gates/g.sh' 'sed -i "s/^anchorcheck() { # BODY\$/anchorcheck() { return 0/" tools/gate_anchor.sh && ! cmp -s tools/gate_anchor.sh "$SELF" && '"$E"
  sctl control-run-never-passes 3 'GATE-ANCHOR NOT_RUN: control run' ':'
  local want got
  want=$(printf '%s\n' $CONTROLS | sort); got=$(sort "$C/keys")
  if [ "$want" != "$got" ]; then
    echo "FAIL controls: the controls that passed are not the list (missing: $(comm -23 <(echo "$want") <(echo "$got") | tr '\n' ' '); unlisted or repeated: $(printf '%s\n' "$got" | uniq -d | tr '\n' ' ')$(comm -13 <(echo "$want") <(echo "$got" | sort -u) | tr '\n' ' '))"
    return 1
  fi
}
# ctlres NAME WANT EXPECT RC OUT: judge one control run
ctlres() {
  if [ "$4" = "$2" ] && { [ -z "$3" ] || grep -qF -- "$3" "$5"; } &&
    case $2 in 0) true ;; 1) grep -q '^GATE-ANCHOR \(CHANGED\|BLOCKED_OPERATOR\|FAIL\)' "$5" ;; 3) grep -q '^GATE-ANCHOR NOT_RUN' "$5" ;; esac; then
    if [ "$2" = 0 ]; then echo "PASS control $1 (exit 0)"; else echo "CONTROL $GATE/$1 FAILED_AS_REQUIRED"; fi
    echo "$1" >> "$T/ctl/keys"
  else
    echo "FAIL control $1: exit $4, expected $2${3:+ with '$3'}: $(grep -v '^AIEN-OBS' "$5" | tr '\n' ' ' | cut -c1-400)"
  fi
}
# ctl NAME WANT EXPECT CHANGE [ENV [DIR]]: copy the throwaway repository to NAME, make CHANGE there
# (shell; may cd into DIR next to it), then run anchorcheck with ENV (shell) in effect
ctl() {
  local C=$T/ctl rc=0 d=$T/ctl/$1
  cp -a "$C/proto" "$d" || { echo "FAIL control $1: cannot copy the throwaway repository"; return; }
  if ! ( cd "$d" && clear_git_env && eval "$4" ) > "$C/$1.setup" 2>&1; then
    echo "FAIL control $1: the change could not be made: $(tr '\n' ' ' < "$C/$1.setup" | cut -c1-300)"; return
  fi
  ( cd "$C/${6:-$1}" && export AIEN_BASE_REF=origin/main && unset AIEN_GATE_ANCHOR_ACK && eval "${5:-:}" && anchorcheck ) > "$C/$1.out" 2>&1 || rc=$?
  ctlres "$1" "$2" "$3" "$rc" "$C/$1.out"
}
# sctl NAME WANT EXPECT CHANGE: as ctl, but runs the copy's tools/gate_anchor.sh in control-run mode
sctl() {
  local C=$T/ctl rc=0 d=$T/ctl/$1
  cp -a "$C/proto" "$d" || { echo "FAIL control $1: cannot copy the throwaway repository"; return; }
  if ! ( cd "$d" && clear_git_env && eval "$4" ) > "$C/$1.setup" 2>&1; then
    echo "FAIL control $1: the change could not be made: $(tr '\n' ' ' < "$C/$1.setup" | cut -c1-300)"; return
  fi
  ( cd "$d" && clear_git_env && unset AIEN_GATE_ANCHOR_ACK &&
    AIEN_BASE_REF=origin/main AIEN_GATE_ANCHOR_CONTROL_RUN=1 bash tools/gate_anchor.sh ) > "$C/$1.out" 2>&1 || rc=$?
  ctlres "$1" "$2" "$3" "$rc" "$C/$1.out"
}

[ $# = 0 ] || { echo "GATE-ANCHOR FAIL: $ME takes no arguments (AIEN_BASE_REF names the base)"; exit 1; }
T=$(mktemp -d "${TMPDIR:-/tmp}/gate-anchor.XXXXXX") || { echo "GATE-ANCHOR NOT_RUN: mktemp failed"; exit 3; }
trap 'rm -rf "$T"' EXIT
clear_git_env
# the base ref's copy of this script, when its bytes differ from this file's
brc=0
if top=$(git rev-parse --show-toplevel 2> /dev/null) && cd "$top" &&
  bcb=$(git rev-parse --verify -q "${AIEN_BASE_REF:-origin/main}^{commit}") && git cat-file -e "$bcb:$ME" 2> /dev/null; then
  bb=$(git rev-parse "$bcb:$ME"); own=$(git hash-object --no-filters -- "$SELF")
  if [ "$bb" != "$own" ]; then
    echo "GATE-ANCHOR BASE-COPY: the base ref's $ME (blob $bb) differs from this file ($own); it runs first"
    if git cat-file blob "$bb" > "$T/base-copy.sh"; then bash "$T/base-copy.sh" || brc=$?; else brc=1; fi
    echo "GATE-ANCHOR BASE-COPY exit $brc"
  fi
fi
if [ -n "${AIEN_GATE_ANCHOR_CONTROL_RUN:-}" ]; then
  rc=0; anchorcheck > "$T/real" 2>&1 || rc=$?
  cat "$T/real"
  [ "$rc" = 0 ] && { echo "GATE-ANCHOR NOT_RUN: control run (AIEN_GATE_ANCHOR_CONTROL_RUN): its controls did not run, so it does not pass"; rc=3; }
  exit "$(worst "$brc" "$rc")"
fi
cbad=0
controls > "$T/controls" 2>&1 || cbad=1
cat "$T/controls"
grep -q '^FAIL' "$T/controls" && cbad=1
nctl=$(grep -c '^\(PASS control\|CONTROL \)' "$T/controls")
rc=0; anchorcheck > "$T/real" 2>&1 || rc=$?
cat "$T/real"
n=$(sed -n 's/^AIEN-OBS gate_anchor_changed //p' "$T/real"); n=${n:-0}
fin=$(worst "$brc" "$rc" "$cbad")
if [ "$cbad" != 0 ]; then echo "GATE-ANCHOR FAIL: controls"
elif [ "$fin" = 1 ] && grep -q '^GATE-ANCHOR BLOCKED_OPERATOR' "$T/real"; then echo "GATE-ANCHOR BLOCKED_OPERATOR controls=$nctl changed=$n"
elif [ "$fin" = 1 ] && [ "$rc" = 1 ]; then echo "GATE-ANCHOR FAIL controls=$nctl (above)"
elif [ "$fin" = 1 ]; then echo "GATE-ANCHOR FAIL: the base ref's copy exited $brc (above)"
elif [ "$fin" = 3 ]; then echo "GATE-ANCHOR NOT_RUN controls=$nctl (above)"
else echo "GATE-ANCHOR PASS controls=$nctl changed=$n"; fi
exit "$fin"
