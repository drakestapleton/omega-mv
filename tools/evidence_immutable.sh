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

# tools/evidence_immutable.sh: OMEGA-EVIDENCE-IMMUTABLE (tests/gates/run.sh evidence-immutable) and
# the unchanged-receipt check of the kernel hw-gates gate. Reviewed evidence is additions only.
#   tools/evidence_immutable.sh           the folders in DEFAULT_PATHS below
#   tools/evidence_immutable.sh PATH...   those paths, relative to the repository root
#                                         (kernel/tools/hwgates/gate.sh: kernel/evidence kernel/import)
# Exit 0 PASS, 1 FAIL, 3 NOT_RUN (no history to compare with: not a git work tree, a shallow clone,
# or no base ref [ctl:OMEGA-EVIDENCE-IMMUTABLE/shallow] [ctl:OMEGA-EVIDENCE-IMMUTABLE/no-git]
# [ctl:OMEGA-EVIDENCE-IMMUTABLE/no-base]). NOT_RUN is not a pass.
#
# Base copy: when the base ref (AIEN_BASE_REF, default origin/main) holds a tools/evidence_immutable.sh
# with other bytes than this file, that copy runs first with the same arguments (none when none were
# given, so it checks its own default paths [ctl:OMEGA-EVIDENCE-IMMUTABLE/base-copy-own-defaults]; its output prefixed
# "base-copy: "), then this file's own check; the exit is the worse of the two, 1 over 3 over 0
# [ctl:OMEGA-EVIDENCE-IMMUTABLE/base-copy-runs] [ctl:OMEGA-EVIDENCE-IMMUTABLE/base-copy-same]. So the
# import commit and the trust logic of the base still run when a head edits IMPORT, the default paths
# or anything below this script's first statements. A head that edits those first statements is not
# caught here; tools/gate_anchor.sh reports this file as GATE-ANCHOR CHANGED [ctl:OMEGA-GATE-ANCHOR/edited].
#
# A file HEAD tracks under PATH is protected. The check fails when
#  1. base: a protected file of the merge base of the base ref and HEAD is modified, deleted, renamed
#     or changed in type at HEAD [ctl:OMEGA-EVIDENCE-IMMUTABLE/base-file-edited];
#  2. import: HEAD descends from $IMPORT, the commit that brought aienux in as kernel/, and a
#     protected file of that commit is modified, deleted, renamed or changed in type at HEAD; or HEAD
#     has kernel/ and does not descend from that commit [ctl:OMEGA-EVIDENCE-IMMUTABLE/rebuilt-on-base];
#     or the oldest commit on HEAD's first-parent line that changes kernel/ is not $IMPORT
#     [ctl:OMEGA-EVIDENCE-IMMUTABLE/import-moved-forward];
#  3. history: a commit reachable from HEAD and not from $IMPORT modifies, deletes, renames or
#     changes the type of a protected file under kernel/ against one of its parents (a merge is
#     compared with each parent; a rename is a delete) [ctl:OMEGA-EVIDENCE-IMMUTABLE/edit-reverted]
#     [ctl:OMEGA-EVIDENCE-IMMUTABLE/orphan-merge-receipt]. evidence/ keeps the hosted rule (1),
#     which allows a file added on the unlanded branch to change before it lands;
#  4. index and work tree: a protected file of HEAD is staged as modified or deleted, or its
#     work-tree copy is missing, is not the regular file or symlink HEAD has, or differs from HEAD
#     in raw bytes (hashed with no filters) or executable bit [ctl:OMEGA-EVIDENCE-IMMUTABLE/worktree-edit]
#     [ctl:OMEGA-EVIDENCE-IMMUTABLE/crlf-attributes] [ctl:OMEGA-EVIDENCE-IMMUTABLE/worktree-mode].
# kernel/ paths are NOT_RUN (exit 3, the other paths still checked) when the base ref has no
# tools/evidence_immutable.sh, since $IMPORT would then come from the head alone
# [ctl:OMEGA-EVIDENCE-IMMUTABLE/kernel-base-without-script]
# [ctl:OMEGA-EVIDENCE-IMMUTABLE/evidence-base-without-script]. origin/main has no kernel/ yet: run
# with AIEN_BASE_REF set to the branch the head lands on.
# Before the check it runs its controls (CONTROLS below) on throwaway repositories, each a way
# through that a reviewer or the author tried, and fails unless each one gives its expected exit;
# a control that must fail prints CONTROL OMEGA-EVIDENCE-IMMUTABLE/<name> FAILED_AS_REQUIRED.
# The environment does not point the check at another repository: GIT_* variables other than
# GIT_CEILING_DIRECTORIES are cleared, and replace refs and grafts are ignored
# [ctl:OMEGA-EVIDENCE-IMMUTABLE/git-dir-knob] [ctl:OMEGA-EVIDENCE-IMMUTABLE/replace-ref]
# [ctl:OMEGA-EVIDENCE-IMMUTABLE/grafts].
# Limits: (1) holds against the base the caller names; with AIEN_BASE_REF=HEAD the head is its own
# base. A head rebuilt so that it no longer descends from a commit that added a kernel/ file after
# $IMPORT escapes (3); naming a base that holds that commit catches it through (1). Untracked files
# are not evidence and are not read. Folders named evidence/ or receipts/ outside DEFAULT_PATHS are
# not checked (FOLDERS.md names them).
# AIEN_EVIMM_CONTROL_RUN=1 is how the controls run this script in a throwaway repository: after the
# base copy it stops with NOT_RUN, so it does not pass.
set -u
IMPORT=67945327139b31a6eb60cff62d0e5823a77249de
# the folders checked when no PATH is given: omega-mv's evidence/ and the kernel's receipt folders
DEFAULT_PATHS="evidence kernel/evidence kernel/import kernel/native/om/lm1b/evidence kernel/native/net/receipts
kernel/docs/design/boot/receipts"
# Every control, by name; each must run and give its expected exit (asserted, not only printed).
CONTROLS="untouched added no-kernel-untouched base-file-edited base-file-edited-without-kernel
correction-deleted-decoy-added orphan-merge-receipt orphan-merge-commit-map orphan-first-parent
orphan-merge-late-file late-file-deleted edit-reverted renamed symlink-committed mode-committed
worktree-edit worktree-symlink worktree-symlink-retargeted worktree-mode staged-delete crlf-attributes
kernel-deleted rebuilt-on-base base-ref-knob git-dir-knob replace-ref grafts shallow no-git no-base
import-moved-forward kernel-base-without-script evidence-base-without-script base-copy-runs base-copy-own-defaults base-copy-same"

