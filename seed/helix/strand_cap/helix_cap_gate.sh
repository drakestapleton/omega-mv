#!/bin/sh
# seed/helix/strand_cap/helix_cap_gate.sh -- Capability Containment, W^X & Seccomp cBPF Gate for Helix.
#
# Enforces pure-Omega OS effect containment via `seed/effects/effects.om`:
#   1. Dual-strand compiles `effects` (`omc_A == omc_B`) and verifies `enlarge` -> `mem` class split
#      (verifiers/compilers allow `io,fd,path,env,mem` with ZERO `net`, ZERO `proc`, ZERO `device`/ioctl 29).
#   2. Verifies source-to-ELF syscall closure + allowlists on ALL Helix verifiers & compilers.
#   3. Verifies W^X + exact syscall closure on hand-written seeds (`seedB0`, `seedC0`, `seedD0`)
#      and ALL Helix ELFs, plus a W+X negative control (`ELF REFUSED wx-segment`).
#   4. Generates real seccomp cBPF via `effects bpf` for Wall 1's untrusted proposer (`arboris_predator`)
#      and enforces it via `bwrap --seccomp` (positive offline pass + negative net-probe SIGSYS kill).
#
# Usage:
#   sh seed/helix/strand_cap/helix_cap_gate.sh [OMC_A] [OMC_B] [COLD_DIR] [RSI_DIR]
set -eu
export CUDA_VISIBLE_DEVICES=""
R=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
cd "$R"

OMC_A=${1:-build/cold-regrowth/omc_A}
OMC_B=${2:-build/cold-regrowth/omc_B_fast}
COLD=${3:-build/cold-regrowth}
RSI=${4:-build/rsi-loop1}

[ -x "$OMC_A" ] || OMC_A=seed/out/omc
[ -x "$OMC_B" ] || OMC_B="$OMC_A"

CAP=build/helix-cap-gate
rm -rf "$CAP"
mkdir -p "$CAP/src" "$CAP/bin" "$CAP/run"

bad() { printf 'HELIX_CAP_GATE FAIL: %s\n' "$*" >&2; exit 1; }
sha() { sha256sum "$1" | cut -d' ' -f1; }

printf '=== [CAP 1/4] DUAL-STRAND BUILD effects.om + VERIFY mem VS device CAPABILITY SPLIT ===\n'
"$OMC_A" < seed/effects/effects.om > "$CAP/bin/effects_A"
"$OMC_B" < seed/effects/effects.om > "$CAP/bin/effects_B"
cmp -s "$CAP/bin/effects_A" "$CAP/bin/effects_B" || bad "effects binary diverged across Strand A and Strand B"
mv "$CAP/bin/effects_A" "$CAP/bin/effects"
rm -f "$CAP/bin/effects_B"
chmod +x "$CAP/bin/effects"
EFF="$CAP/bin/effects"
printf 'PASS effects dual-strand identical (%s)\n' "$(sha "$EFF")"

# Positive: enlarge is in `mem` class (syscalls 216, 222) and allowed by verifier allowlist
"$EFF" src allow=io,fd,path,env,mem < seed/effects/cases/probe-enlarge.om > "$CAP/run/enlarge_mem.txt"
grep -qx 'EFFECTS 1 words=1 classes=mem syscalls=93,216,222' "$CAP/run/enlarge_mem.txt" \
  || bad "enlarge did not classify as mem: $(cat "$CAP/run/enlarge_mem.txt")"

# Negative 1: enlarge must NOT be in `device`
set +e
"$EFF" src allow=io,device < seed/effects/cases/probe-enlarge.om > "$CAP/run/enlarge_dev.txt"
rc=$?
set -e
[ "$rc" -eq 1 ] || bad "Expected enlarge refused under allow=io,device, got rc=$rc"
grep -qx 'EFFECTS REFUSED word=enlarge class=mem line=6' "$CAP/run/enlarge_dev.txt" \
  || bad "Unexpected enlarge refusal text: $(cat "$CAP/run/enlarge_dev.txt")"

# Negative 2: GPU ioctl 29 (`devctl`) MUST be refused under verifier allowlist `io,fd,path,env,mem`
printf 'fn main to int\nb = new uchar 8 0\nr = devctl 3 1 b 0 8\nret 0\nend\n' > "$CAP/src/gpu_probe.om"
set +e
"$EFF" src allow=io,fd,path,env,mem < "$CAP/src/gpu_probe.om" > "$CAP/run/gpu_refuse.txt"
rc=$?
set -e
[ "$rc" -eq 1 ] || bad "Expected devctl refused under verifier allowlist, got rc=$rc"
grep -qx 'EFFECTS REFUSED word=devctl class=device line=3' "$CAP/run/gpu_refuse.txt" \
  || bad "Unexpected devctl refusal text: $(cat "$CAP/run/gpu_refuse.txt")"
