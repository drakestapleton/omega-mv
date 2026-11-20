#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Drake Stapleton (AIEN / aien-dev)
#
# Materialize or verify an exact, read-only checkout from a full commit id.
# Replace refs and grafts are disabled, object identities are re-hashed, and the
# worktree is compared as raw bytes and modes without checkout filters.
set -euo pipefail
unset GIT_CONFIG GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR
unset GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE
unset GIT_TEMPLATE_DIR GIT_SSH_COMMAND GIT_EXTERNAL_DIFF
export GIT_NO_REPLACE_OBJECTS=1
export GIT_GRAFT_FILE=/nonexistent/omega-pinned-checkout-grafts
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_ATTR_NOSYSTEM=1
export LC_ALL=C

# Command-line config beats the repository's. The source checkout is the thing
# this tool refuses to trust: its hooks, fsmonitor, commit-graph and upload-pack
# hook must not run, and a commit-graph must not choose a different tree than
# the one stored in the commit object.
gitc() {
    command git \
        -c core.commitGraph=false \
        -c core.multiPackIndex=false \
        -c core.hooksPath=/dev/null \
        -c core.fsmonitor= \
        -c core.fsmonitorHookVersion= \
        -c uploadpack.packObjectsHook= \
        -c protocol.file.allow=always \
        "$@"
}

PROG=${0##*/}
tmpd=""
created=""
empty=""

die() { echo "$PROG: REFUSED: $*" >&2; exit 1; }

cleanup() {
    local rc=$?
    if [ -n "$tmpd" ] && [ -d "$tmpd" ]; then rm -rf -- "$tmpd"; fi
    if [ "$rc" -ne 0 ] && [ -n "$created" ] && [ -d "$created" ]; then
        chmod -R u+w -- "$created" 2>/dev/null || true
        rm -rf -- "$created"
    fi
    if [ -n "$empty" ] && [ -d "$empty" ]; then rmdir -- "$empty" 2>/dev/null || true; fi
}
trap cleanup EXIT

# The Spark judge provisions sibling worktrees from operator-owned mirrors.
# Git discovery as aien-run refuses their ownership. Use their object store
# only as input to pack-objects in the newly initialized destination.
spark_sibling_objects() {
    local source=$1 root sibling project mirror link admin path operator_uid owner_uid
    [ "$(id -un)" = aien-run ] || return 1
    root=$(pwd -P)
    [[ "$root" =~ ^/var/lib/aien-run/wt/omega/[0-9a-f]{40}/omega$ ]] || return 1
    sibling=${source##*/}
    [ "$source" = "${root%/*}/$sibling" ] || return 1
    case "$sibling" in
        physics|omega-bridge|aien-train|aien-architecture) project=$sibling ;;
        aienos) project=aienux ;;
        *) return 1 ;;
    esac
    mirror=/var/lib/aien-run/mirror/$project.git
    [ -f "$source/.git" ] && [ ! -L "$source/.git" ] || return 1
    link=$(<"$source/.git")
    admin=${link#gitdir: }
    [[ "$link" = "gitdir: $admin" && "$admin" = "$mirror/worktrees/"* ]] || return 1
    [[ "${admin#"$mirror/worktrees/"}" =~ ^[a-zA-Z0-9._-]+$ ]] || return 1
    [ "$(realpath -e -- "$admin")" = "$admin" ] || return 1
    [ "$(realpath -e -- "$mirror/objects")" = "$mirror/objects" ] || return 1
    # wt.sh installs the worktree registry inside the root-owned sandbox home.
    [ "$(stat -c %u /var/lib/aien-run)" = 0 ] || return 1
    operator_uid=$(stat -c %u /var/lib/aien-run/wt) || return 1
    [ "$operator_uid" != "$(id -u)" ] || return 1
    for path in /var/lib/aien-run /var/lib/aien-run/wt /var/lib/aien-run/wt/omega "${root%/*}" "$source" "$source/.git" /var/lib/aien-run/mirror \
                "$mirror" "$mirror/worktrees" "$admin" "$admin/gitdir" "$admin/commondir" "$mirror/objects"; do
        [ ! -w "$path" ] && [ ! -L "$path" ] || return 1
        owner_uid=$(stat -c %u -- "$path") || return 1
        [ "$owner_uid" = 0 ] || [ "$owner_uid" = "$operator_uid" ] || return 1
    done
    [ "$(<"$admin/gitdir")" = "$source/.git" ] && [ "$(<"$admin/commondir")" = ../.. ] || return 1
    [ ! -e "$mirror/objects/info/alternates" ] && [ ! -L "$mirror/objects/info/alternates" ] || return 1
    printf '%s\n' "$mirror/objects"
}

full_commit() {
    [[ "$1" =~ ^[0-9a-f]{40}$ ]] || die "commit must be one full lowercase 40-hex id: '$1'"
}

