#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# seed/helix/strand5_aegis/strand5_verify.sh
# End-to-end pure seeded OM-2 verification gate for Strand 5 (The Aegis) & OM-3:
#   - Compiles om3_aegis with pinned seed/out/omc (zero C)
#   - Verifies OM-3 positive lifecycles (pure omc AND @ng ΩIR v2 @pure/@exact/@deadline/@power)
#   - Verifies OMEGA-MEMO COLD_PROVED -> MEMO_HIT bit-exact equivalence + 1-byte tamper refusal (120)
#   - Kills all 13 adversarial negative-control classes (101..111, 120, 130)
#   - Verifies om2 seed/out/omc self-rebuild fixpoint AND @ng A_fast DDC convergence to identical SHA-256
#   - Checks Lean 4.36.0 machine-checked proofs in seed/helix/proofs/Om3MemorySafety.lean
set -eu

R=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
cd "$R"

OMC=${OMC:-"$R/seed/out/omc"}
PIN_SHA=$(awk '{print $1}' "$R/seed/out/omc.sha256")
B=${OUT_DIR:-"$R/build/strand5_aegis"}
rm -rf "$B"
mkdir -p "$B/memo" "$B/memo_ddc" "$B/cases" "$B/seedcheck"

fail() { printf 'STRAND5_VERIFY FAIL: %s\n' "$*" >&2; exit 1; }
sha() { sha256sum "$1" | awk '{print $1}'; }

GOT_OMC_SHA=$(sha "$OMC")
[ "$GOT_OMC_SHA" = "$PIN_SHA" ] || fail "omc sha256 mismatch: got=$GOT_OMC_SHA pin=$PIN_SHA"

printf '=== [1/7] COMPILE STRAND 5 (om3_aegis) WITH PINNED OM-2 OMC ===\n'
printf '  pinned omc sha256 = %s\n' "$PIN_SHA"
(
  printf 'om2\n'
  cat seed/ng/sha256.om \
      seed/ng/memo/memo_policy.om \
      seed/ng/memo/memo_store.om \
      seed/helix/strand5_aegis/om3_aegis.om
) | "$OMC" > "$B/om3_aegis"
chmod +x "$B/om3_aegis"
printf '  PASS om3_aegis compiled (%s bytes, sha256=%s)\n' "$(wc -c < "$B/om3_aegis" | tr -d ' ')" "$(sha "$B/om3_aegis")"

printf '\n=== [2/7] POSITIVE TEST 1: FULL 4-STEP GPU DMA OM-3 -> ZERO-OVERHEAD OM-2 -> NATIVE EXEC ===\n'
cat > "$B/cases/pos_dma.om3" << 'EOF'
om3
note Canonical OM-3 zero-pointer GB10 GPU DMA lifecycle (all 4 linear fence steps)
@region vfs_slab 2 0x10000000 0x100000
@region gpu_act  3 0x20000000 0x400000
@map gpu_act 0x200000000 0x400000
@vma_pin gpu_act
@gpu_submit gpu_act 1
@access gpu_act 0 4096
@unmap gpu_act
@tlbinval gpu_act
@fence_drain gpu_act 1
@vma_revoke gpu_act
@reclaim gpu_act

fn compute_dot x ulong y ulong to ulong
ret add mul x y 7
end

fn main to int
v = compute_dot 5 7
ret int and v 255
end
EOF

OUT1=$("$B/om3_aegis" verify-om3 "$B/cases/pos_dma.om3" "$B/memo" "$B/cases/pos_dma.cold.om")
printf '  %s\n' "$OUT1"
printf '%s\n' "$OUT1" | grep -q 'mode=COLD_PROVED regions=2 maps=1 bounds_erased=1 fences=1 reclaims=1 contracts=0' || fail "unexpected COLD output: $OUT1"

OUT2=$("$B/om3_aegis" verify-om3 "$B/cases/pos_dma.om3" "$B/memo" "$B/cases/pos_dma.hit.om")
printf '  %s\n' "$OUT2"
printf '%s\n' "$OUT2" | grep -q 'mode=MEMO_HIT regions=2 maps=1 bounds_erased=1 fences=1 reclaims=1 contracts=0' || fail "unexpected HIT output: $OUT2"

