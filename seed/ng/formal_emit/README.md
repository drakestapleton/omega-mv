# `seed/ng/formal_emit/` — Per-Binary Lean 4 Auto-Formalizer (`alien-formal`)

> **TL;DR (Everyday Analogy):** Most compilers behave like a builder who writes down "the bridge looks sturdy" and opens traffic anyway. `lean_emit` behaves like an automated structural inspector standing in front of the lockbox: before sealing a single executable byte onto disk as read+execute (`0500 RX`), it forces the program's math, memory domains, thermal budget (`< 80 W`), and GPU pipeline hazards to pass a live **Lean 4.36.0** machine-checked proof with zero warnings, zero `sorry`, and zero fake axioms. If even one proof step or safety limit fails—even if someone edits the `.lean` file to inject a hidden `axiom` or `native_decide`—no executable is ever written.

## What You Get Without vs. With `lean_emit`

| Step | Traditional Compiler | `seed/ng/formal_emit/lean_emit.om` |
|---|---|---|
| IR purity & fold | Trusts optimizer silently | Checks `ΩIR v2` (`ver=10`) canonical 28-byte contract, structural purity scan, exact constant fold, and SHA-256 `SEMANTIC_ID` |
| Memory & DMA safety | Runtime crashes / silent UAF | Checks `OM-3` disjoint regions, forbids `CPU_KERNEL_SLAB` mapping, and verifies 4-step reclaim (`@unmap -> @tlbinval -> @fence_drain -> @vma_revoke -> @reclaim`) |
| Thermal cap | Thermal throttling after launch | Enforces `WattCBF` strict `< 80 W` (`<= 79999 mW`) GPU cap and positive forward-time thermal barrier |
| GPU hazard & regs | Runtime stall / register spill | Enforces SM121 `rawFloor >= 6`, per-pipe stalls (`ALU=6`, `HMMA=22`, `OMMA=29`), and `regalloc.om` / `chips.tsv` register budget |
| Independent proof | None | Emits self-contained ASCII `GeneratedCert.lean` and invokes live `lean -DwarningAsError=true` via pure-OM `fork`/`execprog`/`waitpid`, inspecting `#print axioms` |
| Binary sealing | Writes `0755` or `RWX` directly | Writes `0600 RW` staging file -> verifies readback SHA-256 -> `fchmod 0500 RX` -> atomic `renames` (`--rwx` refused `rc=2`) |

## Honest Verification Scope (Current Pin)

| Layer | Verdict | Details |
|---|---|---|
| Spark AArch64 Host Build (`seed/out/omc`) | **HOST-VERIFIED** | 2x byte-identical `omc-pin` (`85b84c6d...`) compiles of `lean_emit` (`b0c46d5a...`) and `gate_formal_emit` (`29c89bca...`) |
| Live Lean 4.36.0 Proof + `W^X` Seal + Negative Mutants | **HOST-VERIFIED** | `GATE_FORMAL_EMIT PASS (17 checks passed, 0 failed)`: 2x compiler determinism, 3 distinct units sealed (`0500 RX`, `PT_LOAD PF_R|PF_X=5`) & executed (`rc=36, 62, 48`), 12 negative mutants refused before sealing |
| Live GB10 GPU Silicon Execution (`hw_writes=0`) | **NOT_RUN** | Deferred to Coordinator post-Wave1 GB10 activation; zero GPU hardware/MMIO/VFIO/driver touches in this layer |

**Honest Tradeoff / Limitation:** Running live `lean -DwarningAsError=true` per binary adds ~2–3 seconds of Lean checking per unit compile and verifies the declared unit model (`IrContract`, `OM-3` trace, `WattCBF` state/policy, `SM121` instruction hazard table) together with the sealed AArch64 witness binary; full end-to-end equivalence across arbitrary multi-block PTX/SASS loops remains an incremental IR extension beyond this single-kernel witness pass.

## Source Files

- [lean_emit.om](lean_emit.om) (3,289 lines): Pure seeded OM-2 CLI, unit parser, `chips.tsv` / `regalloc.om` / `isel.om` / `ir.om` checkers, ASCII `GeneratedCert.lean` generator, `fork`+`execprog`+`waitpid` Lean 4.36.0 runner, strict `#print axioms` auditor, and `0600 RW -> SHA-256 -> fchmod 0500 RX` ELF sealer.
- [gate_formal_emit.om](gate_formal_emit.om) (1,177 lines): Pure seeded OM-2 verification suite testing 2x `omc` determinism, 3 positive units (`pure_arith`, `om3_gb20b_dma`, `sm121_gemv_contract`), and 12 killed negative mutants (before sealing).
- [RECEIPT.txt](../../../evidence/ALIEN-AUTO-FORMALIZER-20261127/RECEIPT.txt) & [SHA256SUMS.txt](../../../evidence/ALIEN-AUTO-FORMALIZER-20261127/SHA256SUMS.txt): Content-addressed verification receipt and root checksum manifest.

