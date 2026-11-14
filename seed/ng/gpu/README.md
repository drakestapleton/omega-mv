# seed/ng/gpu: the sm_121 path of Omega NG (Hive NG lane ng-gpu)

Omega NG's GPU stage turns ΩIR kernel functions into sm_121 machine code and launches it. It consumes the seeded
units `gpu/nvidia/om/encoder/bw_enc_sm121.om`, `gpu/nvidia/om/components/bw_alloc.om` and
`gpu/nvidia/om/cubin/cubin_elf.om` (with `gpu/nvidia/native/blackwell/launch.om` and `gpu/nvidia/native/nvrm/context.om`
also pinned). They came from aien-dev/CUDApp at the commit in `seed/ng/cudapp.lock` (1988c50e) with their history, per
ADR 0047 (aien-architecture-mv; the GPU layer of Sovereign Intelligence moves into this repository); before that, Hive
NG decision D10 consumed them from a sibling `../CUDApp` checkout. `seed/ng/cudapp.lock` keeps its bytes: its five
digest rows are the identities the `lock-*` cases check against the files in `gpu/nvidia/`. ng-gpu's own code is
`seed/ng/src/gpu.om` (functions `gp_`, globals `g_`), which does not exist yet: it waits for ng-ir's ΩIR kernel form.

What is here today: the conformance gate of the encoder ng consumes.

| File | Role |
|---|---|
| `encrun.om` | Program-mode harness composed after the pinned encoder: NGBWENC1 frames in, result frames out (format in its header). |
| `pinsum.om` | SHA-256 filter (stdin to 64 hex digits and a newline), composed after the plain-function form of `om/sha256/sha256-om2.om`; the lock-* cases use it. |
| `gate.cases` | Case list for `seed/qualification/om2/gate.om`: 6 lock pins, compiled-bytes pin of the encoder, 4 fixture sets, 3 refusals, 4 mutants. |
| `tests/golden.*` | 145 single-instruction encodes of CUDApp's golden fixtures (140 accepted, 5 refused). |
| `tests/dump.*` | 14 fixture programs of CUDApp's codegen dump. |
| `tests/slice.*` | 52 frames (every 64th of 3265, plus the last) of CUDApp's sm121dis corpus producers. |
| `tests/ldg.*` | The bw_hazard_test program (310 insns) with two LDG.E +0x40 loads (CUDApp#373). |
| `tests/badmagic.*`, `tests/trunc.*` | Malformed input: exit 2 / exit 3 with one stderr line. |
| `tests/m1..m4.{from,to}` | Encoder mutants, applied by `subst`: CUDApp mk/om-encoder.mk OM_ENC_MUTANTS 1..3 and OM_ENC_LDG_RED's first edit (the pre-fix LDG.E line). |

Run from the repository root (no CUDApp checkout is needed):

    seed/out/omc < seed/qualification/om2/gate.om > /tmp/gate && chmod +x /tmp/gate
    /tmp/gate seed/out/omc "$(cut -c1-64 seed/out/omc.sha256)" seed/ng/gpu/gate.cases /tmp/ng-gpu-gate

Final line `OM2GATE PASS cases=18 pass=18 ...`.

The lock is enforced by the gate: the `lock-*` run cases hash each file ng composes from `gpu/nvidia/` (the five rows
of `seed/ng/cudapp.lock`) and the lock file itself with `pinsum.om` and compare the digest with the pinned one. A
different file makes its case FAIL and the gate exit 1, naming the row; a missing file is INVALID (exit 3). A wrong
file is FAIL rather than INVALID because the shared `seed/qualification/om2/gate.om` has no input-identity case
kind; adding one is a separate proposal for the OM-2 owner (the gate's binary hash is replayed by historical
records such as security673/relational). A lock edit needs the matching `lock-*` rows in gate.cases.

## Fixture provenance
Inputs were captured from CUDApp's real C builders (`tests/test_omega_codegen_freestanding.c --golden/--dump` and
`tools/sm121dis/corpus.sh` producers, CUDApp b774723f) through a link-time wrap of `omega_bw_enc_sm121` that appends
each call's arguments and result to a file. The wrap and the C-oracle replayer are referee instruments, kept outside
every repository (history: CUDApp `b056bf7e:evidence/ldg-offset-20261107/{ngcap.c,encref.c}`; removed from CUDApp at
its desk review; on the Spark at `~/handoffs/hive-ng/gpu/evidence/ldg-offset-20261107-instruments/`); nothing here
builds or runs C. Expected
outputs: golden and dump are the bytes on which CUDApp's `.om` encoder and its C oracle agreed; slice and ldg are the C
oracle's bytes, which the pinned `.om` encoder reproduces and CUDApp b774723f's (before #373) does not (LDG.E offset defect).

## Status
HOST_TESTED (Linux AArch64, core 1): 18/18 PASS with CUDApp at the lock commit 1988c50e; with CUDApp 1818e9d2 (only
bw_alloc.om differs) lock-bw_alloc FAILs and the gate exits 1; against CUDApp b774723f's encoder (before #373) the
pin, slice and ldg cases FAIL as well. No GPU involved. After the move to `gpu/nvidia/` (2026-11-14) the same 18 cases,
with the same digests and goldens, run against the in-tree files; see `gpu/nvidia/README.md`. Later that day the
encoder and `cubin_elf.om` were replaced by CUDApp 84b524ca's bytes (the lock's comment says which rows): the lock
rows, `lock-self` and `enc-pin` were re-pinned, the goldens, refusals and mutants are unchanged, and 18/18 pass.