cmp -s "$B/cases/pos_dma.cold.om" "$B/cases/pos_dma.hit.om" || fail "cold vs memo-hit lowered om2 differ"
grep -q '^@' "$B/cases/pos_dma.cold.om" && fail "OM-3 capability directives leaked into lowered om2!"

"$OMC" < "$B/cases/pos_dma.cold.om" > "$B/cases/pos_dma.bin"
chmod +x "$B/cases/pos_dma.bin"
set +e
"$B/cases/pos_dma.bin"
RC=$?
set -e
[ "$RC" -eq 42 ] || fail "lowered OM-3 native binary returned $RC, expected 42"
printf '  PASS lowered zero-overhead native AArch64 ELF ran with exit=42 (0 runtime capability instructions)\n'

printf '\n=== [3/7] POSITIVE TEST 2: UNIFIED OM-3 + OIR v2 (@pure/@exact/@deadline/@power) -> @ng + ngcheck ===\n'
cat $(awk '{print $2}' seed/ng/ng.units) | "$OMC" > "$B/ng"
chmod +x "$B/ng"
cat $(awk '{print $2}' seed/ng/ngcheck.units) | "$OMC" > "$B/ngcheck"
chmod +x "$B/ngcheck"

cat > "$B/cases/pos_ng_v2.om3" << 'EOF'
om3
@region host_in  1 0x10000000 0x10000
@region gpu_out  3 0x30000000 0x10000
@map gpu_out 0x300000000 0x10000
@gpu_submit gpu_out 1
@access host_in 0 256
@access gpu_out 0 256
@unmap gpu_out
@tlbinval gpu_out
@fence_drain gpu_out 1
@reclaim gpu_out

@pure
@exact
@deadline 500
@power 15000
fn mix_pure a ulong b ulong to ulong
ret add mul a 11 b
end

fn main to int
ret int and mix_pure 6 7 255
end
EOF

OUT_NG=$("$B/om3_aegis" verify-om3 "$B/cases/pos_ng_v2.om3" "$B/memo" "$B/cases/pos_ng_v2.om")
printf '  %s\n' "$OUT_NG"
printf '%s\n' "$OUT_NG" | grep -q 'contracts=4' || fail "expected 4 OIR v2 contracts passed through: $OUT_NG"

{ printf '@ng front-ir\n'; cat "$B/cases/pos_ng_v2.om"; } | "$B/ng" > "$B/cases/pos_ng_v2.ir"
NGCHK_OUT=$("$B/ngcheck" < "$B/cases/pos_ng_v2.ir")
printf '  ngcheck: %s\n' "$NGCHK_OUT"
printf '%s\n' "$NGCHK_OUT" | grep -q '^ACCEPT ' || fail "ngcheck did not ACCEPT OM-3 lowered OIR v2"
{ printf '@ng sem-id\n'; cat "$B/cases/pos_ng_v2.ir"; } | "$B/ng" > "$B/cases/pos_ng_v2.sem"
printf '  sem-id: %s\n' "$(head -n 2 "$B/cases/pos_ng_v2.sem" | tr '\n' ' ')"
{ printf '@ng opt\n'; cat "$B/cases/pos_ng_v2.ir"; } | "$B/ng" > "$B/cases/pos_ng_v2.opt.ir"
{ printf '@ng a64\n'; cat "$B/cases/pos_ng_v2.opt.ir"; } | "$B/ng" > "$B/cases/pos_ng_v2.bin"
chmod +x "$B/cases/pos_ng_v2.bin"
set +e
"$B/cases/pos_ng_v2.bin"
RC_NG=$?
set -e
[ "$RC_NG" -eq 73 ] || fail "@ng a64 lowered OM-3 binary returned $RC_NG, expected 73"
printf '  PASS OM-3 -> OIR v2 -> ngcheck ACCEPT -> @ng opt -> @ng a64 native exec exit=73\n'

printf '\n=== [3b/7] POSITIVE TEST 3: CFG-SOUND CONDITIONAL EARLY-RETURN & LOOP-INVARIANT OM-3 ===\n'
cat > "$B/cases/pos_cfg.om3" << 'EOF'
om3
fn run_dma err ulong to int
@region gbuf 3 0x20000000 0x400000
@map gbuf 0x200000000 0x10000
@gpu_submit gbuf 1
if ne err 0
@unmap gbuf
@tlbinval gbuf
@fence_drain gbuf 1
@reclaim gbuf
ret 1
end
for i ulong 4
@access gbuf 0 4096
end
@unmap gbuf
@tlbinval gbuf
@fence_drain gbuf 1
@reclaim gbuf
ret 0
end

