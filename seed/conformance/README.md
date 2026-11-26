# RM11 `OM-1.0` Conformance Suite (`seed/conformance/`)

Pure seeded OM-2 conformance suite verifying the **`OM-1.0` 1.x compatibility promise** required by [`docs/ROADMAP-1.0.md`](../../docs/ROADMAP-1.0.md) §RM11 (*"a conformance suite that every 1.x compiler must pass"*).

Zero C, Python, Node, or shell runs on the verification path. The runner compiles cleanly with the pinned seeded compiler (`seed/out/omc`) and computes all FIPS 180-4 SHA-256 digests in pure Omega via [`seed/ng/sha256.om`](../ng/sha256.om).

## 1. Compatibility Contract Checked

| Pillar | Guarantee | Checks | What is verified |
|---|---|---:|---|
| **0. Pin Verification** | Fail-closed compiler identity | 1 | Reads `<REPO_ROOT>/seed/out/omc.sha256`, validates strict 64-char lowercase hex + delimiter, computes SHA-256 of `<OMC_BIN>`, refuses immediately on missing/corrupted/mismatched pin. |
| **1. C2 Golden Byte-Identity** | Machine-code byte identity where promised | 9 | 4 frozen OM-1 `manifest-c2.txt` slices from `seed/qualification/om2/c2/corpus.pack` (`c2-00001` `b3unit.om`, `c2-00002` `blake3.om`, `c2-00004` `args.om`, `c2-00012`), 3 frozen OM-2 ABI v2 units (`s4/x-two.om` `export fn`, `s4/o-out.om`, `s4/v-fm-entry.om`), and 2 RM2 erasure byte-identity pairs (`contracts/release.om == erased.om`, `contracts/proved.om == plain.om`). |
| **1b. 2x Determinism** | Bit-identical compilation | 5 | Compiles OM-1, OM-2 (`s4/v-ok.om`), RM2 (`contracts/ok.om`), RM4 (`pools/g8b.om`), and RM5 (`seed/text/text.om` + driver) twice independently and verifies identical SHA-256 and byte-for-byte equality. |
| **2. C1 Golden Corpus** | Behavioral stability (verdict, exit, stdout) | 14 | **OM-1** (1: `struct`, `global`, `new`, `for`, `text`, OM-1 non-reserved identifiers `rotr`/`fresh`/`at`), **OM-2** (5: `s4/v-ok.om`, `s4/p-ok.om`, `s2/u1.om` vs rolled twin `s2/u1r.om`, inline `view`/`edit`/`part`/`inline`/`unroll`/`0x`/`rotr`), **RM2 contracts** (4: `ok.om` pass, `requires.om` exit 109, `ensures.om` exit 110, `forvalfinal.om` exit 110), **RM4 runtime pools** (3: growth/preservation/no-shrink, `g2a.om` bounds trap 103, `g8b.om` 2^63 overflow `-22` & host refusal `-12`), **RM5 text primitives** (1: live `<REPO_ROOT>/seed/text/text.om` testing `tx_eq`, `tx_cmp`, `tx_find`, `tx_field`, `tx_pdec`/`tx_pdeci`/`tx_phex`, `tx_fdec`/`tx_fdeci`/`tx_fhex`, `tx_u8ok`/`tx_u8dec`/`tx_u8enc`, plus overlong, surrogate, and above-`U+10FFFF` rejections). |
| **3a. C1 Trap & Order Stability** | Exact trap exit codes `100 + N` & evaluation order | 7 | `101` signed overflow, `102` div0, `103` bounds, `107` rotate shift out of range, `109` contract `requires`, `110` contract `ensures`, and `102` trap evaluation order (`part a (div 1 0) 99` evaluates `o` before bounds check). |
| **3b. C1 Error Refusal Stability** | Exact `omc: line N: error E` & 0-byte stdout | 10 | Minimal invalid inputs verified for exact exit code, empty stdout, and exact `omc: line N: error E\n` stderr across error codes `3, 4, 5, 6, 7, 8, 9, 15, 20, 30`. |
| **4. Fail-Closed Negative Controls** | Real verifier refusal proof | 6 | **NC-A** (1-byte flip in compiled golden ELF -> C2 refuses), **NC-B1** (mutated exit code -> C1 refuses), **NC-B2** (mutated stdout -> C1 refuses), **NC-C1/C2/C3** (missing, non-hex corrupted, and 1-nibble mismatched compiler pin -> pin verifier refuses). |

Total verified assertions per clean run: **52 checks**.

## 2. Build & Run (AArch64 Linux Host)

Build twice with the pinned seeded compiler (`seed/out/omc`, pinned in `seed/out/omc.sha256`) and verify 2x bit-identical output:

```sh
{ printf 'om2\n'; cat seed/ng/sha256.om seed/conformance/gate_om_1_0_conformance.om; } | seed/out/omc > /tmp/om_sw_conf10/gate_1
{ printf 'om2\n'; cat seed/ng/sha256.om seed/conformance/gate_om_1_0_conformance.om; } | seed/out/omc > /tmp/om_sw_conf10/gate_2
cmp /tmp/om_sw_conf10/gate_1 /tmp/om_sw_conf10/gate_2
chmod +x /tmp/om_sw_conf10/gate_1
```

Run the full conformance suite:

```sh
/tmp/om_sw_conf10/gate_1 <OMC_BIN> <REPO_ROOT> <SCRATCH_DIR>
```

### External Fail-Closed Negative Control Modes

In addition to the 6 in-suite negative controls executed on every normal run, the runner supports optional 4th-argument fault-injection modes that inject each failure directly into the live forward verification path (each MUST exit non-zero and print `OM10-CONFORMANCE FAIL step=<N>`):

```sh
# (a) 1-byte flip in golden compiled binary -> C2 refusal (step=20)
gate_1 <OMC_BIN> <REPO_ROOT> <SCRATCH_DIR>/nc_c2 neg-c2

# (b1) Mutated exit code in OM-1 golden -> C1 refusal (step=40)
gate_1 <OMC_BIN> <REPO_ROOT> <SCRATCH_DIR>/nc_exit neg-c1-exit

# (b2) Mutated stdout in OM-1 golden -> C1 refusal (step=40)
gate_1 <OMC_BIN> <REPO_ROOT> <SCRATCH_DIR>/nc_out neg-c1-stdout

# (c) Corrupted compiler pin -> Pin refusal (step=12)
gate_1 <OMC_BIN> <REPO_ROOT> <SCRATCH_DIR>/nc_pin neg-pin
```

You can also test missing/corrupted/mismatched `seed/out/omc.sha256` directly in standard 3-argument mode by pointing `<REPO_ROOT>` at a staging directory with a missing, corrupted, or altered pin file (steps `11`, `12`, `13` respectively).

## 3. Evidence Scope

Execution on DGX Spark Linux AArch64 (`HOST_VERIFIED`) qualifies the AArch64 Linux static-ELF host profile of `OM-1.0`. It does not claim physical bare-metal UEFI or GPU hardware qualification (which remain gated separately under RM9).
