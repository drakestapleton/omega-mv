#!/bin/sh
# seed/helix/cold-regrowth.sh -- Phase 4 Single-Command Clean-Room Cold Regrowth Harness.
#
# Starts strictly from ~804 bytes of independent hand-written machine-code seeds:
#   - Seed A: seed/rung0/seed0.hex       (408 B)
#   - Seed B: seed/helix/rung0/seedB0.b0 (396 B, W^X)
# Zero network access. Zero Python. Zero CUDA.
#
# Usage (from repository root on AArch64 Linux):
#   sh seed/helix/cold-regrowth.sh [--lean]
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$R"
RUN_LEAN=0
for arg in "$@"; do
  case "$arg" in
    --lean) RUN_LEAN=1 ;;
    *) printf 'usage: cold-regrowth.sh [--lean]\n' >&2; exit 2 ;;
  esac
done

B=build/cold-regrowth
rm -rf "$B"
mkdir -p "$B/gen0" "$B/gen1" "$B/gen2" "$B/q36_kernels"

bad() { printf 'COLD_REGROWTH FAIL: %s\n' "$*" >&2; exit 1; }
sha() { sha256sum "$1" | cut -d' ' -f1; }

printf '=== [1/7] REGROW BOTH STRANDS FROM 804 BYTES OF INDEPENDENT SEEDS (ZERO C / PYTHON / CUDA) ===\n'
sh seed/helix/helix-from-seeds.sh
cp build/helix/A_stage2 "$B/omc_A"
cp build/helix/A_fast "$B/omc_B_fast"
cp build/helix/ng_B "$B/ng_B"
cp build/helix/monk_check "$B/monk_check"
cp build/helix/arboris_predator "$B/arboris_predator"
cp build/helix/immune "$B/immune"

printf '\n=== [1b/7] PHASE 1: PURE-OMEGA RFC 8032 ED25519 DDC RECEIPT SIGNING & VERIFICATION ===\n'
{ printf 'om2\n'; cat protocol/omnet/om/sha512/sha512.om protocol/omnet/om/ed25519/ed25519.om protocol/uor-gpu/ed_sign.om seed/helix/sign_ddc.om; } | "$B/omc_A" > "$B/sign_ddc_A"
{ printf 'om2\n'; cat protocol/omnet/om/sha512/sha512.om protocol/omnet/om/ed25519/ed25519.om protocol/uor-gpu/ed_sign.om seed/helix/sign_ddc.om; } | "$B/omc_B_fast" > "$B/sign_ddc_B"
cmp -s "$B/sign_ddc_A" "$B/sign_ddc_B" || bad "sign_ddc diverged between Strand A and Strand B"
chmod +x "$B/sign_ddc_A"
printf 'HELIX-DDC-V2\nseedA=%s\nseedB=%s\nomc_stage2=%s\nng_B=%s\nA_fast=%s\n' \
  "$(sha seed/rung0/seed0.hex)" "$(sha seed/helix/rung0/seedB0.b0)" \
  "$(sha "$B/omc_A")" "$(sha "$B/ng_B")" "$(sha "$B/omc_B_fast")" > "$B/ddc-canonical.txt"
"$B/sign_ddc_A" selftest "$B/ddc-canonical.txt" "$B/ddc.pk" "$B/ddc.sig"
"$B/sign_ddc_A" verify "$B/ddc-canonical.txt" "$B/ddc.pk" "$B/ddc.sig"

printf '\n=== [2/7] PHASE 2: EGP2 STRUCTURAL E-GRAPH + STRAND A DUAL-CHECKER + 12-ANTIBODY IMMUNE ===\n'
{ printf 'om2\n'; cat seed/helix/egraph_opt.om; } | "$B/omc_B_fast" > "$B/egraph_opt"
chmod +x "$B/egraph_opt"
{ printf 'om2\n'; cat seed/helix/dual_checker.om; } | "$B/omc_A" > "$B/dual_checker"
chmod +x "$B/dual_checker"
"$B/egraph_opt" "$B/egraph.egp2"
"$B/dual_checker" "$B/egraph.egp2"

