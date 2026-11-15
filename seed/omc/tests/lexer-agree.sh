#!/bin/sh
# TEST INSTRUMENT. keyword-users S mode and omc tokens mode must print the same
# spans. The old compiler has no tokens mode, and the old keyword-users rejects S.
set -eu
ROOT=${1:-.}
cd "$ROOT"
OMC=${OMC:-seed/out/omc}
KW=${KW:-/tmp/omc-b-build/keyword-users}
mkdir -p /tmp/omc-b-build
"$OMC" < seed/omc/keyword-users.om > "$KW"
chmod +x "$KW"
fail=0
probe() {
  name=$1
  body=$2
  set +e
  printf 'S\n%s\0' "$body" | "$KW" > /tmp/omc-b-build/kw.out
  kw=$?
  printf 'tokens\n%s' "$body" | "$OMC" > /tmp/omc-b-build/omc.out
  om=$?
  set -e
  if [ "$kw" != 0 ] || [ "$om" != 0 ] || ! cmp -s /tmp/omc-b-build/kw.out /tmp/omc-b-build/omc.out; then
    echo "FAIL probe $name keyword=$kw omc=$om"
    echo "keyword:"; cat /tmp/omc-b-build/kw.out
    echo "omc:"; cat /tmp/omc-b-build/omc.out
    fail=1
  else
    echo "ok probe $name"
  fi
}
probe quote 'enlarge" = long 0
'
probe text 'text t "enlarge"
'
probe call 'enlarge(x)
'
probe note '  note enlarge
'
probe num '123
'
probe neg '-4
'
# A compile that does not start with the tokens line still builds.
set +e
printf 'fn main to int\nret 0\nend\n' | "$OMC" > /tmp/omc-b-build/lexer-tiny
ordinary=$?
set -e
[ "$ordinary" = 0 ] || { echo "FAIL ordinary program exit=$ordinary"; fail=1; }
[ "$fail" = 0 ]
echo "LEXER-AGREE PASS"
