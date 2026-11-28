# Omega Mindmesh (`apps/omega-mindmesh/`)

> **Plain-English overview:** Imagine a six-stage relay assembly line spanning three completely different computers (an Apple Silicon laptop, an ARMv9 server, and a Raspberry Pi 5). Each station must stamp a tamper-proof cryptographic wax seal—checking that no station ran hot (`< 80 W`), no code cheated its math proof (`Lean 4.36.0` with zero `sorry`), no worker slipped in an unapproved rounding drift (`0 ULP` vs scalar), and no secret Trojan compiler lied about what it built (`Ken Thompson` quorum kill). If someone tampers with even **one byte** at any seam, the next station immediately locks the line shut before any later station ever starts.

## Honest Verification Scope

| Domain | Status | Evidence / Limits |
| --- | --- | --- |
| **Pure OM-2 toolchain (`omc` + `ng`)** | **HOST-VERIFIED** | 100% handwritten `.om` (zero `.c`, `.h`, `.py`, `.rs`, `gcc`, or dynamic shared libs); 2x byte-identical builds on Spark (`readelf -d`: `There is no dynamic section in this file.`) and pre-codesign MacBook (`target a64macos`). |
| **Spark + MacBook + Pi 5 3-host loop** | **HOST-VERIFIED** | Executed physically across MacBook (`a64macos`, Mach-O `exit 36`, Role 1 `OMRC0001`), DGX Spark (`aarch64` Grace 20-core X925+A725, Stages 1–6, Role 2 + `trojan_omc` kill `109`), and Pi 5 `hub` (`/tmp/` only, Role 3), with final `OMMM01` verified on all 3 hosts. |
| **Formal certificates (`sm121_gemv_contract`)** | **LEAN-VERIFIED** | Emitted `.lean` checked with `Lean 4.36.0` (`0 sorry`, `STANDARD_ONLY` axioms) paired with W^X `0500 RX` native binary (`exit 48`). |
| **Physical GB10 GPU hardware** | **`NOT_RUN`** | `hw_writes=0`; zero `/dev/nvidia*` opens; zero UEFI/NVRAM/SPI touches; `WattCBF` strictly models `< 80 W` thermal headroom read-only. Coordinator executes any serialized GB10 pass separately. |

## Everyday Analogy & Six-Stage Relay

| Stage | Everyday Analogy | Real Pure-OM-2 Engine | Cryptographic Seam & Refusal Code |
| --- | --- | --- | --- |
| **1. Pack & Morph (`MacBook -> Spark`)** | Sealing a blueprint in a tamper-evident envelope on your laptop and mailing it to the factory floor. | `ommp_morph` (`OMMP01`, Ed25519, `apple-m` Mach-O `exit 36` + `grace-x925` ELF `exit 36`). | 1-byte Ed25519 / hash tamper -> `rc=11` (`MM_ERR_STAGE1`). |
| **2. Counterfactual Speculation (`Spark`)** | Running 3 simulator timelines side-by-side while watching the factory thermometer. | `chrono_forge` (`tl_0..2.rx` `0500` W^X ELFs, `chrono.otkj` hash journal, live read-only `WattCBF`). | `WattCBF >= 80 W` -> `rc=12`; `OTKJ` tamper -> `rc=13`; `--rwx` -> `rc=2`. |
| **3. Formal Proof Seal (`Spark`)** | Having an independent mathematician verify the safety rules before locking the blueprint `read+execute` only. | `lean_emit` + `Lean 4.36.0` (`10` theorems in `GeneratedCert`, `0500 RX` binary `exit 48`). | Tampered `0500 RX` (`RWX`) or injected `sorry` -> `rc=14` (`MM_ERR_STAGE3`). |
| **4. 20-Core Grace NEON + Memo (`Spark`)** | Twenty specialists compute in lockstep with zero rounding drift and store the verified answer in a locked vault. | `symbiote_coord` + `@ng opt`/`@ng a64` `symbiote_worker` (`10x X925 + 10x A725`, `0` ULP diff, `OMEGA-MEMO` `OMEM v1`). | ULP drift or `.ome` byte tamper -> `rc=15` (`MM_ERR_STAGE4`). |
| **5. 3-Host Byzantine DDC Quorum (`Mac + Spark + Pi 5`)** | Three independent workshops build the same recipe from scratch; any compiler that sneaks in a backdoor is voted out immediately. | `ddc_mesh` (`OMRC0001` 352 B receipts across `{1,2,3}` distinct PKs/ABIs) + live `trojan_omc` compiler attack. | Poisoned receipt -> `rc=16`; `trojan_omc` divergence -> `rc=109` (`KEN_THOMPSON_CROSS_ELF_DIVERGENCE`). |
| **6. Immune Evolution & Convergence (`OMMM01`)** | Raising the security bar permanently so tomorrow's immune defense never forgets today's attack, sealed into a single signed manifest. | `proof_dna` (`OMDNA1` `ratchet_floor 5 -> 22`, `5/5` surfaces) + `mindmesh_pipe seal` (`OMMM01` 512 B). | Ratchet downgrade / corpus tamper -> `rc=17`; truncated / bad `OMMM01` -> `rc=18`. |