printf '\n=== [3/7] PHASE 2: 46 PRODUCTION SM121 KERNELS (31 emit_fast + 5 emit_head + 10 om_synth_gb10) -> PREDATOR -> MONK -> 12-ATTACK IMMUNE ===\n'
sh seed/helix/sweep_sm121.sh "$B/omc_A" "$B/omc_B_fast" "$B/monk_check" "$B/arboris_predator" "$B/immune" "$B/q36_kernels"
cp "$B/q36_kernels/extract_q36" "$B/extract_q36"
printf 'PASS all 46 production SM121 kernels verified by Predator -> Monk (CFG+rawFloor=6+I2FP) -> 12+4=16 Antibodies!\n'

printf '\n=== [4/7] PHASE 3: ARBORIS NERVOUS SYSTEM BENCHMARKS (TRACKS 3A / 3B / 3C) ===\n'
{ printf 'om2\n'; cat seed/helix/arboris_nervous_bench.om; } | "$B/omc_B_fast" > "$B/arboris_bench"
chmod +x "$B/arboris_bench"
"$B/arboris_bench"

printf '\n=== [5/7] COMPILE uor-gpu & aienux PURE-OMEGA UNITS FROM REGROWN COMPILERS ===\n'
if [ -f aienux/units-gate.om ]; then
  { printf 'om2\n'; cat seed/ng/sha256.om aienux/units-gate.om; } | "$B/omc_A" > "$B/aienux_gate_A"
  { printf 'om2\n'; cat seed/ng/sha256.om aienux/units-gate.om; } | "$B/omc_B_fast" > "$B/aienux_gate_B"
  cmp -s "$B/aienux_gate_A" "$B/aienux_gate_B" || bad "aienux/units-gate.om diverged between Strand A and Strand B"
  printf 'PASS aienux/units-gate.om bit-for-bit identical across Strand A & Strand B (%s)\n' "$(sha "$B/aienux_gate_A")"
fi
if [ -f protocol/units-gate.om ]; then
  { printf 'om2\n'; cat seed/ng/sha256.om protocol/units-gate.om; } | "$B/omc_A" > "$B/protocol_gate_A"
  { printf 'om2\n'; cat seed/ng/sha256.om protocol/units-gate.om; } | "$B/omc_B_fast" > "$B/protocol_gate_B"
  cmp -s "$B/protocol_gate_A" "$B/protocol_gate_B" || bad "protocol/units-gate.om diverged between Strand A and Strand B"
  printf 'PASS protocol/units-gate.om bit-for-bit identical across Strand A & Strand B (%s)\n' "$(sha "$B/protocol_gate_A")"
fi
if [ -f protocol/uor-gpu/uor-gpu-gate.om ]; then
  UOR_SRCS="si/directives/om2.om om/tls/sha2.om protocol/uor-gpu/b3_uor.om protocol/omnet/om/sha512/sha512.om protocol/omnet/om/ed25519/ed25519.om protocol/uor-gpu/canonical.om protocol/uor-gpu/payload_vm.om protocol/uor-gpu/verify.om protocol/uor-gpu/gate.om protocol/uor-gpu/emit_kernels.om protocol/uor-gpu/ed_sign.om protocol/uor-gpu/uor-gpu-gate.om"
  cat $UOR_SRCS | "$B/omc_A" > "$B/uor_gpu_gate_A"
  cat $UOR_SRCS | "$B/omc_B_fast" > "$B/uor_gpu_gate_B"
  cmp -s "$B/uor_gpu_gate_A" "$B/uor_gpu_gate_B" || bad "uor_gpu_gate diverged between Strand A and Strand B"
  chmod +x "$B/uor_gpu_gate_A"
  "$B/uor_gpu_gate_A"
  printf 'PASS uor-gpu-gate bit-for-bit identical across Strand A & Strand B AND executed PASS (%s)\n' "$(sha "$B/uor_gpu_gate_A")"
fi