rehash() {
    local repo=$1 type=$2 id=$3 got
    got=$(gitc -C "$repo" cat-file "$type" "$id" 2>/dev/null |
          gitc -C "$repo" hash-object -t "$type" --stdin 2>/dev/null) ||
        die "cannot read $type object $id from $repo"
    [ "$got" = "$id" ] || die "$type object $id fails its content hash in $repo"
}

# The root tree is the first line of the commit object, not a peeled rev-parse,
# so a rewritten commit-graph cannot point this check at a different tree.
commit_tree() {
    local repo=$1 commit=$2 line
    line=$(gitc -C "$repo" cat-file commit "$commit" | awk 'NR==1 { print; exit }') ||
        die "cannot read commit $commit"
    [[ "$line" =~ ^tree\ [0-9a-f]{40}$ ]] || die "commit $commit has no literal root tree"
    printf '%s\n' "${line#tree }"
}

# verify_checkout <directory> <commit>: print the verified root tree id.
verify_checkout() {
    local dir=$1 commit=$2 top actual tree ent meta path mode type id file got gitlink_entries
    local bad=""
    full_commit "$commit"
    [ -d "$dir" ] || die "$dir is not a directory"
    dir=$(cd "$dir" && pwd -P) || die "cannot resolve $dir"
    top=$(gitc -C "$dir" rev-parse --show-toplevel 2>/dev/null) || die "$dir is not a Git worktree"
    top=$(cd "$top" && pwd -P) || die "cannot resolve worktree root $top"
    [ "$top" = "$dir" ] || die "$dir is not the root of its Git worktree ($top)"

    actual=$(gitc -C "$dir" rev-parse --verify -q "$commit^{commit}" 2>/dev/null) ||
        die "$dir does not hold commit $commit"
    [ "$actual" = "$commit" ] || die "$commit resolves to unexpected commit $actual in $dir"
    actual=$(gitc -C "$dir" rev-parse --verify -q HEAD 2>/dev/null) || die "cannot read HEAD in $dir"
    [ "$actual" = "$commit" ] || die "$dir is at $actual, not locked commit $commit"

    rehash "$dir" commit "$commit"
    tree=$(commit_tree "$dir" "$commit")
    rehash "$dir" tree "$tree"

    tmpd=$(mktemp -d "${TMPDIR:-/tmp}/omega-pinned-checkout.XXXXXX") || die "mktemp failed"
    : > "$tmpd/want0"
    : > "$tmpd/regular"
    : > "$tmpd/regular.ids"

    # Re-hash every nested tree. Blob ids are proved below from the exact bytes
    # in the worktree, binding what consumers read to the locked tree.
    gitc -C "$dir" ls-tree -r -t -z --full-tree "$tree" > "$tmpd/objects" ||
        die "cannot enumerate objects at $commit"
    while IFS= read -r -d '' ent; do
        meta=${ent%%$'\t'*}
        path=${ent#*$'\t'}
        read -r mode type id <<< "$meta"
        case "$path" in *$'\n'*) die "path with a newline at $commit is unsupported" ;; esac
        case "$type" in
            tree) rehash "$dir" tree "$id" ;;
            blob) ;;
            commit) [ "$mode" = 160000 ] || die "$path has unexpected commit mode $mode" ;;
            *) die "$path has unsupported object type $type" ;;
        esac
    done < "$tmpd/objects"

    gitc -C "$dir" ls-tree -r -z --full-tree "$tree" > "$tmpd/entries" ||
        die "cannot enumerate paths at $commit"
    while IFS= read -r -d '' ent; do
        meta=${ent%%$'\t'*}
        path=${ent#*$'\t'}
        read -r mode type id <<< "$meta"
        case "$path" in *$'\n'*) die "path with a newline at $commit is unsupported" ;; esac
        file=$dir/$path
        case "$mode:$type" in
            100644:blob|100755:blob)
                [ -f "$file" ] && [ ! -L "$file" ] || { bad+="$path(type) "; continue; }
                if [ "$mode" = 100755 ]; then
                    [ -x "$file" ] || { bad+="$path(mode) "; continue; }
                else
                    [ ! -x "$file" ] || { bad+="$path(mode) "; continue; }
                fi
                printf '%s\n' "$file" >> "$tmpd/regular"
                printf '%s\n' "$id" >> "$tmpd/regular.ids"
                printf '%s\0' "$path" >> "$tmpd/want0" ;;
            120000:blob)
                if [ -L "$file" ]; then
                    # readlink -z preserves embedded/trailing newlines; remove only its NUL delimiter.
                    got=$(readlink -z -- "$file" | head -c -1 | gitc -C "$dir" hash-object --stdin 2>/dev/null) || got=""
                    [ "$got" = "$id" ] || bad+="$path(symlink) "
                else
                    bad+="$path(type) "
                fi
                printf '%s\0' "$path" >> "$tmpd/want0" ;;
            160000:commit)
                if [ -e "$file" ] || [ -L "$file" ]; then
                    if [ -d "$file" ] && [ ! -L "$file" ]; then
                        gitlink_entries=$(find "$file" -mindepth 1 -print -quit 2>/dev/null) ||
                            { bad+="$path(unreadable-gitlink) "; continue; }
                        [ -z "$gitlink_entries" ] || bad+="$path(gitlink) "
                    else
                        bad+="$path(gitlink) "
                    fi
                fi ;;
            *) die "$path has unsupported mode and type $mode $type at $commit" ;;
        esac
    done < "$tmpd/entries"

    if [ -s "$tmpd/regular" ]; then
        gitc -C "$dir" hash-object --no-filters --stdin-paths < "$tmpd/regular" > "$tmpd/regular.got" 2>/dev/null ||
            die "cannot hash regular files under $dir"
        if ! cmp -s "$tmpd/regular.ids" "$tmpd/regular.got"; then
            bad+="regular-file-content "
        fi
    fi

    (cd "$dir" && find . -path './.git' -prune -o ! -type d -printf '%P\0') > "$tmpd/have0" ||
        die "cannot enumerate every worktree path under $dir"
    sort -z -o "$tmpd/want0" "$tmpd/want0"
    sort -z -o "$tmpd/have0" "$tmpd/have0"
    if ! cmp -s "$tmpd/want0" "$tmpd/have0"; then bad+="missing-or-extra-path "; fi
    [ -z "$bad" ] || die "$dir differs from $commit: ${bad:0:300}"

    rm -rf -- "$tmpd"
    tmpd=""
    printf '%s\n' "$tree"
}

