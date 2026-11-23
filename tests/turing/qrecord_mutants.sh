#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# qrecord_mutants.sh -- negative controls for tests/turing/qrecord_parity.sh.
#
# Each mutant is one deliberate fault in the shipped OM-2 companion records
# (src/turing/ty_qrecord.om): a field dropped or misread, a refusal rule widened or narrowed, a
# binding check removed, the writer's flags, mode or path limit changed, the file verifier's
# domain or size rule changed, a sidecar parser or builder rule changed. The mutant is applied to
# a copy of the sources, the OM dumper is rebuilt, and the corpora of a passing parity run must
# show at least one difference from the committed C-reference goldens (tests/turing/
# qrecord_golden, generated from the C at main commit 3f2c70dc5), or the run must fail. A mutant
# that does not apply, does not build, or shows no difference fails this script.
#
# usage: QRECORD_PARITY_WORK=<work dir of a passing qrecord_parity.sh run> tests/turing/qrecord_mutants.sh [OMC]
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OMC=${1:-$ROOT/seed/out/omc}
case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
W=${QRECORD_PARITY_WORK:?set QRECORD_PARITY_WORK to the work dir of a passing qrecord_parity.sh run}
GOLD=$ROOT/tests/turing/qrecord_golden
[ -x "$W/qrecord_dump_om" ] && [ -d "$W/corpus" ] || { echo "MUTANTS FAIL no parity work dir"; exit 2; }
[ -f "$GOLD/MANIFEST" ] || { echo "MUTANTS FAIL missing $GOLD/MANIFEST"; exit 2; }
M=$W/mut
rm -rf "$M"; mkdir -p "$M"
F=src/turing/ty_qrecord.om

