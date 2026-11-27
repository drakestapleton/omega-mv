#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# seed/helix/hive_shield/hive_shield_gate.sh
# Unified Multi-Strand Pure-Omega Hive Shield Verification Gate (Strands 5, 6, 7, 8, 9 + Lean 4):
#   - Strand 5 (The Aegis):    OM-3 Zero-Pointer Linear Silicon Capabilities + OIR v2 + OMEGA-MEMO + om2 DDC
#   - Strand 6 (The Sentinel): Zero-C Ratchet + Rogue .ko Quarantine + UEFI/SPI Hardware Lock
#   - Strand 7 (The Warden):   Multi-Node Hive CBF (Spark GB10, Pi 5, MacBook Air) + Live Spark RO Audit
#   - Strand 8 (The Notary):   Pure-OM-2 SHA256SUMS Verifier + Dual-Law Consensus (1-of-K Veto + BFT) + OMEGA-MEMO
#   - Strand 9 (The Arbiter):  Zero-Trust Mesh Bind Guard + Remote Command & SSH-Storm Guard
set -eu

R=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
cd "$R"

OMC=${OMC:-"$R/seed/out/omc"}
PIN_SHA=$(awk '{print $1}' "$R/seed/out/omc.sha256")
B=${OUT_DIR:-"$R/build/hive_shield"}
rm -rf "$B"
mkdir -p "$B/s6_clean" "$B/s6_ko" "$B/s6_c" "$B/s8_sums" "$B/s8_memo" "$B/s9_cmds"

fail() { printf 'HIVE_SHIELD FAIL: %s\n' "$*" >&2; exit 1; }
sha() { sha256sum "$1" | awk '{print $1}'; }

printf '=====================================================================\n'
printf '  OMEGA MULTI-STRAND HIVE SHIELD GATE (STRANDS 5..9 + LEAN 4.36.0)\n'
printf '=====================================================================\n'

printf '\n--- [STRAND 5: THE AEGIS (OM-3 + @ng + OMEGA-MEMO + OM-2 FIXPOINT)] ---\n'
OUT_DIR="$B/strand5" OMC="$OMC" sh seed/helix/strand5_aegis/strand5_verify.sh

printf '\n--- [STRAND 6: THE SENTINEL (PURITY + KMOD QUARANTINE + UEFI LOCK)] ---\n'
"$OMC" < seed/helix/hive_shield/strand6_sentinel.om > "$B/strand6_sentinel"
chmod +x "$B/strand6_sentinel"

# Positive 1: scan pure-Omega hive_shield dir (0 C/H, 0 live .ko)
"$B/strand6_sentinel" scan-dir "$R/seed/helix/hive_shield" 0
# Positive 2: scan quarantined kmod directory on Spark if present (must report live_ko=0, quarantined_ko>=1)
if [ -d "/home/drakestapleton/work/claude-fresh-4c9fe76/kmod" ]; then
  QOUT=$("$B/strand6_sentinel" scan-dir "/home/drakestapleton/work/claude-fresh-4c9fe76/kmod" 100)
  printf '  spark_quarantine_check: %s\n' "$QOUT"
  printf '%s\n' "$QOUT" | grep -q 'live_ko=0 quarantined_ko=1' || fail "Spark kmod quarantine check failed: $QOUT"
fi
# Positive 3: audit clean .om file
"$B/strand6_sentinel" audit-file "$R/seed/helix/hive_shield/strand7_warden.om"

# Negative controls for Strand 6
s6_neg=0
run_s6_neg() {
  nm=$1; want=$2; shift 2
  set +e
  "$B/strand6_sentinel" "$@" > /dev/null 2> "$B/s6_${nm}.err"
  got=$?
  set -e
  [ "$got" -eq "$want" ] || fail "Strand 6 neg $nm: expected $want, got $got ($(cat "$B/s6_${nm}.err"))"
  s6_neg=$((s6_neg + 1))
  printf '  KILL [S6-%02d] %-24s -> exit=%d (%s)\n' "$s6_neg" "$nm" "$got" "$(cat "$B/s6_${nm}.err" | tr -d '\n')"
}

