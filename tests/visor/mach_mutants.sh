#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# mach_mutants.sh -- negative controls for tests/visor/mach_parity.sh.
#
# Each mutant is one deliberate fault in the shipped OM-2 machine lane
# (src/visor/visor_machine.om): at least one per function the C lane exported (unit_name, view,
# from_facts, host_facts, current, the text and JSON renderings, blackwell_id) and per check
# they make (topology validation, the placeholder seal, the profile choice, provenance limits). The mutant is applied to a copy of the sources, the OM
# dumper is rebuilt, and the corpora of a passing parity run must show at least one difference
# from the committed C-reference goldens (tests/visor/mach_golden, generated from the C at main
# commit 3f2c70dc5). A mutant that does not apply, does not build, or shows no difference
# fails this script.
#
# usage: MACH_PARITY_WORK=<work dir of a passing mach_parity.sh run> tests/visor/mach_mutants.sh [OMC]
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OMC=${1:-$ROOT/seed/out/omc}
case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
W=${MACH_PARITY_WORK:?set MACH_PARITY_WORK to the work dir of a passing mach_parity.sh run}
GOLD=$ROOT/tests/visor/mach_golden
[ -x "$W/mach_dump_om" ] && [ -d "$W/corpus" ] || { echo "MUTANTS FAIL no parity work dir"; exit 2; }
[ -f "$GOLD/MANIFEST" ] || { echo "MUTANTS FAIL missing $GOLD/MANIFEST"; exit 2; }
M=$W/mut
rm -rf "$M"; mkdir -p "$M"

# name|perl substitution on src/visor/visor_machine.om (perl -0pi, so \n spans lines).
# The host-* mutants change how this host is read; only the host corpus (compared on the
# generating host) can catch them.
cat > "$M/list" <<'EOF'
unit-name-acc|s/text vmch_u_acc "ACCELERATOR_PORT"/text vmch_u_acc "ACCELERATOR"/
unit-name-unknown|s/text vmch_u_unk "UNKNOWN"/text vmch_u_unk "UNK"/
unit-pad-15|s/vmch_pad vmch_unit_name_len t 16/vmch_pad vmch_unit_name_len t 15/
text-units-clamp-7|s/fn vmch_text_units g ulong to void\n  uc = vmch_gget g VMCH_K_UCNT\n  if gt uc VMCH_MAXU\n    uc = VMCH_MAXU/fn vmch_text_units g ulong to void\n  uc = vmch_gget g VMCH_K_UCNT\n  if gt uc 7\n    uc = 7/
json-units-clamp-7|s/fn vmch_json_units g ulong to void\n  uc = vmch_gget g VMCH_K_UCNT\n  if gt uc VMCH_MAXU\n    uc = VMCH_MAXU/fn vmch_json_units g ulong to void\n  uc = vmch_gget g VMCH_K_UCNT\n  if gt uc 7\n    uc = 7/
text-caches-clamp-7|s/fn vmch_text_caches g ulong to void\n  cc = vmch_gget g VMCH_K_CCNT\n  if gt cc VMCH_MAXC\n    cc = VMCH_MAXC/fn vmch_text_caches g ulong to void\n  cc = vmch_gget g VMCH_K_CCNT\n  if gt cc 7\n    cc = 7/
cache-data-letter|s/      if eq lvl 1\n        ob_putc uchar 68/      if eq lvl 2\n        ob_putc uchar 68/
cache-instr-letter|s/      ob_putc uchar 73\n/      ob_putc uchar 105\n/
json-cache-instr|s/    vmch_jbool vmch_gget g add b 1\n/    vmch_jbool 0\n/
validate-issue|s/if eq vmch_gget g VMCH_K_ISSUE 0/if eq vmch_gget g VMCH_K_ISSUE 1/
validate-gpr-count|s/  if ne gc 31\n/  if gt gc 31\n/
validate-gpr-width|s/  if ne gw 64\n/  if lt gw 64\n/
cache-inversion-le|s/    if lt lvl prev\n/    if le lvl prev\n/
line-not-pow2|s/      bad = ne and line sub line 1 0\n/      bad = false\n/
line-zero|s/    bad = eq line 0\n/    bad = false\n/
err-cap-50|s/  if lt l 95\n    put vmch_err l c/  if lt l 50\n    put vmch_err l c/
seal-const-30|s/  s0 = get vmch_gseal sb\n  for k ulong 31/  s0 = get vmch_gseal sb\n  for k ulong 30/
view-no-placeholder|s/  if vmch_seal_const g\n    put vmch_vph v 1\n  end\n//
view-observed|s/  put vmch_vobs v 0\n  put vmch_vph v 0/  put vmch_vobs v 1\n  put vmch_vph v 0/
prov-cap-200|s/  if lt l 383\n/  if lt l 200\n/
fit-mismatch-text|s/host cores do NOT match \(no 0xd4f\)/host cores do not match (no 0xd4f)/
facts-dmi-one|s/  dmi = or vmch_fact_has 1 vmch_w_dgx1 vmch_fact_has 1 vmch_w_dgx2/  dmi = vmch_fact_has 1 vmch_w_dgx1/
facts-uname-prefix|s/  a64 = vmch_fact_eq 0 vmch_w_a64/  a64 = vmch_fact_has 0 vmch_w_a64/
facts-spark-needs-both|s/  spark = and a64 or dmi nv2/  spark = and a64 and dmi nv2/
prov-uname-30|s/  vmch_prov_fact v 0 31/  vmch_prov_fact v 0 30/
prov-dmi-62|s/  vmch_prov_fact v 1 63/  vmch_prov_fact v 1 62/
prov-parts-62|s/  vmch_prov_fact v 2 63/  vmch_prov_fact v 2 62/
json-escape-31|s/  if lt c 32\n    ob_putc uchar 92\n    ob_putc uchar 117/  if lt c 31\n    ob_putc uchar 92\n    ob_putc uchar 117/
json-backslash|s/  if or eq c 34 eq c 92\n    ob_putc uchar 92\n    ob_putc c/  if eq c 34\n    ob_putc uchar 92\n    ob_putc c/
hex64-zero|s/    if or ne nib 0 or started eq i 15\n/    if or ne nib 0 started\n/
blackwell-name|s/text vmch_bw_name "NVIDIA_DGX_SPARK_GB10_SM121"/text vmch_bw_name "NVIDIA_DGX_SPARK_GB10_SM120"/
text-exact-size|s/  ob_reset sub n 1\n  vmch_text_head v/  ob_reset n\n  vmch_text_head v/
json-exact-size|s/  ob_reset sub n 1\n  vmch_json_head v/  ob_reset n\n  vmch_json_head v/
text-zero-size|s/fn vmch_vtext v ulong n ulong to long\n  if eq n 0\n    ret -1/fn vmch_vtext v ulong n ulong to long\n  if eq n 0\n    ret 0/
host-no-dedupe|s/  if dup\n    ret\n  end\n//
host-uname-cap|s/    vmch_first_line 0 32\n/    vmch_first_line 0 5\n/
EOF

