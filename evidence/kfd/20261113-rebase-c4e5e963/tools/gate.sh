#!/bin/sh
# gate.sh NAME CMD...: run CMD under the CPU pool lock with nice, log to build/kfd-gates/NAME.log
name=$1; shift
mkdir -p build/kfd-gates
start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
flock /home/drakestapleton/handoffs/hive/queen/pool-16-18.lock taskset -c 16-18 nice -n 10 "$@" > build/kfd-gates/$name.log 2>&1
rc=$?
printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$rc" "$start" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> build/kfd-gates/exits.tsv
printf '%s exit %s\n' "$name" "$rc"