printf 'PASS mem/device split verified (enlarge=mem allowed; devctl/ioctl-29=device REFUSED)\n'

printf '\n=== [CAP 2/4] VERIFIER & COMPILER ALLOWLISTS (allow=io,fd,path,env,mem; ZERO net/proc/device) ===\n'
ALLOW_VERIF="allow=io,fd,path,env,mem"

verify_unit() {
  name=$1; src=$2; bin=$3; allow=$4
  "$EFF" verify "$src" "$bin" "$allow" > "$CAP/run/v_${name}.txt" \
    || bad "effects verify failed for $name ($allow): $(cat "$CAP/run/v_${name}.txt")"
  printf '  PASS verify %-18s %s\n' "$name" "$(tail -n 1 "$CAP/run/v_${name}.txt")"
}

# Self-verify effects
verify_unit "effects" seed/effects/effects.om "$EFF" "$ALLOW_VERIF"

# Verify Strand A compiler omc_A (uses enlarge -> mem, ZERO device/net/proc!)
verify_unit "omc_A" seed/omc/omc.om "$OMC_A" "$ALLOW_VERIF"

# Compose sources and verify each Helix verifier / compiler / ratchet binary
{ printf 'om2\n'; cat seed/ng/sha256.om gpu/nvidia/om/codegen/bw_hazard.om seed/helix/hx_dec_ext.om seed/helix/monk_check.om; } > "$CAP/src/monk_check.om"
MONK_BIN="$COLD/monk_check"
if [ ! -x "$MONK_BIN" ]; then
  "$OMC_A" < "$CAP/src/monk_check.om" > "$CAP/bin/monk_check" && chmod +x "$CAP/bin/monk_check"
  MONK_BIN="$CAP/bin/monk_check"
fi
verify_unit "monk_check" "$CAP/src/monk_check.om" "$MONK_BIN" "$ALLOW_VERIF"

{ printf 'om2\n'; cat seed/helix/dual_checker.om; } > "$CAP/src/dual_checker.om"
DUAL_BIN="$COLD/dual_checker"
if [ ! -x "$DUAL_BIN" ]; then
  "$OMC_A" < "$CAP/src/dual_checker.om" > "$CAP/bin/dual_checker" && chmod +x "$CAP/bin/dual_checker"
  DUAL_BIN="$CAP/bin/dual_checker"
fi
verify_unit "dual_checker" "$CAP/src/dual_checker.om" "$DUAL_BIN" "$ALLOW_VERIF"

{ printf 'om2\n'; cat protocol/omnet/om/sha512/sha512.om protocol/omnet/om/ed25519/ed25519.om protocol/uor-gpu/ed_sign.om seed/helix/sign_ddc.om; } > "$CAP/src/sign_ddc.om"
SIGN_BIN="$COLD/sign_ddc_A"
if [ ! -x "$SIGN_BIN" ]; then
  "$OMC_A" < "$CAP/src/sign_ddc.om" > "$CAP/bin/sign_ddc" && chmod +x "$CAP/bin/sign_ddc"
  SIGN_BIN="$CAP/bin/sign_ddc"
fi
verify_unit "sign_ddc" "$CAP/src/sign_ddc.om" "$SIGN_BIN" "$ALLOW_VERIF"

{ printf 'om2\n'; cat seed/helix/egraph_opt.om; } > "$CAP/src/egraph_opt.om"
EG_BIN="$COLD/egraph_opt"
if [ ! -x "$EG_BIN" ]; then
  "$OMC_A" < "$CAP/src/egraph_opt.om" > "$CAP/bin/egraph_opt" && chmod +x "$CAP/bin/egraph_opt"
  EG_BIN="$CAP/bin/egraph_opt"
fi
verify_unit "egraph_opt" "$CAP/src/egraph_opt.om" "$EG_BIN" "$ALLOW_VERIF"

{ printf 'om2\n'; cat seed/helix/bft_healer.om; } > "$CAP/src/bft_healer.om"
"$OMC_A" < "$CAP/src/bft_healer.om" > "$CAP/bin/bft_healer" && chmod +x "$CAP/bin/bft_healer"
verify_unit "bft_healer" "$CAP/src/bft_healer.om" "$CAP/bin/bft_healer" "$ALLOW_VERIF"