OMS="src/visor/visor.om src/visor/visor_machine.om tests/visor/mach_dump.om"
f=src/visor/visor_machine.om
same_host=$(cat "$W/same_host" 2>/dev/null || echo 0)
n=0; killed=0; bad=0; skipped=0
while IFS='|' read -r name expr; do
  [ -n "$name" ] || continue
  n=$((n + 1))
  case $name in host-*) if [ "$same_host" -ne 1 ]; then skipped=$((skipped + 1)); echo "MUTANT $n $name SKIPPED (host corpus not comparable here)"; continue; fi ;; esac
  T=$M/t$n
  mkdir -p "$T"
  (cd "$ROOT" && tar -cf - $OMS) | tar -xf - -C "$T"
  cp "$T/$f" "$T/$f.orig"
  perl -0pi -e "$expr" "$T/$f"
  if cmp -s "$T/$f" "$T/$f.orig"; then
    echo "MUTANT $n $name NOT-APPLIED $expr"; bad=$((bad + 1)); continue
  fi
  if ! (cd "$T" && (printf 'om2\n'; sed -e '/^om2$/d' -e 's/^export fn /fn /' $OMS) | "$OMC" > "$T/dump" 2>"$T/omc.err"); then
    echo "MUTANT $n $name NO-BUILD $(head -1 "$T/omc.err") $expr"; bad=$((bad + 1)); continue
  fi
  chmod +x "$T/dump"
  hit=""
  for c in "$W"/corpus/*.txt; do
    b=$(basename "$c" .txt)
    [ "$b" = host ] && [ "$same_host" -ne 1 ] && continue
    rc=0
    "$T/dump" < "$c" > "$T/$b.om" 2>/dev/null || rc=$?
    if [ "$rc" -ne 0 ] || ! cmp -s "$T/$b.om" "$GOLD/$b.out"; then hit="$hit $b"; fi
  done
  if [ -n "$hit" ]; then
    killed=$((killed + 1)); echo "MUTANT $n $name KILLED by$hit"
  else
    bad=$((bad + 1)); echo "MUTANT $n $name SURVIVED $expr"
  fi
done < "$M/list"
echo "MACH_MUTANTS run=$n killed=$killed bad=$bad skipped=$skipped"
[ "$bad" -eq 0 ]