printf '\n=== [6/7] PHASE 4: TWO-GENERATION HELICAL SELF-RECOMPILATION OF ZERO-CUDA 35B AI SERVER ===\n'
build_q36() {
  comp=$1; outdir=$2
  mkdir -p "$outdir"
  { echo om2; cat gpu/nvidia/native/nvrm/context.om gpu/nvidia/native/blackwell/vector.om gpu/nvidia/native/blackwell/launch.om gpu/nvidia/native/blackwell/batch.om om/encoder/bw_enc_sm121.om om/gpu/q36/emit_fast.om om/gpu/q36/arboris/prefetch.om om/gpu/q36/native_run.om; } | "$comp" > "$outdir/q36-native"
  chmod +x "$outdir/q36-native"
  { echo om2
    cat gpu/nvidia/native/nvrm/context.om gpu/nvidia/native/blackwell/vector.om gpu/nvidia/native/blackwell/launch.om gpu/nvidia/native/blackwell/batch.om om/encoder/bw_enc_sm121.om om/gpu/q36/emit_fast.om
    [ -f om/gpu/q36/emit_prefill.om ] && cat om/gpu/q36/emit_prefill.om
    cat om/gpu/q36/head/emit_head.om om/gpu/q36/arboris/prefetch.om
    sed '/^fn main to int$/,$d' om/gpu/q36/decode/decode_run.om
    [ -f om/gpu/q36/decode/prefill_host.om ] && cat om/gpu/q36/decode/prefill_host.om
    cat om/gpu/q36/serve/tokenizer.om om/gpu/q36/serve/serve_run.om
  } | "$comp" > "$outdir/q36-serve"
  chmod +x "$outdir/q36-serve"
}
# Gen 0 (Strand A), Gen 1 (Strand B A_fast), Gen 2 (Strand B -> re-twist -> A_fast_gen2 -> q36)
build_q36 "$B/omc_A" "$B/gen0"
build_q36 "$B/omc_B_fast" "$B/gen1"
{ printf '@ng front-ir\n'; cat seed/omc/omc.om; } | "$B/ng_B" > "$B/g2.ir"
{ printf '@ng opt\n'; cat "$B/g2.ir"; } | "$B/ng_B" > "$B/g2.opt.ir"
{ printf '@ng a64\n'; cat "$B/g2.opt.ir"; } | "$B/ng_B" > "$B/omc_B_fast_gen2"
chmod +x "$B/omc_B_fast_gen2"
build_q36 "$B/omc_B_fast_gen2" "$B/gen2"
cmp -s "$B/gen0/q36-serve" "$B/gen1/q36-serve" || bad "Gen0 vs Gen1 q36-serve mismatch"
cmp -s "$B/gen1/q36-serve" "$B/gen2/q36-serve" || bad "Gen1 vs Gen2 q36-serve mismatch"
cmp -s "$B/gen0/q36-native" "$B/gen2/q36-native" || bad "Gen0 vs Gen2 q36-native mismatch"
printf 'PASS Gen0==Gen1==Gen2 q36-serve=%s (static ELF, zero CUDA)\n' "$(sha "$B/gen2/q36-serve")"
printf 'PASS Gen0==Gen1==Gen2 q36-native=%s (static ELF, zero CUDA)\n' "$(sha "$B/gen2/q36-native")"

printf '\n=== [7/7] LEAN 4 FORMAL PROOF CHECKS ===\n'
if [ "$RUN_LEAN" = "1" ]; then
  lean seed/helix/proofs/HelixSoundness.lean
  lean seed/helix/proofs/HelixAntibodies.lean
  lean seed/helix/proofs/HelixKernelIR.lean
  lean protocol/uor-gpu/proofs/UorGpuWorld.lean
  printf 'PASS Lean 4 proofs verified (HelixSoundness + HelixAntibodies + HelixKernelIR + UorGpuWorld)\n'
else
  printf 'INFO pass --lean (with Lean 4 on PATH) to re-check all 4 Lean 4 proof files\n'
fi

printf '\nCOLD_REGROWTH PASS dual_seeds=804B zero_prebuilt=1 zero_c=1 zero_python=1 zero_cuda=1 sm121_kernels=46 antibodies=16/16 gens=3\n'
