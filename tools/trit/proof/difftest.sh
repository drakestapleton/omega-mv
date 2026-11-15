#!/bin/sh
# difftest.sh -- Lean model (TritSignal.lean, namespace TritBin) vs trit.bin on N generated cases.
# Usage: BIN=... N=600 SEED=1 sh tools/trit/proof/difftest.sh   (needs python3 and lean)
# Both sides read the same fixture directories; stdout, stderr and exit status must match exactly.
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
BIN=${BIN:-build/trit/trit}; case $BIN in /*) ;; *) BIN=$(pwd)/$BIN ;; esac
N=${N:-600}; SEED=${SEED:-1}; LEAN=${LEAN:-lean}
W=${W:-${TMPDIR:-/tmp}/trit-diff.$$}
rm -rf "$W"; mkdir -p "$W/cases"
python3 "$HERE/gen.py" "$W/cases" "$N" "$SEED" "$HERE/../../codebook/codebook.tsv"
i=0
: > "$W/bin.out"
while [ "$i" -lt "$N" ]; do
  D="$W/cases/$i"
  set +e; "$BIN" "$D" a > "$W/o" 2> "$W/e"; rc=$?; set -e
  printf '%s\t%s\t%s\n' "$rc" "$(awk '{printf "%s\\n", $0}' "$W/o")" "$(awk '{printf "%s\\n", $0}' "$W/e")" >> "$W/bin.out"
  i=$((i+1))
done
{ cat "$HERE/TritSignal.lean"; cat <<LEAN

def readOpt (p : System.FilePath) : IO (Option (List Char)) := do
  if (← p.pathExists) then
    let b ← IO.FS.readBinFile p
    return some (b.data.toList.map fun x => Char.ofNat x.toNat)
  else return none

def escNl (s : String) : String := String.join (s.toList.map fun c => if c == '\n' then "\\\\n" else String.singleton c)

def runDir (d : System.FilePath) : IO String := do
  let inbox := d / "inbox"
  let ents ← inbox.readDir
  let ents := ents.toList
  let allow := ents.filterMap fun e =>
    let f := e.fileName
    if f.endsWith ".md" then some (String.ofList (f.toList.take (f.length - 3))) else none
  let cbf ← readOpt (d / "codebook" / "codebook.tsv")
  let kf ← readOpt (d / "codebook" / "key")
  let codesOf (cb : List Char) : List String :=
    (((String.ofList cb).splitOn "\n").filter (fun x => x != "" && !x.startsWith "#")).map (fun x => (x.splitOn "\t").headD "")
  let vc : Option TritBin.VC := match cbf, kf with
    | some cb, some k => some (TritBin.VC.mk (TritBin.sha256 cb) (codesOf cb) (TritBin.toB k))
    | _, _ => none
  let mut ctrs : List (String × List Char) := []
  for e in ents do
    let f := e.fileName
    if f.startsWith "a." && f.endsWith ".ctr" then
      if let some c ← readOpt e.path then ctrs := ctrs ++ [(String.ofList ((f.toList.drop 2).take (f.length - 6)), c)]
  let fc : String → Nat × String := fun s => TritBin.rdctf (ctrs.lookup s)
  let nm ← readOpt (inbox / "a.md")
  let em ← readOpt (inbox / "a.emergency.md")
  let nc ← readOpt (inbox / "a.md.cur")
  let ec ← readOpt (inbox / "a.emergency.md.cur")
  let (o, e, rc) := TritBin.runBot vc fc allow nm em nc ec
  return toString rc ++ "\t" ++ escNl o ++ "\t" ++ escNl e

#eval show IO Unit from do
  for i in [0:$N] do
    IO.println (← runDir ("$W/cases" / toString i))
LEAN
} > "$W/Diff.lean"
"$LEAN" "$W/Diff.lean" | grep -v "axioms" > "$W/lean.out"
if cmp -s "$W/bin.out" "$W/lean.out"; then
  printf 'DIFF agree=%s/%s seed=%s (stdout, stderr, status) lean-sha256=%s\n' "$N" "$N" "$SEED" "$(sha256sum < "$W/lean.out" | cut -c1-16)"
  awk -F'\t' '{c[$1]++; if ($2 ~ /^a 2/) t2++; else if ($2 ~ /^a 1/) t1++; if ($3 != "") r++} END {printf "MIX exit0=%d exit1=%d trit1=%d trit2=%d with-stderr=%d\n", c[0], c[1], t1, t2, r}' "$W/bin.out"
else
  n=$(diff "$W/bin.out" "$W/lean.out" | grep -c '^<' || true)
  printf 'DIFF disagree=%s of %s seed=%s; see %s\n' "$n" "$N" "$SEED" "$W"
  diff "$W/bin.out" "$W/lean.out" | head -20
  exit 1
fi