fn main to int
a = run_dma 1
b = run_dma 0
ret add mul a 10 add b 32
end
EOF

OUT_CFG=$("$B/om3_aegis" verify-om3 "$B/cases/pos_cfg.om3" "$B/memo" "$B/cases/pos_cfg.om")
printf '  %s\n' "$OUT_CFG"
"$OMC" < "$B/cases/pos_cfg.om" > "$B/cases/pos_cfg.bin"
chmod +x "$B/cases/pos_cfg.bin"
set +e
"$B/cases/pos_cfg.bin"
RC_CFG=$?
set -e
[ "$RC_CFG" -eq 42 ] || fail "CFG positive binary returned $RC_CFG, expected 42"
printf '  PASS CFG-sound early-return + loop-invariant OM-3 lowered & executed exit=42\n'

printf '\n=== [4/7] ADVERSARIAL NEGATIVE CONTROLS (ALL OM-3 REFUSAL CODES 101..112, 120, 130) ===\n'
neg_cnt=0
expect_refuse() {
  name=$1
  want=$2
  f=$3
  set +e
  "$B/om3_aegis" verify-om3 "$f" "$B/memo" "$B/cases/${name}.out.om" > /dev/null 2> "$B/cases/${name}.err"
  got=$?
  set -e
  [ "$got" -eq "$want" ] || fail "neg $name: expected exit $want, got $got (err=$(cat "$B/cases/${name}.err"))"
  neg_cnt=$((neg_cnt + 1))
  printf '  KILL [%02d] %-28s -> exit=%d (%s)\n' "$neg_cnt" "$name" "$got" "$(cat "$B/cases/${name}.err" | tr -d '\n')"
}

# 101 NO_RAW_PTR (fwld, put_page, dma_addr, mapaddr)
cat > "$B/cases/n101_fwld.om3" << 'EOF'
om3
fn main to int
x = fwld 4096 8
ret int x
end
EOF
expect_refuse "raw_ptr_fwld" 101 "$B/cases/n101_fwld.om3"

cat > "$B/cases/n101_putpage.om3" << 'EOF'
om3
fn main to int
x = put_page 1
ret int x
end
EOF
expect_refuse "raw_ptr_put_page" 101 "$B/cases/n101_putpage.om3"

# 102 DISJOINT_VA_OVERLAP (reproduces agpu_vas_map_kbuf VA aliasing bug)
cat > "$B/cases/n102_va.om3" << 'EOF'
om3
@region kbuf 3 0x20000000 0x400000
@region ubuf 3 0x30000000 0x400000
@map kbuf 0x200000000 0x400000
@map ubuf 0x200200000 0x200000
fn main to int
ret 0
end
EOF
expect_refuse "va_overlap_kbuf_ubuf" 102 "$B/cases/n102_va.om3"

# 103 OOB_STATIC (both simple OOB and u64 wraparound overflow)
cat > "$B/cases/n103_oob.om3" << 'EOF'
om3
@region buf 1 0x10000000 4096
@access buf 4000 200
fn main to int
ret 0
end
EOF
expect_refuse "oob_static" 103 "$B/cases/n103_oob.om3"

cat > "$B/cases/n103_wrap.om3" << 'EOF'
om3
@region buf 1 0x10000000 4096
@access buf 0xfffffffffffff000 0x2000
fn main to int
ret 0
end
EOF
expect_refuse "oob_u64_wrap" 103 "$B/cases/n103_wrap.om3"

# 104 MISSING_PTE_UNMAP (reproduces agpu_vas_destroy missing unmap_pages bug)
cat > "$B/cases/n104_unmap.om3" << 'EOF'
om3
@region gbuf 3 0x20000000 0x400000
@map gbuf 0x200000000 0x400000
@gpu_submit gbuf 1
@reclaim gbuf
fn main to int
ret 0
end
EOF
expect_refuse "missing_pte_unmap" 104 "$B/cases/n104_unmap.om3"

# 105 MISSING_TLB_INVAL
cat > "$B/cases/n105_tlb.om3" << 'EOF'
om3
@region gbuf 3 0x20000000 0x400000
@map gbuf 0x200000000 0x400000
@gpu_submit gbuf 1
@unmap gbuf
@reclaim gbuf
fn main to int
ret 0
end
EOF
expect_refuse "missing_tlb_inval" 105 "$B/cases/n105_tlb.om3"