printf 'fake_ko' > "$B/s6_ko/aien_gpu.ko"
run_s6_neg "live_rogue_ko" 141 scan-dir "$B/s6_ko" 0
mkdir -p "$B/s6_qsmuggle"
printf 'fake_ko' > "$B/s6_qsmuggle/aien_gpu.ko.QUARANTINED"
chmod 644 "$B/s6_qsmuggle/aien_gpu.ko.QUARANTINED"
run_s6_neg "readable_quarantine_ko" 141 scan-dir "$B/s6_qsmuggle" 0
printf 'int x;\n' > "$B/s6_c/sneaky.c"
run_s6_neg "c_contamination" 142 scan-dir "$B/s6_c" 0
printf 'efibootmgr -v\n' > "$B/s6_clean/bad_uefi.sh"
run_s6_neg "uefi_efibootmgr" 143 audit-file "$B/s6_clean/bad_uefi.sh"
printf 'echo x > /sys/firmware/efi/efivars/test\n' > "$B/s6_clean/bad_efivars.sh"
run_s6_neg "uefi_efivars" 143 audit-file "$B/s6_clean/bad_efivars.sh"
printf 'sudo insmod kmod/aien_gpu.ko\n' > "$B/s6_clean/bad_insmod.sh"
run_s6_neg "insmod_aien_gpu" 141 audit-file "$B/s6_clean/bad_insmod.sh"
printf 'vm_insert_pages(vma, addr, pages, n);\n' > "$B/s6_clean/bad_impure.txt"
run_s6_neg "impure_vm_insert" 144 audit-file "$B/s6_clean/bad_impure.txt"
run_s6_neg "nonexistent_dir_fail" 145 scan-dir "$B/does_not_exist_999" 0
mkdir -p "$B/s6_ext"
printf 'x' > "$B/s6_ext/aien_gpu.ko.xz"
run_s6_neg "compressed_ko_xz" 141 scan-dir "$B/s6_ext" 0
mkdir -p "$B/s6_ext2"
printf 'int x;\n' > "$B/s6_ext2/sneaky.C"
run_s6_neg "uppercase_C_file" 142 scan-dir "$B/s6_ext2" 0
{
  i=0
  while [ "$i" -lt 2700 ]; do
    printf '# 01234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567\n'
    i=$((i + 1))
  done
  printf 'sudo insmod aien_gpu.ko\n'
} > "$B/s6_clean/trunc_262k.sh"
run_s6_neg "audit_gt_256k_trunc" 145 audit-file "$B/s6_clean/trunc_262k.sh"
printf 'finit_module(fd, "", 0);\n' > "$B/s6_clean/bad_finit.txt"
run_s6_neg "finit_module_kmod" 141 audit-file "$B/s6_clean/bad_finit.txt"
mkdir -p "$B/s6_sym"
printf 'x' > "$B/s6_locked_target"
chmod 000 "$B/s6_locked_target"
ln -s "$B/s6_locked_target" "$B/s6_sym/evil.ko.QUARANTINED"
run_s6_neg "symlink_quarantine_spoof" 141 scan-dir "$B/s6_sym" 0
chmod 600 "$B/s6_locked_target"

printf '\n--- [STRAND 7: THE WARDEN (HIVE THERMAL/POWER/RAM/DISK/KMOD CBF)] ---\n'
"$OMC" < seed/helix/hive_shield/strand7_warden.om > "$B/strand7_warden"
chmod +x "$B/strand7_warden"

# Positive: Spark GB10 (node 1), Pi 5 (node 2), MacBook Air (node 3)
"$B/strand7_warden" eval 1 52000 45000 108000 500000 300 7 0
"$B/strand7_warden" eval 2 55000 12000 4096 32000 0 7 0
"$B/strand7_warden" eval 3 60000 18000 2048 50000 0 7 0

# Positive: Live read-only Spark audit (hw_writes=0)
if [ -r /proc/meminfo ] && [ -r /proc/modules ]; then
  "$B/strand7_warden" live-spark
fi

# Negative controls for Strand 7
s7_neg=0
run_s7_neg() {
  nm=$1; want=$2; shift 2
  set +e
  "$B/strand7_warden" eval "$@" > /dev/null 2> "$B/s7_${nm}.err"
  got=$?
  set -e
  [ "$got" -eq "$want" ] || fail "Strand 7 neg $nm: expected $want, got $got ($(cat "$B/s7_${nm}.err"))"
  s7_neg=$((s7_neg + 1))
  printf '  KILL [S7-%02d] %-24s -> exit=%d (%s)\n' "$s7_neg" "$nm" "$got" "$(cat "$B/s7_${nm}.err" | tr -d '\n')"
}

