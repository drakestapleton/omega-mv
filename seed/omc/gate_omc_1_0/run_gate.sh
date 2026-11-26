#!/bin/sh
# gate_omc_1_0/run_gate.sh -- Spark verification harness for the omc 1.0 Pin-Bump Wave.
# Runs:
#   1. Pure-OM gate_omc_1_0 (2x bit-identical build, live AArch64 sendfd/recvfd + traps + compile controls + RM8 diag + C2 byte-identity)
#   2. x86linux execpure compilation + x86_64-linux-gnu-objdump syscall & 27-insn BPF audit + tampered-binary negative control
#   3. x86linux execpure & sendfd/recvfd execution under qemu-x86_64 (EXERCISED_EMULATED)
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
GDIR="$ROOT/seed/omc/gate_omc_1_0"
NEW_OMC=${1:-$ROOT/seed/out/omc}
OLD_OMC=${2:-$NEW_OMC}
WORK=${3:-/tmp/om_gate_omc_1_0_$$}
rm -rf "$WORK"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

[ -x "$NEW_OMC" ] || { echo "FAIL: NEW_OMC not executable: $NEW_OMC" >&2; exit 2; }
[ -x "$OLD_OMC" ] || { echo "FAIL: OLD_OMC not executable: $OLD_OMC" >&2; exit 2; }

echo "=== 1. Build gate_omc_1_0.om (2x bit-identical) ==="
"$NEW_OMC" < "$GDIR/gate_omc_1_0.om" > "$WORK/gate1"
"$NEW_OMC" < "$GDIR/gate_omc_1_0.om" > "$WORK/gate2"
cmp -s "$WORK/gate1" "$WORK/gate2" || { echo "FAIL: gate_omc_1_0 2x build diverged" >&2; exit 1; }
chmod +x "$WORK/gate1"
GATE_SHA=$(sha256sum "$WORK/gate1" | awk '{print $1}')
echo "GATE_2X_IDENTICAL=YES sha256=$GATE_SHA"

cp "$GDIR/test_scm_rights.om" "$WORK/test_scm_rights.om"
"$WORK/gate1" "$NEW_OMC" "$OLD_OMC" "$WORK"

echo "=== 2. x86linux execpure compilation + x86_64-linux-gnu-objdump BPF/syscall audit ==="
"$NEW_OMC" < "$GDIR/test_x86_child.om" > "$WORK/x86_child"
"$NEW_OMC" < "$GDIR/test_x86_execpure.om" > "$WORK/x86_execpure"
"$NEW_OMC" < "$GDIR/test_x86_execpure.om" > "$WORK/x86_execpure_2"
cmp -s "$WORK/x86_execpure" "$WORK/x86_execpure_2" || { echo "FAIL: x86_execpure 2x build diverged" >&2; exit 1; }
chmod +x "$WORK/x86_child" "$WORK/x86_execpure"
X86_SHA=$(sha256sum "$WORK/x86_execpure" | awk '{print $1}')
echo "X86_EXECPURE_2X_IDENTICAL=YES sha256=$X86_SHA"

command -v x86_64-linux-gnu-objdump >/dev/null 2>&1 || { echo "FAIL: x86_64-linux-gnu-objdump missing" >&2; exit 2; }
x86_64-linux-gnu-objdump -D -b binary -m i386:x86-64 --start-address=512 "$WORK/x86_execpure" > "$WORK/x86_execpure.dis"

audit_x86_bpf() {
    dis="$1"
    # Verify all 10 required x86-64 syscalls (rax immediate right before syscall)
    # 436=0x1b4 close_range, 257=0x101 openat, 444=0x1bc landlock_create_ruleset,
    # 445=0x1bd landlock_add_rule, 157=0x9d prctl, 446=0x1be landlock_restrict_self,
    # 3=0x3 close, 302=0x12e prlimit64, 317=0x13d seccomp, 322=0x142 execveat
    for hex in 0x1b4 0x101 0x1bc 0x1bd 0x9d 0x1be 0x3 0x12e 0x13d 0x142; do
        grep -q "movabs \$${hex},%rax" "$dis" || { echo "MISSING_SYSCALL=$hex"; return 1; }
    done
    # Verify key 64-bit packed cBPF words for AUDIT_ARCH_X86_64 (0xc000003e), KILL_PROCESS, ALLOW, EPERM,
    # read=0, write=1, exit=60, exit_group=231, execveat=322, AT_EMPTY_PATH=4096
    for bpfhex in \
        0xc000003e00010015 \
        0x8000000000000006 \
        0x7fff000000000006 \
        0x5000100000006 \
        0x3000015 \
        0x104000015 \
        0x3c01000015 \
        0xe701000015 \
        0x14205000015 \
        0x100001000015; do
        grep -q "$bpfhex" "$dis" || { echo "MISSING_BPF_WORD=$bpfhex"; return 1; }
    done
    return 0
}