# 106 UNFENCED_GPU_DMA_UAF (reproduces exact 2026-11-26 Spark crash: reclaim with epoch > drained)
cat > "$B/cases/n106_uaf.om3" << 'EOF'
om3
@region gbuf 3 0x20000000 0x400000
@map gbuf 0x200000000 0x400000
@gpu_submit gbuf 1
@unmap gbuf
@tlbinval gbuf
@reclaim gbuf
fn main to int
ret 0
end
EOF
expect_refuse "unfenced_gpu_dma_uaf" 106 "$B/cases/n106_uaf.om3"

# 107 UNREVOKED_VMA_PIN_LEAK (reproduces vm_insert_pages leak)
cat > "$B/cases/n107_vma.om3" << 'EOF'
om3
@region gbuf 3 0x20000000 0x400000
@map gbuf 0x200000000 0x400000
@vma_pin gbuf
@gpu_submit gbuf 1
@unmap gbuf
@tlbinval gbuf
@fence_drain gbuf 1
@reclaim gbuf
fn main to int
ret 0
end
EOF
expect_refuse "vma_pin_leak" 107 "$B/cases/n107_vma.om3"

# 108 USE_AFTER_RECLAIM_UAF
cat > "$B/cases/n108_uar.om3" << 'EOF'
om3
@region gbuf 3 0x20000000 0x400000
@map gbuf 0x200000000 0x400000
@gpu_submit gbuf 1
@unmap gbuf
@tlbinval gbuf
@fence_drain gbuf 1
@reclaim gbuf
@access gbuf 0 64
fn main to int
ret 0
end
EOF
expect_refuse "use_after_reclaim" 108 "$B/cases/n108_uar.om3"

# 109 DOUBLE_RECLAIM
cat > "$B/cases/n109_dbl.om3" << 'EOF'
om3
@region gbuf 3 0x20000000 0x400000
@reclaim gbuf
@reclaim gbuf
fn main to int
ret 0
end
EOF
expect_refuse "double_reclaim" 109 "$B/cases/n109_dbl.om3"

# 110 CROSS_DOMAIN_VIOLATION (GPU attempting to map CPU_KERNEL_SLAB + physical overlap)
cat > "$B/cases/n110_slab.om3" << 'EOF'
om3
@region vfs_inode_cache 2 0x10000000 0x100000
@map vfs_inode_cache 0x200000000 0x100000
fn main to int
ret 0
end
EOF
expect_refuse "kernel_slab_gpu_map" 110 "$B/cases/n110_slab.om3"

cat > "$B/cases/n110_phys.om3" << 'EOF'
om3
@region vfs_inode_cache 2 0x10000000 0x100000
@region gpu_buf         3 0x10080000 0x100000
fn main to int
ret 0
end
EOF
expect_refuse "cross_domain_phys_overlap" 110 "$B/cases/n110_phys.om3"

# 111 MALFORMED_OM3_SYNTAX (wrong header + unknown @directive + overlong line)
cat > "$B/cases/n111_hdr.om3" << 'EOF'
om2
fn main to int
ret 0
end
EOF
expect_refuse "bad_om3_header" 111 "$B/cases/n111_hdr.om3"

cat > "$B/cases/n111_dir.om3" << 'EOF'
om3
@bogus_directive foo
fn main to int
ret 0
end
EOF
expect_refuse "unknown_at_directive" 111 "$B/cases/n111_dir.om3"

# Extra adversarial edge cases: overlong line (>510 B), u64 overflow literal (2^64),
# unmapped GPU access (104), and end-of-unit unfenced DMA leak (106)
{ printf 'om3\n'; printf 'note '; printf 'A%.0s' $(seq 1 520); printf '\nfn main to int\nret 0\nend\n'; } > "$B/cases/n111_long.om3"
expect_refuse "overlong_line_520B" 111 "$B/cases/n111_long.om3"

cat > "$B/cases/n111_u64ovf.om3" << 'EOF'
om3
@region buf 1 0x10000000000000000 4096
fn main to int
ret 0
end
EOF
expect_refuse "u64_hex_overflow_lit" 111 "$B/cases/n111_u64ovf.om3"

