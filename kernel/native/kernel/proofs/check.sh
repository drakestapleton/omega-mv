#!/usr/bin/env bash
# proofs/check.sh FILE.lean -- the check behind "make ticketlock-proof" (DRA-556). FILE is a version of
# proofs/TicketLock.lean; it counts as proved only when every rule holds, in this order:
#   source     FILE with its comments removed has none of the words sorry, admit, native_decide, axiom, unsafe,
#              implemented_by, extern, ofReduceBool, ofReduceNat, skipKernelTC, debug, eval, run_cmd, run_tac,
#              elab, macro, syntax, initialize, set_option, import;
#   syntax     Lean's own parser (checker/Syntax.lean, no elaboration) finds only the syntax node kinds listed
#              in proofs/TicketLock.syntax, an allowlist: declarations (def, theorem, structure, inductive),
#              their terms and the tactics the proof uses. No #eval, run_cmd, elab, macro, syntax,
#              initialize, set_option, attribute, import or tactic that runs code. When this rule fails lean
#              never runs FILE, so code in FILE never runs;
#   lean       lean (the toolchain proofs/lean-toolchain names) compiles FILE as module TicketLock to an
#              .olean with exit 0 and no warning or error;
#   kernel     leanchecker (same toolchain, a separate process) replays every constant of that .olean
#              through Lean's kernel, so a declaration added without kernel checking fails here;
#   constants  checker/Inspect.lean (a separate process that imports the .olean) lists every constant the
#              module declares, generated ones included; none is an axiom or unsafe, and each uses only
#              propext, Classical.choice and Quot.sound;
#   pins       those constants equal proofs/TicketLock.pins exactly: the same names (none missing, none
#              extra), kinds, elaborated types (sha256 of Lean's repr), definition bodies (sha256) and
#              theorem statements (pretty-printed). A changed statement, a changed definition a statement
#              uses, or a declaration that did not come from the reviewed source fails here.
# Each broken rule prints "FAIL <rule>: ...". Last line CK_TICKETLOCK_PROOF: PASS (exit 0), FAIL (exit 1), or
# NOT_RUN (exit 3: no lean or leanchecker, or a lean other than the pinned one; never a pass).
# proofs/check.sh --print-pins FILE.lean: the pin lines of FILE (after the lean, kernel and constants rules
#   pass), to replace the body of proofs/TicketLock.pins after a reviewed change of TicketLock.lean.
# proofs/check.sh --selftest FILE.lean: every control in proofs/controls/ must FAIL with every rule its
#   "expect:" line names: a .lean control is appended to a copy of FILE, a .sed control is a sed script run
#   on a copy (it must change it). A control with an "expect-unrestricted:" line is run again with the
#   syntax rule off (check.sh --control-unrestricted, whose last line is CK_TICKETLOCK_PROOF_CONTROL, never
#   the PASS line) and must FAIL with those rules too, so the later rules catch it on their own. Last line
#   CK_TICKETLOCK_PROOF_SELFTEST: PASS|FAIL.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
usage="usage: proofs/check.sh [--selftest | --print-pins] FILE.lean"
# The caller's environment does not choose what lean loads or which toolchain elan runs.
unset LEAN_PATH LEAN_SYSROOT LEAN_SRC_PATH LEAN_CC ELAN_TOOLCHAIN