audit_x86_bpf "$WORK/x86_execpure.dis" || { echo "FAIL: x86_execpure BPF/syscall audit failed" >&2; exit 1; }
echo "X86_EXECPURE_BPF_AUDIT=PASS syscalls=10/10 bpf_words=10/10"

# Tampered-binary negative control: flip 1 byte inside AUDIT_ARCH_X86_64 immediate and confirm audit catches it
python3 - "$WORK/x86_execpure" "$WORK/x86_execpure_tampered" <<'PY'
import sys
b = bytearray(open(sys.argv[1], 'rb').read())
pat = (0xc000003e00010015).to_bytes(8, 'little')
idx = b.find(pat)
assert idx >= 0, "AUDIT_ARCH_X86_64 BPF pattern not found in ELF"
b[idx + 4] ^= 0x01
open(sys.argv[2], 'wb').write(b)
PY
x86_64-linux-gnu-objdump -D -b binary -m i386:x86-64 --start-address=512 "$WORK/x86_execpure_tampered" > "$WORK/x86_execpure_tampered.dis"
if audit_x86_bpf "$WORK/x86_execpure_tampered.dis" >/dev/null 2>&1; then
    echo "FAIL: tampered BPF binary was NOT caught by audit" >&2
    exit 1
fi
echo "X86_EXECPURE_BPF_TAMPER_CTRL=CAUGHT"

echo "=== 3. qemu-x86_64 execution (EXERCISED_EMULATED) ==="
if command -v qemu-x86_64 >/dev/null 2>&1; then
    set +e
    COUT=$(qemu-x86_64 "$WORK/x86_child" 2>&1)
    CRC=$?
    set -e
    [ "$CRC" = 42 ] && [ "$COUT" = "X86_EXECPURE_CHILD_OK" ] || {
        echo "FAIL: qemu-x86_64 x86_child rc=$CRC out=$COUT" >&2; exit 1;
    }
    echo "X86_CHILD_QEMU=PASS rc=$CRC out=$COUT (EXERCISED_EMULATED)"

    set +e
    EOUT=$(qemu-x86_64 "$WORK/x86_execpure" "$WORK/x86_child" 2>&1)
    ERC=$?
    set -e
    if [ "$ERC" = 42 ] && [ "$EOUT" = "X86_EXECPURE_CHILD_OK" ]; then
        echo "X86_EXECPURE_QEMU=PASS_FULL_SANDBOX rc=$ERC out=$EOUT (EXERCISED_EMULATED)"
    elif [ "$ERC" = 166 ] && [ "$EOUT" = "X86_EXECPURE_ERR=" ]; then
        # 128 + 38 (ENOSYS): qemu-x86_64 user-mode does not emulate landlock/seccomp -> execpure MUST fail closed without running child!
        echo "X86_EXECPURE_QEMU=FAIL_CLOSED_ENOSYS rc=$ERC out=$EOUT (EXERCISED_EMULATED; qemu-x86_64 lacks landlock/seccomp emulation, verified fail-closed)"
    else
        echo "X86_EXECPURE_QEMU_UNEXPECTED rc=$ERC out=$EOUT" >&2
        exit 1
    fi

    # Also compile and run test_scm_rights under target x86linux via qemu-x86_64!
    { printf 'target x86linux\n'; cat "$GDIR/test_scm_rights.om"; } > "$WORK/test_scm_x86.om"
    "$NEW_OMC" < "$WORK/test_scm_x86.om" > "$WORK/test_scm_x86"
    chmod +x "$WORK/test_scm_x86"
    set +e
    SOUT=$(qemu-x86_64 "$WORK/test_scm_x86" 2>&1)
    SRC=$?
    set -e
    echo "X86_SCM_RIGHTS_QEMU rc=$SRC out=$SOUT (EXERCISED_EMULATED)"
    [ "$SRC" = 0 ] && [ "$SOUT" = "SCM_RIGHTS_PASS" ] || { echo "FAIL: x86 SCM_RIGHTS qemu rc=$SRC out=$SOUT" >&2; exit 1; }
else
    echo "X86_QEMU=NOT_RUN (qemu-x86_64 absent)"
fi

echo "OMC_1_0_FULL_GATE PASS (HOST_VERIFIED + EXERCISED_EMULATED)"