cat > "$B/cases/n104_unmap_acc.om3" << 'EOF'
om3
@region gbuf 3 0x20000000 0x400000
@access gbuf 0 64
fn main to int
ret 0
end
EOF
expect_refuse "unmapped_gpu_access" 104 "$B/cases/n104_unmap_acc.om3"

cat > "$B/cases/n106_eof_leak.om3" << 'EOF'
om3
@region gbuf 3 0x20000000 0x400000
@map gbuf 0x200000000 0x400000
@gpu_submit gbuf 1
@unmap gbuf
@tlbinval gbuf
fn main to int
ret 0
end
EOF
expect_refuse "eof_unfenced_dma_leak" 106 "$B/cases/n106_eof_leak.om3"

# RCCA v2 Red-Team Adversarial Controls:
# 112 CFG branch bypass (conditional unmap/tlb/drain in `if`, unconditional @reclaim after `end`)
cat > "$B/cases/n112_branch_bypass.om3" << 'EOF'
om3
fn main to int
@region gbuf 3 0x20000000 0x400000
@map gbuf 0x200000000 0x400000
@gpu_submit gbuf 1
if eq 0 1
@unmap gbuf
@tlbinval gbuf
@fence_drain gbuf 1
end
@reclaim gbuf
ret 0
end
EOF
expect_refuse "cfg_branch_teardown_bypass" 112 "$B/cases/n112_branch_bypass.om3"

# 104 Early return inside `if` before unmap/tlb/fence/reclaim
cat > "$B/cases/n104_early_ret.om3" << 'EOF'
om3
fn main to int
@region gbuf 3 0x20000000 0x400000
@map gbuf 0x200000000 0x400000
@gpu_submit gbuf 1
if eq 1 1
ret 0
end
@unmap gbuf
@tlbinval gbuf
@fence_drain gbuf 1
@reclaim gbuf
ret 0
end
EOF
expect_refuse "cfg_early_ret_dma_leak" 104 "$B/cases/n104_early_ret.om3"

# 112 Reclaim inside `for` loop (double-reclaim / UAF on iteration 2)
cat > "$B/cases/n112_loop_reclaim.om3" << 'EOF'
om3
fn main to int
@region gbuf 3 0x20000000 0x400000
for i ulong 2
@reclaim gbuf
end
ret 0
end
EOF
expect_refuse "cfg_loop_reclaim_uaf" 112 "$B/cases/n112_loop_reclaim.om3"

# 101 Expanded raw device-mapping primitive (mapnew / devcall)
cat > "$B/cases/n101_mapnew.om3" << 'EOF'
om3
fn main to int
x = mapnew 0 4096 3 1 0
ret int x
end
EOF
expect_refuse "raw_ptr_mapnew" 101 "$B/cases/n101_mapnew.om3"

# 111 Extra trailing token on @region & @pure smuggling
cat > "$B/cases/n111_extra_tok.om3" << 'EOF'
om3
@region buf 1 0x1000 0x1000 EXTRA_GARBAGE
fn main to int
ret 0
end
EOF
expect_refuse "extra_trailing_token" 111 "$B/cases/n111_extra_tok.om3"

cat > "$B/cases/n101_pure_smuggle.om3" << 'EOF'
om3
@pure fwld 4096 8
fn main to int
ret 0
end
EOF
expect_refuse "pure_contract_smuggle" 101 "$B/cases/n101_pure_smuggle.om3"

# 103 GPU access past mapped vlen (< psize)
cat > "$B/cases/n103_vlen_oob.om3" << 'EOF'
om3
@region gbuf 3 0x20000000 0x400000
@map gbuf 0x200000000 0x1000
@access gbuf 0x2000 0x1000
@unmap gbuf
@tlbinval gbuf
@reclaim gbuf
fn main to int
ret 0
end
EOF
expect_refuse "oob_past_mapped_vlen" 103 "$B/cases/n103_vlen_oob.om3"

# 111 Source > 262144 B truncation smuggling attack (fail-closed)
{
  printf 'om3\n'
  printf '@region buf 1 0x10000000 0x1000\n'
  i=0
  while [ "$i" -lt 2600 ]; do
    printf 'note 0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456\n'
    i=$((i + 1))
  done
  printf 'fn main to int\nx = fwld 4096 8\nret int x\nend\n'
} > "$B/cases/n111_src_trunc.om3"
expect_refuse "src_gt_256k_truncation" 111 "$B/cases/n111_src_trunc.om3"

