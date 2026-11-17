#!/bin/sh
# tests/a64efi/run.sh [OMC]: compile the a64efi tests with OMC (default seed/out/omc) and run each
# image as \EFI\BOOT\BOOTAA64.EFI on a fresh FAT disk under QEMU virt (cortex-a72, TCG) + AAVMF,
# serial console to a file. Every check prints PASS, FAIL or NOT_RUN. Exit 1 on any FAIL; else 77
# when the boots could not run (qemu-system-aarch64, the firmware or mtools absent, or OMC cannot
# run on this machine); else 0. A boot is stopped when the firmware moves on to its next boot option
# or after EFI_TIMEOUT seconds (default 60). AAVMF_CODE / AAVMF_VARS override the firmware paths
# (64 MiB pflash images). A64EFI_ONLY="group ..." runs only the named groups of
# refuse exit con float addr pl011. Results are emulated, not hardware evidence.
# No em dash or en dash is used in this file.
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
omc=${1:-$root/seed/out/omc}
case $omc in /*) ;; *) omc=$PWD/$omc ;; esac
wait=${EFI_TIMEOUT:-60}
only=${A64EFI_ONLY:-refuse exit con float addr pl011}
work=$(mktemp -d "${TMPDIR:-/tmp}/a64efi.XXXXXX")
trap 'rm -rf "$work"' EXIT
pass=0 fail=0 notrun=0
ok() { pass=$((pass + 1)); echo "PASS $*"; }
bad() { fail=$((fail + 1)); echo "FAIL $*"; }
nr() { notrun=$((notrun + 1)); echo "NOT_RUN $*"; }
want() { case " $only " in *" $1 "*) return 0 ;; esac; return 1; }
finish() {
  echo "SUMMARY pass=$pass fail=$fail not_run=$notrun"
  [ $fail = 0 ] || exit 1
  [ "$1" = yes ] || exit 77
  exit 0
}

# The compiler is an AArch64 Linux program: it runs natively or through a registered qemu-user.
printf 'fn main to int\nret 0\nend\n' > "$work/probe.om"
if ! "$omc" < "$work/probe.om" > "$work/probe.out" 2> /dev/null; then
  nr "all: $omc does not run here (not an AArch64 host and no qemu-user registration, or not a compiler)"
  finish no
fi

code=${AAVMF_CODE:-} vars=${AAVMF_VARS:-}
for d in /usr/share/AAVMF /usr/share/edk2/aarch64; do
  [ -z "$code" ] && [ -f "$d/AAVMF_CODE.fd" ] && code=$d/AAVMF_CODE.fd && vars=$d/AAVMF_VARS.fd
  [ -z "$code" ] && [ -f "$d/QEMU_EFI-pflash.raw" ] && code=$d/QEMU_EFI-pflash.raw && vars=$d/vars-template-pflash.raw
done
efi=yes why=
command -v qemu-system-aarch64 > /dev/null 2>&1 || { efi=no; why="qemu-system-aarch64 not found"; }
command -v mformat > /dev/null 2>&1 || { efi=no; why="mtools not found"; }
{ [ -n "$code" ] && [ -f "$code" ] && [ -f "$vars" ]; } || { efi=no; why="AArch64 UEFI firmware not found (set AAVMF_CODE and AAVMF_VARS)"; }

# app LOG: what the application wrote: the lines from ==B up to the firmware's next BdsDxe line.
app() { tr -d '\r' < "$1" | awk '/^==B$/ { on = 1 } on && /^BdsDxe:/ { exit } on { print }'; }
# status LOG: the EFI_STATUS the firmware reports for the image ("failed to start ...: 00000067"), else nothing.
status() { tr -d '\r' < "$1" | sed -n 's/^BdsDxe: failed to start .*: \([0-9A-Fa-f]*\)$/\1/p' | head -n 1; }

# boot NAME SOURCE...: compile the concatenated sources and boot the image; leaves $work/NAME/serial.log.
boot() {
  name=$1; shift; d=$work/$name; mkdir -p "$d"
  cat "$@" > "$d/app.om"
  if ! "$omc" < "$d/app.om" > "$d/app.efi" 2> "$d/omc.err"; then bad "$name: omc refused it: $(cat "$d/omc.err")"; return 1; fi
  cp "$vars" "$d/vars.fd"
  dd if=/dev/zero of="$d/disk.img" bs=1048576 count=16 2> /dev/null
  mformat -i "$d/disk.img" :: && mmd -i "$d/disk.img" ::/EFI ::/EFI/BOOT && mcopy -i "$d/disk.img" "$d/app.efi" ::/EFI/BOOT/BOOTAA64.EFI
  : > "$d/serial.log"
  qemu-system-aarch64 -M virt -cpu cortex-a72 -m 1024 -display none \
    -drive if=pflash,format=raw,readonly=on,file="$code" -drive if=pflash,format=raw,file="$d/vars.fd" \
    -drive if=none,id=hd,format=raw,file="$d/disk.img" -device virtio-blk-device,drive=hd \
    -net none -serial file:"$d/serial.log" -no-reboot > "$d/qemu.out" 2>&1 &
  q=$!
  t=0
  while [ $t -lt "$wait" ] && kill -0 $q 2> /dev/null; do
    # The image has returned once the firmware loads a second boot option (UiApp or the shell).
    [ "$(grep -c 'BdsDxe: loading' "$d/serial.log")" -ge 2 ] && break
    sleep 1; t=$((t + 1))
  done
  kill $q 2> /dev/null; wait $q 2> /dev/null
  if ! grep -q 'BdsDxe: starting' "$d/serial.log"; then bad "$name: the firmware did not start the image"; return 1; fi
  return 0
}
# out NAME EXPECTED LABEL: the application output equals the expected file.
out() {
  app "$work/$1/serial.log" > "$work/$1/app.txt"
  if cmp -s "$work/$1/app.txt" "$2"; then ok "$3"; else bad "$3: output differs from $(basename "$2")"; fi
}
# st NAME WANT LABEL: the firmware status is WANT (empty: the image returned success).
st() {
  got=$(status "$work/$1/serial.log")
  if [ "$got" = "$2" ]; then ok "$3"; else bad "$3: firmware status '${got:-none}', wanted '${2:-none}'"; fi
}
pre="$work/pre.om"
{ echo "target a64efi"; cat "$here/lib.om"; } > "$pre"

# refuse: compile only. NAME is CODE-LINE-what.om: omc must exit CODE and report that line (0-0: accepted).
if want refuse; then
  for f in "$here"/refuse/*.om; do
    b=$(basename "$f" .om); c=${b%%-*}; r=${b#*-}; l=${r%%-*}
    "$omc" < "$f" > "$work/r.out" 2> "$work/r.err"; rc=$?
    if [ "$c" = 0 ]; then
      if [ $rc = 0 ]; then ok "refuse $b: accepted"; else bad "refuse $b: exit $rc, wanted 0"; fi
    elif [ $rc = "$c" ] && [ "$(cat "$work/r.err")" = "omc: line $l: error $c" ]; then ok "refuse $b: line $l error $c"
    else bad "refuse $b: exit $rc '$(cat "$work/r.err")', wanted line $l error $c"; fi
  done
  # Every efi OP literal 0..22 and 255: only 13, 20 and 21 exist on this target. 15 and 16 are port
  # I/O, which AArch64 does not have; the rest are not implemented here. All others are error 25.
  acc= ref=
  for op in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 255; do
    printf 'target a64efi\nglobal b uchar 8\nfn main to ulong\nr = efi %s 0 b 0 1\nret 0\nend\n' "$op" > "$work/op.om"
    "$omc" < "$work/op.om" > "$work/r.out" 2> "$work/r.err"; rc=$?
    if [ $rc = 0 ]; then acc="$acc $op"
    elif [ $rc = 25 ] && [ "$(cat "$work/r.err")" = "omc: line 4: error 25" ]; then ref="$ref $op"
    else bad "refuse efi $op: exit $rc '$(cat "$work/r.err")'"; fi
  done
  if [ "$acc" = " 13 20 21" ]; then ok "refuse efi OP: accepted exactly 13 20 21"; else bad "refuse efi OP: accepted '$acc', wanted ' 13 20 21'"; fi
  if [ "$ref" = " 0 1 2 3 4 5 6 7 8 9 10 11 12 14 15 16 17 18 19 22 255" ]; then ok "refuse efi OP: error 25 at the efi line for 0..12, 14..19, 22, 255 (15 and 16 are port I/O)"
  else bad "refuse efi OP: error 25 for '$ref'"; fi
fi

[ $efi = yes ] || { nr "exit, con, float, addr, pl011: $why"; finish no; }

# exit: main's value is the EFI_STATUS; exit and traps return to the firmware; nothing runs after them.
if want exit; then
  E=$here/exit
  boot ret0 "$pre" "$E/ret0.om" && { out ret0 "$E/ret0.txt" "exit ret0: output"; st ret0 "" "exit ret0: main returned 0, the firmware reports no failure"; }
  boot ret77 "$pre" "$E/ret77.om" && { out ret77 "$E/ret77.txt" "exit ret77: output"; st ret77 0000004D "exit ret77: main's 2^63|77 is the status (0000004D)"; }
  boot exit3 "$pre" "$E/exit3.om" && { out exit3 "$E/exit3.txt" "exit exit3: nothing runs after exit"; st exit3 FFFFFFFD "exit exit3: exit -3 two calls deep is the status (FFFFFFFD)"; }
  boot trap3 "$pre" "$E/trap3.om" && { out trap3 "$E/trap3.txt" "exit trap3: nothing runs after the trap"; st trap3 00000067 "exit trap3: trap 3 four calls deep is 2^63|103 (00000067)"; }
  boot trap6 "$pre" "$E/trap6.om" && { out trap6 "$E/trap6.txt" "exit trap6: seven 1 MiB frames fit the 8 MiB stack"; st trap6 0000006A "exit trap6: the eighth is trap 6, 2^63|106 (0000006A)"; }
fi
# con: efi 13 results, refusals 32 and 42, chunking, then OFF + N past the array (trap 3).
if want con; then
  if boot con "$pre" "$here/con/c1.om"; then
    out con "$here/con/c1.txt" "con: $(wc -l < "$here/con/c1.txt") lines match (601 bytes in one call, OFF, N 0, codes 32 and 42)"
    st con 00000067 "con: OFF + N past the array is trap 3 (00000067)"
    # Every LF the program wrote must reach the console as CR LF: no line of the raw block lacks its CR.
    n=$(awk '/^==B\r?$/ { on = 1 } on && /^BdsDxe:/ { exit } on && !/\r$/ { c++ } END { print c + 0 }' "$work/con/serial.log")
    if [ ! -s "$work/con/app.txt" ]; then bad "con: CR LF not checked, the image wrote nothing"
    elif [ "$n" = 0 ]; then ok "con: every LF reached the console as CR LF"; else bad "con: $n lines without CR"; fi
  fi
fi
# float: the x86efi float body gives the same 41 bit patterns here; floats survive the firmware calls.
if want float; then
  F=$root/tests/x86efi/float
  sed '1s/.*/target a64efi/' "$F/efi-pre.om" > "$work/fpre.om"
  if boot float "$work/fpre.om" "$F/body.om" "$F/fexplog.om" "$F/main-efi.om"; then
    tr -d '\r' < "$work/float/serial.log" | awk '/^==B$/ { on = 1; next } on && /^==/ { exit } on { print }' > "$work/float/block.txt"
    if cmp -s "$work/float/block.txt" "$F/expected.txt"; then ok "float: $(wc -l < "$F/expected.txt") lines match tests/x86efi/float/expected.txt"; else bad "float differs"; fi
    st float "" "float: returned 0"
  fi
