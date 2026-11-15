#!/bin/sh
# FR-6: the 42 program, the plain-store refusals, the oversized frame,
# the 8 by 10000 atomic stress, and the two mutations that must go red.
# From the repository root: sh seed/omc/tests/fr6/run.sh [omc]
set -u
cd "$(dirname "$0")/../../../.."
ROOT=$(pwd)
OMC=${1:-$ROOT/seed/out/omc}
[ -x "$OMC" ] || { echo "no omc at $OMC"; exit 2; }
fail=0

say() { echo "$*"; }

compile() {
    "$OMC" < "$1" > "$2" 2>"$3"
}

# sum, fifty times, exit 42
compile seed/omc/tests/fr6/sum.om /tmp/fr6-sum /tmp/fr6-sum.err
rc=$?
if [ "$rc" != 0 ]; then
    say "sum did not compile: exit $rc"
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
        say "sum run $i exit $ec"
    fi
    i=$((i + 1))
done
say "sum $ok/50 exit 42, other $bad"
if [ "$ok" != 50 ] || [ "$bad" != 0 ]; then
    fail=1
fi

# put of a global from a thread
compile seed/omc/tests/fr6/race.om /tmp/fr6-race /tmp/fr6-race.err
rc=$?
say "race exit $rc"
if [ "$rc" != 9 ]; then
    cat /tmp/fr6-race.err
    fail=1
fi

