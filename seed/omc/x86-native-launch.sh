#!/bin/bash
# x86-native-launch.sh -- stand-in for qemu-x86_64 when qualify-x86.py runs on
# an x86-64 Linux host (--x86-native): the x86 program is executed directly by
# the processor, not emulated. It accepts only the argument forms the runner
# uses:  --version | [-0 <argv0>] <program> [args...]
# -strace has no native equivalent here and is refused (exit 125), so an
# emulator-artifact claim can never be produced by a native run.
set -u
case "${1:-}" in
--version) echo "native x86-64 execution, no emulator ($(uname -m) $(uname -r))"; exit 0 ;;
-strace) echo "x86-native-launch: -strace is not available natively" >&2; exit 125 ;;
-0) [ $# -ge 3 ] || exit 125; a0=$2; shift 2; exec -a "$a0" "$@" ;;
'') exit 125 ;;
*) exec "$@" ;;
esac
