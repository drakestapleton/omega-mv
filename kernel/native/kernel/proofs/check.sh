#!/usr/bin/env bash
# proofs/check.sh FILE.lean -- the check behind "make ticketlock-proof" (DRA-556). FILE counts as proved only when
# every rule holds:
#   source     FILE with its comments removed has none of the words sorry, admit, native_decide, axiom, unsafe,
#              implemented_by, extern, ofReduceBool, ofReduceNat, skipKernelTC;
#   lean       lean (the toolchain proofs/lean-toolchain names) elaborates FILE, then one `#print axioms` per
#              top-level theorem of FILE, then a listing of every constant FILE declares, with exit 0 and no
#              warning or error;
#   theorems   one `#print axioms` answer per theorem, each a subset of [propext, Classical.choice, Quot.sound];
#   constants  every constant FILE declares (theorems, definitions, instances and the ones Lean generates, listed
#              by Lean from the environment, so a theorem the line match above misses is still checked) uses only
#              those three axioms, at least one is listed per theorem, and FILE declares no axiom.
# Each broken rule prints "FAIL <rule>: ...". Last line CK_TICKETLOCK_PROOF: PASS (exit 0), FAIL (exit 1), or
# NOT_RUN (exit 3: no lean, or a lean other than the pinned one; never a pass).
# proofs/check.sh --selftest FILE.lean: each file in proofs/controls/ appended to a copy of FILE must FAIL, with
# every rule its "# expect:" line names (the reviewer's three bad edits, and a theorem made by a macro that the
# line match cannot see). Last line CK_TICKETLOCK_PROOF_SELFTEST: PASS|FAIL.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [[ "${1:-}" == "--selftest" ]]; then
    src=$(realpath "$2"); t=$(mktemp -d); bad=0; n=0
    for c in "$here"/controls/*.lean; do
        n=$((n + 1)); name=$(basename "$c" .lean)
        cat "$src" "$c" > "$t/$name.lean"
        rc=0; bash "$here/check.sh" "$t/$name.lean" > "$t/$name.out" 2>&1 || rc=$?
        want=$(sed -n 's/^-- expect: //p' "$c")
        miss=""
        for r in $want; do grep -q "^FAIL $r:" "$t/$name.out" || miss="$miss $r"; done
        if [[ $rc == 1 && -z "$want" ]]; then
            echo "NEG FAIL: $name has no '-- expect:' line"; bad=1
        elif [[ $rc == 1 && -z "$miss" ]] && grep -qx "CK_TICKETLOCK_PROOF: FAIL" "$t/$name.out"; then
            echo "NEG PASS: $name caught by:$(printf ' %s' $want)"
        else
            cat "$t/$name.out"; echo "NEG FAIL: $name exit $rc, rules not reporting it:${miss:- (none)}"; bad=1
        fi
    done
    [[ $n -ge 4 ]] || { echo "NEG FAIL: $n controls in $here/controls, expected at least 4"; bad=1; }
    rm -rf "$t"
    echo "CK_TICKETLOCK_PROOF_SELFTEST: $([[ $bad == 0 ]] && echo PASS || echo FAIL)"
    exit $bad
fi

file=$(realpath "${1:?usage: proofs/check.sh FILE.lean | --selftest FILE.lean}")
notrun() { echo "CK_TICKETLOCK_PROOF: NOT_RUN ($1)"; exit 3; }
command -v lean > /dev/null || notrun "lean not installed"
# Run lean from proofs/ so elan picks the toolchain proofs/lean-toolchain names; refuse any other lean.
want=$(sed -n 's/^leanprover\/lean4:v//p' "$here/lean-toolchain")
have=$(cd "$here" && lean --version 2>/dev/null | sed -n 's/^Lean (version \([^,]*\),.*/\1/p')
[[ -n "$want" && "$have" == "$want" ]] || notrun "lean '$have', proofs/lean-toolchain pins '$want'"