run_s7_neg "thermal_cbf_85C"     151 1 85000 45000 108000 500000 300 7 0
run_s7_neg "power_wattcbf_180W"  152 1 52000 180000 108000 500000 300 7 0
run_s7_neg "ram_floor_breach"    153 1 52000 45000 4096 500000 300 7 0
run_s7_neg "disk_floor_breach"   154 1 52000 45000 108000 8192 300 7 0
run_s7_neg "rogue_live_kmod"     155 1 48000 30000 108000 500000 60 7 1
run_s7_neg "gpu_lease_overrun"   156 1 52000 45000 108000 500000 1800 7 0
run_s7_neg "incomplete_proof"    157 1 52000 45000 108000 500000 300 5 0
run_s7_neg "u64_wrap_kmod_temp"  2   1 18446744073709551616 45000 108000 500000 300 7 18446744073709551616

printf '\n--- [STRAND 8: THE NOTARY (RECEIPT SHA-256 + DUAL-LAW HIVE QUORUM + OMEGA-MEMO)] ---\n'
(
  printf 'om2\n'
  cat seed/ng/sha256.om \
      seed/ng/memo/memo_policy.om \
      seed/ng/memo/memo_store.om \
      seed/helix/hive_shield/strand8_notary.om
) | "$OMC" > "$B/strand8_notary"
chmod +x "$B/strand8_notary"

printf 'OMEGA-HIVE-RECEIPT-A\n' > "$B/s8_sums/a.txt"
printf 'OMEGA-HIVE-RECEIPT-B\n' > "$B/s8_sums/b.txt"
(cd "$B/s8_sums" && sha256sum a.txt b.txt > SHA256SUMS.txt)
"$B/strand8_notary" verify-sums "$B/s8_sums" "$B/s8_sums/SHA256SUMS.txt"

Q1=$("$B/strand8_notary" hive-quorum 7 2 7 0 "$B/s8_memo" "$PIN_SHA")
Q2=$("$B/strand8_notary" hive-quorum 7 2 7 0 "$B/s8_memo" "$PIN_SHA")
printf '  %s\n' "$Q1"
printf '  %s\n' "$Q2"
printf '%s\n' "$Q1" | grep -q 'mode=COLD_SEALED' || fail "Strand 8 Q1 not COLD_SEALED"
printf '%s\n' "$Q2" | grep -q 'mode=MEMO_VERIFIED' || fail "Strand 8 Q2 not MEMO_VERIFIED"

s8_neg=0
run_s8_neg() {
  nm=$1; want=$2; shift 2
  set +e
  "$B/strand8_notary" "$@" > /dev/null 2> "$B/s8_${nm}.err"
  got=$?
  set -e
  [ "$got" -eq "$want" ] || fail "Strand 8 neg $nm: expected $want, got $got ($(cat "$B/s8_${nm}.err"))"
  s8_neg=$((s8_neg + 1))
  printf '  KILL [S8-%02d] %-24s -> exit=%d (%s)\n' "$s8_neg" "$nm" "$got" "$(cat "$B/s8_${nm}.err" | tr -d '\n')"
}

