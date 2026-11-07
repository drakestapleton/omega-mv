set -u
# Lean negative controls for rule forbnd (DRA-189): mutate the rule in the model and require the
# unchanged proof to FAIL to check; then check the original (0 errors).
#   sh seed/omc/om2/bce/lean/negctl.sh LEAN_PROJECT OUT
# LEAN_PROJECT: any lake project on Lean v4.35.0 (the model has no imports); OUT: a new directory.
S=$(cd "$(dirname "$0")" && pwd)/OmegaBce.lean
P=$1; O=$2
[ -e "$O" ] && { echo "OUT exists: $O" >&2; exit 91; }
mkdir -p "$O"; O=$(cd "$O" && pwd)
cd "$P" || exit 3
# L1 (klen): admit an index without the count <= length premise
sed 's/  | .reg r => act.any (fun p => p.1 == r \&\& decide (p.2 ≤ len a))/  | .reg r => act.any (fun p => p.1 == r \&\& (decide (p.2 ≤ len a) || true))/' "$S" > "$O/L1.lean"
# L2 (scan): admit a loop without the body-write premise
sed 's/      if k ≠ 0 ∧ writes r b = false then .forN r k g (erase ((r, k) :: act) b)/      if k ≠ 0 then .forN r k g (erase ((r, k) :: act) b)/' "$S" > "$O/L2.lean"
# L3 (reg): admit any index expression when some counter is admitted
sed 's/  | _ => false$/  | _ => !act.isEmpty/' "$S" > "$O/L3.lean"
bad=0
for m in L1 L2 L3; do
  if cmp -s "$S" "$O/$m.lean"; then echo "LEANNEG $m NOT_APPLIED"; bad=1; continue; fi
  lake env lean "$O/$m.lean" > "$O/$m.log" 2>&1; rc=$?
  n=$(grep -c ': error' "$O/$m.log")
  echo "LEANNEG $m rc=$rc errors=$n first: $(grep -m1 ': error' "$O/$m.log" | sed 's/^.*\.lean://' | cut -c1-120)"
  [ $rc != 0 ] && [ $n -gt 0 ] || bad=1
done
lake env lean "$S" > "$O/orig.log" 2>&1; rc=$?
echo "LEANNEG original rc=$rc errors=$(grep -c ': error' "$O/orig.log") warnings=$(grep -c ': warning' "$O/orig.log")"
[ $rc = 0 ] || bad=1
[ $bad = 0 ] && echo "LEANNEG PASS 3 mutants rejected, original checks" || { echo "LEANNEG FAIL"; exit 1; }
