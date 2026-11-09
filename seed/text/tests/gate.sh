#!/bin/sh
# gate.sh -- seed/text/text.om against an independent oracle (gen.py, Python, test harness only).
# Builds txdrv (om2 + text.om + txdrv.om) with seed/out/omc, generates the fixed and seeded random cases,
# and requires every answer to equal Python's. Then eleven mutants of text.om, each removing or bending
# one rule, must each produce at least one wrong answer. Prints TEXTGATE PASS rows=N mutants=11.
# Exit 0 PASS, 1 FAIL, 3 NOT_RUN (no python3, or python3 older than 3.11).
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
cd "$R"
S=seed/out/omc
notrun() { printf 'NOT_RUN text gate: %s\n' "$*"; exit 3; }
bad() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
[ -x "$S" ] || bad "$S missing; run sh seed/omega-from-seed.sh first"
command -v python3 >/dev/null || notrun 'requires python3 (read-only oracle)'
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' || notrun 'requires python3 >= 3.11'
mkdir -p build/seed/text
T=$(mktemp -d build/seed/text/run.XXXXXX)
trap 'rm -rf "$T"' EXIT HUP INT TERM
python3 -I seed/text/tests/gen.py "$T" > "$T/gen.log"

build() { # build TEXT.om OUT
    { printf 'om2\n'; cat "$1" seed/text/tests/txdrv.om; } > "$T/drv.om"
    "$S" < "$T/drv.om" > "$2" 2> "$T/build.err" || bad "omc refused the driver with $1: $(cat "$T/build.err")"
    chmod +x "$2"
}
# runall DRIVER: 0 when every cases file gives exactly its want file
runall() {
    for c in "$T"/cases-*.bin; do
        k=${c##*/cases-}; k=${k%.bin}
        "$1" < "$c" > "$T/got.txt" 2>/dev/null || return 1
        cmp -s "$T/got.txt" "$T/want-$k.txt" || return 1
    done
    return 0
}

build seed/text/text.om "$T/txdrv"
runall "$T/txdrv" || bad "text.om disagrees with the oracle (first file: compare $T/got.txt with its want file)"
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
printf 'TEXTGATE PASS rows=%s mutants=%s\n' "$rows" "$m"
