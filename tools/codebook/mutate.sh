#!/bin/sh
# mutate.sh -- mutation check: each mutant of codebook.om must make test.sh fail.
# Run from the repo root:  sh tools/codebook/mutate.sh   (OMC defaults to seed/out/omc)
set -u
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd); cd "$R"
OMC=${OMC:-$R/seed/out/omc}
case $OMC in /*) ;; *) OMC=$R/$OMC ;; esac
export OMC
[ -f "$OMC" ] && [ -x "$OMC" ] || { echo "compiler unavailable: $OMC" >&2; exit 2; }
if [ -z "${M:-}" ]; then M=$(mktemp -d "${TMPDIR:-/tmp}/codebook-mut.XXXXXX") || exit 2
else
  if [ -e "$M" ] || [ -L "$M" ]; then echo "work directory already exists: $M (preserved)" >&2; exit 2; fi
  mkdir -p "$M" || exit 2
fi
case $M in /*) ;; *) M=$R/$M ;; esac
# Only completed assertion failures are kills. Preserve full logs and raw exits.
check_test() {
  BIN=$1 FIX=$2 sh tools/codebook/test.sh > "$3" 2>&1; rc=$?
  printf '%s\n' "$rc" > "$3.rc"
  total=$(grep '^TOTAL pass=[0-9]* fail=[0-9]* skip=[0-9]*$' "$3" | tail -1)
  failed=${total#*fail=}; failed=${failed%% *}
  case $total in
    *' skip=0')
      if [ "$rc" = 0 ] && [ "$failed" = 0 ]; then echo survived
      elif [ "$rc" = 1 ] && [ "$failed" -ge 1 ] 2>/dev/null && grep -q '^FAIL ' "$3"; then echo killed
      else echo harness-error; fi ;;
    *) echo harness-error ;;
  esac
}
B="$M/base" sh tools/codebook/build.sh > "$M/base.build.log" 2>&1 || { echo 'BASELINE build failed'; exit 5; }
base=$(check_test "$M/base/codebook" "$M/base/fix" "$M/base.test.log")
[ "$base" = survived ] || { echo "BASELINE did not pass: $base"; exit 5; }
KEYDIR=$M/key; export KEYDIR
SRC=tools/codebook/codebook.om
# name|sed expression (applied to one copy of the source each)
cat > "$M/list" <<'L'
escape-threshold-800|/^fn decl /,/^$/s/^if lt g 900$/if lt g 800/
no-dangling-escape-check|/^fn decl /,/^$/s/^ret 3$/ret 0/
encoder-no-structure-check|/^fn encv /,/^$/s/^ret 5$/ret 0/
o3-digit-order|/^fn o3 /,/^$/s/rem div v 100 10/rem v 10/
hmac-ipad-55|s/mbyte uchar xor get kz i 54/mbyte uchar xor get kz i 55/
long-key-not-hashed|/^fn mkk0 /,/^$/s/^if gt n 64$/if gt n 65/
mac-compare-always-true|/^fn maceq /,/^$/s/^ret eq x 0$/ret true/
mac-compare-first-byte-only|/^fn maceq /,/^$/s/^for i ulong 64$/for i ulong 1/
replay-accepted|/^fn verl4 /,/^$/s/^if le ctr rdctr s sn$/if lt ctr rdctr s sn/
counter-not-stored|/^fn verl4 /,/^$/s/^wrctr s sn c cn$//
cbsha-not-checked|/^fn verl3 /,/^$/s/^bad vcb$/put mo 0 get mo 0/
trit-ignores-verification|/^fn ltrit /,/^$/s/^if and ok em$/if em/
emergency-lower-bound-100|/^fn hasem /,/^$/s/ge g 300/ge g 100/
bademd-trit-ignores-ok|/^fn ltrit /,/^$/s/^if and ok em$/if or ok em/
emergency-range-to-499|/^fn hasem /,/^$/s/lt g 400/lt g 500/
codebook-dup-allowed|/^fn cbent2 /,/^$/s/^if sameb get eo b cs0 cl$/if false/
unknown-codes-accepted|/^fn known /,/^$/s/^if eq lookup a n false$/if false/
missing-mac-not-unsigned|/^fn verl /,/^$/s/^if eq get fs 0 get fs 1$/if false/
malformed-counter-fails-open|/^fn rdctf /,/^$/s/^ret BIG$/ret 0/
L
n=0; caught=0; invalid=0; errors=0
while IFS='|' read -r name expr; do
  n=$((n+1)); d=$M/$name; mkdir -p "$d"
  sed "$expr" "$SRC" > "$d/codebook.om"
  if cmp -s "$d/codebook.om" "$SRC"; then echo "MUTANT $name: sed did not change the source (BAD LIST)"; invalid=$((invalid+1)); continue; fi
  { printf 'om2\n'; grep '^abstract ' "$d/codebook.om"; sed '/^fn sha256 /,$d' seed/trace/sha256.om; grep -v "^abstract " "$d/codebook.om"; cat tools/codebook/main.om; } > "$d/full.om"
  if ! "$OMC" < "$d/full.om" > "$d/bin" 2>"$d/omc.err"; then echo "MUTANT $name: does not compile ($(cat "$d/omc.err"))"; invalid=$((invalid+1)); continue; fi
  chmod +x "$d/bin"
  out=$(check_test "$d/bin" "$d/fix" "$d/test.log")
  case "$out" in
    survived) echo "MUTANT $name: SURVIVED" ;;
    killed) caught=$((caught+1)); echo "MUTANT $name: caught (assertions failed)" ;;
    *) errors=$((errors+1)); echo "MUTANT $name: HARNESS ERROR (not a kill)" ;;
  esac
done < "$M/list"
echo "MUTANTS $n CAUGHT $caught"
[ "$errors" = 0 ] || exit 4
[ "$invalid" = 0 ] || exit 3
[ "$n" -gt 0 ] && [ "$caught" -eq "$n" ]
