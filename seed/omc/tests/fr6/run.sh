#!/bin/sh
# Run the FR-6 unit fifty times, and confirm the racy program is refused.
# From the repository root: sh seed/omc/tests/fr6/run.sh [omc]
set -u
cd "$(dirname "$0")/../../../.."
ROOT=$(pwd)
OMC=${1:-$ROOT/seed/out/omc}
[ -x "$OMC" ] || { echo "no omc at $OMC"; exit 2; }
"$OMC" < seed/omc/tests/fr6/sum.om > /tmp/fr6-sum 2>/tmp/fr6-sum.err
rc=$?
if [ "$rc" != 0 ]; then
    echo "sum did not compile: exit $rc"
    cat /tmp/fr6-sum.err
    exit 1
fi
chmod +x /tmp/fr6-sum
ok=0
bad=0
i=1
while [ "$i" -le 50 ]; do
    timeout 5 /tmp/fr6-sum
    ec=$?
    if [ "$ec" = 42 ]; then
        ok=$((ok + 1))
    else
        bad=$((bad + 1))
        echo "run $i exit $ec"
    fi
    i=$((i + 1))
done
echo "sum $ok/50 exit 42, other $bad"
"$OMC" < seed/omc/tests/fr6/race.om > /tmp/fr6-race 2>/tmp/fr6-race.err
rc=$?
echo "race exit $rc"
cat /tmp/fr6-race.err
if [ "$ok" = 50 ] && [ "$bad" = 0 ] && [ "$rc" = 9 ]; then
    echo "PASS fr6"
    exit 0
fi
echo "FAIL fr6"
exit 1
