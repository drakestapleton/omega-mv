# gfx942 cache-policy encodings

The bytes below were produced on this tree by:

```
llvm-mc-18 -triple=amdgcn -mcpu=gfx942 -show-encoding
```

Ubuntu LLVM 18.1.3. `check.sh` requires those bytes, the `.text` of
`llvm-mc-18 -filetype=obj`, the `.text` `gpu/amd/gfx942/hsaco.om` packs from the
`.isa`, and the committed `.golden` file to be identical. Bit positions are the
positions that reproduce these bytes. They are not taken from a chat claim.

CDNA3 ISA §10.1 Table 53 names the FLAT/GLOBAL fields and their widths (OP 7,
ADDR 8, DATA 8, VDST 8, SC 2, NT 1, ACC 1, SEG 2, SVE 1, OFFSET 13, SADDR 7 with
0x7F meaning off). §9.1.2 Table 40 does the same for MUBUF (OP 7, OFFSET 12,
OFFEN 1, IDXEN 1, SC0 1, NT 1, ACC 1, SC1 1, LDS 1, VADDR 8, VDATA 8, SRSRC 5,
SOFFSET 8). Neither table, in the text of the "AMD Instinct MI300" ISA, prints a
bit number. The order of names in Table 40 is not the order of the bits.

## GLOBAL word, from the bytes

`global_load_dwordx4 v[0:3], v[0:1], off` is `00 80 5c dc 00 00 7f 00`.
XOR against the sc0, nt and sc1 variants puts the flags here:

| field | bits | evidence |
| --- | --- | --- |
| OFFSET | 12:0 | `offset:16` changes byte 0 from `00` to `10` |
| SC0 | 16 | sc0 sets byte 2 from `5c` to `5d` |
| NT | 17 | nt sets byte 2 from `5c` to `5e` |
| OP | 24:18 | dwordx4 is 23 (`5c` with the flags clear) |
| SC1 | 25 | sc1 sets byte 3 from `dc` to `de` |
| encoding | 31:26 | `0x37`, the FLAT encoding |

Word 1 is VADDR, VDATA, SADDR (7 bits, `0x7f` is off), then VDST. `s[0:1]` as
the scalar base is SADDR 0, so the plain saddr form is `00 80 5c dc 00 00 00 00`.

| instruction | bytes |
| --- | --- |
| global_load_dwordx4 v[0:3], v[0:1], off | `00 80 5c dc 00 00 7f 00` |
| same sc0 | `00 80 5d dc 00 00 7f 00` |
| same sc1 | `00 80 5c de 00 00 7f 00` |
| same nt | `00 80 5e dc 00 00 7f 00` |
| same sc0 sc1 | `00 80 5d de 00 00 7f 00` |
| same sc0 nt | `00 80 5f dc 00 00 7f 00` |
| same nt sc1 | `00 80 5e de 00 00 7f 00` |
| same sc0 nt sc1 | `00 80 5f de 00 00 7f 00` |
| global_load_dwordx4 v[0:3], v0, s[0:1] | `00 80 5c dc 00 00 00 00` |
| same nt | `00 80 5e dc 00 00 00 00` |
| global_load_dwordx4 v[4:7], v1, s[2:3] offset:16 | `10 80 5c dc 01 00 02 04` |
| same nt | `10 80 5e dc 01 00 02 04` |

SC1 is bit 25. It is not bit 55. Bit 55 is outside this 64-bit instruction.
ACC is the bit Table 53 gives a width of 1; in these encodings it stays 0.

The kernel's weight load is the saddr form with nt and no sc bit. `llvm-objdump`
of the assembled kernel prints it as `DC5E8000 08160002`, which is the bytes
`00 80 5e dc 02 00 16 08`. Activation loads are the same opcode with nt clear.
The tail, the scale load and the stores are in the kernel golden, not in the
probe. From that object:

| instruction in the kernel | bytes |
| --- | --- |
| global_load_dwordx4 v[8:11], v2, s[22:23] nt | `00 80 5e dc 02 00 16 08` |
| global_load_ubyte v10, v[8:9], off nt | `00 80 42 dc 08 00 7f 0a` |
| global_load_dword v11, v[8:9], off | `00 80 50 dc 08 00 7f 0b` |
| global_store_short v[8:9], v5, off | `00 80 68 dc 08 05 7f 00` |
| global_store_dword v[8:9], v4, off | `00 80 70 dc 08 04 7f 00` |