# name|perl substitution on src/turing/ty_qrecord.om (perl -0pi, so \n spans lines)
cat > "$M/list" <<'EOF'
profile-drop-edge-rule|s/  qr_t_text 0 3 t_qk_edge_rule\n//
profile-delta-as-sd-min|s/ca_add_i64 t_qk_delta_log2 get g_qp_i 0/ca_add_i64 t_qk_delta_log2 get g_qp_i 1/
text-accepts-7f|s/    if gt b 126\n      ret false\n    end\n  end\n  ret true\nend\n\nfn qr_list_ok/    if gt b 127\n      ret false\n    end\n  end\n  ret true\nend\n\nfn qr_list_ok/
text-refuses-20|s/    if lt b 32\n/    if lt b 33\n/
text-max-511|s/  n = ulong nl\n  if gt n 512\n    ret false\n/  n = ulong nl\n  if gt n 511\n    ret false\n/
text-no-nul-accepted|s/      ret long i\n    end\n  end\n  ret -1\n/      ret long i\n    end\n  end\n  ret 512\n/
list-leading-space|s/  if eq get g_qr_str 0 32\n    ret false\n  end\n//
list-double-space|s/      if eq get g_qr_str sub i 1 32\n        ret false\n      end\n//
name-allows-space|s/    if eq get g_qr_str i 32\n      ret false\n    end\n  end\n  ret true\nend\n\nfn qr_hex40_ok/  end\n  ret true\nend\n\nfn qr_hex40_ok/
hex40-uppercase|s/    if ge c 97\n      if le c 102\n        d_ok = true/    if ge c 65\n      if le c 102\n        d_ok = true/
hex40-checks-39|s/  for i ulong 40\n    c = get g_qr_str i\n    d_ok = false/  for i ulong 39\n    c = get g_qr_str i\n    d_ok = false/
world-mode-parent-agree|s/    if ne dev_mode dev_parent\n      put g_ca_err 0 1\n    else/    if false\n      put g_ca_err 0 1\n    else/
world-qfreeze-iff-dev|s/      if ne dev_parent qr_dig_is_zero 1 1\n/      if false\n/
world-mode-no-discovery|s/  if qr_str_eq t_qr_cert\n    ret true\n  end\n  ret qr_str_eq t_qr_disc\nend\n\nfn qr_chk_parent/  if qr_str_eq t_qr_cert\n    ret true\n  end\n  ret false\nend\n\nfn qr_chk_parent/
world-block-as-rep-first|s/ca_add_u64 t_qk_block get g_qw_u 0/ca_add_u64 t_qk_block get g_qw_u 1/
freeze-artifact-bin-iff-cert|s/    if ne cert qr_dig_is_zero 2 1\n/    if false\n/
freeze-cert-tool-not-none|s/    if not t_none\n      put g_ca_err 0 1\n      ret\n    end\n//
freeze-disc-no-transcript|s/  if qr_dig_is_zero 2 5\n    put g_ca_err 0 1\n  end\nend/  if false\n    put g_ca_err 0 1\n  end\nend/
freeze-tree-dirty-2|s/  if gt td 1\n/  if gt td 2\n/
freeze-lineage-9|s/  if gt nl TYQR_MAX_LINEAGE\n/  if gt nl 9\n/
freeze-lineage-key|s/text t_qr_linp "lineage."/text t_qr_linp "lineage_"/
freeze-label-no-ambiguous|s/  if qr_str_eq t_qr_neg\n    ret true\n  end\n  ret qr_str_eq t_qr_amb\n/  if qr_str_eq t_qr_neg\n    ret true\n  end\n  ret false\n/
gain-baseline-op-8|s/gt bop 7/gt bop 8/
gain-candidate-255|s/eq cop 255/eq cop 254/
gain-official-2|s/if gt off_v 1\n/if gt off_v 2\n/
gain-ladder-iff-official|s/    if ne eq off_v 1 is_dash\n/    if false\n/
gain-t-ub-unchecked|s/      if ne get g_ty_ret_i 0 get g_qg_i 6\n/      if false\n/
gain-lo-eq-hi-refused|s/    if gt get g_qg_i 7 get g_qg_i 8\n/    if ge get g_qg_i 7 get g_qg_i 8\n/
gain-three-counts|s/    for i ulong 4\n      if gt i 0\n        tv_b uchar 32\n      end\n      tv_u64 get g_qg_u add 3 i/    for i ulong 3\n      if gt i 0\n        tv_b uchar 32\n      end\n      tv_u64 get g_qg_u add 3 i/
gain-scored-protocol-failures|s/    if ne st_k 2\n      if ne pf 0\n/    if ne st_k 2\n      if gt pf 1\n/
gain-status-fail-prefix|s/text t_qr_failp "FAIL_"/text t_qr_failp "FAIL"/
gain-status-space|s/  if not qr_name_ok TYQR_VAL\n    ret 0\n  end\n//
gain-leak-no-inconclusive|s/  if qr_str_eq t_qr_1\n    ret true\n  end\n  ret qr_str_eq t_qr_inc\n/  if qr_str_eq t_qr_1\n    ret true\n  end\n  ret false\n/
gain-coverage-minus-2|s/lt get g_qg_i add 11 i -1/lt get g_qg_i add 11 i -2/
gain-class-no-weak|s/  if qr_str_eq t_qr_weak\n    ret true\n  end\n//
verify-ignores-digest|s/  if not dg_eq TYQR_VERIFY_SLOT want_slot\n    ret TY_E_DIGEST\n  end\n  ret TY_OK\nend\n\nfn tyqr_profile_verify/  ret TY_OK\nend\n\nfn tyqr_profile_verify/
bind-skips-freeze-verify|s/  rc = tyqr_freeze_verify fd\n  if ne rc TY_OK\n    ret rc\n  end\n//
bind-world-not-sealed|s/  if not qr_dig_eq_slot 1 1 fd\n    ret TY_E_PROFILE\n  end\n//
bind-freeze-profile|s/  if not qr_dig_eq_slot 2 2 pd\n    ret TY_E_PROFILE\n  end\n//
bind-gen-version|s/  qr_load_str 3 2\n  qr_load_str2 1 4\n  if not qr_str_eq_str2\n    ret TY_E_PROFILE\n  end\n//
bind-candidate|s/  if not qr_dig_eq_dig 3 4 2 0\n    ret TY_E_PROFILE\n  end\n//
write-no-excl|s/fd = fopen g_qr_wpath 0 pl int 524481 int 292/fd = fopen g_qr_wpath 0 pl int 524353 int 292/
write-mode-0644|s/int 524481 int 292/int 524481 int 420/
write-path-1024|s/71 1023/71 1024/
write-failure-keeps-file|s/      z2 = unlink g_qr_wpath 0 pl\n//
write-record-name|s/text t_qr_rec_gain "turing.qgain"/text t_qr_rec_gain "turing.qgainx"/
fileverify-size-40001|s/  if gt tot TYQR_CANON_CAP\n    ret TY_E_FORMAT/  if gt tot 40001\n    ret TY_E_FORMAT/
fileverify-no-separator|s/  sh_slice dom len dom\n  sh_byte uchar 0\n/  sh_slice dom len dom\n/
sidecar-digest-drops-last|s/  for i ulong n bound 8192\n    sh_byte get g_qr_mbuf i\n/  for i ulong sub n 1 bound 8192\n    sh_byte get g_qr_mbuf i\n/
dec-leading-zero|s/    if eq get g_qr_mbuf off 48\n      ret false\n/    if eq get g_qr_mbuf off 49\n      ret false\n/
dec-overflow|s/    if gt v div sub umax dg 10\n      ret false\n    end\n//
dec-21-digits|s/  if or lt n 1 gt n 20\n/  if or lt n 1 gt n 21\n/
hex64-uppercase|s/        if and ge c 97 le c 102\n          d = add long sub c 97 10\n        end\n/        if and ge c 97 le c 102\n          d = add long sub c 97 10\n        end\n        if and ge c 65 le c 70\n          d = add long sub c 65 10\n        end\n/
split-accepts-7f|s/      if or lt b 33 gt b 126\n        ret -1\n/      if or lt b 33 gt b 127\n        ret -1\n/
split-trailing-space|s/    i = add i 1\n    if eq i ln\n      ret -1\n    end\n/    i = add i 1\n    if eq i ln\n      ret long add c 0\n    end\n/
line-no-final-lf|s/    i = add i 1\n  end\n  ret -1\nend\n\nfn tyqr_repman_build/    i = add i 1\n  end\n  ret 0\nend\n\nfn tyqr_repman_build/
repman-build-equal-rep|s/      if le r get g_qr_rep_u sub i 1\n/      if lt r get g_qr_rep_u sub i 1\n/
repman-build-nul-room|s/    note C snprintf needs room for its NUL: each line must leave len < cap\n    if ge get g_qr_mlen 0 cap\n      ret TY_E_FORMAT\n    end\n  end\n  ret TY_OK\nend\n\nfn tyqr_repman_parse/  end\n  ret TY_OK\nend\n\nfn tyqr_repman_parse/
repman-parse-order|s/      if le repv get g_qr_rep_u sub c 1\n/      if lt repv get g_qr_rep_u sub c 1\n/
repman-parse-cap|s/    if ge c cap\n      ret TY_E_FORMAT\n    end\n    if ne qr_split_line lo ln 2 2/    if gt c cap\n      ret TY_E_FORMAT\n    end\n    if ne qr_split_line lo ln 2 2/
devman-block-tie|s/      ret lt get g_qr_dev_b a get g_qr_dev_b b/      ret le get g_qr_dev_b a get g_qr_dev_b b/
devman-cell-control-byte|s/    if or lt b 33 gt b 126\n      ret -1\n/    if or lt b 32 gt b 126\n      ret -1\n/
devman-parse-cell-128|s/  if ge cl TYQR_CELL_MAX\n/  if gt cl TYQR_CELL_MAX\n/
devman-parse-unordered|s/  if gt c 0\n    if not qr_devline_before sub c 1 c\n      ret false\n    end\n  end\n  ret true\n/  ret true\n/
table-kv-equals-last|s/    if eq ulong eqp sub fl 1\n      ret false\n    end\n//
table-kv-equals-first|s/    if le eqp 0\n/    if lt eqp 0\n/
table-thr-two-fields|s/qr_table_check tot 3 3 0 0/qr_table_check tot 2 3 0 0/
table-thr-no-max|s/qr_table_check tot 3 3 0 0/qr_table_check tot 3 0 0 0/
table-cell-by-line|s/    al = sp\n    bl = get g_qr_fl 0\n/    al = prev_l\n/
table-equal-lines|s/  ret lt al bl\nend/  ret le al bl\nend/
EOF

