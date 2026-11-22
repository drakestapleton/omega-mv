#!/bin/sh
# seed/helix/rsi-loop1.sh -- Four-Wall Loop-1 Helical RSI Containment & Generational Cold-Regrowth Gate.
#
# Snaps ALL FOUR containment walls together in 100% pure seeded Omega + Lean 4 (zero C, zero Python, zero CUDA):
#   Wall 1 (The Proposer -- Untrusted):
#     Predator + Arboris running in an isolated ephemeral sandbox, proposing candidate SM121 schedules
#     and EGP2 kernel-IR optimizations.
#   Wall 2 (The Formal & Chaos Gauntlet -- Correctness Gate):
#     Strand A Monk (CFG fixed-point dataflow + fixed-latency RAW floor + Basic-Block Leader Antibody #13)
#     + EGP2 structural dual-checker + 12/12 Antibodies + Strand 3 Trickster chaos pass + all 4 Lean 4
#     proof files (HelixSoundness, HelixAntibodies, HelixKernelIR, HelixBFT = 29 theorems, 0 sorry).
#   Wall 3 (The Sealed Judge -- Performance & Capability Gate):
#     Pure-OM-2 spark-rsi evaluator (core/rsi/om/eval/evaluator.om + canary + rollback) + dual-strand
#     Proof-Carrying SM121 Evolutionary JIT binaries (q36-helix-native & q36-helix-decode).
#   Wall 4 (The Cryptographic Ratchet -- Promotion Authority):
#     Pure-OM-2 RSI V2 ECDSA P-256 promotion gate (core/rsi/om/governance/v2_main.om, dual-strand
#     compiled identically by Strand A & Strand B; selfcheck + v2_test negative controls: same-key
#     refusal, protected-path refusal, bad-signature refusal) + RFC 8032 Ed25519 receipt verification
#     + 4-Strand Byzantine Self-Healing Braid (1,612 B stem cells) + Compiler Mitosis + Arboris
#     Predator <-> Ascetic thermal/power hot-swap!
#
# Usage (from repository root on AArch64 Linux):
#   sh seed/helix/rsi-loop1.sh [--lean]
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$R"
LEAN_ARG=""
for arg in "$@"; do
  case "$arg" in
    --lean) LEAN_ARG="--lean" ;;
    *) printf 'usage: rsi-loop1.sh [--lean]\n' >&2; exit 2 ;;
  esac
done

B=build/rsi-loop1
rm -rf "$B"
mkdir -p "$B/sandbox" "$B/ratchet" "$B/jit"

bad() { printf 'RSI_LOOP1 FAIL: %s\n' "$*" >&2; exit 1; }
sha() { sha256sum "$1" | cut -d' ' -f1; }

printf '========================================================================\n'
printf '=== WALL 1 & 2: COLD REGROWTH + MONK + EGP2 + 12+ ANTIBODIES + LEAN4 ===\n'
printf '========================================================================\n'
sh seed/helix/cold-regrowth.sh $LEAN_ARG
OMC_A=build/cold-regrowth/omc_A
OMC_B=build/cold-regrowth/omc_B_fast

printf '\n========================================================================\n'
printf '=== WALL 3: SEALED JUDGE EVALUATOR + DUAL-STRAND EVOLUTIONARY JIT    ===\n'
printf '========================================================================\n'
# Build pure-Omega spark-rsi evaluator suite identically with Strand A & Strand B
EVAL_SRCS="si/directives/om2.om core/rsi/om/eval/evaluator.om om/tls/sha2.om core/rsi/om/eval/canary.om core/rsi/om/eval/rollback.om core/rsi/om/eval/eval_test.om"
cat $EVAL_SRCS | "$OMC_A" > "$B/ratchet/rsi_eval_test_A"
cat $EVAL_SRCS | "$OMC_B" > "$B/ratchet/rsi_eval_test_B"
cmp -s "$B/ratchet/rsi_eval_test_A" "$B/ratchet/rsi_eval_test_B" || bad "rsi_eval_test diverged across strands"
chmod +x "$B/ratchet/rsi_eval_test_A"
"$B/ratchet/rsi_eval_test_A"
printf 'PASS Wall 3 Sealed Judge evaluator bit-for-bit dual-strand identical (%s)\n' "$(sha "$B/ratchet/rsi_eval_test_A")"

# Build dual-strand Proof-Carrying SM121 Evolutionary JIT binaries (Monk/Predator/Trickster/Ascetic)
sh seed/helix/helix-build-jit.sh "$OMC_A" "$OMC_B" "$B/jit"

printf '\n========================================================================\n'
printf '=== WALL 4: CRYPTOGRAPHIC RATCHET (RSI V2 ECDSA P-256 + 4-STRAND BFT)===\n'
printf '========================================================================\n'
P256_GATE_SRCS="core/rsi/om/p256/sha256.om core/rsi/om/p256/p256.om core/rsi/om/governance/receipt_v2.om core/rsi/om/governance/v2_main.om"
cat $P256_GATE_SRCS | "$OMC_A" > "$B/ratchet/rsi_v2_gate_A"
cat $P256_GATE_SRCS | "$OMC_B" > "$B/ratchet/rsi_v2_gate_B"
cmp -s "$B/ratchet/rsi_v2_gate_A" "$B/ratchet/rsi_v2_gate_B" || bad "rsi_v2_gate diverged across strands"
chmod +x "$B/ratchet/rsi_v2_gate_A"
"$B/ratchet/rsi_v2_gate_A" version
"$B/ratchet/rsi_v2_gate_A" selfcheck
printf 'PASS Wall 4 RSI V2 P-256 gate dual-strand identical + selfcheck PASS (%s)\n' "$(sha "$B/ratchet/rsi_v2_gate_A")"

P256_TEST_SRCS="core/rsi/om/p256/sha256.om core/rsi/om/p256/p256.om core/rsi/om/governance/receipt_v2.om core/rsi/om/governance/v2_test.om"
cat $P256_TEST_SRCS | "$OMC_A" > "$B/ratchet/rsi_v2_test_A"
cat $P256_TEST_SRCS | "$OMC_B" > "$B/ratchet/rsi_v2_test_B"
cmp -s "$B/ratchet/rsi_v2_test_A" "$B/ratchet/rsi_v2_test_B" || bad "rsi_v2_test diverged across strands"
chmod +x "$B/ratchet/rsi_v2_test_A"
"$B/ratchet/rsi_v2_test_A"
printf 'PASS Wall 4 RSI V2 P-256 negative controls (same-key, protected-path, tamper) PASS (%s)\n' "$(sha "$B/ratchet/rsi_v2_test_A")"

# Generational 4-Strand BFT Cold Regrowth + Quarantine Auto-Heal + Compiler Mitosis + Hot-Swap + HelixBFT.lean
sh seed/helix/braid4-verify.sh

printf '\nRSI_LOOP1_FOUR_WALL PASS walls=4/4 strands=4(1612B) p256_ratchet=PASS ed25519_ddc=PASS bft_heal=2/2 mitosis=PASS hotswap=PASS\n'
