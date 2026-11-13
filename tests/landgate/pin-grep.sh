#!/bin/bash
# TEST INSTRUMENT (tests/landgate): the one compiler-pin grep, kept as a receipt. Run in a checkout of HEAD.
# usage: pin-grep.sh BASE   (BASE: the commit whose seed/out/omc the head replaces)
# One git grep over the tracked files for the base compiler's sha256 and the head compiler's sha256.
# Every hit outside evidence/ must have a class; a hit in code (*.sh *.py *.om *.c *.pin *.yml *.awk) is a
# typed live pin and fails, except the named qualification-bound pair. The scan must be observed to complete: both
# compiler digests are 64 hex digits, git grep exits 0, and the record seed/out/omc.sha256 is among its hits; any other
# outcome is "PINGREP SCAN FAILED", never a pass with fewer hits. Exit 0 PASS, 1 FAIL.
set -u
BASE=$1
H=$(cut -d ' ' -f 1 seed/out/omc.sha256); B=$(git show "$BASE:seed/out/omc.sha256" | cut -d ' ' -f 1)
echo "PINGREP head $(git rev-parse HEAD) omc $H base $BASE omc $B"
echo "PINGREP command: git grep -n -I -e $B -e $H -- . ':!evidence'"
case "$H:$B" in [0-9a-f]*:[0-9a-f]*) ;; *) echo "PINGREP SCAN FAILED: compiler digests not read (head [$H] base [$B])"; exit 1 ;; esac
[ "${#H}" = 64 ] && [ "${#B}" = 64 ] || { echo "PINGREP SCAN FAILED: compiler digests are not 64 hex digits"; exit 1; }
fails=0; n=0; rec=0; hits=$(mktemp) || exit 1; trap 'rm -f "$hits"' EXIT
git grep -n -I -e "$B" -e "$H" -- . ':!evidence' > "$hits"; grc=$?
[ "$grc" = 0 ] || { echo "PINGREP SCAN FAILED: git grep exit $grc"; exit 1; }  # scan predicate
while IFS= read -r hit; do
  n=$((n + 1)); f=${hit%%:*}; rest=${hit#*:}; line=${rest%%:*}; text=${rest#*:}
  which=head; case $text in *"$B"*) which=base ;; esac
  case "$which:$f" in
    head:seed/out/omc.sha256) c="the record itself"; rec=1 ;;
    *:seed/omc/size-history.tsv) c="generated size-history row" ;;
    head:src/omega_native.h|head:src/omega_om_units.c|head:src/omega_om_units.ident|head:src/omega_om_units_fs.c) c="generated binding identity (om/units.sh --check)" ;;
    base:native/prefetch/compiler.sha256) c="qualification-bound pair, not repinned (listed limit; tools/run_gpu_l2d_prefetch_chip.sh host qualification NOT_RUN 3)" ;;
    base:native/prefetch/README.md) c="prose of the qualification-bound pair" ;;
    base:AUDIT_SCOPE.md|base:neuralese/README.md|base:om/gpumath/README.md)
      if printf '%s' "$text" | grep -q 'last\|was$\|was,\|Before that record' || sed -n "$((line - 3)),${line}p" "$f" | grep -q 'last typed\|last pin typed\|Before that record\|was typed'; then c="history: named as the last typed pin"; else c=UNCLASSIFIED; fi ;;
    *) c=UNCLASSIFIED ;;
  esac
  case "$c:$f" in "generated binding identity"*) ;; *:*.sh|*:*.py|*:*.om|*:*.c|*:*.pin|*:*.yml|*:*.awk) c="TYPED LIVE PIN" ;; esac
  echo "HIT $which $f:$line class=$c"
  case $c in UNCLASSIFIED|"TYPED LIVE PIN") fails=$((fails + 1)) ;; esac
done < "$hits"
[ "$rec" = 1 ] || { echo "PINGREP SCAN FAILED: the record seed/out/omc.sha256 is not among the $n hits"; exit 1; }  # scan predicate
rl=$(git grep -l -I 'omc\.sha256') || { echo "PINGREP SCAN FAILED: reader listing"; exit 1; }; readers=$(printf '%s\n' "$rl" | grep -c .)
echo "PINGREP hits=$n tracked readers of omc.sha256=$readers (each classified by seed/omc/tests/pins/admission-check.sh)"
[ "$fails" = 0 ] && { echo "PINGREP PASS hits=$n"; exit 0; }  # class predicate
echo "PINGREP FAIL unclassified=$fails"; exit 1
