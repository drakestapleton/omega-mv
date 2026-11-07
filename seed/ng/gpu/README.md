# seed/ng/gpu: the sm_121 path of Omega NG (Hive NG lane ng-gpu)

Omega NG's GPU stage turns ΩIR kernel functions into sm_121 machine code and launches it. Per Hive NG decision D10 it
does not copy CUDApp's seeded units: it consumes `om/encoder/bw_enc_sm121.om`, `om/components/bw_alloc.om` and
`om/cubin/cubin_elf.om` from aien-dev/CUDApp at the commit pinned in `seed/ng/cudapp.lock`, checked out as the sibling
directory `../CUDApp`. ng-gpu's own code is `seed/ng/src/gpu.om` (functions `gp_`, globals `g_`), which does not
exist yet: it waits for ng-ir's ΩIR kernel form.

What is here today: the conformance gate of the encoder ng consumes.

| File | Role |
|---|---|
| `encrun.om` | Program-mode harness composed after the pinned encoder: NGBWENC1 frames in, result frames out (format in its header). |
| `gate.cases` | Case list for `seed/qualification/om2/gate.om`: compiled-bytes pin of the encoder, 4 fixture sets, 3 refusals, 4 mutants. |
| `tests/golden.*` | 145 single-instruction encodes of CUDApp's golden fixtures (140 accepted, 5 refused). |
| `tests/dump.*` | 14 fixture programs of CUDApp's codegen dump. |
| `tests/slice.*` | 52 frames (every 64th of 3265, plus the last) of CUDApp's sm121dis corpus producers. |
| `tests/ldg.*` | The bw_hazard_test program (310 insns) with two LDG.E +0x40 loads (CUDApp#373). |
| `tests/badmagic.*`, `tests/trunc.*` | Malformed input: exit 2 / exit 3 with one stderr line. |
| `tests/m1..m4.{from,to}` | Encoder mutants (CUDApp mk/om-encoder.mk OM_ENC_MUTANTS 1..4), applied by `subst`. |

Run from the repository root, with CUDApp at the lock's commit in `../CUDApp`:

    seed/out/omc < seed/qualification/om2/gate.om > /tmp/gate && chmod +x /tmp/gate
    /tmp/gate seed/out/omc "$(cut -c1-64 seed/out/omc.sha256)" seed/ng/gpu/gate.cases /tmp/ng-gpu-gate

Final line `OM2GATE PASS cases=12 pass=12 ...`.

## Fixture provenance
Inputs were captured from CUDApp's real C builders (`tests/test_omega_codegen_freestanding.c --golden/--dump` and
`tools/sm121dis/corpus.sh` producers, CUDApp b774723f) through a link-time wrap of `omega_bw_enc_sm121` that appends
each call's arguments and result to a file. The wrap and the C-oracle replayer are referee instruments, kept outside
this repository (CUDApp `evidence/ldg-offset-20261107/ngcap.c`, `encref.c`); nothing here builds or runs C. Expected
outputs: golden and dump are the bytes on which CUDApp's `.om` encoder and its C oracle agreed; slice and ldg are the C
oracle's bytes, which the pinned `.om` encoder reproduces and CUDApp main b774723f's does not (LDG.E offset defect).

## Status
HOST_TESTED (Linux AArch64): 12/12 PASS against the pinned encoder; against CUDApp main b774723f's encoder the pin,
slice and ldg cases FAIL, as they must. No GPU involved.