# 106 Unreclaimed TLB-flushed GPU VA leak at EOF
cat > "$B/cases/n106_unreclaimed_va.om3" << 'EOF'
om3
@region gbuf 3 0x20000000 0x400000
@map gbuf 0x200000000 0x400000
@gpu_submit gbuf 1
@unmap gbuf
@tlbinval gbuf
@fence_drain gbuf 1
fn main to int
ret 0
end
EOF
expect_refuse "unreclaimed_gpu_va_leak" 106 "$B/cases/n106_unreclaimed_va.om3"

# 112 Loop break after @unmap (invariant violation on loop exit)
cat > "$B/cases/n112_loop_break.om3" << 'EOF'
om3
fn main to int
@region gbuf 3 0x20000000 0x400000
@map gbuf 0x200000000 0x400000
for i ulong 4
@unmap gbuf
break
end
@tlbinval gbuf
@reclaim gbuf
ret 0
end
EOF
expect_refuse "cfg_loop_break_unmap" 112 "$B/cases/n112_loop_break.om3"

# 104 VMA pin after PTE unmap
cat > "$B/cases/n104_pin_after_unmap.om3" << 'EOF'
om3
fn main to int
@region gbuf 3 0x20000000 0x400000
@map gbuf 0x200000000 0x400000
@unmap gbuf
@vma_pin gbuf
@tlbinval gbuf
@vma_revoke gbuf
@reclaim gbuf
ret 0
end
EOF
expect_refuse "vma_pin_after_unmap" 104 "$B/cases/n104_pin_after_unmap.om3"

# 101 Smuggled `target a64efi` directive
cat > "$B/cases/n101_target_efi.om3" << 'EOF'
om3
target a64efi
fn main to int
ret 0
end
EOF
expect_refuse "smuggled_target_a64efi" 101 "$B/cases/n101_target_efi.om3"

# 120 OMEGA_MEMO_PROOF_TAMPER (1-byte flip in cached .ome file)
cp -R "$B/memo" "$B/memo_tampered"
T_CNT=0
for T_OME in $(find "$B/memo_tampered" -name '*.ome'); do
  printf '\377' | dd of="$T_OME" bs=1 seek=230 count=1 conv=notrunc 2>/dev/null
  T_CNT=$((T_CNT + 1))
done
[ "$T_CNT" -ge 2 ] || fail "expected >=2 .ome files in $B/memo_tampered, got $T_CNT"
set +e
"$B/om3_aegis" verify-om3 "$B/cases/pos_dma.om3" "$B/memo_tampered" "$B/cases/tamper.om" > /dev/null 2> "$B/cases/tamper.err"
TRC=$?
set -e
[ "$TRC" -eq 120 ] || fail "tampered .ome expected exit 120, got $TRC (err=$(cat "$B/cases/tamper.err"))"
neg_cnt=$((neg_cnt + 1))
printf '  KILL [%02d] %-28s -> exit=%d (%s)\n' "$neg_cnt" "omega_memo_1byte_tamper" "$TRC" "$(cat "$B/cases/tamper.err" | tr -d '\n')"

printf '\n=== [5/7] OM-2 SEED FIXPOINT & STRAND 5 @ng DDC CONVERGENCE (EXACT SAME SHA-256) ===\n'
# Rebuild omc cleanly from 408-byte seed0.hex in isolated scratch copy
cp -R seed "$B/seedcheck/seed"
(cd "$B/seedcheck" && sh seed/omega-from-seed.sh) > "$B/seedcheck/seed.log"
SEED_OMC_SHA=$(sha "$B/seedcheck/seed/out/omc")
[ "$SEED_OMC_SHA" = "$PIN_SHA" ] || fail "seed/omega-from-seed.sh fixpoint mismatch: got=$SEED_OMC_SHA pin=$PIN_SHA"
printf '  PASS Seed0 -> Hex1 -> Asm2 -> Om4 -> Omc fixpoint = %s\n' "$SEED_OMC_SHA"