OMS="src/turing/ty_core_lib.om src/turing/ty_qrecord.om tests/turing/qrecord_dump.om"
n=0; killed=0; bad=0
while IFS='|' read -r name expr; do
  [ -n "$name" ] || continue
  n=$((n + 1))
  T=$M/t$n
  mkdir -p "$T"
  (cd "$ROOT" && tar -cf - $OMS) | tar -xf - -C "$T"
  file=$T/$F
  cp "$file" "$file.orig"
  perl -0pi -e "$expr" "$file"
  if cmp -s "$file" "$file.orig"; then
    echo "MUTANT $n $name NOT-APPLIED $expr"; bad=$((bad + 1)); continue
  fi
  if ! (cd "$T" && (printf 'om2\n'; sed '/^om2$/d' $OMS) | "$OMC" > "$T/dump" 2>"$T/omc.err"); then
    echo "MUTANT $n $name NO-BUILD $(head -1 "$T/omc.err") $expr"; bad=$((bad + 1)); continue
  fi
  chmod +x "$T/dump"
  hit=""
  for c in "$W"/corpus/*.txt; do
    b=$(basename "$c" .txt)
    R=$T/run; rm -rf "$R"; mkdir -p "$R/qr_w"
    : > "$R/qr_empty"; head -c 40000 /dev/zero > "$R/qr_40000"; head -c 40001 /dev/zero > "$R/qr_40001"
    rc=0
    case $b in
      fsize-*) (cd "$R" && trap '' XFSZ && ulimit -f 12 && "$T/dump" < "$c" 2>/dev/null) | cat > "$T/$b.om" || rc=$?
               [ -z "$(ls "$R/qr_w")" ] || rc=99 ;;
      *) (cd "$R" && "$T/dump" < "$c" > "$T/$b.om" 2>/dev/null) || rc=$? ;;
    esac
    if [ "$rc" -ne 0 ] || ! cmp -s "$T/$b.om" "$GOLD/$b.out"; then hit="$hit $b"; fi
  done
  if [ -n "$hit" ]; then
    killed=$((killed + 1)); echo "MUTANT $n $name KILLED by$hit"
  else
    bad=$((bad + 1)); echo "MUTANT $n $name SURVIVED $expr"
  fi
  rm -rf "$T"
done < "$M/list"
echo "QRECORD_MUTANTS run=$n killed=$killed bad=$bad"
[ "$bad" -eq 0 ]
