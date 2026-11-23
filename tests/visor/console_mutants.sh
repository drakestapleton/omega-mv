#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# console_mutants.sh -- negative controls for tests/visor/console_parity.sh.
#
# Each mutant is one deliberate fault in the shipped OM-2 omega console: the command parser
# (src/visor/visor_parse_command.om), the console (src/visor/visor_console.om), the session
# tables (src/visor/visor.om), the CLI (tools/omega.om), the hooks (tools/omega_ops.om) or the
# hook dispatcher (tools/omega_wire.om). The mutant is applied to a copy of the sources, the
# omega binary is rebuilt from $(OMEGA_OM_SRCS) as mk/00-visor-core.mk builds it, and the
# corpora of a passing parity run must show at least one difference from the committed
# C-reference goldens (tests/visor/console_golden, from the C at main commit 3f2c70dc5). A
# mutant that does not apply, does not build, or shows no difference fails this script.
#
# usage: CONSOLE_PARITY_WORK=<work dir of a passing console_parity.sh run> \
#        CONSOLE_PARITY_OMS='<OMEGA_OM_SRCS>' tests/visor/console_mutants.sh [OMC]
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OMC=${1:-$ROOT/seed/out/omc}
case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
W=${CONSOLE_PARITY_WORK:?set CONSOLE_PARITY_WORK to the work dir of a passing console_parity.sh run}
OMS=${CONSOLE_PARITY_OMS:?set CONSOLE_PARITY_OMS to the omega sources (OMEGA_OM_SRCS)}
GOLD=$ROOT/tests/visor/console_golden
[ -x "$W/omega_om" ] && [ -d "$W/corpus" ] || { echo "MUTANTS FAIL no parity work dir"; exit 2; }
[ -f "$GOLD/MANIFEST" ] || { echo "MUTANTS FAIL missing $GOLD/MANIFEST"; exit 2; }
M=$W/mut
rm -rf "$M"; mkdir -p "$M"

