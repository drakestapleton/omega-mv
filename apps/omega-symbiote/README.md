# 20-Core Grace NEON Symbiote (`apps/omega-symbiote/`)

**Status:** Pure seeded OM-2 + Omega NG (`@ng opt` + `@ng a64`) 20-core Grace CPU engine (`HOST-VERIFIED` on DGX Spark; **Full-APU Grace + GB10 `/dev/nvidia*` co-execution `NOT_RUN` in this lane — serialized separately by coordinator**).

---

## Plain-English Overview

Think of the NVIDIA DGX Spark Grace CPU like a kitchen with **10 head chefs** (`Cortex-X925` cores at `3.90 GHz`: CPUs `5..9, 15..19`) and **10 line cooks** (`Cortex-A725` cores at `2.81 GHz`: CPUs `0..4, 10..14`).

| Mode | How it works | Measured `med9` (`iters=512`, `81,920` floats) | Measured `med5` (`iters=1024`, `81,920` floats) | Bit-exact vs Scalar `omc` |
| --- | --- | --- | --- | --- |
| Scalar OM-2 (`omc`) | 1 core, 1 `f32` element at a time | `166.09 ms` (`166,089,047 ns`) | `339.11 ms` (`339,106,113 ns`) | Reference (`0` bytes diff) |
| `W=1` NEON (`X925 CPU 5`) | 1 pinned core, 4-wide `vec f32 4` NEON (`10 × 8,192` chunks) | `71.70 ms` (`71,699,114 ns`) | `144.30 ms` (`144,298,897 ns`) | `0` bytes diff |
| `W=20` Grace Symbiote | 20 pinned cores (`4,352` per X925, `3,840` per A725) + Arboris prefetch cues | **`10.91 ms`** (`10,906,415 ns`, **`6.57×` vs `W=1`**, **`15.22×` vs Scalar**) | **`42.78 ms`** (`42,780,498 ns`, **`3.37×` vs `W=1`**, **`7.92×` vs Scalar**) | **`0` bytes diff (`0` ULP)** |
| Warm `OMEGA-MEMO` (`OMEM v1`) | Content-addressed disk hit skipping worker compute (`skipped_compute=1`) | **`6.14 ms`** (`6,140,628 ns`) | **`6.14 ms`** (`6,140,323 ns`) | `0` bytes diff |

*(Note: DGX Spark runs `20` online cores with occasional CFS scheduling contention across other active host work (`load avg ~6`), so multi-trial medians `med5` / `med9` capture tail noise honestly while proving consistent multi-core speedup and deterministic `SHA-256` output parity.)*

---

## Pure-Omega Components & Safety Boundaries

1. **`emit_symbiote_ir.om`** — Pure seeded OM-2 binary `ΩIR` (`OSC1IR v9`, `omega.ng.ir.v1`) generator linked with `seed/ng/src/ir.om`.
   - Emits an 8-function native worker kernel over `vec f32 4` 128-bit NEON SIMD (`fma` pipeline, `4` fused multiply-adds per iteration) with constant bounds (`ES_MAX_FLOATS = 8192`, `ES_VEC_LIM = 8189`, `ES_HDR_BYTES = 32`).
   - `@ng opt-count` confirms loop/bounds optimization: `opt fns=8 loops=8 inloop=236->160 phi=0 bce=12 hoisted=66 merged=17 rotated=8 preheaders=0`.
   - `ngcheck` returns `ACCEPT` both before (`048be0ad...`, `ops=367`) and after `@ng opt` (`b41da053...`, `ops=348`).
   - `@ng a64` emits static ELF `symbiote_worker` (`3,264` bytes, `There is no dynamic section in this file.`).

2. **`symbiote_coord.om`** — Pure seeded OM-2 20-core Grace coordinator linked with `apps/omega-wattd/{watt_sense.om, watt_cbf.om}` + `seed/ng/sha256.om` + `seed/ng/memo/{memo_policy.om, memo_store.om}`.
   - **Live 7-zone `WattCBF` (`< 80,000 mW`, `hw_writes=0`):** Reads Spark `/sys/class/thermal/thermal_zone0..6` and CPU frequency sysfs (`thermal_zones=7 cpus=20 tmax_mc=51300..52500 a725_khz=2808000 x925_khz=3900000`) read-only (`hw_writes=0`), refusing real or simulated over-power (`> 80,000 mW`, `rc=66`) or thermal ceiling/floor violations (`t_die >= 85,000 mC` or `< 5,000 mC`, `rc=67`).
   - **OMEGA-MEMO (`OMEM v1`):** Keys `(SYM1-NEON-FMA4-HETEROG-V1 || worker_elf_sha256 || shape/params, input_sha256)`. Cold miss (`MM_MISS`) stores exact `327,680`-byte tensor (`MM_OK`), warm lookup (in-process & cross-process `--memo-expect-hit`) skips compute (`MEMO_HIT`), 1-bit input flip misses (`MM_MISS`), and `.ome` body tamper fails closed (`MM_ERR_TAMPER`, `rc=63`).
   - **Arboris-style prefetch descriptors & weighted cluster split:** Empirical single-core X925 vs A725 ratio on Spark (`14.39 ms` vs `16.73 ms` = `1.16×`) yields balanced `4,352` floats (`68 × 64`) per X925 and `3,840` floats (`60 × 64`) per A725 (`10×4352 + 10×3840 = 81,920` floats), with `stride_f=16` (`64 B` cache line), L2 tile sizes (`2,097,152 B` X925 vs `524,288 B` A725), and `prefetch_ahead=64` floats encoded in the 32-byte worker header.
   - **Pure-OM-2 ELF & `cpuset` hygiene:** Parses ELF64 program headers in pure `.om` to enforce `e_machine == 183` and `pt_dynamic=0`, validates `cpuset` error handling against empty masks (`-22`, `rc=65`), pins workers via `cpuset` + `pipefds` + `dupfd` + `execprog`, and enforces `0`-byte diff against scalar OM-2 `fma`.

