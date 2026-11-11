#!/bin/sh
# The Mach-O mode of ng a64 (`@ng a64 macho`, DESIGN.md section 11), checked in two steps, as the output is for
# another system than the one the compiler runs on.
#   sh seed/ng/a64/tests/macho/run.sh bundle NG DIR   on Linux AArch64, from the omega-mv root. NG is the ng
#       built from seed/ng/ng.units. Every seed/ng/tests/ir/x-*.om, seed/ng/a64/tests/front/*.om and
#       seed/ng/a64/tests/macho/*.om goes through front-ir and opt, then `@ng a64` and `@ng a64 macho`. A unit
#       either target refuses must be refused by both with the same line. Each ELF runs here; its status and
#       stdout sha256 go to DIR/linux.txt, the Mach-O files to DIR/m/. Two mutant compilers (built here with
#       seed/out/omc from a changed a64.om) write DIR/mut1/ and DIR/mut2/ for the controls below.
#       The library fixtures seed/ng/a64/tests/macho/lib/*.om (`target macos`: libfn, libptr, libcall; DESIGN.md
#       section 13) have no ELF: `@ng a64` must refuse each (exit 5, `a64: unsupported 241..243`). Their Mach-O
#       files go to DIR/lib/, what each must give (lib/expect.txt: name, status, stdout sha256) to DIR/lib.txt,
#       and four more mutant compilers write DIR/mut3/ .. DIR/mut6/. libback and libbackobjc are the callback
#       fixtures (DESIGN.md section 14): library code calls the Omega function libback.
#   sh run.sh run DIR                                  on an arm64 Mac, from anywhere (copy DIR and this file).
#       Signs every Mach-O ad hoc, runs it and compares with linux.txt. Negative controls: mut1 (read and write
#       without the CSNEG, so a failed call is plus errno) must change badfd; mut2 (a class-1 global address
#       taken as x28 plus, not minus) must change gtext. Then the library fixtures against lib.txt, with their
#       controls: mut3 (libcall does not store d0 and d1 back) must change libmath; mut4 (libfn gives dlopen for
#       every number) must change libwrite; mut5 (the callback body does not pass x0 on) and mut6 (libcall does
#       not leave its stack pointer for a callback) must change libback.
# Last line: NG-A64-MACHO-BUNDLE OK n, or NG-A64-MACHO PASS / FAIL n. Only OK and PASS exit 0.
set -eu
mode=${1:?usage: run.sh bundle NG DIR | run DIR}
sha() { if command -v sha256sum > /dev/null; then sha256sum | cut -c1-64; else shasum -a 256 | cut -c1-64; fi; }
if [ "$mode" = bundle ]; then
    NG=${2:?}; D=${3:?}
    [ "$(uname -sm)" = "Linux aarch64" ] || { echo "NG-A64-MACHO-BUNDLE NOT_RUN (host is $(uname -sm))"; exit 1; }
    rm -rf "$D"; mkdir -p "$D/m" "$D/mut1" "$D/mut2" "$D/mut3" "$D/mut4" "$D/mut5" "$D/mut6" "$D/lib" "$D/w"
    # the mutant compilers
    mk() { # mk N SED-EXPRESSION
        mkdir -p "$D/w/src$1"; : > "$D/w/ng$1.om"
        while read -r _ p; do
            if [ "$p" = seed/ng/src/a64.om ]; then sed "$2" "$p" > "$D/w/a64-$1.om"
                ! cmp -s "$p" "$D/w/a64-$1.om" || { echo "mutant $1 not applied" >&2; exit 1; }
                cat "$D/w/a64-$1.om" >> "$D/w/ng$1.om"
            else cat "$p" >> "$D/w/ng$1.om"; fi
        done < seed/ng/ng.units
        seed/out/omc < "$D/w/ng$1.om" > "$D/w/ng$1"; chmod +x "$D/w/ng$1"
    }
    mk 1 '/^a6_ew a_csnegx 0 0 0 3 0$/d'
    mk 2 's/^a6_ew a_subx d 28 d 0 0$/a6_ew a_addx d 28 d 0 0/'
    mk 3 '/^a6_emitw 0x6d040680$/d'
    mk 4 's/^a6_emitw 0xf8707a20$/a6_emitw 0xf9400220/'
    mk 5 '/^a6_emitw 0xaa0003e1$/d'
    mk 6 '/^a6_emitw 0xf9000d33$/d'
    n=0; : > "$D/linux.txt"; : > "$D/refused.txt"
    for f in seed/ng/tests/ir/x-*.om seed/ng/a64/tests/front/*.om seed/ng/a64/tests/macho/*.om; do
        b=$(basename "$f" .om)
        { printf '@ng front-ir\n'; cat "$f"; } | "$NG" > "$D/w/$b.ir" 2> /dev/null || { echo "$b front" >> "$D/refused.txt"; continue; }
        { printf '@ng opt\n'; cat "$D/w/$b.ir"; } | "$NG" > "$D/w/$b.o.ir"
        r1=0; { printf '@ng a64\n'; cat "$D/w/$b.o.ir"; } | "$NG" > "$D/w/$b.elf" 2> "$D/w/$b.e1" || r1=$?
        r2=0; { printf '@ng a64 macho\n'; cat "$D/w/$b.o.ir"; } | "$NG" > "$D/m/$b" 2> "$D/w/$b.e2" || r2=$?
        if [ $r1 -ne 0 ] || [ $r2 -ne 0 ]; then
            rm -f "$D/m/$b"
            [ $r1 -eq $r2 ] && cmp -s "$D/w/$b.e1" "$D/w/$b.e2" || { echo "FAIL $b: elf $r1, macho $r2, or another line"; exit 1; }
            echo "$b a64 $r1 $(cat "$D/w/$b.e1")" >> "$D/refused.txt"; continue
        fi
        chmod +x "$D/w/$b.elf"
        st=0; timeout 60 "$D/w/$b.elf" < /dev/null > "$D/w/$b.out" 2> /dev/null || st=$?
        echo "$b $st $(sha < "$D/w/$b.out")" >> "$D/linux.txt"; n=$((n + 1))
        for k in 1 2; do { printf '@ng a64 macho\n'; cat "$D/w/$b.o.ir"; } | "$D/w/ng$k" > "$D/mut$k/$b" 2> /dev/null || rm -f "$D/mut$k/$b"; done
    done
    for b in badfd gtext; do grep -q "^$b " "$D/linux.txt" || { echo "FAIL: control fixture $b missing"; exit 1; }; done
    # the library fixtures: Mach-O only
    nl=0
    for f in seed/ng/a64/tests/macho/lib/*.om; do
        b=$(basename "$f" .om)
        { printf '@ng front-ir\n'; cat "$f"; } | "$NG" > "$D/w/$b.ir" 2> /dev/null || { echo "FAIL lib $b: front"; exit 1; }
        { printf '@ng opt\n'; cat "$D/w/$b.ir"; } | "$NG" > "$D/w/$b.o.ir"
        r1=0; { printf '@ng a64\n'; cat "$D/w/$b.o.ir"; } | "$NG" > /dev/null 2> "$D/w/$b.e1" || r1=$?
        [ $r1 -eq 5 ] && grep -Eq '^a64: unsupported 24[123]$' "$D/w/$b.e1" || { echo "FAIL lib $b: the ELF target must refuse it (exit $r1)"; exit 1; }
        { printf '@ng a64 macho\n'; cat "$D/w/$b.o.ir"; } | "$NG" > "$D/lib/$b" 2> /dev/null || { echo "FAIL lib $b: macho"; exit 1; }
        for k in 3 4 5 6; do { printf '@ng a64 macho\n'; cat "$D/w/$b.o.ir"; } | "$D/w/ng$k" > "$D/mut$k/$b" 2> /dev/null || rm -f "$D/mut$k/$b"; done
        grep -q "^$b " seed/ng/a64/tests/macho/lib/expect.txt || { echo "FAIL lib $b: no line in expect.txt"; exit 1; }
        nl=$((nl + 1))
    done
    cp seed/ng/a64/tests/macho/lib/expect.txt "$D/lib.txt"
    [ "$(wc -l < "$D/lib.txt" | tr -d ' ')" = "$nl" ] || { echo "FAIL: expect.txt lines and library fixtures differ"; exit 1; }
    rm -rf "$D/w"
    echo "NG-A64-MACHO-BUNDLE OK $n ($(wc -l < "$D/refused.txt" | tr -d ' ') refused by both targets; $nl library fixtures)"
    exit 0
fi
D=${2:?}
[ "$(uname -sm)" = "Darwin arm64" ] || { echo "NG-A64-MACHO NOT_RUN (host is $(uname -sm))"; exit 1; }
echo "host $(uname -sm) $(sw_vers -productVersion)"
fails=0; same=0
one() { # one DIR NAME -> "status sha"
    cp "$D/$1/$2" "$D/run.bin"; chmod 755 "$D/run.bin"
    /usr/bin/codesign --force --sign - "$D/run.bin" 2> /dev/null || { echo "sign-failed -"; return; }
    st=0; /usr/bin/perl -e 'alarm 60; exec @ARGV' "$D/run.bin" < /dev/null > "$D/run.out" 2> /dev/null || st=$?
    echo "$st $(sha < "$D/run.out")"
}
while read -r b st h; do
    got=$(one m "$b")
    if [ "$got" = "$st $h" ]; then same=$((same + 1)); else fails=$((fails + 1)); echo "FAIL $b: linux $st $h, mac $got"; fi
done < "$D/linux.txt"
echo "PASS-COUNT $same of $(wc -l < "$D/linux.txt" | tr -d ' ') equal their ELF (status and stdout)"
ctl() { # ctl MUTDIR NAME WHAT
    want=$(grep "^$2 " "$D/linux.txt" | cut -d' ' -f2-)
    got=$(one "$1" "$2")
    if [ "$got" != "$want" ]; then echo "PASS control $1 ($3): $2 gives $got, not $want"
    else fails=$((fails + 1)); echo "FAIL control $1 ($3): $2 unchanged"; fi
}
ctl mut1 badfd "no CSNEG after write"
ctl mut2 gtext "class-1 global address added, not subtracted"
ls=0
while read -r b st h; do
    got=$(one lib "$b")
    if [ "$got" = "$st $h" ]; then ls=$((ls + 1)); else fails=$((fails + 1)); echo "FAIL lib $b: want $st $h, mac $got"; fi
done < "$D/lib.txt"
echo "PASS-COUNT $ls of $(wc -l < "$D/lib.txt" | tr -d ' ') library fixtures give their status and stdout"
lctl() { # lctl MUTDIR NAME WHAT
    want=$(grep "^$2 " "$D/lib.txt" | cut -d' ' -f2-)
    got=$(one "$1" "$2")
    if [ "$got" != "$want" ]; then echo "PASS control $1 ($3): $2 gives $got, not $want"
    else fails=$((fails + 1)); echo "FAIL control $1 ($3): $2 unchanged"; fi
}
lctl mut3 libmath "libcall does not store d0 and d1 back"
lctl mut4 libwrite "libfn gives dlopen for every number"
lctl mut5 libback "the callback body does not pass x0 on"
lctl mut6 libback "libcall does not leave its stack pointer for a callback"
rm -f "$D/run.bin" "$D/run.out"
if [ $fails -eq 0 ]; then echo "NG-A64-MACHO PASS"; else echo "NG-A64-MACHO FAIL $fails"; exit 1; fi