## Owned Source Files

- [`mindmesh_pipe.om`](mindmesh_pipe.om): Portable pure OM-2 seam verifier & `OMMM01` manifest driver (compiles identically on Spark `aarch64`, Pi 5 `aarch64`, and MacBook `target a64macos`). Composes `watt_sense`, `watt_cbf`, `sha256`, `sha512`, `ed25519`, and `ed_sign`.
- [`gate_mindmesh.om`](gate_mindmesh.om): Standalone pure OM-2 verification gate on Linux `aarch64`. Deterministically compiles all 14 Wave 1–3 / Mindmesh binaries (2x `cmp -s` + `PT_DYNAMIC == 0` / Mach-O), executes the complete Stages 1–6 positive closed loop, and runs 11 adversarial seam controls proving non-zero refusal AND zero downstream stage execution (`downstream_executed=0`).

## Clean-Room Verification Commands

### 1. DGX Spark (`aarch64` Linux) — Build & Standalone Gate

Run from a clean repository checkout containing the pinned `seed/out/omc` (`85b84c6de85083e4d9d2368015c1ddcab3d863aada922be0e63d774dddf23134`):

```bash
sha256sum seed/out/omc

# Build mindmesh_pipe twice and confirm byte-identical ELF with zero dynamic section
cat si/directives/om2.om apps/omega-wattd/watt_sense.om apps/omega-wattd/watt_cbf.om \
    seed/ng/sha256.om protocol/omnet/om/sha512/sha512.om protocol/omnet/om/ed25519/ed25519.om \
    protocol/uor-gpu/ed_sign.om apps/omega-mindmesh/mindmesh_pipe.om | seed/out/omc > /tmp/mindmesh_pipe_1
cat si/directives/om2.om apps/omega-wattd/watt_sense.om apps/omega-wattd/watt_cbf.om \
    seed/ng/sha256.om protocol/omnet/om/sha512/sha512.om protocol/omnet/om/ed25519/ed25519.om \
    protocol/uor-gpu/ed_sign.om apps/omega-mindmesh/mindmesh_pipe.om | seed/out/omc > /tmp/mindmesh_pipe_2
cmp -s /tmp/mindmesh_pipe_1 /tmp/mindmesh_pipe_2 && chmod +x /tmp/mindmesh_pipe_1
readelf -d /tmp/mindmesh_pipe_1
/tmp/mindmesh_pipe_1 selftest

# Build gate_mindmesh twice and execute the full positive + 11-control clean-room gate
cat si/directives/om2.om seed/ng/sha256.om apps/omega-mindmesh/gate_mindmesh.om | seed/out/omc > /tmp/gate_mindmesh_1
cat si/directives/om2.om seed/ng/sha256.om apps/omega-mindmesh/gate_mindmesh.om | seed/out/omc > /tmp/gate_mindmesh_2
cmp -s /tmp/gate_mindmesh_1 /tmp/gate_mindmesh_2 && chmod +x /tmp/gate_mindmesh_1
readelf -d /tmp/gate_mindmesh_1
rm -rf /tmp/omega-mindmesh-gate
/tmp/gate_mindmesh_1 ./seed/out/omc . /tmp/omega-mindmesh-gate
```

### 2. MacBook Apple Silicon (`target a64macos`) — Pack, Execute Mach-O, Verify Manifest