{ printf 'om2\n'; cat om/encoder/bw_enc_sm121.om om/gpu/q36/emit_fast.om om/gpu/q36/head/emit_head.om seed/helix/extract_q36_kernels.om; } > "$CAP/src/extract_q36.om"
EXT_BIN="$COLD/extract_q36"
if [ ! -x "$EXT_BIN" ]; then
  "$OMC_A" < "$CAP/src/extract_q36.om" > "$CAP/bin/extract_q36" && chmod +x "$CAP/bin/extract_q36"
  EXT_BIN="$CAP/bin/extract_q36"
fi
verify_unit "extract_q36" "$CAP/src/extract_q36.om" "$EXT_BIN" "$ALLOW_VERIF"

if [ -x "$RSI/ratchet/rsi_eval_test_A" ]; then
  cat si/directives/om2.om core/rsi/om/eval/evaluator.om om/tls/sha2.om core/rsi/om/eval/canary.om core/rsi/om/eval/rollback.om core/rsi/om/eval/eval_test.om > "$CAP/src/rsi_eval_test.om"
  verify_unit "rsi_eval_test" "$CAP/src/rsi_eval_test.om" "$RSI/ratchet/rsi_eval_test_A" "$ALLOW_VERIF"
fi
if [ -x "$RSI/ratchet/rsi_v2_gate_A" ]; then
  cat core/rsi/om/p256/sha256.om core/rsi/om/p256/p256.om core/rsi/om/governance/receipt_v2.om core/rsi/om/governance/v2_main.om > "$CAP/src/rsi_v2_gate.om"
  verify_unit "rsi_v2_gate" "$CAP/src/rsi_v2_gate.om" "$RSI/ratchet/rsi_v2_gate_A" "$ALLOW_VERIF"
fi

# Wall 1 untrusted proposer (arboris_predator): allow=io,fd,path,env,net (ZERO proc, ZERO device!)
{ printf 'om2\n'; cat seed/ng/sha256.om gpu/nvidia/om/codegen/bw_hazard.om seed/helix/hx_dec_ext.om seed/helix/arboris_predator.om; } > "$CAP/src/arboris_predator.om"
PRED_BIN="$COLD/arboris_predator"
if [ ! -x "$PRED_BIN" ]; then
  "$OMC_B" < "$CAP/src/arboris_predator.om" > "$CAP/bin/arboris_predator" && chmod +x "$CAP/bin/arboris_predator"
  PRED_BIN="$CAP/bin/arboris_predator"
fi
verify_unit "arboris_predator" "$CAP/src/arboris_predator.om" "$PRED_BIN" "allow=io,fd,path,env,net"

# Negative control: arboris_predator MUST be refused under strict verifier allowlist (because it contains net words)
set +e
"$EFF" verify "$CAP/src/arboris_predator.om" "$PRED_BIN" "$ALLOW_VERIF" > "$CAP/run/pred_strict.txt"
rc=$?
set -e
[ "$rc" -eq 1 ] || bad "Expected arboris_predator refused under verifier allowlist (has net), got rc=$rc"
printf '  PASS negative control: arboris_predator refused under verifier allowlist (rc=1, net blocked)\n'

printf '\n=== [CAP 3/4] W^X & SYSCALL CLOSURE ON seedB0 / seedC0 / seedD0 + HELIX ELFs ===\n'
sh seed/helix/rung0/loadB0.sh seed/helix/rung0/seedB0.b0 "$CAP/bin/seedB0.bin"
sh seed/helix/strand3_trickster/loadC0.sh seed/helix/strand3_trickster/seedC0.c0 "$CAP/bin/seedC0.bin"
sh seed/helix/strand4_ascetic/loadD0.sh seed/helix/strand4_ascetic/seedD0.d0 "$CAP/bin/seedD0.bin"

for sb in seedB0.bin seedC0.bin seedD0.bin; do
  out=$("$EFF" elf < "$CAP/bin/$sb") || bad "W^X / ELF scan failed on $sb"
  printf '%s\n' "$out" | grep -q 'syscalls=63,64,93$' || bad "Unexpected syscalls on $sb: $out"
  printf '  PASS W^X + ELF closure %-12s (%s)\n' "$sb" "$out"
done

