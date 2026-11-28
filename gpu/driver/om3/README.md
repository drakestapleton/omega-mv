# Pure `OM-3` Verified GB20B Driver & Read-Only VFIO/IORT Audit

## What This Is (Plain English)

On DGX Spark (Blackwell GB20B GPU), a bug in a legacy C kernel driver (`dma_unmap_page` without draining the GPU/TLB or revoking userspace VMAs, or exposing Linux kernel slab pages to GPU DMA) caused a real physical kernel crash (`RCCA-SPARK-DMA-UAF-20261126`). At the same time, binding the GPU through Linux `vfio-pci` fails with `-EINVAL` because Spark's ACPI IORT firmware sets `remap_permitted = 0` (`RMR_NODE idx=50`) on three reserved DMA memory carveouts.

Think of normal C driver code like a shared storage warehouse where anyone can walk out with a box while another forklift is still moving it. **OM-3 (`om3_aegis`) puts a lock-and-checklist inspector at the warehouse door at compile time**: every buffer belongs to one strict owner (`CPU_KERNEL_SLAB` can never even get a GPU badge), freeing any GPU-mapped buffer will not even compile unless all four teardown steps (`@unmap -> @tlbinval -> @fence_drain -> @vma_revoke`) happen in order along every control-flow path, and once proven, all `@` annotations erase completely down to zero-runtime-overhead `om2` machine code.

| Layer | Legacy C / `vfio-pci` Path | Pure `OM-3` + Lean Path (`gpu/driver/om3/`) |
|---|---|---|
| Raw pointers | `void *` / `uint64_t` casts anywhere | **Refused (`exit 101`)**: raw-pointer words banned statically |
| Kernel slab isolation | Runtime discipline only | **Exclusive Domain 2 (`CPU_KERNEL_SLAB`)**: cannot GPU-map (`exit 110`) |
| DMA teardown order | Manual unmap/flush/revoke ordering | **Compile-time linear 4-step fence** across all CFG paths (`104..107`, `112`) |
| ACPI RMR & VA bounds | Hardcoded or runtime checks | **Static + runtime + Lean 4.36.0** disjointness over 3 RMRs + `vaBase = 2 GiB` + `[4 GiB, 4.5 GiB)` split-VAS |
| GR context PTE cacheability | Runtime flag mistakes possible | **Enforced `VER3 PTE PCF=0x11` (uncached, aperture 2)** across all 10 GR slots |
| Verification cache | Re-check on every build | **`OMEGA-MEMO` CAS**: `COLD_PROVED` -> bit-exact `MEMO_HIT`, tamper kills (`exit 120`) |
| Spark VFIO state | Probes often write `driver_override` / `reset` | **`gb20b_vfio_probe.om`**: strictly `hw_writes=0`, reports `VFIO_DEVICE_BIND=BLOCKED_HARDWARE` safely |

## Owned Files

- [gb20b_om3_dma.om](gb20b_om3_dma.om) — Strict `om3` GB20B DMA, pre-bootstrap, GMMU `VER3 PTE PCF=0x11` GR context promoter, `SC_PDB(0)` patcher, and RMR/split-VAS runtime verifier; lowers through `om3_aegis` to zero-overhead `om2`.
- [gb20b_vfio_probe.om](gb20b_vfio_probe.om) — Strictly read-only (`hw_writes=0`) pure `om2` Spark audit of `000f:01:00.0` (`10de:2e12`), `IOMMU group 20`, `/dev/vfio/vfio`, `reserved_regions`, and optional `/sys/firmware/acpi/tables/IORT` inspection (plus `--root <prefix>` for hermetic fixture tests).
- [gate_driver_om3.om](gate_driver_om3.om) — Pure seeded `om2` verification gate (zero C, Python, or shell) driving `om3_aegis` (`COLD_PROVED` -> `MEMO_HIT`), `omc-pin` 2x compilation, native lowered execution, 19 negative kills (`13` OM-3 Aegis refusals + `4` lowered GB20B runtime mutants + `OMEGA-MEMO` 1-byte tamper + `vfio_probe` multi-device negative fixture), and positive `vfio_probe` fixture check.
- [Gb20bDriverOm3.lean](../../../seed/helix/proofs/Gb20bDriverOm3.lean) — Machine-checked Lean 4.36.0 proof (`0` warnings, `0` `sorry`, standard axioms `[propext, Classical.choice, Quot.sound]` only) of kernel slab non-mapping, 3-RMR/MSI + GPU VA disjointness, 4-step fence-before-reclaim necessity, 9 MSI-X + `0x008a1d58/5c` flush arming, `SC_PDB(0)` + 10-buffer `PCF=0x11` promotion, plus `19` constructive `by decide` negative controls.
- [RECEIPT.txt](../../../evidence/OM3-GB20B-DRIVER-20261127/RECEIPT.txt) & [SHA256SUMS.txt](../../../evidence/OM3-GB20B-DRIVER-20261127/SHA256SUMS.txt) — Immutable verification receipt and content checksums.