```bash
{ printf 'target a64macos\n'; cat si/directives/om2.om apps/omega-wattd/watt_sense.om apps/omega-wattd/watt_cbf.om \
    seed/ng/sha256.om protocol/omnet/om/sha512/sha512.om protocol/omnet/om/ed25519/ed25519.om \
    protocol/uor-gpu/ed_sign.om apps/omega-mindmesh/mindmesh_pipe.om; } > /tmp/mp_mac_src.om
~/.local/bin/omc < /tmp/mp_mac_src.om > /tmp/mindmesh_pipe_mac_1
~/.local/bin/omc < /tmp/mp_mac_src.om > /tmp/mindmesh_pipe_mac_2
cmp -s /tmp/mindmesh_pipe_mac_1 /tmp/mindmesh_pipe_mac_2
chmod +x /tmp/mindmesh_pipe_mac_1 && codesign -s - -f /tmp/mindmesh_pipe_mac_1
/tmp/mindmesh_pipe_mac_1 selftest

# Verify a sealed OMMM01 manifest transferred from Spark:
/tmp/mindmesh_pipe_mac_1 verify-manifest /tmp/mindmesh.ommm
```

### 3. Raspberry Pi 5 `hub` (`/tmp/` ONLY — zero `/etc` or `omega-edge` service changes)

All Pi 5 verification MUST stay strictly inside `/tmp/mindmesh-hub/` (do not touch `/etc`, `nginx`, or `omega-edge.target`):

```bash
mkdir -p /tmp/mindmesh-hub
# With pinned omc, ddc_mesh, mindmesh_pipe, p.om, p_spark, and mindmesh.ommm placed under /tmp/mindmesh-hub/:
chmod +x /tmp/mindmesh-hub/{omc,ddc_mesh,mindmesh_pipe,p_spark}
/tmp/mindmesh-hub/omc < /tmp/mindmesh-hub/p.om > /tmp/mindmesh-hub/p_hub
chmod +x /tmp/mindmesh-hub/p_hub
/tmp/mindmesh-hub/p_hub > /tmp/mindmesh-hub/p_hub_out.txt; echo "exit=$?"
/tmp/mindmesh-hub/ddc_mesh attest --role 3 --abi linux-aarch64-pi5-hub \
    --source /tmp/mindmesh-hub/p.om --compiled /tmp/mindmesh-hub/p_hub \
    --cross-elf /tmp/mindmesh-hub/p_spark --exec-out /tmp/mindmesh-hub/p_hub_out.txt \
    --exec-rc 53 --seed-tag WAVE3-LIVE-HUB-R3 --out /tmp/mindmesh-hub/r3_hub.rcpt
/tmp/mindmesh-hub/mindmesh_pipe selftest
/tmp/mindmesh-hub/mindmesh_pipe verify-manifest /tmp/mindmesh-hub/mindmesh.ommm
```

## Negative Controls Verified by `gate_mindmesh`

| Control | Seam Fault Injected | Expected Exit | Downstream Executed |
| --- | --- | --- | --- |
| `NEG_1` | 1-byte flip in `OMMP01` Ed25519 signature (`offset 170`) | `11` (`MM_ERR_STAGE1`) | `0` |
| `NEG_2` | `--rwx` flag (`rc=2`) + `WattCBF >= 80 W` (`--sim-watt-mw 80000`) | `12` (`MM_ERR_WATTCBF`) | `0` |
| `NEG_3` | 1-byte tamper inside `chrono.otkj` journal | `13` (`MM_ERR_STAGE2`) | `0` |
| `NEG_4` | `sm121.rx` ELF `PT_LOAD p_flags` tampered `0x5 -> 0x7` (`RWX`) | `14` (`MM_ERR_STAGE3`) | `0` |
| `NEG_5` | `sorry` theorem injected into `GeneratedCert.lean` | `14` (`MM_ERR_STAGE3`) | `0` |
| `NEG_6` | `symbiote_coord --inject-ulp` + `diff_w20_scalar=1` seam tamper | `15` (`MM_ERR_STAGE4`) | `0` |
| `NEG_7` | `symbiote_coord --tamper-memo` + 1-byte flip in `.ome` payload | `15` (`MM_ERR_STAGE4`) | `0` |
| `NEG_8` | Poisoned `OMRC0001` Role 2 receipt signature | `16` (`MM_ERR_STAGE5`) | `0` |
| `NEG_9` | Live `trojan_omc` Ken Thompson backdoor (`exit 54 != 53`) | `109` (`KEN_THOMPSON_CROSS_ELF_DIVERGENCE`) | `0` |
| `NEG_10` | `proof_dna` `OMDNA1` ratchet downgrade (`22 -> 5`) | `17` (`MM_ERR_STAGE6`) | `0` |
| `NEG_11` | `OMMM01` truncated (`511 B`) + 1-byte Ed25519 signature flip | `18` (`MM_ERR_MANIFEST`) | `0` |