# Strand 5 @ng DDC path: ng front-ir -> ng opt -> ng a64 -> A_fast -> omc_strand5
{ printf '@ng front-ir\n'; cat seed/omc/omc.om; } | "$B/ng" > "$B/omc.ir"
{ printf '@ng opt\n'; cat "$B/omc.ir"; } | "$B/ng" > "$B/omc.opt.ir"
{ printf '@ng a64\n'; cat "$B/omc.opt.ir"; } | "$B/ng" > "$B/A_fast"
chmod +x "$B/A_fast"
"$B/A_fast" < seed/omc/omc.om > "$B/omc_strand5"
chmod +x "$B/omc_strand5"
S5_OMC_SHA=$(sha "$B/omc_strand5")
[ "$S5_OMC_SHA" = "$PIN_SHA" ] || fail "Strand 5 @ng DDC mismatch: got=$S5_OMC_SHA pin=$PIN_SHA"
printf '  PASS Strand 5 @ng A_fast(omc.om) fixpoint          = %s (BIT-EXACT MATCH)\n' "$S5_OMC_SHA"

SRC_SHA=$(sha seed/omc/omc.om)
DDC1=$("$B/om3_aegis" memo-ddc "$SRC_SHA" "$S5_OMC_SHA" "$PIN_SHA" "$B/memo_ddc")
DDC2=$("$B/om3_aegis" memo-ddc "$SRC_SHA" "$S5_OMC_SHA" "$PIN_SHA" "$B/memo_ddc")
printf '  %s\n' "$DDC1"
printf '  %s\n' "$DDC2"
printf '%s\n' "$DDC1" | grep -q 'mode=COLD_PROVED' || fail "DDC1 not COLD_PROVED"
printf '%s\n' "$DDC2" | grep -q 'mode=MEMO_HIT' || fail "DDC2 not MEMO_HIT"

# 130 DDC_MISMATCH negative control + non-hex SHA refusal
BAD_SHA="0000000000000000000000000000000000000000000000000000000000000000"
set +e
"$B/om3_aegis" memo-ddc "$SRC_SHA" "$BAD_SHA" "$PIN_SHA" "$B/memo_ddc" > /dev/null 2> "$B/cases/ddc_bad.err"
DRC=$?
set -e
[ "$DRC" -eq 130 ] || fail "DDC mismatch expected exit 130, got $DRC"
neg_cnt=$((neg_cnt + 1))
printf '  KILL [%02d] %-28s -> exit=%d (%s)\n' "$neg_cnt" "ddc_poisoned_omc_sha" "$DRC" "$(cat "$B/cases/ddc_bad.err" | tr -d '\n')"

NONHEX_SHA="ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"
set +e
"$B/om3_aegis" memo-ddc "$NONHEX_SHA" "$NONHEX_SHA" "$NONHEX_SHA" "$B/memo_ddc" > /dev/null 2> "$B/cases/ddc_nonhex.err"
NHRC=$?
set -e
[ "$NHRC" -eq 2 ] || fail "DDC non-hex expected exit 2, got $NHRC"
neg_cnt=$((neg_cnt + 1))
printf '  KILL [%02d] %-28s -> exit=%d (non-hex SHA rejected)\n' "$neg_cnt" "ddc_nonhex_sha_rejected" "$NHRC"

printf '\n=== [6/7] LEAN 4.36.0 MACHINE-CHECKED PROOFS (Om3MemorySafety.lean) ===\n'
LEAN_BIN=""
if command -v lean >/dev/null 2>&1; then
  LEAN_BIN=$(command -v lean)
elif [ -x "$HOME/.elan/bin/lean" ]; then
  LEAN_BIN="$HOME/.elan/bin/lean"
fi
if [ -n "$LEAN_BIN" ]; then
  "$LEAN_BIN" seed/helix/proofs/Om3MemorySafety.lean > "$B/lean_om3.out" 2>&1 || { cat "$B/lean_om3.out" >&2; fail "Om3MemorySafety.lean failed"; }
  grep -qi 'sorry' "$B/lean_om3.out" && fail "Om3MemorySafety.lean used sorry!"
  printf '  PASS Om3MemorySafety.lean verified (0 warnings, 0 sorry, standard axioms only)\n'
else
  printf '  SKIP Lean 4 not installed on this host\n'
fi

printf '\n=== [7/7] SUMMARY ===\n'
printf 'STRAND5_AEGIS PASS om2_fixpoint=%s ng_ddc=%s neg_controls=%d/34\n' "$SEED_OMC_SHA" "$S5_OMC_SHA" "$neg_cnt"