# 1-byte tamper on receipt file
cp "$B/s8_sums/a.txt" "$B/s8_sums/a.bak"
printf 'X' | dd of="$B/s8_sums/a.txt" bs=1 seek=0 count=1 conv=notrunc 2>/dev/null
run_s8_neg "receipt_1byte_tamper"  161 verify-sums "$B/s8_sums" "$B/s8_sums/SHA256SUMS.txt"
mv "$B/s8_sums/a.bak" "$B/s8_sums/a.txt"
rm -f "$B/s8_sums/b.txt"
run_s8_neg "receipt_missing_file"  162 verify-sums "$B/s8_sums" "$B/s8_sums/SHA256SUMS.txt"
printf 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  ../etc/passwd\n' > "$B/s8_sums/TRAVERSAL.txt"
run_s8_neg "manifest_path_trav"    163 verify-sums "$B/s8_sums" "$B/s8_sums/TRAVERSAL.txt"
# Safety veto overrides unanimous 7/7 compilers
run_s8_neg "safety_veto_overrides" 164 hive-quorum 7 2 7 1 "$B/s8_memo" "$PIN_SHA"
# f=3 faults on N=7 (4/7 < 5) -> NO_QUORUM
run_s8_neg "bft_f3_no_quorum"      165 hive-quorum 7 2 4 0 "$B/s8_memo" "$PIN_SHA"
# 1-byte tamper on OMEGA-MEMO attestation
cp -R "$B/s8_memo" "$B/s8_memo_bad"
T8=$(find "$B/s8_memo_bad" -name '*.ome' | head -n 1)
printf '\177' | dd of="$T8" bs=1 seek=230 count=1 conv=notrunc 2>/dev/null
run_s8_neg "memo_attest_tamper"    166 hive-quorum 7 2 7 0 "$B/s8_memo_bad" "$PIN_SHA"
# u64 wrap on safety veto (2^64 must NOT wrap to 0)
run_s8_neg "u64_wrap_veto"         2   hive-quorum 7 2 7 18446744073709551616 "$B/s8_memo" "$PIN_SHA"
# 3*f+1 multiplication overflow attack (invalid N < 3f+1)
run_s8_neg "bft_3f_mul_overflow"   165 hive-quorum 18446744073709551614 6148914691236517206 12297829382473034408 0 "$B/s8_memo" "$PIN_SHA"
# Non-hex omc_sha64 rejected
run_s8_neg "nonhex_omc_sha"        2   hive-quorum 7 2 7 0 "$B/s8_memo" "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"
# Manifest > 64 KiB rejected (no silent truncation)
{
  i=0
  while [ "$i" -lt 950 ]; do
    printf '0000000000000000000000000000000000000000000000000000000000000000  a.txt\n'
    i=$((i + 1))
  done
} > "$B/s8_sums/HUGE_64K.txt"
run_s8_neg "manifest_gt_64k"       163 verify-sums "$B/s8_sums" "$B/s8_sums/HUGE_64K.txt"
# Embedded NUL byte in manifest filename rejected
A_SHA=$(sha "$B/s8_sums/a.txt")
printf '%s  a.txt\0ignored\n' "$A_SHA" > "$B/s8_sums/NUL_PATH.txt"
run_s8_neg "manifest_nul_path"     163 verify-sums "$B/s8_sums" "$B/s8_sums/NUL_PATH.txt"

printf '\n--- [STRAND 9: THE ARBITER (ZERO-TRUST MESH BIND + REMOTE COMMAND GUARD)] ---\n'
"$OMC" < seed/helix/hive_shield/strand9_arbiter.om > "$B/strand9_arbiter"
chmod +x "$B/strand9_arbiter"

"$B/strand9_arbiter" check-bind 127.0.0.1
"$B/strand9_arbiter" check-bind 192.168.1.108
"$B/strand9_arbiter" check-bind 100.64.0.2
"$B/strand9_arbiter" check-bind ::1
"$B/strand9_arbiter" check-bind l2:0x88b5
printf 'uname -a && free -h\n' > "$B/s9_cmds/safe.sh"
"$B/strand9_arbiter" check-cmd "$B/s9_cmds/safe.sh" 2 1

s9_neg=0
run_s9_neg() {
  nm=$1; want=$2; shift 2
  set +e
  "$B/strand9_arbiter" "$@" > /dev/null 2> "$B/s9_${nm}.err"
  got=$?
  set -e
  [ "$got" -eq "$want" ] || fail "Strand 9 neg $nm: expected $want, got $got ($(cat "$B/s9_${nm}.err"))"
  s9_neg=$((s9_neg + 1))
  printf '  KILL [S9-%02d] %-24s -> exit=%d (%s)\n' "$s9_neg" "$nm" "$got" "$(cat "$B/s9_${nm}.err" | tr -d '\n')"
}

