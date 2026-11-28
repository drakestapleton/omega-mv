# Proof-DNA Immune Evolution (`OMDNA1`)

> **Qualification:** `HOST-VERIFIED` on DGX Spark AArch64 CPU (`hw_writes=0`; no GPU device writes, no kernel modules, zero C/GCC/Python/Rust).

## Plain-English Overview

Think of `proof_dna.om` like an **immune system for safety rules**. Instead of waiting for someone to spot a bug manually, a built-in fuzzer ("Mutagen") keeps trying weird inputs—off-by-one power readings, missing memory-fence barriers, malformed network packets, and stale GPU stalls.

Whenever it finds a tricky input that slips past or hits a safety limit, four independent judges (`Monk | Predator | Trickster | Ascetic`) check it, a strict veto rule checks nothing dangerous is allowed through, and the engine replays the exact input to prove the bug is real. Only then does it save a tamper-evident, Ed25519-signed **Antibody** record (`OMDNA1`) into a ledger that can only grow—never shrink or forget. Every future build replays every saved Antibody at startup, so a fixed loophole can never silently come back.

| Aspect | Static Single-Pass Gate | `OMDNA1` Proof-DNA Evolution |
| :--- | :--- | :--- |
| Coverage discovery | Fixed hand-written test list only | Deterministic + OS-seeded (`random`) boundary Mutagen across 5 surfaces |
| Admission authority | Single script assertion | 3-of-4 BFT strand consensus + 1-of-K Safety Veto + deterministic replay |
| Persistence | Ephemeral pass/fail stdout | Hash-chained, Ed25519-signed `OMDNA1` ledger (`antibodies.omdna`) |
| Regression lock | Manual test additions | Monotonic ratchet (`old` prefix preserved, `new_count >= old_count`, replay on load) |

## Protected Surfaces

1. **`OM-3` Linear DMA Fence & `NO_RAW_PTR`** (`surface_id=1`, rules `1..5`, kill codes `101..106`): raw pointer tokens (`fwld`, `fwsys`, `efi`, `mapnew`, `execprog`, etc.), unsealed DMA regions, OOB VA access, and missing `@unmap`/`@tlbinval`/`@fence_drain`/`@reclaim`.
2. **SM121 SASS Scoreboard & `rawFloor >= 6`** (`surface_id=2`, rules `11..15`, kill codes `15, 17`): missing barriers, `< 6` cycle RAW hazards (`22`/`29` floors for `STG`/`BF16` classes), `WAR`/`WAW` floors, and `TMA` wait-mask parity.
3. **`EGP3` E-Graph Rewrite Soundness** (`surface_id=3`, rules `21..24`, kill code `31`): type/lane mismatches, zero-divisor / negative shift rewrites, overflow algebra, and cyclic e-class merges.
4. **`WattCBF` `< 80 W` Thermal & Overflow Guard** (`surface_id=4`, rules `31..35`, kill codes `151..157`): GPU hard power cap (`> 80000 mW`), total board cap (`> 140000 mW`), thermal cap (`>= 85 C`), control barrier sign inversion, and `u64` arithmetic overflow (`> MAX_F`).
5. **`OMSH` / `OMRC0001` Wire & IPv4 Validation** (`surface_id=5`, rules `41..44`, kill codes `171..174`): magic/version bounds, leading-zero octal IPv4 spoofing, reserved/multicast routing targets, and shell metacharacter injection in command strings.

## `OMDNA1` Binary Ledger Format

Header (`64 B`) + `N` signed records (`256 B` each, `1 <= N <= 240`) + Corpus Ed25519 trailer (`64 B`):

- **Header `[0..64)`**: `"OMDNA1"`, `u16` version (`1`), `u32` record_size (`256`), `u32` count, `u64` epoch, `u64` ratchet_floor, `pubkey[32]` (RFC 8032 Ed25519 authority key).
- **Record `[0..256)`**: `"ABDY"`, `antibody_id`, `surface_id`, `attack_class`, `rule_id`, `bft_votes` (`>= 3`), `bft_mask`, `veto_mask` (`0`), `discovered_epoch`, `rng_seed`, `expected_kill_rc` (`> 0`), `param0..param5` (`6 x u64`), `payload_len` (`0..20`), `payload[20]`, `attack_sha256[32]`, `chain_sha256[32]`, `ed25519_sig[64]`.
- **Trailer `[64 + N*256 .. +64)`**: `Ed25519(header[0..64) || last_chain[32])`.

## Build & Run (Pure Seeded OM-2 on Spark AArch64)

`seed/out/omc` reads a concatenated source unit on `stdin` and writes the native ELF on `stdout`:

```sh
cat si/directives/om2.om \
    seed/ng/sha256.om \
    protocol/omnet/om/sha512/sha512.om \
    protocol/omnet/om/ed25519/ed25519.om \
    protocol/uor-gpu/ed_sign.om \
    seed/helix/proof_dna/proof_dna.om > /tmp/proof_dna_unit.om
./seed/out/omc < /tmp/proof_dna_unit.om > /tmp/proof_dna
chmod +x /tmp/proof_dna

cat si/directives/om2.om seed/ng/sha256.om seed/helix/proof_dna/gate_proof_dna.om > /tmp/gate_unit.om
./seed/out/omc < /tmp/gate_unit.om > /tmp/gate_proof_dna
chmod +x /tmp/gate_proof_dna

/tmp/gate_proof_dna ./seed/out/omc "$PWD" /tmp/proof_dna_scratch
```

CLI commands on `/tmp/proof_dna`:
- `seed-init <out.omdna>` — generate the deterministic 5-antibody initial corpus (`1,408 B`).
- `verify-corpus <in.omdna> [min_ratchet]` — verify magic, bounds, SHA-256 hash chain, RFC 8032 Ed25519 signatures, and positive healthy-workload controls.
- `replay <in.omdna> [mutant_mask]` — replay every antibody (exit `109` if any attack slips through or a positive control breaks).
- `check-ratchet <old.omdna> <new.omdna>` — enforce monotonic growth and byte-identical verified record prefix.
- `evolve <in.omdna> <out.omdna> [rounds] [rng_seed] [bft_fault_mask] [veto_mask]` — run Mutagen + 3-of-4 BFT + Safety Veto + replay + Ed25519 crystallization (`hw_writes=0`).

Refusal exit codes: `101` IO, `102` format/magic/bounds, `103` Ed25519/hash-chain tamper, `104` BFT `< 3`-of-`4` quorum, `105` 1-of-K Safety Veto override attempt, `106` monotonic ratchet violation, `107` non-reproducible/bogus injection, `108` bad CLI args, `109` verifier regression/mutant caught.

## Formal Lean 4.36.0 Verification

`seed/helix/proofs/ProofDnaSoundness.lean` proves overflow-safe `u64` BFT quorum bounds (`4 >= 3(1) + 1`), 1-of-K Safety Veto non-bypassability, Ed25519 + SHA-256 signature binding before admission, monotonic antibody-set ratchet preservation across `evolveTrace`, regression detection (`weakened_mutant_detected`), and 8 concrete `decide` positive/negative controls (`0` warnings, `0` `sorry`, standard axioms only):

```sh
~/.elan/bin/lean -DwarningAsError=true seed/helix/proofs/ProofDnaSoundness.lean
```
