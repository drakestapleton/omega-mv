#!/bin/sh
# gate-packed.sh -- FR-2 packed structs. The compiler is argument 1, else seed/out/omc.
# It does not rebuild the compiler. Positive units must exit with the status named below.
# Negative units must be refused with that error. The x86 unit is not executed: its ELF
# machine is EM_X86_64. A mutant that drops the packed attribute must not still exit 0.
# Last line: RC=0.
set -u
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$R"
D=seed/omc/tests/packed
mkdir -p build/seed
B=$(mktemp -d build/seed/packed.XXXXXX)
S=${1:-${OMC:-seed/out/omc}}
case "$S" in /*) ;; *) S="$R/$S";; esac
[ -x "$S" ] || { printf 'FAIL: %s missing; run sh seed/omega-from-seed.sh first\n' "$S" >&2; exit 1; }
ulimit -c 0
fail=0
bad() { printf 'FAIL %s\n' "$*"; fail=1; }
say() { printf '%s\n' "$*"; }

run_ok() {
  name=$1
  want=$2
  set +e
  timeout 60 "$S" < "$D/$name.om" > "$B/$name.bin" 2> "$B/$name.err"
  crc=$?
  set -e
  if [ "$crc" != 0 ]; then bad "$name compiler exit $crc ($(head -c 120 "$B/$name.err"))"; return; fi
  chmod +x "$B/$name.bin"
  set +e
  timeout 15 "$B/$name.bin" >/dev/null 2>&1
  rc=$?
  set -e
  if [ "$rc" = "$want" ]; then say "PASS $name exit $rc"
  else bad "$name exit $rc, wanted $want"; fi
}

run_bad() {
  name=$1
  want=$2
  set +e
  timeout 60 "$S" < "$D/bad/$name.om" > "$B/bad-$name.bin" 2> "$B/bad-$name.err"
  crc=$?
  set -e
  if [ "$crc" != "$want" ]; then bad "$name compiler exit $crc, wanted $want ($(head -c 120 "$B/bad-$name.err"))"; return; fi
  if ! grep -q "error $want" "$B/bad-$name.err"; then bad "$name stderr missing error $want ($(head -c 120 "$B/bad-$name.err"))"; return; fi
  say "PASS $name refused $want"
}

run_ok size 0
run_ok values 0
run_ok unaligned 0
run_ok overlap 1
run_ok array 0
run_ok bigu 0
run_ok bits 0
run_ok bits12 0
run_ok window 0
run_ok exact512 0
run_ok ordinary 16
run_ok f32 0
run_ok bigf 0
run_ok boolp 0
run_ok afterbits 0
run_ok signed 0
run_ok signbit 0
run_ok named 1
run_ok little 0

set +e
timeout 60 "$S" < "$D/x86.om" > "$B/x86.bin" 2> "$B/x86.err"
crc=$?
set -e
if [ "$crc" != 0 ]; then bad "x86 compiler exit $crc ($(head -c 120 "$B/x86.err"))"
else
  m=$(od -An -t u1 -j 18 -N 2 "$B/x86.bin" | tr -s ' ' | sed 's/^ //')
  if [ "$m" = "62 0" ]; then say "PASS x86 ELF machine 62"
  else bad "x86 ELF machine '$m', wanted 62 0"; fi
fi

sed 's/struct packed /struct /' "$D/size.om" > "$B/size.mut.om"
cmp -s "$D/size.om" "$B/size.mut.om" && bad "size mutant did not change the source"
set +e
timeout 60 "$S" < "$B/size.mut.om" > "$B/size.mut.bin" 2> "$B/size.mut.err"
crc=$?
set -e
if [ "$crc" != 0 ]; then bad "size mutant compiler exit $crc ($(head -c 120 "$B/size.mut.err"))"
else
  chmod +x "$B/size.mut.bin"
  set +e
  timeout 15 "$B/size.mut.bin" >/dev/null 2>&1
  rc=$?
  set -e
  if [ "$rc" = 0 ]; then bad "size mutant still exited 0"
  else say "PASS size mutant exit $rc"; fi
fi

run_bad empty 16
run_bad packedend 16
run_bad plainbits 16
run_bad wide 8
run_bad zero 8
run_bad floatbits 7
run_bad boolbits 7
run_bad over 14
run_bad afterfn 9
run_bad dup 10
run_bad ir 9
run_bad index 21

# Raw image. A value round trip stays green when the byte swap is missing on
# both the store and the load. These bytes do not. Scratch is the gate's own
# directory, removed with the rest of the build tree.
set +e
timeout 180 python3 "$D/rawbyte.py" "$S" "$B/raw"
rrc=$?
set -e
if [ "$rrc" = 0 ]; then say "PASS raw bytes"
else bad "raw bytes exit $rrc"; fi

if [ "$fail" != 0 ]; then
  printf 'RC=1\n'
  exit 1
fi
printf 'RC=0\n'
exit 0
