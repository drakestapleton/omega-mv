#!/bin/sh
# difftest.sh OLD_OMC NEW_OMC OUT : same source, same inputs, old and new compiler; exit, stdout, stderr and the files left behind must match.
OLD=$1; NEW=$2; OUT=$3; S=~/work/L1041/src29; mkdir -p "$OUT"; : > "$OUT/summary.tsv"
ARGS=~/work/L1041/repo/seed/host/tests/args.om
runone() { # omc id mode dir -> writes dir/{rc,out,err,ls}
  omc=$1; id=$2; mode=$3; d=$4; rm -rf "$d"; mkdir -p "$d/w"
  "$omc" < "$S/$id.om" > "$d/prog" 2> "$d/cerr"; echo $? > "$d/crc"; chmod 700 "$d/prog"
  cd "$d/w" || return
  case $mode in
    plain) timeout 60 "$d/prog" > "$d/out" 2> "$d/err"; echo $? > "$d/rc";;
    tcp)   timeout 60 "$d/prog" tcp > "$d/out" 2> "$d/err"; echo $? > "$d/rc";;
    comp)  timeout 60 "$d/prog" "$omc" > "$d/out" 2> "$d/err"; echo $? > "$d/rc";;
    child) "$omc" < "$ARGS" > exec-child; chmod 700 exec-child; timeout 60 "$d/prog" > "$d/out" 2> "$d/err"; echo $? > "$d/rc";;
  esac
  find . -printf '%p %y %m %s\n' | sort > "$d/ls"
  cd "$OUT"
}
for spec in "$@"; do :; done
for id in $(cat ~/work/L1041/rows29.txt); do
  case $id in c2-00128|c2-05721) continue;; c2-00025) modes=comp;; c2-00029) modes=child;; c2-00026) modes="plain tcp";; *) modes=plain;; esac
  for mode in $modes; do
    runone "$OLD" $id $mode "$OUT/$id.$mode.old"; runone "$NEW" $id $mode "$OUT/$id.$mode.new"
    o=$OUT/$id.$mode.old; n=$OUT/$id.$mode.new
    # compiled bytes must differ (that is the delta); behaviour must not
    bytes=same; cmp -s $o/prog $n/prog || bytes=differ
    beh=PASS
    cmp -s $o/rc $n/rc || beh=FAIL-exit
    cmp -s $o/out $n/out || beh=FAIL-stdout
    cmp -s $o/err $n/err || beh=FAIL-stderr
    cmp -s $o/ls $n/ls || beh=FAIL-files
    printf '%s\t%s\texit_old=%s exit_new=%s\tout=%sB err=%sB\tbytes=%s\t%s\n' $id $mode "$(cat $o/rc)" "$(cat $n/rc)" $(wc -c < $n/out) $(wc -c < $n/err) $bytes $beh >> "$OUT/summary.tsv"
  done
done
cat "$OUT/summary.tsv"
