#!/bin/sh
# gate.sh -- seed/text/text.om against an independent oracle (tests/gen.om, seeded Omega).
# Builds the case generator gen.om and txdrv (om2 + text.om + txdrv.om) with seed/out/omc, writes the
# fixed and seeded random cases with their expected answers, and requires every answer of text.om to
# equal the oracle's. Then twelve mutants of text.om, each removing or bending one rule, must each
# produce at least one wrong answer. Prints TEXTGATE PASS rows=N mutants=12.
# Exit 0 PASS, 1 FAIL, 3 NOT_RUN (interrupted by HUP, INT or TERM).
# Migration debt: this driver is still sh, with perl for the mutant edits; it is not ported to .om yet.
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
cd "$R"
S=seed/out/omc
notrun() { printf 'NOT_RUN text gate: %s\n' "$*"; exit 3; }
bad() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
[ -x "$S" ] || bad "$S missing; run sh seed/omega-from-seed.sh first"
mkdir -p build/seed/text
T=$(mktemp -d build/seed/text/run.XXXXXX)
trap 'rm -rf "$T"' EXIT
trap 'notrun interrupted' HUP INT TERM
"$S" < seed/text/tests/gen.om > "$T/gen" 2> "$T/build.err" || bad "omc refused seed/text/tests/gen.om: $(cat "$T/build.err")"
chmod +x "$T/gen"
"$T/gen" "$T" > "$T/gen.log" || bad "seed/text/tests/gen.om exited $? (80: a write failed)"

build() { # build TEXT.om OUT
    { printf 'om2\n'; cat "$1" seed/text/tests/txdrv.om; } > "$T/drv.om"
    "$S" < "$T/drv.om" > "$2" 2> "$T/build.err" || bad "omc refused the driver with $1: $(cat "$T/build.err")"
    chmod +x "$2"
}
# runall DRIVER: 0 when every cases file gives exactly its want file; on 1, k names the first file that does not
# and st is the driver's exit status on it (0: it ran and its answers differ; 100+N: trap N)
runall() {
    for c in "$T"/cases-*.bin; do
        k=${c##*/cases-}; k=${k%.bin}
        st=0; "$1" < "$c" > "$T/got.txt" 2>/dev/null || st=$?
        [ "$st" -eq 0 ] || return 1
        cmp -s "$T/got.txt" "$T/want-$k.txt" || return 1
    done
    return 0
}

build seed/text/text.om "$T/txdrv"
runall "$T/txdrv" || { trap - EXIT HUP INT TERM; bad "text.om disagrees with the oracle on $T/cases-$k.bin: driver exit $st; compare $T/got.txt with $T/want-$k.txt ($T kept)"; }
rows=$(cat "$T"/want-*.txt | wc -l)
printf 'PASS %s cases equal the oracle (%s)\n' "$rows" "$(cat "$T/gen.log")"

m=0
mutant() { # mutant NAME PERL-EXPR
    perl -0pe "$2" seed/text/text.om > "$T/mut.om"
    cmp -s seed/text/text.om "$T/mut.om" && bad "mutant $1 did not apply"
    build "$T/mut.om" "$T/mutdrv"
    runall "$T/mutdrv" && bad "mutant $1 survived"
    m=$((m + 1)); printf 'PASS mutant caught: %s\n' "$1"
}
mutant "decimal overflow boundary" 's/gt d 5\n/gt d 6\n/'
mutant "surrogates accepted after ED" 's/if eq s 5\nhi = uchar 159/if eq s 5\nhi = uchar 191/'
mutant "overlong accepted after E0" 's/if eq s 4\nlo = uchar 160/if eq s 4\nlo = uchar 128/'
mutant "needle at the very end missed" 's/stop = add sub hn m 1/stop = sub hn m/'
mutant "shorter prefix sorts last" 's/if lt len a len b\nret int -1/if lt len a len b\nret int 1/'
mutant "-2^63 refused" 's/if gt x 9223372036854775808/if ge x 9223372036854775808/'
mutant "truncated sequence accepted" 's/if ne st 0\nret lead\nend\nret stop/ret stop/'
mutant "3-byte lead keeps too few bits" 's/cp = ulong and c 15/cp = ulong and c 7/'
mutant "U+D800 encoded" 's/if and ge cp 55296/if and ge cp 55297/'
mutant "3-byte lead written as 4-byte" 's/lead = 224/lead = 240/'
mutant "U+07FF sized as 3 bytes" 's/if lt cp 2048/if lt cp 2047/'
mutant "backquote read as a hex digit" 's/if and ge c 97 le c 102/if and ge c 96 le c 102/'
printf 'TEXTGATE PASS rows=%s mutants=%s\n' "$rows" "$m"