cmd=${1:-}
case "$cmd" in
verify)
    [ $# = 3 ] || die "usage: $PROG verify CHECKOUT COMMIT"
    verify_checkout "$2" "$3" ;;
materialize)
    [ $# = 4 ] || die "usage: $PROG materialize SOURCE_REPOSITORY COMMIT DESTINATION"
    source_repo=$2
    commit=$3
    destination=$4
    full_commit "$commit"
    [ -d "$source_repo" ] || die "$source_repo is not a repository directory"
    source_repo=$(cd "$source_repo" && pwd -P) || die "cannot resolve $source_repo"
    objects=""
    if ! gitc -C "$source_repo" rev-parse --git-dir >/dev/null 2>&1; then
        objects=$(spark_sibling_objects "$source_repo") || die "$source_repo is not a readable Git repository"
    fi
    [ ! -e "$destination" ] && [ ! -L "$destination" ] || die "destination already exists: $destination"
    mkdir -p -- "$(dirname "$destination")" || die "cannot create destination parent"
    empty=$(mktemp -d "${TMPDIR:-/tmp}/omega-pin-template.XXXXXX") || die "mktemp failed"
    gitc init --quiet --template="$empty" "$destination" || die "cannot initialize $destination"
    rmdir -- "$empty" || true
    empty=""
    created=$destination
    # Copy the commit with pack-objects in this process. Fetching the source
    # repository would execute its upload-pack, including a configured
    # packObjectsHook. A raw commit id is not a bundle tip (git refuses an
    # "empty" bundle), and a shared clone would keep the source object store.
    tmpd=$(mktemp -d "${TMPDIR:-/tmp}/omega-pinned-checkout.XXXXXX") || die "mktemp failed"
    if [ -n "$objects" ]; then
        printf '%s\n' "$commit" | GIT_ALTERNATE_OBJECT_DIRECTORIES="$objects" \
            gitc -C "$destination" pack-objects --revs --quiet --stdout > "$tmpd/pin.pack" ||
            die "cannot copy locked commit $commit from the Spark mirror"
    else
        printf '%s\n' "$commit" | gitc -C "$source_repo" pack-objects --revs --quiet --stdout > "$tmpd/pin.pack" ||
            die "cannot copy locked commit $commit from $source_repo"
    fi
    gitc -C "$destination" unpack-objects -q < "$tmpd/pin.pack" ||
        die "cannot import locked commit $commit"
    gitc -C "$destination" checkout --quiet --detach "$commit" || die "cannot check out $commit"
    rm -rf -- "$tmpd"
    tmpd=""
    tree=$(verify_checkout "$destination" "$commit")
    chmod -R a-w -- "$destination" || die "cannot make $destination read-only"
    created=""
    printf '%s\n' "$tree" ;;
*)
    die "usage: $PROG verify CHECKOUT COMMIT | materialize SOURCE_REPOSITORY COMMIT DESTINATION" ;;
esac