# one refusal per store word. The id on line note id N must be shset.
ids=$(awk '
    $0 == "fn shset c ulong to ulong" { on = 1; next }
    on && $0 == "fn thframe s ulong to void" { on = 0 }
    on && $1 == "if" && $2 == "eq" && $3 == "c" { print $4 }
' seed/omc/omc.om | sort -n)
nids=$(printf '%s\n' "$ids" | grep -c .)
nfiles=0
for f in seed/omc/tests/fr6/write/*.om; do
    nfiles=$((nfiles + 1))
    id=$(awk '$1 == "note" && $2 == "id" { print $3; exit }' "$f")
    hit=$(printf '%s\n' "$ids" | grep -x "$id" || true)
    compile "$f" /tmp/fr6-w /tmp/fr6-w.err
    rc=$?
    if [ "$rc" != 9 ] || [ -z "$hit" ]; then
        say "FAIL $(basename "$f") id $id exit $rc"
        cat /tmp/fr6-w.err
        fail=1
    fi
done
if [ "$nfiles" != "$nids" ]; then
    say "FAIL write cases $nfiles shset $nids"
    fail=1
else
    say "write $nfiles/$nids exit 9"
fi

# a thread may read a global out to a file. That is not a store.
compile seed/omc/tests/fr6/writeok.om /tmp/fr6-wok /tmp/fr6-wok.err
rc=$?
if [ "$rc" != 0 ]; then
    say "writeok did not compile: exit $rc"
    cat /tmp/fr6-wok.err
    fail=1
else
    chmod +x /tmp/fr6-wok
    timeout 5 /tmp/fr6-wok >/dev/null
    ec=$?
    say "writeok exit $ec"
    if [ "$ec" != 0 ]; then
        fail=1
    fi
fi

# 60000 bytes fits. 70000 does not, and must not hang.
compile seed/omc/tests/fr6/stackok.om /tmp/fr6-ok /tmp/fr6-ok.err
rc=$?
if [ "$rc" != 0 ]; then
    say "stackok did not compile: exit $rc"
    cat /tmp/fr6-ok.err
    fail=1
else
    chmod +x /tmp/fr6-ok
    timeout 5 /tmp/fr6-ok
    ec=$?
    say "stackok exit $ec"
    if [ "$ec" != 42 ]; then
        fail=1
    fi
fi
compile seed/omc/tests/fr6/stackbig.om /tmp/fr6-big /tmp/fr6-big.err
rc=$?
if [ "$rc" = 9 ]; then
    say "stackbig refused 9"
elif [ "$rc" = 0 ]; then
    chmod +x /tmp/fr6-big
    timeout 3 /tmp/fr6-big
    ec=$?
    say "stackbig ran exit $ec"
    if [ "$ec" = 0 ] || [ "$ec" = 124 ]; then
        fail=1
    fi
else
    say "stackbig exit $rc"
    cat /tmp/fr6-big.err
    fail=1
fi

# eight threads, 10000 adds each
compile seed/omc/tests/fr6/stress.om /tmp/fr6-stress /tmp/fr6-stress.err
rc=$?
if [ "$rc" != 0 ]; then
    say "stress did not compile: exit $rc"
    cat /tmp/fr6-stress.err
    fail=1
else
    chmod +x /tmp/fr6-stress
    timeout 10 /tmp/fr6-stress
    ec=$?
    say "stress exit $ec"
    if [ "$ec" != 42 ]; then
        fail=1
    fi
fi

# Drop random (135) from the write set. That one program must compile.
# read stays refused, so the rest of the set is still in force.
python3 - << 'PY'
from pathlib import Path
src = Path("seed/omc/omc.om").read_text()
old = "if eq c 135\nret 1\nend\n"
if src.count(old) != 1:
    raise SystemExit("random entry missing")
Path("/tmp/fr6-drop135.om").write_text(src.replace(old, "", 1))
needle = """hi = shl rs 16
lo = shl rn 5
lo = or lo rd
w = or hi lo
w = or 4175429632 w
emit w
vdone 1 rd 5
"""
repl = """mload rd rn 0
tmp = alloc
e3 2332033024 tmp rd rs
mstore tmp rn 0
vdone 1 rd 5
"""
if src.count(needle) != 1:
    raise SystemExit("haemit pattern missing")
Path("/tmp/fr6-plain.om").write_text(src.replace(needle, repl, 1))
PY
py=$?
if [ "$py" != 0 ]; then
    say "mutation source edit failed"
    fail=1
else
    "$OMC" < /tmp/fr6-drop135.om > /tmp/fr6-drop135 2>/tmp/fr6-drop135.err
    rc=$?
    if [ "$rc" != 0 ]; then
        say "drop135 compiler exit $rc"
        cat /tmp/fr6-drop135.err
        fail=1
    else
        chmod +x /tmp/fr6-drop135
        /tmp/fr6-drop135 < seed/omc/tests/fr6/write/random.om >/tmp/o 2>/tmp/e
        rrc=$?
        /tmp/fr6-drop135 < seed/omc/tests/fr6/write/read.om >/tmp/o 2>/tmp/e2
        rdc=$?
        say "drop135 random exit $rrc read exit $rdc"
        if [ "$rrc" != 0 ] || [ "$rdc" != 9 ]; then
            cat /tmp/e
            cat /tmp/e2
            fail=1
        fi
    fi
    "$OMC" < /tmp/fr6-plain.om > /tmp/fr6-plain 2>/tmp/fr6-plain.err
    rc=$?
    if [ "$rc" != 0 ]; then
        say "plain compiler exit $rc"
        cat /tmp/fr6-plain.err
        fail=1
    else
        chmod +x /tmp/fr6-plain
        /tmp/fr6-plain < seed/omc/tests/fr6/stress.om > /tmp/fr6-pstress 2>/tmp/e
        rc=$?
        if [ "$rc" != 0 ]; then
            say "plain stress did not compile: exit $rc"
            cat /tmp/e
            fail=1
        else
            chmod +x /tmp/fr6-pstress
            pok=0
            pbad=0
            i=1
            while [ "$i" -le 20 ]; do
                /tmp/fr6-pstress
                ec=$?
                if [ "$ec" = 42 ]; then
                    pok=$((pok + 1))
                else
                    pbad=$((pbad + 1))
                fi
                i=$((i + 1))
            done
            nld=$(python3 -c '
import sys
b=open("/tmp/fr6-pstress","rb").read()
n=0
for i in range(0,len(b)-3,4):
    if b[i+3]==0xF8 and (b[i+2] & 0xE0)==0xE0:
        n+=1
print(n)
')
            say "plain stress ok $pok bad $pbad ldadd $nld"
            if [ "$pbad" = 0 ] || [ "$nld" != 0 ]; then
                fail=1
            fi
        fi
    fi
fi

if [ "$fail" = 0 ]; then
    say "PASS fr6"
    exit 0
fi
say "FAIL fr6"
exit 1