## MUBUF word, from the bytes

`buffer_load_dwordx4 v[0:3], v0, s[0:3], 0 offen` is `00 10 5c e0 00 00 00 80`.

| field | bits | evidence |
| --- | --- | --- |
| OFFSET | 11:0 | these rows use 0 |
| OFFEN | 12 | the `10` in byte 1 |
| SC0 | 14 | sc0 sets byte 1 from `10` to `50` |
| SC1 | 15 | sc1 sets byte 1 from `10` to `90` |
| NT | 17 | nt sets byte 2 from `5c` to `5e` |
| OP | 24:18 | load dwordx4 is 23; WBL2 is 40; INV is 41 |
| encoding | 31:26 | `0x38` |

Word 1 is VADDR, VDATA, SRSRC (SGPR/4), SOFFSET. The inline constant 0 in the
soffset operand is `0x80` in byte 7. `buffer_wbl2` and `buffer_inv` use soffset 0
in the encoding (`00` in byte 7), which is what `llvm-mc` emits for the forms
with no soffset operand.

| instruction | bytes |
| --- | --- |
| buffer_load_dwordx4 offen | `00 10 5c e0 00 00 00 80` |
| sc0 | `00 50 5c e0 00 00 00 80` |
| sc1 | `00 90 5c e0 00 00 00 80` |
| nt | `00 10 5e e0 00 00 00 80` |
| sc0 sc1 | `00 d0 5c e0 00 00 00 80` |
| sc0 nt | `00 50 5e e0 00 00 00 80` |
| nt sc1 | `00 90 5e e0 00 00 00 80` |
| sc0 nt sc1 | `00 d0 5e e0 00 00 00 80` |
| buffer_wbl2 | `00 00 a0 e0 00 00 00 00` |
| buffer_wbl2 sc0 | `00 40 a0 e0 00 00 00 00` |
| buffer_wbl2 sc1 | `00 80 a0 e0 00 00 00 00` |
| buffer_wbl2 sc0 sc1 | `00 c0 a0 e0 00 00 00 00` |
| buffer_inv | `00 00 a4 e0 00 00 00 00` |
| buffer_inv sc0 | `00 40 a4 e0 00 00 00 00` |
| buffer_inv sc1 | `00 80 a4 e0 00 00 00 00` |
| buffer_inv sc0 sc1 | `00 c0 a4 e0 00 00 00 00` |

## Atomics

ISA §9.1.10.2: for vector atomics, SC0 is "return the pre-op value" (0 no, 1 yes),
SC1 is 0 device / 1 system, and NT is 0 last-level allocate / 1 no allocate.
That is a different meaning of SC0 from the load/store scope tables.

`llvm-mc` rejects `global_atomic_add` on the `v[addr]` form unless sc0 is set,
and rejects sc0 on the `s[addr]` form. The probe records only the forms it accepts.

| instruction | bytes |
| --- | --- |
| global_atomic_add v0, v[0:1], v2, off sc0 | `00 80 09 dd 00 02 7f 00` |
| sc0 sc1 | `00 80 09 df 00 02 7f 00` |
| sc0 nt | `00 80 0b dd 00 02 7f 00` |
| sc0 nt sc1 | `00 80 0b df 00 02 7f 00` |
| global_atomic_add v4, v2, s[6:7] | `00 80 08 dd 04 02 06 00` |
| sc1 | `00 80 08 df 04 02 06 00` |
| nt | `00 80 0a dd 04 02 06 00` |
| nt sc1 | `00 80 0a df 04 02 06 00` |

On the saddr form the first vector operand is the address (`v4` → VADDR 4) and
the second is the data (`v2` → VDATA 2). SC1 is again bit 25 (`dc` vs `df` in
the high byte of word 0: `dd` vs `df`).

## What the bits do to L2 and the last-level cache

ISA §9.1.10.2, Table 48 (loads). SC[1:0] is 0 wave, 1 group, 2 device, 3 system.
NT 0 is temporal, 1 is non-temporal. The table's third cache column is headed
"Last-level Cache", not MALL.

