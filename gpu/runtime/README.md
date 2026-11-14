# gpu/runtime: CUDApp `src/` (the C runtime) brought into Omega

CUDApp's `src/` is the runtime behind its CUDA-compatible ABI. Most of it was not written by hand. The Omega Bridge
emitted it from Omega source, and each emitted file has an `.ident` record naming its parts. The rest is hand-written
C and headers. This directory sorts every file of CUDApp `src/` into one of those classes. Hand-written files are
rewritten here in seeded Omega, one slice at a time. No C, Python, shell or assembly is kept here. The old C stays
in CUDApp and serves as the reference (the oracle); it is compiled and run outside this repository.

## What is here

| path | what it is |
| --- | --- |
| `inventory.om` | the inventory program (OM-2): reads the five input lists and prints one row per CUDApp `src/` file |
| `zsha.om` | streaming SHA-256 over a file, on top of `seed/ng/sha256.om` (used by the inventory and the gate) |
| `INVENTORY.tsv` | the inventory's output, committed; the gate requires the program to reproduce it byte for byte |
| `cudapp-src.sha256.txt` | input: `sha256sum` of every file under CUDApp `src/` |
| `cudapp-ident.txt` | input: every CUDApp `src/*.ident` record, concatenated |
| `omega-base.sha256.txt` | input: `sha256sum` of every file under `src/` and `gpu/` of this repository at the base |
| `pathmap.tsv` | input: where a CUDApp Omega path (`om/`, `native/`, ...) lives in this tree |
| `rewrites.tsv` | input: a hand-written CUDApp file and the Omega file here that replaces it |
| `scanref.om` | rewrite of `src/omega_gpu_scan_ref.c` (OM-1): the host scan, prefix sum and radix sort references |
| `check/scanref-check.om`, `check/scanref.expect.txt` | the scanref check program and the old C's output it must match |
| `checks.tsv` | the gate's checks: parts to compose, expected output, and a source mutation that must be caught |
| `controls.tsv` | the gate's inventory controls: an input byte changed, and how the inventory must notice |
| `gate.om` | the gate, OMEGA-GPU-RUNTIME (OM-2) |

The headers of `inventory.om` and `gate.om` define their columns, fields and exit codes.

## The inventory at this base

The last summary line of `INVENTORY.tsv` gives the counts. It is the source; this file does not restate them. Every
file is one of three kinds:

- `record`: an `.ident` file.
- `bridge`: emitted by the Omega Bridge. The row says whether its parts are in this tree and compose to the
  recorded source (`same`), compose to something else (`changed`), or are missing here (`absent`).
- `hand`: written by hand. The row says whether it has been `rewritten` (with the Omega path), or `none`.

To list the hand files that are not yet rewritten:

    awk -F'\t' '$4=="hand" && $5=="none"' gpu/runtime/INVENTORY.tsv

## Regenerating the inputs

Run these from a directory that holds a CUDApp checkout `cudapp/` at the source commit and this repository
`omega-mv/`. The inventory at this base used CUDApp `84b524cadaaa8bc9b556adfaea9d6dd2e0d67a66` and omega-mv base
`f7a068ec54d67ccad504cf5e5887376916158b7b`. All three commands were checked to reproduce the committed files byte
for byte.

    (cd cudapp && find src -type f | LC_ALL=C sort | xargs sha256sum) > omega-mv/gpu/runtime/cudapp-src.sha256.txt
    (cd cudapp && find src -name '*.ident' -type f | LC_ALL=C sort | xargs cat) > omega-mv/gpu/runtime/cudapp-ident.txt
    (cd omega-mv && git ls-tree -r --name-only BASE src gpu | LC_ALL=C sort | xargs sha256sum) > omega-mv/gpu/runtime/omega-base.sha256.txt

Then rebuild the inventory and write its output:

    { printf 'om2\n'; cat seed/ng/sha256.om gpu/runtime/zsha.om gpu/runtime/inventory.om; } | seed/out/omc > inventory
    ./inventory > gpu/runtime/INVENTORY.tsv

The inventory refuses to run (exit 3) when a Bridge source part in this tree differs from `omega-base.sha256.txt`.
When that happens, the list is stale: regenerate it.

## The scanref oracle

`check/scanref.expect.txt` is the output of the old C. It was produced by a driver kept outside this repository
(`scanref_driver.c`, sha256 `0861c617842414d024db4ae95de0d45fb8f0cd74ca8037c43940d6aedb3b6fa7`). The driver was built
against CUDApp `84b524ca` `src/`:

    cc -std=c11 -O1 -ffp-contract=off -Icudapp/src scanref_driver.c cudapp/src/omega_gpu_scan_ref.c \
       cudapp/src/cudapp_om_av_scan.c cudapp/src/cudapp_om_ar_carry.c -lm -o scanref_oracle
    ./scanref_oracle > scanref.expect.txt

The Omega check prints the same 25 lines, built from the same inputs in the same order. The C was compiled and run
only to produce that file; it is not part of this repository.

## The gate

    tests/gates/run.sh gpu-runtime

Or, by hand, from the repository root:

    { printf 'om2\n'; cat seed/ng/sha256.om gpu/runtime/zsha.om gpu/runtime/gate.om; } | seed/out/omc > gate
    ./gate seed/out/omc SCRATCH        # SCRATCH must not exist yet

The gate takes these steps:

1. It checks the compiler against `seed/out/omc.sha256`.
2. It runs each row of `checks.tsv`: compose the parts, compile, run, and compare the output with the expected file.
   It then applies the row's mutation, which must change the output or the exit status.
3. It reruns the inventory on an unchanged copy of its inputs, which must reproduce `INVENTORY.tsv`.
4. It runs each row of `controls.tsv`, each on a copy with one byte changed.
5. It checks that a compiler one byte longer is refused.

Its last line is `OMEGA-GPU-RUNTIME PASS|FAIL checks=N controls=C caught=K hardware=NOT_RUN`. A PASS needs at least
one check, no FAIL line, and K equal to C.

A new rewrite slice adds four things:

- the Omega file;
- its check program and the oracle's output;
- one row in `checks.tsv`;
- one row in `rewrites.tsv`.

It then regenerates `INVENTORY.tsv`.

Hardware: none of this opens a device. The runtime's device paths have not run on hardware from this tree; every
hardware tier is NOT_RUN.