fail=0
no() { echo "FAIL $1: $2"; fail=1; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

# Comments removed: "--" to the end of the line, and /- ... -/ blocks (they nest).
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
grep -nwE 'sorry|admit|native_decide|axiom|unsafe|implemented_by|extern|ofReduceBool|ofReduceNat|skipKernelTC' "$t/code" \
    > "$t/words" && while IFS= read -r l; do no source "line ${l%%:*}: ${l#*:}"; done < "$t/words"

thms=$(sed -nE 's/^(@\[[^]]*\][[:space:]]*)?((private|protected|nonrec)[[:space:]]+)*theorem[[:space:]]+([^[:space:]({:]+).*/\4/p' "$t/code")
nthm=$(printf '%s' "$thms" | grep -c . || true)
[[ $nthm -ge 1 ]] || no theorems "no top-level theorem in $file"
{
    grep -E '^import ' "$t/code"
    echo 'import Lean'
    grep -vE '^import ' "$file"
    echo
    for x in $thms; do echo "#print axioms $x"; done
    cat <<'EOF'
open Lean Elab Command in
#eval show CommandElabM Unit from do
  let env ← getEnv
  let mut ls : Array String := #[]
  for (n, ci) in env.constants.map₂.toList do
    let k := match ci with
      | .axiomInfo _ => "axiom" | .thmInfo _ => "theorem" | .defnInfo _ => "def" | .opaqueInfo _ => "opaque"
      | .quotInfo _ => "quot" | .inductInfo _ => "inductive" | .ctorInfo _ => "ctor" | .recInfo _ => "rec"
    let ax ← collectAxioms n
    ls := ls.push s!"CK_CONST {k} {n} axioms:{",".intercalate (ax.toList.map toString)}"
  logInfo ("CK_CONSTANTS\n" ++ "\n".intercalate (ls.qsort (· < ·)).toList)
EOF
} > "$t/Check.lean"
rc=0; (cd "$here" && lean "$t/Check.lean") > "$t/lean.log" 2>&1 || rc=$?
[[ $rc == 0 ]] || no lean "exit $rc"
grep -nE '(^|: )(warning|error):' "$t/lean.log" | head -n 20 | while IFS= read -r l; do echo "FAIL lean: $l"; done
grep -qE '(^|: )(warning|error):' "$t/lean.log" && fail=1

std='^(propext|Classical\.choice|Quot\.sound)$'
nax=$(grep -cE "depends on axioms|does not depend on any axioms" "$t/lean.log" || true)
[[ $nax == "$nthm" ]] || no theorems "$nax '#print axioms' answers for $nthm theorems"
while IFS= read -r l; do
    for a in $(sed 's/.*\[\(.*\)\].*/\1/' <<<"$l" | tr ',' ' '); do
        [[ $a =~ $std ]] || no theorems "$l"
    done
done < <(grep -E "depends on axioms" "$t/lean.log")

nconst=$(grep -c '^CK_CONST ' "$t/lean.log" || true)
[[ $nconst -ge $nthm && $nconst -ge 1 ]] || no constants "Lean listed $nconst constants for $nthm theorems"
while IFS= read -r l; do
    set -- $l
    [[ $2 == axiom ]] && no constants "$3 is an axiom declared in $file"
    for a in $(tr ',' ' ' <<<"${4#axioms:}"); do [[ $a =~ $std ]] || no constants "$3 ($2) uses $a"; done
done < <(grep '^CK_CONST ' "$t/lean.log")
for x in $thms; do grep -qE "^CK_CONST theorem $x axioms:" "$t/lean.log" || no constants "theorem $x not listed by Lean"; done

echo "theorems $nthm, '#print axioms' answers $nax, constants $nconst, lean $have"
[[ $fail == 0 ]] && { echo "CK_TICKETLOCK_PROOF: PASS"; exit 0; }
echo "CK_TICKETLOCK_PROOF: FAIL"; exit 1