# name|file|perl substitution (applied with perl -0pi, so \n spans lines)
cat > "$M/list" <<'EOF'
line-max-4097|src/visor/visor_parse_command.om|s/const VPC_LINE_MAX ulong 4096/const VPC_LINE_MAX ulong 4097/
token-max-257|src/visor/visor_parse_command.om|s/    if ge tl VPC_TOKEN_MAX\n/    if gt tl VPC_TOKEN_MAX\n/
allow-del|src/visor/visor_parse_command.om|s/if or and lt b 0x20 ne b 9 eq b 0x7f/if and lt b 0x20 ne b 9/
allow-tab-rejected|src/visor/visor_parse_command.om|s/if or and lt b 0x20 ne b 9 eq b 0x7f/if or lt b 0x20 eq b 0x7f/
accept-surrogate|src/visor/visor_parse_command.om|s/  if and ge cp 0xd800 le cp 0xdfff\n    ret 0\n  end\n//
accept-overlong|src/visor/visor_parse_command.om|s/  if or lt cp cmin gt cp 0x10ffff\n/  if gt cp 0x10ffff\n/
accept-above-10ffff|src/visor/visor_parse_command.om|s/  if or lt cp cmin gt cp 0x10ffff\n/  if lt cp cmin\n/
accept-bad-continuation|src/visor/visor_parse_command.om|s/    if ne and b 0xc0 0x80\n      ret 0xffffffff\n    end\n//
accept-truncated-utf8|src/visor/visor_parse_command.om|s/  if gt add pos clen n\n    ret 0\n  end\n//
any-for-machine|src/visor/visor_parse_command.om|s/      if not vpc_tok_is sub nt 1 vpc_w_cur\n/      if false\n/
no-for-strip|src/visor/visor_parse_command.om|s/      put vpc_for_cur 0 1\n      nt = sub nt 2\n/      put vpc_for_cur 0 1\n/
comment-is-source|src/visor/visor_parse_command.om|s/  if eq get vpc_line 0 35\n    put vpc_cmd 0 VPC_EMPTY/  if eq get vpc_line 0 36\n    put vpc_cmd 0 VPC_EMPTY/
compare-one-arg|src/visor/visor_parse_command.om|s/  if eq cmd 17\n    put vpc_bdst 0 2\n/  if eq cmd 17\n    put vpc_bdst 0 1\n/
run-five-args|src/visor/visor_parse_command.om|s/  if eq cmd 10\n    put vpc_bdst 0 1\n    put vpc_bdst 1 4\n/  if eq cmd 10\n    put vpc_bdst 0 1\n    put vpc_bdst 1 5\n/
keep-cr|src/visor/visor_parse_command.om|s/    if eq get vpc_in sub n 1 13\n/    if eq get vpc_in sub n 1 14\n/
arity-plural|src/visor/visor_parse_command.om|s/    if ne mn 1\n      vpc_ec uchar 115\n/    if ne mn 2\n      vpc_ec uchar 115\n/
too-many-args|src/visor/visor_parse_command.om|s/    if ge nt add VPC_MAX_ARGS 2\n/    if ge nt add VPC_MAX_ARGS 3\n/
json-quote|src/visor/visor_console.om|s/  if eq c 34\n    vk_putc uchar 92\n    vk_putc uchar 34\n/  if eq c 34\n    vk_putc uchar 34\n/
json-newline-body|src/visor/visor_console_hooks.om|s/  if eq c 10\n    vb_putc uchar 92\n    vb_putc uchar 110\n/  if eq c 10\n    vb_putc uchar 110\n/
simulation-is-pure|src/visor/visor_console.om|s/  if or eq cmd 9 or eq cmd 16 eq cmd 17\n    ret VCON_CL_SIM/  if or eq cmd 9 or eq cmd 16 eq cmd 17\n    ret VCON_CL_PURE/
nul-message|src/visor/visor_console.om|s/text vcon_m_nul "NUL byte in line is not allowed"/text vcon_m_nul "NUL byte in line"/
prompt-byte|src/visor/visor_console.om|s/  vk_putc uchar 206\n  vk_putc uchar 169\n/  vk_putc uchar 206\n  vk_putc uchar 168\n/
tab-not-blank|src/visor/visor_console.om|s/    if and ne c 32 ne c 9\n      break\n/    if ne c 32\n      break\n/
no-bindings-text|src/visor/visor_console.om|s/text vcon_t_nobind "\(no bindings\)\\n"/text vcon_t_nobind "(none)\\n"/
long-line-raw-length|src/visor/visor_console.om|s/    ve_put_u64 m\n/    ve_put_u64 n\n/
no-such-command|src/visor/visor_console.om|s/text vcon_m_nocmd1 "no such command '"/text vcon_m_nocmd1 "no command '"/
bindings-no-last|src/visor/visor_console.om|s/  if ne get v_has_last 0 0\n    vcon_last_row/  if ne get v_has_last 0 1\n    vcon_last_row/
help-exit-1|tools/omega.om|s/          v_write_all 1 omcli_usage\n          ret 0\n/          v_write_all 1 omcli_usage\n          ret 1\n/
two-scripts-ok|tools/omega.om|s/            if ge scr 0\n              v_write_all 2 omcli_m_one/            if lt scr -1\n              v_write_all 2 omcli_m_one/
quit-not-stop-commands|tools/omega.om|s/    if ne get vcon_quit 0 0\n      break\n    end\n    if ne omcli_run_cmd ci 0/    if ne omcli_run_cmd ci 0/
script-after-quit|tools/omega.om|s/  if and ge sfd 0 eq get vcon_quit 0 0\n/  if ge sfd 0\n/
repl-after-commands|tools/omega.om|s/  if and lt scr 0 eq get omcli_ccnt 0 0\n/  if lt scr 0\n/
exit-always-0|tools/omega.om|s/  if ne any 0\n    ret 1\n  end\n  ret 0\nend/  ret 0\nend/
run-no-binary|tools/omega_ops.om|s/          radix = 2\n/          radix = 10\n/
run-octal-decimal|tools/omega_ops.om|s/    radix = 8\n/    radix = 10\n/
run-overflow-wraps|tools/omega_ops.om|s/    if gt v div sub ulong 0xffffffffffffffff d radix\n/    if gt v div ulong 0xffffffffffffffff radix\n/
run-bare-0x|tools/omega_ops.om|s/        if gt al 2\n          radix = 16\n/        if gt al 1\n          radix = 16\n/
no-effects-text|tools/omega_ops.om|s/text vom_t_noeffs "no effect objects in session\\n"/text vom_t_noeffs "no effects\\n"/
alternatives-added-json|tools/omega_ops.om|s/text vom_j_added ",\\"added\\":"/text vom_j_added ",\\"new\\":"/
program-input-text|tools/omega_ops.om|s/text vom_m_prog3 " takes 1 input; got "/text vom_m_prog3 " takes one input; got "/
canonical-len-json|tools/omega_ops.om|s/text vom_j_clen2 "\\",\\"canonical_len\\":"/text vom_j_clen2 "\\",\\"len\\":"/
bindings-63|src/visor/visor.om|s/const V_MAX_BINDINGS ulong 64/const V_MAX_BINDINGS ulong 63/
programs-15|src/visor/visor.om|s/const V_MAX_PROGRAMS ulong 16/const V_MAX_PROGRAMS ulong 15/
realizations-15|src/visor/visor.om|s/const V_MAX_REALS ulong 16/const V_MAX_REALS ulong 15/
no-sha256-prefix|src/visor/visor.om|s/text vt_sha256_pfx "sha256:"/text vt_sha256_pfx "sha512:"/
hook-why-unwired|tools/omega_wire.om|s/  ret lt hid 17\n/  ret lt hid 16\n/
EOF

n=0; killed=0; bad=0
while IFS='|' read -r name f expr; do
  [ -n "$name" ] || continue
  n=$((n + 1))
  T=$M/t$n
  mkdir -p "$T"
  (cd "$ROOT" && tar -cf - $OMS) | tar -xf - -C "$T"
  file=$T/$f
  cp "$file" "$file.orig"
  perl -0pi -e "$expr" "$file"
  if cmp -s "$file" "$file.orig"; then
    echo "MUTANT $n $name NOT-APPLIED $expr"; bad=$((bad + 1)); continue
  fi
  if ! (cd "$T" && (printf 'om2\n'; sed -e '/^om2$/d' -e 's/^export fn /fn /' $OMS) | "$OMC" > "$T/omega" 2>"$T/omc.err"); then
    echo "MUTANT $n $name NO-BUILD $(head -1 "$T/omc.err") $expr"; bad=$((bad + 1)); continue
  fi
  chmod +x "$T/omega"
  CONSOLE_PARITY_WORK=$T/w CONSOLE_PARITY_BIN=$T/omega sh "$ROOT/tests/visor/console_parity.sh" --run-only
  hit=""
  for g in "$GOLD"/*.out; do
    b=$(basename "$g" .out)
    cmp -s "$g" "$T/w/out/$b.out" || hit="$hit $b"
  done
  if [ -n "$hit" ]; then
    killed=$((killed + 1)); echo "MUTANT $n $name KILLED by$hit"
  else
    bad=$((bad + 1)); echo "MUTANT $n $name SURVIVED $expr"
  fi
  rm -rf "$T/w"
done < "$M/list"
echo "CONSOLE_MUTANTS run=$n killed=$killed bad=$bad"
[ "$bad" -eq 0 ]
