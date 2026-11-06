#!/bin/sh
# Host-only qualification. GCC/QEMU/ptrace/Python are verification oracles only.
# Never opens /dev/vfio or /dev/nvidia, alters bindings, or touches a GPU service.
set -eu
cd "$(dirname "$0")/../.."
R=$PWD
OMC=${OMC:-"$R/seed/out/omc"}
B=${IRQ_WORK:-"$R/build/seed/irq"}
mkdir -p "$B"
B=$(CDPATH= cd -- "$B" && pwd)
expectrc() {
    want=$1
    shift
    set +e
    "$@"
    got=$?
    set -e
    [ "$got" = "$want" ] || { printf 'FAIL exit=%s expected=%s command=%s\n' "$got" "$want" "$*" >&2; return 1; }
}
compile() {
    "$OMC" < "seed/host/tests/$1.om" > "$B/$1" 2> "$B/$1.err"
    chmod +x "$B/$1"
}
for name in eventfd vfioirq irqlayout irqcheck irqnovfio; do compile "$name"; done
"${CC:-gcc}" -std=c11 -O2 -Wall -Wextra -Werror seed/host/irq-oracle.c -o "$B/oracle"
"$B/oracle" --layout > "$B/layout.txt"
cat "$B/layout.txt"
"$B/oracle" --bytes > "$B/gcc-layout.bin"
"$B/irqlayout" > "$B/omega-layout.bin"
cmp "$B/gcc-layout.bin" "$B/omega-layout.bin"
printf 'PASS GCC/Omega IRQ wire-layout differential\n'
"$B/eventfd"
"$B/eventfd" 2
printf 'PASS real eventfd initial/read/write/drain/poll/close and table capacity\n'
(cd "$B"; ./irqcheck "$OMC")
"$B/oracle" "$B/vfioirq" 0 0 0
"$B/oracle" "$B/vfioirq" 0 0 1
"$B/oracle" "$B/vfioirq" '?' 0 0
for mode in 1 2 3 4 5 6 7 8 9 ':' ';' '<' '=' '>'; do
    "$B/oracle" "$B/vfioirq" "$mode" 103 0
done
expectrc 103 "$B/irqnovfio"
QEMU=${QEMU_AARCH64:-qemu-aarch64}
"$B/oracle" "$B/vfioirq" '@' 0 0
"$B/oracle" "$B/vfioirq" A 103 0
command -v "$QEMU" >/dev/null || { printf 'NOT_RUN QEMU VFIO-less negative: missing qemu-aarch64\n' >&2; exit 3; }
expectrc 103 "$QEMU" "$B/irqnovfio"
"$QEMU" "$B/eventfd"
printf 'PASS QEMU user-mode VFIO-less refusal and real translated eventfd behavior (not system/hardware qualification)\n'
python3 seed/host/irq-mutants.py "$OMC" "$B/oracle" "$B/mutants"
sha256sum "$OMC" seed/omc/omc.om "$B/eventfd" "$B/vfioirq" "$B/irqlayout"
printf 'PASS typed VFIO IRQ/eventfd host qualification; real device IRQ delivery NOT_RUN\n'