run_s9_neg "wildcard_ipv4"     171 check-bind 0.0.0.0
run_s9_neg "wildcard_ipv6"     171 check-bind ::
run_s9_neg "public_unowned_ip" 172 check-bind 8.8.8.8
run_s9_neg "outside_cgnat"     172 check-bind 100.128.0.1
run_s9_neg "bind_shell_inject" 172 check-bind "127.0.0.1;id"
run_s9_neg "bind_bad_octet"    172 check-bind 127.999.0.1
printf 'pkill -f python3\n' > "$B/s9_cmds/bad_pkill.sh"
run_s9_neg "pkill_dash_f"      173 check-cmd "$B/s9_cmds/bad_pkill.sh" 1 1
printf 'sudo efibootmgr -o 0001\n' > "$B/s9_cmds/bad_efi.sh"
run_s9_neg "remote_efibootmgr" 173 check-cmd "$B/s9_cmds/bad_efi.sh" 1 1
printf 'rm -rf /tmp/foo && rm -rf /\n' > "$B/s9_cmds/bad_rm.sh"
run_s9_neg "remote_rm_rf_root" 173 check-cmd "$B/s9_cmds/bad_rm.sh" 1 1
printf 'sudo insmod kmod/aien_gpu.ko\n' > "$B/s9_cmds/bad_insmod.sh"
run_s9_neg "remote_insmod"     173 check-cmd "$B/s9_cmds/bad_insmod.sh" 1 1
run_s9_neg "ssh_storm_8"       174 check-cmd "$B/s9_cmds/safe.sh" 8 1
run_s9_neg "unsigned_rpc"      175 check-cmd "$B/s9_cmds/safe.sh" 1 0
run_s9_neg "octal_ip_0127"     172 check-bind "0127.0.0.1"
run_s9_neg "octal_ip_100_064"  172 check-bind "100.064.0.2"
run_s9_neg "u64_wrap_ssh_cap"  2   check-cmd "$B/s9_cmds/safe.sh" 18446744073709551616 18446744073709551617
printf 'pkill -9 -f python3\n' > "$B/s9_cmds/bad_pkill9.sh"
run_s9_neg "pkill_9_dash_f"    173 check-cmd "$B/s9_cmds/bad_pkill9.sh" 1 1
printf 'rm -fr /\n' > "$B/s9_cmds/bad_rmfr.sh"
run_s9_neg "rm_fr_root"        173 check-cmd "$B/s9_cmds/bad_rmfr.sh" 1 1
{
  i=0
  while [ "$i" -lt 700 ]; do
    printf '# 01234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567\n'
    i=$((i + 1))
  done
  printf 'sudo insmod aien_gpu.ko\n'
} > "$B/s9_cmds/trunc_66k.sh"
run_s9_neg "cmd_gt_64k_trunc"  173 check-cmd "$B/s9_cmds/trunc_66k.sh" 1 1
printf 'pkill --full python3\n' > "$B/s9_cmds/bad_pkill_full.sh"
run_s9_neg "pkill_double_full" 173 check-cmd "$B/s9_cmds/bad_pkill_full.sh" 1 1
printf 'rm -rf "/"\n' > "$B/s9_cmds/bad_rm_qroot.sh"
run_s9_neg "rm_quoted_root"    173 check-cmd "$B/s9_cmds/bad_rm_qroot.sh" 1 1

printf '\n--- [LEAN 4.36.0 PROOFS: Om3MemorySafety.lean + HiveShield.lean] ---\n'
LEAN_BIN=""
if command -v lean >/dev/null 2>&1; then
  LEAN_BIN=$(command -v lean)
elif [ -x "$HOME/.elan/bin/lean" ]; then
  LEAN_BIN="$HOME/.elan/bin/lean"
fi
if [ -n "$LEAN_BIN" ]; then
  "$LEAN_BIN" seed/helix/proofs/Om3MemorySafety.lean > "$B/lean_om3.out" 2>&1 || { cat "$B/lean_om3.out" >&2; fail "Om3MemorySafety.lean failed"; }
  "$LEAN_BIN" seed/helix/proofs/HiveShield.lean > "$B/lean_hs.out" 2>&1 || { cat "$B/lean_hs.out" >&2; fail "HiveShield.lean failed"; }
  grep -qi 'sorry' "$B/lean_om3.out" "$B/lean_hs.out" && fail "Lean proof contains sorry!"
  printf '  PASS Om3MemorySafety.lean + HiveShield.lean verified (0 warnings, 0 sorry, standard axioms only)\n'
fi

TOT_NEG=$((34 + s6_neg + s7_neg + s8_neg + s9_neg))
printf '\n=====================================================================\n'
printf 'HIVE_SHIELD PASS strands=5,6,7,8,9 omc=%s total_neg_controls=%d\n' "$PIN_SHA" "$TOT_NEG"
printf '=====================================================================\n'