# Negative W^X control: patch p_flags of phdr[0] (offset 68) on a copy of seedB0.bin from PF_R|PF_X (5) to PF_R|PF_W|PF_X (7)
cp "$CAP/bin/seedB0.bin" "$CAP/bin/seedB0_wx.bin"
printf '\007' | dd of="$CAP/bin/seedB0_wx.bin" bs=1 seek=68 count=1 conv=notrunc 2>/dev/null
set +e
wx_out=$("$EFF" elf < "$CAP/bin/seedB0_wx.bin")
rc=$?
set -e
[ "$rc" -eq 3 ] && [ "$wx_out" = "ELF REFUSED wx-segment" ] \
  || bad "W+X negative control failed (rc=$rc out=$wx_out)"
printf '  PASS negative control: W+X patched seedB0 rejected (%s, rc=3)\n' "$wx_out"

printf '\n=== [CAP 4/4] REAL SECCOMP cBPF (effects bpf) FOR WALL 1 UNTRUSTED PROPOSER ===\n'
# Build Wall-1 strict offline cBPF filter (ZERO net, ZERO proc, ZERO device, ZERO mem: only read/write/openat/close/exit + launch execve)
cat > "$CAP/src/wall1_policy.om" <<'EOF'
fn main to int
b = new uchar 16 0
fd = fopen b 0 1 0 0
r = read 0 b 0 1
w = write 1 b 0 1
c = fclose 3
ret 0
end
EOF
"$EFF" bpf launch < "$CAP/src/wall1_policy.om" > "$CAP/run/wall1_proposer.bpf"
bpf_sz=$(wc -c < "$CAP/run/wall1_proposer.bpf" | tr -d ' ')
[ "$bpf_sz" -gt 0 ] && [ $((bpf_sz % 8)) -eq 0 ] || bad "Invalid cBPF filter size: $bpf_sz"
printf '  PASS generated Wall-1 seccomp cBPF filter (%s bytes, %s BPF insns; zero net/proc/device)\n' "$bpf_sz" "$((bpf_sz / 8))"

# Also emit full proposer cBPF filter from arboris_predator.om itself
"$EFF" bpf launch < "$CAP/src/arboris_predator.om" > "$CAP/run/predator_full.bpf"
p_bpf_sz=$(wc -c < "$CAP/run/predator_full.bpf" | tr -d ' ')
[ "$p_bpf_sz" -gt 0 ] && [ $((p_bpf_sz % 8)) -eq 0 ] || bad "Invalid predator cBPF filter size: $p_bpf_sz"

if command -v bwrap >/dev/null 2>&1; then
  # Positive: Wall-1 untrusted proposer runs cleanly under zero-net/zero-proc/zero-device seccomp cBPF
  bwrap --dev-bind / / --seccomp 9 "$PRED_BIN" seed/sm121/vecadd.bin "$CAP/run/w1_cand.bin" "$CAP/run/w1_cert.bin" \
    9< "$CAP/run/wall1_proposer.bpf" > "$CAP/run/w1_pred.out" \
    || bad "Wall-1 seccomp positive run failed"
  "$MONK_BIN" seed/sm121/vecadd.bin "$CAP/run/w1_cand.bin" "$CAP/run/w1_cert.bin" > "$CAP/run/w1_monk.out" \
    || bad "Monk rejected Wall-1 seccomp proposer output"
  printf '  PASS bwrap --seccomp Wall-1 offline proposer PASS + Monk PASS\n'

  # Negative: Wall-1 untrusted proposer attempting TCP socket connect (port 18091) MUST be killed by kernel SIGSYS (exit 159)
  set +e
  bwrap --dev-bind / / --seccomp 9 "$PRED_BIN" seed/sm121/vecadd.bin "$CAP/run/w1_net_cand.bin" "$CAP/run/w1_net_cert.bin" 18091 \
    9< "$CAP/run/wall1_proposer.bpf" > /dev/null 2>&1
  net_rc=$?
  set -e
  [ "$net_rc" -eq 159 ] || bad "Expected SIGSYS (159) killing net-probing Wall-1 proposer under seccomp cBPF, got $net_rc"
  printf '  PASS bwrap --seccomp negative control: Wall-1 net socket attempt KILLED by kernel SIGSYS (rc=159)\n'
  BWRAP_STATUS="enforced(pos=0,neg_sigsys=159)"
else
  printf '  INFO bwrap not installed on host; cBPF generated (%s bytes) without live kernel enforcement\n' "$bpf_sz"
  BWRAP_STATUS="generated_only"
fi

printf '\nHELIX_CAP_GATE PASS mem_split=PASS verifiers=zero_net_proc_device wx_seeds=3/3 wx_neg=PASS wall1_bpf=%sB seccomp=%s\n' \
  "$bpf_sz" "$BWRAP_STATUS"
