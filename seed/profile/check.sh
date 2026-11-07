#!/bin/sh
# Qualification for seed/profile (DRA-419 critical source profile) and the profiled authority modules.
# The checker and the conductor are seeded Omega; this coordinator only compiles, runs and compares.
# Exit 0 PASS, 1 FAIL, 3 NOT_RUN (wrong compiler).
set -u
cd "$(dirname "$0")/../.."
OMC=seed/out/omc
PIN=$(sed -n 's/^OMC_PIN=//p' om/units.sh)
[ -x "$OMC" ] || { echo "NOT_RUN profile: no omc at $OMC"; exit 3; }
[ "$(sha256sum < "$OMC" | cut -c1-64)" = "$PIN" ] || { echo "NOT_RUN profile: omc is not the pinned compiler $PIN"; exit 3; }
B=build/seed/profile
rm -rf "$B"; mkdir -p "$B"
fails=0
ok() { printf 'ok   %s\n' "$*"; }
bad() { fails=$((fails + 1)); printf 'FAIL %s\n' "$*"; }
echo "omc $PIN"
"$OMC" < seed/qualification/om2/gate.om > "$B/gate" || { echo "FAIL gate.om does not compile"; exit 1; }
chmod +x "$B/gate"
"$OMC" < seed/profile/profile.om > "$B/profile" || { echo "FAIL profile.om does not compile"; exit 1; }
chmod +x "$B/profile"
echo "profile sha256 $(sha256sum < "$B/profile" | cut -c1-64)"

# 1. Rule fixtures, real-module pre-fix controls, capacity and stop rows.
"$B/gate" "$OMC" "$PIN" seed/profile/profile.cases "$B/cases" > "$B/cases.log"
grep -qx 'OM2GATE PASS cases=48 pass=48 fail=0 invalid=0 not_run=0' "$B/cases.log" \
    && ok "profile cases (48)" || { bad "profile cases"; grep -v ' PASS ' "$B/cases.log" | grep '^VERDICT'; }

# 2. One profile.om mutant per rule: every control PASS, every kill row FAIL.
"$B/gate" "$OMC" "$PIN" seed/profile/mutants.cases "$B/mutants" > "$B/mutants.log"
st=$?
if [ "$st" = 1 ] && grep -qx 'OM2GATE FAIL cases=20 pass=10 fail=10 invalid=0 not_run=0' "$B/mutants.log" \
    && [ "$(grep -c '^VERDICT ctl-[a-z0-9-]* PASS ' "$B/mutants.log")" = 10 ] \
    && [ "$(grep -c '^VERDICT m-[a-z0-9-]* FAIL ' "$B/mutants.log")" = 10 ]; then
    ok "10 profile.om mutants killed, 10 controls pass"
else bad "profile mutants (gate exit $st)"; tail -1 "$B/mutants.log"; fi

# 3. The profiled modules pass the profile as one unit (dispatch is the consumer of lock and store).
A=seed/authority
"$B/profile" $A/action.om $A/store.om $A/lock.om $A/dispatch.om > "$B/unit.txt"
[ $? = 0 ] && grep -qx 'PROFILE-PASS' "$B/unit.txt" && ok "authority unit profile" || bad "authority unit: $(cat "$B/unit.txt")"

# 4. The authority gates are the committed module text plus the test, and their regression tests pass.
same() { # same GATE PART...
    g=$1; shift
    (cd $A && cat "$@") | cmp -s - "$A/$g.om" && ok "$g.om = $*" || bad "$g.om is stale against $*"
}
same dispatch-gate action.om store.om lock.om dispatch.om dispatch-test.om
same lock-gate lock.om lock-test.om
same store-gate store.om store-test.om
same dispatch-order-gate action.om store.om dispatch.om dispatch-order-test.om
same store-exact-gate store.om store-exact-test.om
# store-cleanup-gate routes the store descriptor calls through the test's failure injectors.
sed -e 's/fopen spath/cfopen/' -e 's/write int fd sb/cwrite int fd/' -e 's/fsync int fd/cfsync int fd/' \
    -e 's/fclose int fd/cfclose int fd/' -e 's/renames spkt/crenames/' $A/store.om | cat - $A/store-cleanup-test.om \
    | cmp -s - $A/store-cleanup-gate.om && ok "store-cleanup-gate.om = injected store.om store-cleanup-test.om" \
    || bad "store-cleanup-gate.om is stale against store.om store-cleanup-test.om"
# dispatch-fault-gate routes dispatch's actlost, actrecon and writerec results through the test's injectors.
finject() { sed -e 's/^err = actlost r$/err = factlost r/' -e 's/^err = actrecon r s$/err = factrecon r s/' \
    -e 's/^err = writerec r$/err = fwriterec r/' "$1" | cat $A/action.om $A/store.om - $A/dispatch-fault-test.om; }
finject $A/dispatch.om | cmp -s - $A/dispatch-fault-gate.om && ok "dispatch-fault-gate.om = injected dispatch.om" \
    || bad "dispatch-fault-gate.om is stale against action.om store.om dispatch.om dispatch-fault-test.om"
for g in dispatch-gate lock-gate store-gate dispatch-order-gate store-exact-gate store-cleanup-gate dispatch-fault-gate; do
    "$OMC" < $A/$g.om > "$B/$g" || { bad "$g does not compile"; continue; }
    chmod +x "$B/$g"
    "$B/$g" < /dev/null > "$B/$g.out" 2>&1
    st=$?
    [ $st = 0 ] && ok "$g exit 0: $(tail -1 "$B/$g.out")" || bad "$g exit $st: $(tail -1 "$B/$g.out")"
done

# 5. Negative controls: the pre-fix modules of main 943d955 fail the new regression tests.
# The old lock test run may signal its own process group, so it runs in a new session.
cat seed/profile/cases/lock-943d955.om $A/lock-test.om | "$OMC" > "$B/lock-old" && chmod +x "$B/lock-old"
setsid -w "$B/lock-old" < /dev/null > "$B/lock-old.out" 2>&1
st=$?
[ $st = 1 ] && ok "pre-fix lock.om refused by lock-test (exit 1)" || bad "pre-fix lock.om: lock-test exit $st"
finject seed/profile/cases/dispatch-943d955.om | "$OMC" > "$B/fault-old" && chmod +x "$B/fault-old"
setsid -w "$B/fault-old" < /dev/null > "$B/fault-old.out" 2>&1
st=$?
got=$(grep -o 'case [0-9]' "$B/fault-old.out" | tr -d 'case ' | tr -d '\n')
[ $st = 1 ] && [ "$got" = 234578 ] && ok "pre-fix dispatch.om fails fault cases 2 3 4 5 7 8 (79 77 78 79 77 78)" \
    || bad "pre-fix dispatch.om: fault gate exit $st cases '$got'"

if [ $fails = 0 ]; then echo "PROFILE CHECK PASS"; exit 0; fi
echo "PROFILE CHECK FAIL failed=$fails"; exit 1