if [[ "${1:-}" == "--selftest" ]]; then
    src=$(realpath "${2:?$usage}"); t=$(mktemp -d); bad=0; n=0; nu=0
    trap 'rm -rf "$t"' EXIT
    rules() { sed -n "s/^$1 $2: //p" "$3"; }  # rules COMMENT-MARK KEY CONTROL
    expect() {  # expect NAME MODE-FLAG OUTPUT-SUFFIX LAST-LINE RULES...
        local name=$1 flag=$2 sfx=$3 last=$4; shift 4
        local miss="" rc=0 r
        bash "$here/check.sh" $flag "$t/$name.lean" > "$t/$name.$sfx" 2>&1 || rc=$?
        for r in "$@"; do grep -q "^FAIL $r:" "$t/$name.$sfx" || miss="$miss $r"; done
        if [[ $# == 0 ]]; then
            echo "NEG FAIL: $name has no expect line"; bad=1
        elif [[ $rc == 1 && -z "$miss" ]] && grep -qx "$last: FAIL" "$t/$name.$sfx"; then
            echo "NEG PASS: $name${flag:+ ($flag)} caught by:$(printf ' %s' "$@")"
        else
            cat "$t/$name.$sfx"; echo "NEG FAIL: $name${flag:+ ($flag)} exit $rc, rules not reporting it:${miss:- (none)}"; bad=1
        fi
    }
    for c in "$here"/controls/*.lean "$here"/controls/*.sed; do
        [[ -e $c ]] || continue
        n=$((n + 1)); name=$(basename "$c"); name=${name%.*}
        case "$c" in
            *.lean) cat "$src" "$c" > "$t/$name.lean"; mark=-- ;;
            *.sed)  sed -f "$c" "$src" > "$t/$name.lean"; mark='#'
                    cmp -s "$src" "$t/$name.lean" && { echo "NEG FAIL: $name changes nothing in $src"; bad=1; continue; } ;;
        esac
        # shellcheck disable=SC2046
        expect "$name" "" out CK_TICKETLOCK_PROOF $(rules "$mark" expect "$c")
        u=$(rules "$mark" expect-unrestricted "$c")
        if [[ -n $u ]]; then
            nu=$((nu + 1))
            # shellcheck disable=SC2086
            expect "$name" --control-unrestricted unrestricted CK_TICKETLOCK_PROOF_CONTROL $u
        fi
    done
    [[ $n -ge 12 ]] || { echo "NEG FAIL: $n controls in $here/controls, expected at least 12"; bad=1; }
    [[ $nu -ge 3 ]] || { echo "NEG FAIL: $nu unrestricted controls, expected at least 3"; bad=1; }
    echo "CK_TICKETLOCK_PROOF_SELFTEST: $([[ $bad == 0 ]] && echo PASS || echo FAIL) ($n controls, $nu also with the syntax rule off)"
    exit $bad
fi

mode=check; last=CK_TICKETLOCK_PROOF
case "${1:-}" in
    --print-pins) mode=pins; shift ;;
    --control-unrestricted) mode=unrestricted; last=CK_TICKETLOCK_PROOF_CONTROL; shift ;;
esac
file=$(realpath "${1:?$usage}")
notrun() { echo "$last: NOT_RUN ($1)"; exit 3; }
command -v lean > /dev/null || notrun "lean not installed"
# Run lean from proofs/ so elan picks the toolchain proofs/lean-toolchain names; refuse any other lean. Every
# later step calls that toolchain's binaries by path.
want=$(sed -n 's/^leanprover\/lean4:v//p' "$here/lean-toolchain")
have=$(cd "$here" && lean --version 2>/dev/null | sed -n 's/^Lean (version \([^,]*\),.*/\1/p')
[[ -n "$want" && "$have" == "$want" ]] || notrun "lean '$have', proofs/lean-toolchain pins '$want'"
prefix=$(cd "$here" && lean --print-prefix 2>/dev/null)
LEAN=$prefix/bin/lean; CHECKER=$prefix/bin/leanchecker
[[ -x $LEAN ]] || notrun "no $LEAN"
[[ -x $CHECKER ]] || notrun "no leanchecker in the pinned toolchain ($CHECKER)"
export PATH="$prefix/bin:$PATH"

fail=0
no() { echo "FAIL $1: $2"; fail=1; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
finish() {
    [[ $fail == 0 ]] && { echo "$last: PASS"; exit 0; }
    echo "$last: FAIL"; exit 1
}

# source. Comments removed: "--" to the end of the line, and /- ... -/ blocks (they nest).
awk '{
    out = ""; i = 1; n = length($0)
    while (i <= n) {
        two = substr($0, i, 2)
        if (depth > 0) {
            if (two == "/-") { depth++; i += 2 } else if (two == "-/") { depth--; i += 2 } else i++
        } else if (two == "/-") { depth = 1; i += 2 }
        else if (two == "--") break
        else { out = out substr($0, i, 1); i++ }
    }
    print out
}' "$file" > "$t/code"
grep -nwE 'sorry|admit|native_decide|axiom|unsafe|implemented_by|extern|ofReduceBool|ofReduceNat|skipKernelTC|debug|eval|run_cmd|run_tac|run_elab|elab|elab_rules|macro|macro_rules|syntax|initialize|builtin_initialize|set_option|import' "$t/code" \
    > "$t/words" && while IFS= read -r l; do no source "line ${l%%:*}: ${l#*:}"; done < "$t/words"

# syntax: parse only, then every node kind must be in the allowlist.
if [[ $mode != unrestricted ]]; then
    rc=0; (cd "$here" && "$LEAN" --run checker/Syntax.lean "$file") > "$t/syntax.out" 2>&1 || rc=$?
    grep '^PARSE_ERROR ' "$t/syntax.out" | head -n 20 | while IFS= read -r l; do echo "FAIL syntax: ${l#PARSE_ERROR }"; done
    nk=$(grep -c '^KIND ' "$t/syntax.out" || true)
    if [[ $rc != 0 || $nk == 0 ]]; then
        [[ $rc != 0 ]] && ! grep -q '^PARSE_ERROR ' "$t/syntax.out" && head -n 20 "$t/syntax.out"
        no syntax "checker/Syntax.lean exit $rc, $nk kinds"
    fi
    grep -v '^#' "$here/TicketLock.syntax" | sed '/^$/d' | sort -u > "$t/allowed"
    sed -n 's/^KIND //p' "$t/syntax.out" | sort -u > "$t/kinds"
    comm -23 "$t/kinds" "$t/allowed" > "$t/refused"
    while IFS= read -r k; do no syntax "kind $k is not in proofs/TicketLock.syntax"; done < "$t/refused"
    if [[ $fail != 0 ]] && [[ -s $t/refused || $rc != 0 || $nk == 0 ]]; then
        echo "SKIP lean, kernel, constants, pins: FILE has syntax outside the allowlist, so lean does not run it"
        echo "syntax kinds $nk, refused $(wc -l < "$t/refused"), lean $have"
        finish
    fi
fi

# lean: compile FILE as module TicketLock (the module name is part of generated constant names).
mkdir -p "$t/build"; cp "$file" "$t/build/TicketLock.lean"
rc=0; (cd "$t/build" && "$LEAN" -o TicketLock.olean TicketLock.lean) > "$t/lean.log" 2>&1 || rc=$?
[[ $rc == 0 ]] || no lean "exit $rc"
grep -nE '(^|: )(warning|error)' "$t/lean.log" | head -n 20 | while IFS= read -r l; do echo "FAIL lean: $l"; done
grep -qE '(^|: )(warning|error)' "$t/lean.log" && fail=1
if [[ ! -s $t/build/TicketLock.olean ]]; then
    echo "SKIP kernel, constants, pins: no TicketLock.olean"
    finish
fi

# kernel: replay every constant of the module through the kernel, in a separate process.
rc=0; (cd "$t/build" && LEAN_PATH="$t/build" "$CHECKER" TicketLock) > "$t/kernel.log" 2>&1 || rc=$?
if [[ $rc != 0 ]]; then
    head -n 20 "$t/kernel.log" | while IFS= read -r l; do echo "FAIL kernel: $l"; done
    no kernel "leanchecker TicketLock exit $rc"
fi

# constants: every constant the module declares, from a separate process.
rc=0; (cd "$here" && LEAN_PATH="$t/build" "$LEAN" --run checker/Inspect.lean TicketLock) > "$t/inspect.out" 2> "$t/inspect.err" || rc=$?
ndecl=$(grep -c '^CK_DECL	' "$t/inspect.out" || true)
[[ $rc == 0 ]] && grep -qx "CK_DECLS $ndecl" "$t/inspect.out" && [[ $ndecl -ge 1 ]] ||
    { head -n 20 "$t/inspect.err"; no constants "checker/Inspect.lean exit $rc, $ndecl constants"; }
std='^(propext|Classical\.choice|Quot\.sound)$'
: > "$t/pins.now"
while IFS=$'\t' read -r tag kind name axs type value stmt; do
    [[ $tag == CK_DECL ]] || continue
    case "$kind" in axiom*) no constants "$name is an axiom" ;; *:unsafe) no constants "$name is unsafe" ;; esac
    if [[ $axs != - ]]; then
        for a in ${axs//,/ }; do [[ $a =~ $std ]] || no constants "$name uses axiom $a"; done
    fi
    th=$(printf '%s' "$type" | sha256sum | cut -c1-64)
    vh=-; [[ $value == - ]] || vh=$(printf '%s' "$value" | sha256sum | cut -c1-64)
    printf '%s\t%s\t%s\t%s\t%s\n' "$kind" "$name" "$th" "$vh" "$stmt" >> "$t/pins.now"
done < "$t/inspect.out"

if [[ $mode == pins ]]; then
    [[ $fail == 0 ]] || { echo "$last: FAIL (no pins printed)"; exit 1; }
    cat "$t/pins.now"; exit 0
fi

# pins: the module's constants against proofs/TicketLock.pins (kind, name, type sha256, value sha256, statement).
grep -v '^#' "$here/TicketLock.pins" | sed '/^$/d' > "$t/pins.want"
[[ -s $t/pins.want ]] || no pins "proofs/TicketLock.pins has no pin lines"
awk -F'\t' '
    NR == FNR { w[$2] = $0; wk[$2] = $1; wt[$2] = $3; wv[$2] = $4; ws[$2] = $5; next }
    { h[$2] = $0; hk[$2] = $1; ht[$2] = $3; hv[$2] = $4; hs[$2] = $5 }
    END {
        for (n in w) if (!(n in h)) print "missing " n " (pinned " wk[n] ")"
        for (n in h) if (!(n in w)) print "extra " hk[n] " " n " (not in proofs/TicketLock.pins)"
        for (n in h) if ((n in w) && w[n] != h[n]) {
            d = ""
            if (wk[n] != hk[n]) d = d " kind " wk[n] "->" hk[n]
            if (wt[n] != ht[n]) d = d " type"
            if (wv[n] != hv[n]) d = d " value"
            if (ws[n] != hs[n]) d = d " statement now: " hs[n]
            print "changed " n ":" d
        }
    }' "$t/pins.want" "$t/pins.now" | sort > "$t/pins.diff"
while IFS= read -r l; do no pins "$l"; done < "$t/pins.diff"

echo "constants $ndecl, pinned $(wc -l < "$t/pins.want"), pin differences $(wc -l < "$t/pins.diff"), lean $have"
finish