obs() { printf 'AIEN-OBS %s %s\n' "$1" "$2"; }
word() { case $1 in M) echo modified ;; D) echo deleted ;; T) echo "changed in type" ;; *) echo "changed ($1)" ;; esac; }
clear_git_env() {
  local v
  for v in $(compgen -e); do
    case $v in GIT_CEILING_DIRECTORIES) ;; GIT_*) unset "$v" ;; esac
  done
  export GIT_NO_REPLACE_OBJECTS=1 GIT_GRAFT_FILE=/nonexistent/evidence-immutable-grafts
}

# evcheck ANCHOR PATH...: the check, run inside the work tree to check (ANCHOR is $IMPORT, or the
# throwaway repository's own import commit). One FAIL line per problem; returns 0, 1 or 3.
evcheck() {
  local anchor=$1 top base bc mb imp="" bad=0 nr=0 a st p c line mode type id ent meta from first
  local -a walk=() keep=()
  shift
  clear_git_env
  top=$(git rev-parse --show-toplevel 2> /dev/null) || { echo "NOT_RUN: $PWD is not in a git work tree, so there is no history to compare with"; return 3; }
  cd "$top" || return 3
  if [ "$(git rev-parse --is-shallow-repository 2> /dev/null)" != false ]; then
    echo "NOT_RUN: shallow clone: the commits to compare with are missing (fetch the full history)"; return 3
  fi
  base=${AIEN_BASE_REF:-origin/main}
  bc=$(git rev-parse --verify -q "$base^{commit}") || { echo "NOT_RUN: base ref '$base' is not a commit here (set AIEN_BASE_REF to the branch this head lands on)"; return 3; }
  obs base_ref "\"$bc\""
  mb=$(git merge-base "$bc" HEAD) || { echo "FAIL: HEAD shares no history with $base"; return 1; }
  # without the script on the base, the import commit would come from the head alone: kernel/ paths
  # are NOT_RUN, the others are still checked against the merge base
  if ! git cat-file -e "$bc:tools/evidence_immutable.sh" 2> /dev/null; then
    for p in "$@"; do case ${p%/}/ in kernel/*) nr=1 ;; *) keep+=("$p") ;; esac; done
    if [ "$nr" = 1 ]; then
      echo "NOT_RUN: base $base (${bc:0:12}) has no tools/evidence_immutable.sh, so the kernel/ import commit cannot be taken from the base: kernel/ paths not checked (set AIEN_BASE_REF to the branch this head lands on)"
      [ ${#keep[@]} -gt 0 ] || return 3
      set -- "${keep[@]}"
    fi
  elif git merge-base --is-ancestor "$anchor" HEAD 2> /dev/null; then
    imp=$anchor
    first=$(git rev-list --first-parent --reverse HEAD -- kernel | head -n 1)
    if [ "$first" != "$anchor" ]; then
      echo "FAIL: the oldest commit on HEAD's first-parent line that changes kernel/ is ${first:-none}, not $anchor, the import commit this check names"; bad=1
    fi
  elif git cat-file -e HEAD:kernel 2> /dev/null; then
    echo "FAIL: HEAD has kernel/ but does not descend from $anchor, the commit that brought kernel/ in"; bad=1
  fi
  # 1 and 2: protected files of the merge base and of the import, at HEAD
  for a in "$mb" $imp; do
    from="the merge base with $base"; [ "$a" = "$imp" ] && from="the kernel/ import"
    git -c core.quotePath=false diff-tree -r --no-renames --name-status --diff-filter=MDT "$a" HEAD -- "$@" > "$T/net" ||
      { echo "FAIL: git diff-tree $a HEAD failed"; bad=1; continue; }
    while IFS=$'\t' read -r st p; do
      echo "FAIL: $p is $(word "$st") at HEAD against ${a:0:12} ($from)"; bad=1
    done < "$T/net"
  done
  # 3: every commit after the import, against each parent, for the paths under kernel/
  for p in "$@"; do case ${p%/}/ in kernel/*) walk+=("$p") ;; esac; done
  if [ -n "$imp" ] && [ ${#walk[@]} -gt 0 ]; then
    if git rev-list --parents HEAD --not "$imp" > "$T/revs" &&
      git -c core.quotePath=false diff-tree --stdin -m -r --no-renames --name-status --diff-filter=MDT -- "${walk[@]}" < "$T/revs" > "$T/walk"; then
      c=""
      while IFS= read -r line; do
        case $line in
          *$'\t'*) echo "FAIL: commit ${c:0:12} leaves ${line#*$'\t'} $(word "${line%%$'\t'*}") against one of its parents"; bad=1 ;;
          *) c=$line ;;
        esac
      done < "$T/walk"
    else echo "FAIL: cannot walk the commits after $imp"; bad=1; fi
  fi
  # 4: index and work tree against HEAD
  git -c core.quotePath=false diff-index --cached --no-renames --name-status --diff-filter=MDT HEAD -- "$@" > "$T/idx" ||
    { echo "FAIL: git diff-index failed"; bad=1; }
  while IFS=$'\t' read -r st p; do echo "FAIL: $p is staged as $(word "$st")"; bad=1; done < "$T/idx"
  git ls-tree -r -z HEAD -- "$@" > "$T/tree" || { echo "FAIL: git ls-tree HEAD failed"; bad=1; }
  : > "$T/reg"; : > "$T/ids"
  while IFS= read -r -d '' ent; do
    meta=${ent%%$'\t'*}; p=${ent#*$'\t'}
    read -r mode type id <<< "$meta"
    case $p in *$'\n'*) echo "FAIL: a protected path holds a newline: $(printf '%q' "$p")"; bad=1; continue ;; esac
    case $mode in
      120000)
        if [ ! -L "$p" ] || [ "$(printf '%s' "$(readlink "$p")" | git hash-object --stdin)" != "$id" ]; then
          echo "FAIL: $p is not, in the work tree, the symlink HEAD has"; bad=1
        fi ;;
      100644|100755)
        if [ -L "$p" ] || [ ! -f "$p" ]; then echo "FAIL: $p is missing or not a regular file in the work tree"; bad=1
        elif { [ "$mode" = 100755 ] && [ ! -x "$p" ]; } || { [ "$mode" = 100644 ] && [ -x "$p" ]; }; then
          echo "FAIL: $p has another executable bit in the work tree than HEAD's $mode"; bad=1
        else printf '%s\n' "$p" >> "$T/reg"; printf '%s\n' "$id" >> "$T/ids"; fi ;;
      *) echo "FAIL: $p has mode $mode at HEAD, not a file or symlink"; bad=1 ;;
    esac
  done < "$T/tree"
  if [ -s "$T/reg" ]; then
    if git hash-object --no-filters --stdin-paths < "$T/reg" > "$T/got"; then
      while IFS=$'\t' read -r id c p; do
        [ "$id" = "$c" ] || { echo "FAIL: $p differs in the work tree from HEAD (raw bytes $c, HEAD $id)"; bad=1; }
      done < <(paste "$T/ids" "$T/got" "$T/reg")
    else echo "FAIL: cannot hash the protected files in the work tree"; bad=1; fi
  fi
  [ "$bad" = 0 ] || return 1
  [ "$nr" = 0 ] || return 3
  return 0
}

# controls: each builds a copy of a throwaway repository shaped like this one (a base with evidence/,
# then the commit that brings kernel/ in, then a kernel/ correction added after it), makes one change,
# and runs evcheck on it. Two must pass; the rest must fail (exit 1) or be NOT_RUN (exit 3).
controls() {
  local C=$T/ctl
  mkdir -p "$C/proto" || return 1
  ( cd "$C/proto" && clear_git_env && g init -q &&
    mkdir -p evidence tools && printf 'base receipt\n' > evidence/BASE.txt && printf 'a base copy of the script\n' > tools/evidence_immutable.sh &&
    g add -A && g commit -qm base &&
    g update-ref refs/remotes/origin/main HEAD &&
    mkdir -p kernel/evidence/R kernel/import &&
    printf 'receipt\nHWGATE ZZ HOST PASS\nHWGATE ZZ PHYSICAL NOT_RUN\n' > kernel/evidence/R/RECEIPT.txt &&
    printf 'CORRECTS HWGATE ZZ HOST PASS\n' > kernel/evidence/R/CORRECTION-1.txt &&
    printf 'old new\n%040d %040d\n' 1 2 > kernel/import/commit-map && ln -s RECEIPT.txt kernel/evidence/R/latest &&
    g add -A && g commit -qm import &&
    g rev-parse HEAD > "$C/anchor" &&
    printf 'a later correction\n' > kernel/evidence/R/CORRECTION-2.txt && g add -A && g commit -qm late
  ) > "$C/proto.log" 2>&1 || { echo "FAIL controls: cannot build the throwaway repository: $(tr '\n' ' ' < "$C/proto.log")"; return 1; }
  : > "$C/keys"
  local R=kernel/evidence/R/RECEIPT.txt M=kernel/import/commit-map L=kernel/evidence/R/CORRECTION-2.txt
  # orphan PATH TEXT [first]: PATH holding TEXT arrives as the file of an unrelated, older root commit,
  # merged with --allow-unrelated-histories (first: the forged root is the first parent)
  local orphan='h=$(g rev-parse HEAD) && g checkout -q --orphan forged && g rm -rqf . && mkdir -p "$(dirname "$1")" &&
    printf "%s" "$2" > "$1" && g add -A && GIT_AUTHOR_DATE=2020-01-01T00:00:00Z GIT_COMMITTER_DATE=2020-01-01T00:00:00Z g commit -qm "$1" &&
    f=$(g rev-parse HEAD) && if [ "${3:-}" = first ]; then x=$h; else g checkout -q -f --detach "$h"; x=$f; fi &&
    { g merge -q --allow-unrelated-histories --no-commit "$x" > /dev/null 2>&1 || true; } &&
    g show "$f:$1" > "$1" && g add -A && g commit -qm merge'
  ctl untouched 0 ':'
  ctl no-kernel-untouched 0 'g reset -q --hard origin/main'
  ctl added 0 'mkdir -p kernel/evidence/S && echo new > kernel/evidence/S/NEW.txt && echo new > evidence/NEW.txt && g add -A && g commit -qm add'
  ctl base-file-edited 1 'echo edit >> evidence/BASE.txt && g commit -qam edit'
  ctl base-file-edited-without-kernel 1 'g reset -q --hard origin/main && echo edit >> evidence/BASE.txt && g commit -qam edit'
  ctl correction-deleted-decoy-added 1 'g rm -q kernel/evidence/R/CORRECTION-1.txt && printf "decoy\nCORRECTS HWGATE ZZ QEMU PASS\n" > kernel/evidence/R/CORRECTION-3.txt && g add -A && g commit -qm swap'
  ctl orphan-merge-receipt 1 "set -- $R \"\$(cat $R; echo HWGATE ZZ PHYSICAL PASS)\"; $orphan"
  ctl orphan-merge-commit-map 1 "set -- $M \"\$(sed s/0000000000000000000000000000000000000002/ffffffffffffffffffffffffffffffffffffffff/ $M)\"; $orphan"
  ctl orphan-first-parent 1 "set -- $R \"\$(cat $R; echo HWGATE ZZ PHYSICAL PASS)\" first; $orphan"
  ctl orphan-merge-late-file 1 "set -- $L \"\$(cat $L; echo CORRECTS HWGATE ZZ PHYSICAL NOT_RUN)\"; $orphan"
  ctl late-file-deleted 1 "g rm -q $L && g commit -qm delete"
  ctl edit-reverted 1 "echo HWGATE ZZ PHYSICAL PASS >> $R && g commit -qam edit && g revert --no-edit HEAD > /dev/null"
  ctl renamed 1 "g mv $R kernel/evidence/R/RECEIPT-old.txt && g commit -qm rename"
  ctl symlink-committed 1 "cp $R kernel/evidence/R/copy && rm $R && ln -s copy $R && g add -A && g commit -qm link"
  ctl mode-committed 1 "chmod +x $R && g add -A && g commit -qm mode"
  ctl worktree-edit 1 "echo HWGATE ZZ PHYSICAL PASS >> $R"
  ctl worktree-symlink 1 "cp $R ../copy && rm $R && ln -s \"\$PWD/../copy\" $R"
  ctl worktree-symlink-retargeted 1 "ln -sfn CORRECTION-1.txt kernel/evidence/R/latest"
  ctl worktree-mode 1 "chmod +x $R"
  ctl staged-delete 1 "g rm -q --cached $L"
  ctl crlf-attributes 1 "printf '* text\n' > kernel/evidence/.gitattributes && g add -A && g commit -qm attributes && sed -i 's/\$/\r/' $R"
  ctl kernel-deleted 1 'g rm -rq kernel && g commit -qm delete'
  ctl rebuilt-on-base 1 "sed -i s/NOT_RUN/PASS/ $R && g add -A && g reset -q --soft origin/main && g commit -qm rebuilt"
  ctl base-ref-knob 1 "g rm -q $L && g commit -qm delete" 'export AIEN_BASE_REF=HEAD'
  ctl git-dir-knob 1 "g rm -q $L && g commit -qm delete" "export GIT_DIR=$C/proto/.git GIT_WORK_TREE=$C/proto"
  # replace-ref: the import commit and the late commit replaced by copies holding the forged receipt,
  # so with replace refs honored no commit after the import changes it
  ctl replace-ref 1 "a=\$(cat $C/anchor) && p=\$(g rev-parse HEAD) && echo HWGATE ZZ PHYSICAL PASS >> $R && g commit -qam edit &&
    b=\$(g hash-object -w $R) && GIT_INDEX_FILE=.git/forged g read-tree \"\$a\" && GIT_INDEX_FILE=.git/forged g update-index --cacheinfo 100644,\$b,$R &&
    g replace \"\$a\" \"\$(g commit-tree \"\$(GIT_INDEX_FILE=.git/forged g write-tree)\" -p \"\$(g rev-parse \"\$a^\")\" -m import)\" &&
    g replace \"\$p\" \"\$(g commit-tree \"\$(g rev-parse HEAD^{tree})\" -p \"\$a\" -m late)\""
  ctl grafts 1 "g rm -q $L && g commit -qm delete && printf '%s %s\n' \"\$(g rev-parse HEAD)\" \"\$(cat $C/anchor)\" > .git/info/grafts"
  ctl shallow 3 "cd .. && rm -rf shallow && g clone -q --depth 1 file://$C/proto shallow && cd shallow && g update-ref refs/remotes/origin/main HEAD" '' shallow
  ctl no-git 3 "cd .. && rm -rf no-git && mkdir no-git && g -C $C/proto archive HEAD | tar -x -C no-git" "export GIT_CEILING_DIRECTORIES=$C" no-git
  ctl no-base 3 ':' 'export AIEN_BASE_REF=refs/heads/no-such-base'
  # the receipt edited in one commit that the script then names as the import (IMPORT moved forward)
  ctl import-moved-forward 1 'echo "HWGATE ZZ PHYSICAL PASS" >> $R && g commit -qam edit && g rev-parse HEAD > "$PWD.anchor" && echo x > free.txt && g add -A && g commit -qm next'
  # a base without the script: kernel/ paths NOT_RUN; an evidence/ edit still fails
  local nb='g checkout -q -b nb origin/main && g rm -q tools/evidence_immutable.sh && g commit -qm nb && g update-ref refs/remotes/origin/main HEAD && g checkout -q main'
  ctl kernel-base-without-script 3 "$nb && echo HWGATE ZZ PHYSICAL PASS >> $R && g commit -qam edit"
  ctl evidence-base-without-script 1 "$nb && echo edit >> evidence/BASE.txt && g commit -qam edit"
  # the base ref's copy runs when it differs from the running file, and only then
  sctl base-copy-runs 1 'base-copy: EVIMM-STUB-RAN evidence' '' 'echo "echo EVIMM-STUB-RAN \"\$*\"; exit 1" > tools/evidence_immutable.sh && g commit -qam stub && g update-ref refs/remotes/origin/main HEAD && cp "$SELF" tools/evidence_immutable.sh && g commit -qam head'
  sctl base-copy-own-defaults 1 'base-copy: EVIMM-STUB-RAN <>' '' 'echo "echo EVIMM-STUB-RAN \"<\$*>\"; exit 1" > tools/evidence_immutable.sh && g commit -qam stub && g update-ref refs/remotes/origin/main HEAD && cp "$SELF" tools/evidence_immutable.sh && g commit -qam head' noargs
  sctl base-copy-same 3 'EVIDENCE-IMMUTABLE NOT_RUN: control run' 'BASE-COPY' 'cp "$SELF" tools/evidence_immutable.sh && g commit -qam same && g update-ref refs/remotes/origin/main HEAD'
  local want got
  want=$(printf '%s\n' $CONTROLS | sort); got=$(sort "$C/keys")
  if [ "$want" != "$got" ]; then
    echo "FAIL controls: the controls that passed are not the list (missing: $(comm -23 <(echo "$want") <(echo "$got") | tr '\n' ' '); unlisted or repeated: $(printf '%s\n' "$got" | uniq -d | tr '\n' ' ')$(comm -13 <(echo "$want") <(echo "$got" | sort -u) | tr '\n' ' '))"
    return 1
  fi
}
g() { git -c user.name=evimm -c user.email=evimm@invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null -c init.defaultBranch=main -c advice.detachedHead=false "$@"; }
# ctl NAME WANT CHANGE [ENV [DIR]]: copy the throwaway repository to NAME, make CHANGE there (shell, may
# cd into DIR next to it), then run evcheck with ENV (shell) in effect; WANT is the exit it must give,
# with a FAIL line for 1 and a NOT_RUN line for 3.
ctl() {
  local C=$T/ctl rc=0 d=$T/ctl/$1
  cp -a "$C/proto" "$d" || { echo "FAIL control $1: cannot copy the throwaway repository"; return; }
  if ! ( cd "$d" && clear_git_env && eval "$3" ) > "$C/$1.setup" 2>&1; then
    echo "FAIL control $1: the change could not be made: $(tr '\n' ' ' < "$C/$1.setup" | cut -c1-300)"; return
  fi
  local a; a=$(cat "$d.anchor" 2> /dev/null || cat "$C/anchor")
  ( cd "$C/${5:-$1}" && export AIEN_BASE_REF=origin/main && eval "${4:-:}" && evcheck "$a" evidence kernel/evidence kernel/import ) > "$C/$1.out" 2>&1 || rc=$?
  if [ "$rc" = "$2" ] && case $2 in 0) true ;; 1) grep -q '^FAIL' "$C/$1.out" ;; 3) grep -q '^NOT_RUN' "$C/$1.out" ;; esac; then
    ctlok "$1" "$2"
  else
    echo "FAIL control $1: exit $rc, expected $2: $(grep -v '^AIEN-OBS' "$C/$1.out" | tr '\n' ' ' | cut -c1-300)"
  fi
}
ctlok() {
  if [ "$2" = 0 ]; then echo "PASS control $1 (exit 0)"; else echo "CONTROL OMEGA-EVIDENCE-IMMUTABLE/$1 FAILED_AS_REQUIRED"; fi
  echo "$1" >> "$T/ctl/keys"
}
# sctl NAME WANT EXPECT NOTEXPECT CHANGE [noargs]: copy the throwaway repository, make CHANGE, then run the
# copy's tools/evidence_immutable.sh evidence (no PATH with noargs) in control-run mode; its output must hold EXPECT and not NOTEXPECT
sctl() {
  local C=$T/ctl rc=0 d=$T/ctl/$1 name=$1 want=$2 exp=$3 nexp=$4
  local -a run=(evidence)
  [ "${6:-}" = noargs ] && run=()
  cp -a "$C/proto" "$d" || { echo "FAIL control $name: cannot copy the throwaway repository"; return; }
  if ! ( cd "$d" && clear_git_env && eval "$5" ) > "$C/$name.setup" 2>&1; then
    echo "FAIL control $name: the change could not be made: $(tr '\n' ' ' < "$C/$name.setup" | cut -c1-300)"; return
  fi
  ( cd "$d" && AIEN_BASE_REF=origin/main AIEN_EVIMM_CONTROL_RUN=1 bash tools/evidence_immutable.sh "${run[@]}" ) > "$C/$name.out" 2>&1 || rc=$?
  if [ "$rc" = "$want" ] && grep -qF -- "$exp" "$C/$name.out" && { [ -z "$nexp" ] || ! grep -qF -- "$nexp" "$C/$name.out"; }; then
    ctlok "$name" "$want"
  else
    echo "FAIL control $name: exit $rc, expected $want with '$exp'${nexp:+ and without '$nexp'}: $(tr '\n' ' ' < "$C/$name.out" | cut -c1-300)"
  fi
}

# no PATH: the base copy gets no PATH either, so it checks its own default paths
args=$#
[ $# -gt 0 ] || set -- $DEFAULT_PATHS
T=$(mktemp -d "${TMPDIR:-/tmp}/evidence-immutable.XXXXXX") || { echo "EVIDENCE-IMMUTABLE NOT_RUN: mktemp failed"; exit 3; }
trap 'rm -rf "$T"' EXIT
SELF=$(realpath -e -- "${BASH_SOURCE[0]}") || { echo "EVIDENCE-IMMUTABLE NOT_RUN: cannot resolve the path of this script"; exit 3; }
# worst RC...: 1 over 3 over 0 (any other exit counts as 1)
worst() {
  local w=0 x
  for x in "$@"; do case $x in 0) ;; 3) [ "$w" = 0 ] && w=3 ;; *) w=1 ;; esac; done
  echo "$w"
}
# the base ref's copy of this script, when its bytes differ from this file's
brc=0
if top=$( (clear_git_env && git rev-parse --show-toplevel) 2> /dev/null) &&
  bb=$( (clear_git_env && cd "$top" && b=$(git rev-parse --verify -q "${AIEN_BASE_REF:-origin/main}^{commit}") &&
    git rev-parse --verify -q "$b:tools/evidence_immutable.sh") 2> /dev/null) &&
  own=$( (clear_git_env && cd "$top" && git hash-object --no-filters -- "$SELF") 2> /dev/null) && [ "$bb" != "$own" ]; then
  echo "EVIDENCE-IMMUTABLE BASE-COPY: the base ref's tools/evidence_immutable.sh (blob $bb) differs from this file ($own); it runs first"
  if (clear_git_env && cd "$top" && git cat-file blob "$bb") > "$T/base-copy.sh"; then
    if [ "$args" = 0 ]; then ( cd "$top" && bash "$T/base-copy.sh" ) 2>&1 | sed 's/^/base-copy: /'; brc=${PIPESTATUS[0]}
    else ( cd "$top" && bash "$T/base-copy.sh" "$@" ) 2>&1 | sed 's/^/base-copy: /'; brc=${PIPESTATUS[0]}; fi
  else brc=1; fi
  echo "EVIDENCE-IMMUTABLE BASE-COPY exit $brc"
fi
if [ -n "${AIEN_EVIMM_CONTROL_RUN:-}" ]; then
  echo "EVIDENCE-IMMUTABLE NOT_RUN: control run (AIEN_EVIMM_CONTROL_RUN): this copy's controls and checks did not run"
  exit "$(worst "$brc" 3)"
fi
cbad=0
controls > "$T/controls" 2>&1 || cbad=1
cat "$T/controls"
grep -q '^FAIL' "$T/controls" && cbad=1
nctl=$(grep -c '^\(PASS control\|CONTROL \)' "$T/controls")
rc=0; evcheck "$IMPORT" "$@" > "$T/real" 2>&1 || rc=$?
cat "$T/real"
nrw=$(grep -c '^FAIL' "$T/real")
[ "$rc" = 3 ] || obs evidence_rewrites "$nrw"
if [ "$rc" = 1 ]; then
  echo "Existing evidence would be changed (above). Add a new, content-addressed file instead of rewriting reviewed evidence."
fi
if [ "$cbad" != 0 ]; then echo "EVIDENCE-IMMUTABLE FAIL: controls"; exit 1; fi
if [ "$rc" = 1 ]; then echo "EVIDENCE-IMMUTABLE FAIL rewrites=$nrw"; exit 1; fi
case $brc in 0 | 3) ;; *) echo "EVIDENCE-IMMUTABLE FAIL: the base ref's copy exited $brc (base-copy: lines above)"; exit 1 ;; esac
if [ "$rc" = 3 ] || [ "$brc" = 3 ]; then echo "EVIDENCE-IMMUTABLE NOT_RUN: $* (above)"; exit 3; fi
echo "$*: additions only"
echo "EVIDENCE-IMMUTABLE PASS controls=$nctl"