fi
# addr: position independent addresses (texts across a page, view arguments, globals; OM-2 inline and part).
if want addr; then
  A=$here/addr
  boot a1 "$pre" "$A/a1.om" && { out a1 "$A/a1.txt" "addr a1: texts, a view argument and a global"; st a1 "" "addr a1: returned 0"; }
  { echo "target a64efi"; echo om2; cat "$here/lib.om"; } > "$work/pre2.om"
  boot a2 "$work/pre2.om" "$A/a2.om" && { out a2 "$A/a2.txt" "addr a2: OM-2 unsized view, inline and part of a text"; st a2 "" "addr a2: returned 0"; }
fi
# pl011: efi 20 / 21 against the virt machine's PL011, PL031 and code flash. The 16 flash bytes at
# 0x1010 are taken from the firmware file, so the expected lines follow the firmware in use.
if want pl011; then
  rev() { echo "$1" | sed 's/../& /g' | awk '{ for (i = NF; i > 0; i--) printf "%s", $i; print "" }'; }
  h=$(od -A n -t x1 -j 4112 -N 16 "$code" | tr -d ' \n')
  lo=$(rev "$(echo "$h" | cut -c1-16)") hi=$(rev "$(echo "$h" | cut -c17-32)")
  u4=00000000$(rev "$(echo "$h" | cut -c3-10)") u3=0000000000$(rev "$(echo "$h" | cut -c3-8)")
  sed "s/@LO@/$lo/; s/@HI@/$hi/; s/@U4@/$u4/; s/@U3@/$u3/" "$here/pl011/p1.txt" > "$work/p1.txt"
  if boot pl011 "$pre" "$here/pl011/p1.om"; then
    out pl011 "$work/p1.txt" "pl011: UARTDR by byte and by word, UARTFR, eight ID registers, 16 flash bytes by every width, RTC match register"
    st pl011 "" "pl011: returned 0"
  fi
fi
finish yes