3. **`gate_symbiote.om`** — Standalone pure seeded OM-2 harness running `4` positive checks and `9` negative fault-injection controls (`P1..P4` + `N1..N9` -> `GATE_SYMBIOTE PASS pos=4 neg=9`).

---

## Honest Verification Scope

| Domain | Status | Evidence |
| --- | --- | --- |
| 20-Core Grace CPU (`10× X925 + 10× A725`) + NEON `@ng a64` | **Verified on DGX Spark** | `2×` deterministic builds, `readelf -d`, `ngcheck`, `@ng opt-count`, `med5`/`med9`, `4+9` gate in [RECEIPT.txt](../../evidence/ALIEN-GRACE-SYMBIOTE-20261127/RECEIPT.txt). |
| Full-APU Grace + GB10 (`/dev/nvidia*` co-execution) | **`NOT_RUN`** | Explicitly deferred to coordinator-serialized GPU window (`spark-window`). |
| C / Header / Python / Rust / `PT_DYNAMIC` | **Zero (`0`)** | 100% pure seeded `.om`; `readelf -d` confirms no dynamic section on all 4 binaries. |

---

## Clean-Room Build & Verification Commands (DGX Spark AArch64)

```sh
# 1. Extract pinned omc (verify exact SHA-256)
git -C ~/git/omega-mv.git show main:seed/out/omc > /tmp/omc-pin
chmod +x /tmp/omc-pin
sha256sum /tmp/omc-pin
# 85b84c6de85083e4d9d2368015c1ddcab3d863aada922be0e63d774dddf23134

# 2. Build Omega NG tools (ng, ngcheck) from their exact unit manifests
awk '{print $2}' seed/ng/ng.units | xargs cat | /tmp/omc-pin > /tmp/ng
awk '{print $2}' seed/ng/ngcheck.units | xargs cat | /tmp/omc-pin > /tmp/ngcheck
chmod +x /tmp/ng /tmp/ngcheck

# 3. Emit, check, optimize, check, and compile 128-bit NEON worker
cat seed/ng/src/ir.om apps/omega-symbiote/emit_symbiote_ir.om | /tmp/omc-pin > /tmp/emit_symbiote_ir
chmod +x /tmp/emit_symbiote_ir
/tmp/emit_symbiote_ir > /tmp/worker.ir
/tmp/ngcheck < /tmp/worker.ir
{ printf '@ng opt-count\n'; cat /tmp/worker.ir; } | /tmp/ng
{ printf '@ng opt\n'; cat /tmp/worker.ir; } | /tmp/ng > /tmp/worker.opt.ir
/tmp/ngcheck < /tmp/worker.opt.ir
{ printf '@ng a64\n'; cat /tmp/worker.opt.ir; } | /tmp/ng > /tmp/symbiote_worker
chmod +x /tmp/symbiote_worker
readelf -d /tmp/symbiote_worker

# 4. Build coordinator & standalone gate
cat si/directives/om2.om \
    apps/omega-wattd/watt_sense.om \
    apps/omega-wattd/watt_cbf.om \
    seed/ng/sha256.om \
    seed/ng/memo/memo_policy.om \
    seed/ng/memo/memo_store.om \
    apps/omega-symbiote/symbiote_coord.om | /tmp/omc-pin > /tmp/symbiote_coord
/tmp/omc-pin < apps/omega-symbiote/gate_symbiote.om > /tmp/gate_symbiote
chmod +x /tmp/symbiote_coord /tmp/gate_symbiote
readelf -d /tmp/symbiote_coord /tmp/gate_symbiote

# 5. Run standalone gate (4 positive + 9 negative controls) and med9 benchmark
mkdir -p /tmp/symbiote-gate-scratch /tmp/symbiote-memo-b9
/tmp/gate_symbiote /tmp/symbiote_coord /tmp/symbiote_worker /tmp/ngcheck /tmp/worker.opt.ir /tmp/symbiote-gate-scratch
/tmp/symbiote_coord bench --worker /tmp/symbiote_worker --memo-dir /tmp/symbiote-memo-b9 --iters 512 --trials 9
```