| scope | SC1 | SC0 | NT | CU | L2 | last-level |
| --- | --- | --- | --- | --- | --- | --- |
| wave | 0 | 0 | 0 | Hit LRU | Hit LRU | Hit LRU |
| wave | 0 | 0 | 1 | Miss Evict | Hit Stream | Hit Evict |
| group | 0 | 1 | 0 | Hit LRU | Hit LRU | Hit Evict |
| group | 0 | 1 | 1 | Miss Evict | Hit Stream | Hit Evict |
| device | 1 | 0 | 0 | Miss Evict | Hit LRU if 1 L2, else coherent bypass | Hit LRU |
| device | 1 | 0 | 1 | Miss Evict | Hit Stream if 1 L2, else coherent bypass | Hit Evict |
| system | 1 | 1 | 0 | Miss Evict | coherent bypass | Hit LRU |
| system | 1 | 1 | 1 | Miss Evict | coherent bypass | Hit Evict |

The table's note: if TG_SPLIT is active, the group + NT=0 row becomes Miss LRU,
Hit LRU, Hit LRU. Table 49 is the store table; wave + NT=0 is CU Miss LRU rather
than Hit LRU. "No Allocate" is stated for atomic NT, not for a Table 48 load.
Hit Stream and Hit Evict are the table's names; the text does not define them
further.

Table 50, BUFFER_WBL2: SC1=0 is a NOP for either SC0. SC1=1 and SC0=0 writebacks
dirty L2 only when there is more than one L2, otherwise NOP. SC1=1 and SC0=1
writebacks dirty data.

Table 51, BUFFER_INV: SC=00 is NOP. SC0=1 and SC1=0 invalidates the CU cache only
if TG split. SC1=1 and SC0=0 invalidates the CU cache, and invalidates
non-coherent L2 lines only when there is more than one L2. Both bits invalidate
the CU cache and the non-coherent L2 lines.

## What LLVM emits on GFX942

LLVM's user guide, "AMDHSA Memory Model Code Sequences GFX942"
(<https://llvm.org/docs/AMDGPUUsage.html>), as fetched for this change:

- A non-volatile nontemporal load is `buffer/global/flat_load nt=1`. No sc0, no sc1.
- A non-volatile nontemporal store on GFX942 is `buffer/global/flat_store nt=1`.
- A volatile load or store is `sc0=1 sc1=1` plus `s_waitcnt vmcnt(0)`.
- Monotonic load: wave none, workgroup `sc0=1`, agent `sc1=1`, system `sc0=1 sc1=1`.
  Stores follow the same pattern.
- Acquire load, agent, global: `buffer/global_load sc1=1`, `s_waitcnt vmcnt(0)`,
  `buffer_inv sc1=1`.
- Acquire load, system, global: `buffer/global/flat_load sc0=1 sc1=1`,
  `s_waitcnt vmcnt(0)`, `buffer_inv sc0=1 sc1=1`.
- Release store, agent: `buffer_wbl2 sc1=1`, then the waits, then
  `buffer/global/flat_store sc1=1`.
- Release store, system: `buffer_wbl2 sc0=1 sc1=1`, then the waits, then
  `buffer/global/flat_store sc0=1 sc1=1`.
- Release atomicrmw, agent: `buffer_wbl2 sc1=1`, then the waits, then
  `buffer/global/flat_atomic sc1=1`.
- Release atomicrmw, system: `buffer_wbl2 sc0=1 sc1=1`, then the waits, then
  `buffer/global/flat_atomic sc0=1 sc1=1`.

The system release atomic sets sc0. On an atomic, ISA §9.1.10.2 defines that bit
as "return the pre-op value", not as a scope bit. The scope bit on an atomic is
SC1. The probe keeps both facts: the bytes LLVM's assembler emits, and the ISA's
definition of the bit.

## Policy used for the weight loads

Weight loads are read once per token and must not be the lines that push
activations out of cache. The kernel sets **nt=1, sc0=0, sc1=0** on those loads
only. That is the GFX942 nontemporal load LLVM emits, and it is Table 48's wave
+ NT row: CU Miss Evict, L2 Hit Stream, last-level Hit Evict.

A device-scope load (sc1=1, sc0=0) is a different policy. With more than one L2
it coherent-bypasses L2. That is not what the GFX942 nontemporal row emits, and
it is not what the weight loads use. Activation, scale, residual, gamma and
output traffic leave every sc/nt bit clear: Table 48 wave + temporal, Hit LRU at
each level named in the table.

The kernel does not emit `buffer_wbl2` or `buffer_inv`. Those encodings are in
`encprobe` so the writer cannot drift, and so the acquire/release sequences
above have a byte to point at. They are not part of the GEMV.
