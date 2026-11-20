#!/usr/bin/env bash
# Research launch glue: resolve the two Linux device nodes and selected RoCEv2 GIDs.
# stdin/stdout belong to the Omega rank's binary control channel. Diagnostics go to stderr.
set -eu
if [[ $# != 4 ]]; then
    echo "usage: run-rank.sh RANK ELEMENTS LEFT_GID_INDEX RIGHT_GID_INDEX" >&2
    exit 2
fi
dir=$(cd -- "$(dirname -- "$0")" && pwd)
rank=$1
elements=$2
args=()
resolve() {
    local device=$1 index=$2 candidate ibdev type gid
    [[ $index =~ ^[0-9]+$ ]] || { echo "invalid GID index" >&2; return 2; }
    for candidate in /sys/class/infiniband_verbs/uverbs*/ibdev; do
        [[ -r $candidate ]] || continue
        read -r ibdev < "$candidate"
        [[ $ibdev == "$device" ]] || continue
        local port=/sys/class/infiniband/"$device"/ports/1
        read -r type < "$port/gid_attrs/types/$index"
        read -r gid < "$port/gids/$index"
        [[ $type == "RoCE v2" ]] || { echo "$device index $index is $type" >&2; return 2; }
        local node=${candidate%/ibdev}
        args+=("${node##*uverbs}" "$index" "$gid")
        return 0
    done
    echo "No uverbs node for $device" >&2
    return 2
}
resolve rocep1s0f0 "$3"
resolve roceP2p1s0f1 "$4"
exec "$dir/cx7-rank" "$rank" "$elements" "${args[@]}"