## Verified GB20B Constants Enforced

| Hardware Parameter | Enforced Value | Domain / Guard |
|---|---|---|
| Device / Group | `000f:01:00.0` (`0x10de:0x2e12`), `IOMMU group 20` sole device | Read-only probe verified on Spark |
| Hardware domains | `1=CPU_HOST`, `2=CPU_KERNEL_SLAB`, `3=GPU_DEVICE_DMA`, `4=GPU_PT_GMMU`, `5=MMIO_BAR0`, `6=SHARED_UNCACHED` | Domain 2 non-GPU-mappable |
| PCIe BAR0 | `0x24000000` (size `0x04000000`, `64 MiB`) | `MMIO_BAR0` (Domain 5) |
| Interrupts | `9` MSI-X vectors required before `bootGsp` | Enforced in OM-2 + Lean (`boot_requires_9msix_and_flush`) |
| Sysmem flush buffer | BAR0 `0x008a1d58` (`LO`) / `0x008a1d5c` (`HI`), `256B`-aligned non-RMR PA `< 2^40` | Enforced before `bootGsp` |
| GMMU `vaBase` & GSP carveout | `va >= 0x80000000` (`2 GiB`), `va + len <= 2^40`, disjoint from `[0x100000000, 0x120000000)` (`[4 GiB, 4.5 GiB)`), `4 KiB`-aligned | Enforced static + runtime + Lean |
| ACPI IORT RMR carveouts + MSI | `0xa1600000..0xb97fffff`, `0x280000000..0x2ffffffff`, `0x300000000..0x302ffffff`, `0x08000000..0x080fffff` | Disjointness enforced across all regions + flush PA |
| `SC_PDB(0)` & GR context promote | 10 slots (`MAIN=0`, `PATCH=2`, `PAM=10`, `GCB[0..6]=3..9`), `aperture=2`, **`VER3 PTE PCF=0x11` (`17`)**, one-shot `bInitialize=1` on `PAM`/`GCB[5..6]` | Cached `PCF=0x10` refused (`exit 5`) |

## Build & Verify on AArch64 Host (Spark)

Extract pinned `omc` (`85b84c6de85083e4d9d2368015c1ddcab3d863aada922be0e63d774dddf23134`), build `om3_aegis`, compile `gb20b_vfio_probe` and `gate_driver_om3`, then run the gate, live read-only probe, and Lean 4.36.0 proof:

```sh
(printf 'om2\n'; cat seed/ng/sha256.om seed/ng/memo/memo_policy.om seed/ng/memo/memo_store.om seed/helix/strand5_aegis/om3_aegis.om) | "$OMC" > /tmp/om3_aegis && chmod +x /tmp/om3_aegis
"$OMC" < gpu/driver/om3/gb20b_vfio_probe.om > /tmp/gb20b_vfio_probe && chmod +x /tmp/gb20b_vfio_probe
"$OMC" < gpu/driver/om3/gate_driver_om3.om > /tmp/gate_driver_om3 && chmod +x /tmp/gate_driver_om3
/tmp/gate_driver_om3 /tmp/om3_aegis "$OMC" gpu/driver/om3/gb20b_om3_dma.om /tmp/gb20b_vfio_probe /tmp/om3_gate
/tmp/gb20b_vfio_probe
~/.elan/bin/lean -DwarningAsError=true seed/helix/proofs/Gb20bDriverOm3.lean
shasum -a 256 -c evidence/OM3-GB20B-DRIVER-20261127/SHA256SUMS.txt
```

## Honest Qualification Status

- **Static OM-3 admission & lowered execution:** `HOST-VERIFIED` (`OM3_AEGIS` `COLD_PROVED` + `MEMO_HIT`, bit-exact 2x compilation with pinned `omc`, `GB20B_OM3_DMA PASS`, `19/19` negative kills).
- **Machine-checked Lean 4.36.0 invariants:** `HOST-VERIFIED` (`0` warnings under `-DwarningAsError=true`, `0` `sorry`, standard axioms `[propext, Classical.choice, Quot.sound]` only).
- **Live Spark VFIO/sysfs audit (`000f:01:00.0` UNBOUND):** `READONLY_AUDIT (hw_writes=0)` (`GB20B_VFIO_PROBE PASS`, `VFIO_DEVICE_BIND=BLOCKED_HARDWARE (IORT RMR_NODE idx=50 remap_permitted=0)`).
- **Physical VFIO GPU kernel execution:** `BLOCKED_HARDWARE` on Spark Linux host due to ACPI IORT `RMR_NODE idx=50 remap_permitted=0`; full GPU hardware ownership requires bare-metal `aienux` or platform firmware RMR remap support.
