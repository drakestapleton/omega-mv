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
#   tools/evidence_immutable.sh           evidence/, kernel/evidence/ and kernel/import/
#   tools/evidence_immutable.sh PATH...   those paths, relative to the repository root
#                                         (kernel/tools/hwgates/gate.sh: kernel/evidence kernel/import)
# Exit 0 PASS, 1 FAIL, 3 NOT_RUN (no history to compare with: not a git work tree, a shallow clone,
# or no base ref). NOT_RUN is never a pass.
#
# A file HEAD tracks under PATH is protected. The check fails when
#  1. base: a protected file of the merge base of AIEN_BASE_REF (default origin/main) and HEAD is
#     modified, deleted, renamed or changed in type at HEAD (what the hosted evidence-immutable.yml
#     checks);
#  2. import: HEAD descends from $IMPORT, the commit that brought aienux in as kernel/, and a
#     protected file of that commit is modified, deleted, renamed or changed in type at HEAD; or
#     HEAD has kernel/ and does not descend from that commit;
#  3. history: a commit reachable from HEAD and not from $IMPORT modifies, deletes, renames or
#     changes the type of a protected file under kernel/ against any of its parents (a merge is
#     compared with every parent; a rename is a delete). kernel/ is not yet on the base, so this is
#     what keeps a kernel/ file added after the import: it cannot be deleted or rewritten, an edit
#     reverted later still fails, and a merge cannot bring in other bytes through an unrelated root
#     commit (the way the import itself came in). evidence/ is on the base and keeps the hosted rule
#     (1), which allows a file added on the unlanded branch to change before it lands;
#  4. index and work tree: a protected file of HEAD is staged as modified or deleted, or its
#     work-tree copy is missing, is not the regular file or symlink HEAD has, or differs from HEAD
#     in raw bytes (hashed with no filters, so a .gitattributes cannot hide an edit) or executable bit.
# Before the check it runs its controls (CONTROLS below) on throwaway repositories, each a way
# through that a reviewer or the author tried, and fails unless every one gives its expected exit.
# The environment cannot point the check elsewhere: every GIT_* variable but GIT_CEILING_DIRECTORIES
# is cleared, and replace refs and grafts are ignored.
# Limits: (1) holds against the base the caller names. A head rebuilt so that it no longer descends
# from a commit that added a kernel/ file after $IMPORT escapes (3); naming a base that holds that
# commit (AIEN_BASE_REF) catches it through (1). Untracked files are not evidence and are not read.
set -u
IMPORT=98671516302b85dc7c2b6d2a1e8bcf993d13e36f
# Every control, by name; each must run and give its expected exit (asserted, not only printed).
CONTROLS="untouched added no-kernel-untouched base-file-edited base-file-edited-without-kernel
correction-deleted-decoy-added orphan-merge-receipt orphan-merge-commit-map orphan-first-parent
orphan-merge-late-file late-file-deleted edit-reverted renamed symlink-committed mode-committed
worktree-edit worktree-symlink worktree-symlink-retargeted worktree-mode staged-delete crlf-attributes
kernel-deleted rebuilt-on-base base-ref-knob git-dir-knob replace-ref grafts shallow no-git no-base"

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
  local anchor=$1 top base bc mb imp="" bad=0 a st p c line mode type id ent meta from
  local -a walk=()
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
  if git merge-base --is-ancestor "$anchor" HEAD 2> /dev/null; then imp=$anchor
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
  return "$bad"
}

# controls: each builds a copy of a throwaway repository shaped like this one (a base with evidence/,
# then the commit that brings kernel/ in, then a kernel/ correction added after it), makes one change,
# and runs evcheck on it. Two must pass; the rest must fail (exit 1) or be NOT_RUN (exit 3).
controls() {
  local C=$T/ctl
  mkdir -p "$C/proto" || return 1
  ( cd "$C/proto" && clear_git_env && g init -q &&
    mkdir -p evidence && printf 'base receipt\n' > evidence/BASE.txt && g add -A && g commit -qm base &&
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
  ( cd "$C/${5:-$1}" && export AIEN_BASE_REF=origin/main && eval "${4:-:}" && evcheck "$(cat "$C/anchor")" evidence kernel/evidence kernel/import ) > "$C/$1.out" 2>&1 || rc=$?
  if [ "$rc" = "$2" ] && case $2 in 0) true ;; 1) grep -q '^FAIL' "$C/$1.out" ;; 3) grep -q '^NOT_RUN' "$C/$1.out" ;; esac; then
    echo "PASS control $1 (exit $rc)"; echo "$1" >> "$C/keys"
  else
    echo "FAIL control $1: exit $rc, expected $2: $(grep -v '^AIEN-OBS' "$C/$1.out" | tr '\n' ' ' | cut -c1-300)"
  fi
}

[ $# -gt 0 ] || set -- evidence kernel/evidence kernel/import
T=$(mktemp -d "${TMPDIR:-/tmp}/evidence-immutable.XXXXXX") || { echo "EVIDENCE-IMMUTABLE NOT_RUN: mktemp failed"; exit 3; }
trap 'rm -rf "$T"' EXIT
cbad=0
controls > "$T/controls" 2>&1 || cbad=1
cat "$T/controls"
grep -q '^FAIL' "$T/controls" && cbad=1
nctl=$(grep -c '^PASS control' "$T/controls")
rc=0; evcheck "$IMPORT" "$@" > "$T/real" 2>&1 || rc=$?
cat "$T/real"
if [ "$rc" = 3 ]; then echo "EVIDENCE-IMMUTABLE NOT_RUN: $*"; [ "$cbad" = 0 ] && exit 3; fi
nrw=$(grep -c '^FAIL' "$T/real")
[ "$rc" = 3 ] || obs evidence_rewrites "$nrw"
if [ "$rc" = 1 ]; then
  echo "Existing evidence would be changed (above). Add a new, content-addressed file instead of rewriting reviewed evidence."
fi
if [ "$cbad" != 0 ]; then echo "EVIDENCE-IMMUTABLE FAIL: controls"; exit 1; fi
if [ "$rc" != 0 ]; then echo "EVIDENCE-IMMUTABLE FAIL rewrites=$nrw"; exit 1; fi
echo "$*: additions only"
echo "EVIDENCE-IMMUTABLE PASS controls=$nctl"