## How to Build & Run (AArch64 Host with `seed/out/omc` + Lean 4.36.0)

```sh
# 1. Build lean_emit (pure seeded OM-2, no C compiler)
cat seed/ng/src/ir.om seed/ng/sha256.om seed/ng/target/target_desc.om \
    seed/ng/target/chips_tsv.om seed/ng/target/regalloc.om \
    seed/ng/target/isel.om seed/ng/target/sm121_pe.om \
    seed/ng/formal_emit/lean_emit.om | seed/out/omc > build/lean_emit
chmod +x build/lean_emit

# 2. Build gate_formal_emit (pure seeded OM-2)
{ printf 'om2\n'; cat seed/ng/sha256.om seed/ng/formal_emit/gate_formal_emit.om; } \
  | seed/out/omc > build/gate_formal_emit
chmod +x build/gate_formal_emit

# 3. Run the 17-check verification gate
build/gate_formal_emit build/lean_emit "$(command -v lean || echo ~/.elan/bin/lean)" \
  /tmp/formal_gate_scr seed/out/omc .
```

### `lean_emit` CLI & Refusal Codes

| Invocation | Purpose | Exit Codes |
|---|---|---|
| `lean_emit --unit FILE --out RX_BIN [--cert-out FILE.lean] [--lean PATH] [--workdir DIR] [--chips FILE]` | Verify `ΩIR v2` + `OM-3` + `WattCBF` + `SM121`, emit & prove `GeneratedCert.lean`, seal `0500 RX` binary | `0` = PASS, `2` = `--rwx`/usage refused, `10` = I/O or syntax |
| `lean_emit --verify-cert FILE.lean --out RX_BIN [--lean PATH] [--workdir DIR]` | Audit an explicit `.lean` certificate under `-DwarningAsError=true` + `#print axioms` gate before `0500 RX` sealing | `11` = `IR_V2` purity/fold, `12` = `OM3` domain/fence, `13` = `WattCBF >= 80 W` |
| Any invocation with `--rwx` | Permanently rejected (`PROT_WRITE\|PROT_EXEC` forbidden) | `14` = `SM121` hazard/regs, `15` = Lean proof/axiom audit, `16` = `W^X` seal |

## What the 17 Gate Checks Prove

1. **2x Determinism (`repro_2x_omc_lean_emit`, `repro_2x_omc_gate_formal_emit`):** Compiling both `lean_emit` and `gate_formal_emit` twice through `omc` produces byte-for-byte identical ELF binaries.
2. **3 End-to-End Sealed Units:**
   - `pure_arith` (`grace-x925`, `15 W` GPU / `16/30` regs) -> Lean `STANDARD_ONLY` -> `0500 RX` -> exits `36` (`(5 + 7) * 3`).
   - `om3_gb20b_dma` (`apu-gb10`, `79.999 W` GPU boundary / multi-domain DMA+GMMU+slab) -> Lean `STANDARD_ONLY` -> `0500 RX` -> exits `62` (`(100 - 40) ^ 2`).
   - `sm121_gemv_contract` (`sm121`, `72 W` GPU / `HMMA` 22 + `OMMA` 29 + `ALU` 6 hazards / `48/64` regs) -> Lean `STANDARD_ONLY` -> `0500 RX` -> exits `48` (`(15 - 3) * 4`).
3. **12 Killed Negative Mutants (All Refused Before `--out` Creation):**
   - `M1_ir_fold` (`rc=11`), `M2_ir_purity` (`rc=11`), `M3_drop_tlbinval` (`rc=12`), `M4_kslab_overlap` (`rc=12`), `M5_kslab_map` (`rc=12`), `M6_wattcbf_82w` (`rc=13`), `M7a_sm121_raw3` (`rc=14`), `M7b_hmma_stall8` (`rc=14`), `M8_lean_sorry` (`rc=15`), `M9_lean_axiom` (`rc=15`, where raw `lean` exits `0`!), `M10_lean_native_decide` (`rc=15`, where raw `lean` exits `0`!), and `M11_rwx_refuse` (`rc=2`).
