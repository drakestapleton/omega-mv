# gpu/runtime: the inventory of CUDApp `src/` (the C runtime) and its Omega rewrites so far

CUDApp's `src/` is the runtime behind its CUDA-compatible ABI. Most of it was not written by hand. The Omega Bridge
emitted it from Omega source, and each emitted file has an `.ident` record naming its parts. No `.ident` record names
the rest: hand-written C and headers, plus files that other CUDApp generators wrote without one. This directory
sorts every file of CUDApp `src/` into those classes. This is one slice of that work, not the move of `src/`: the
files without a record that are rewritten here so far are listed in `rewrites.tsv` (`INVENTORY.tsv` counts them and
the rest), and the others follow one slice at a time. No C, Python, shell or assembly is kept here. The old C stays
in CUDApp and serves as the reference (the oracle); it is compiled and run outside this repository.

## What is here

| path | what it is |
| --- | --- |
| `inventory.om` | the inventory program (OM-2): reads the input lists below and prints one row per CUDApp `src/` file |
| `zsha.om` | streaming SHA-256 over a file, on top of `seed/ng/sha256.om` (used by the inventory and the gate) |
| `INVENTORY.tsv` | the inventory's output, committed; the gate requires the program to reproduce it byte for byte |
| `cudapp-src.sha256.txt` | input: `sha256sum` of every file under CUDApp `src/` |
| `cudapp-ident.txt` | input: every CUDApp `src/*.ident` record, concatenated |
| `omega-base.sha256.txt` | input: `sha256sum` of every file under `src/` and `gpu/` of this repository at the base |
| `pathmap.tsv` | input: where a CUDApp Omega path (`om/`, `native/`, ...) lives in this tree |
| `rewrites.tsv` | input: a CUDApp file without a record and the Omega file here that replaces it |
| `scanref.om` | rewrite of CUDApp's `src/omega_gpu_scan_ref.c` (OM-1): the host scan, prefix sum and radix sort references |
| `check/scanref-check.om`, `check/scanref.expect.txt` | the scanref check program and the old C's output it must match |
| `checks.tsv` | the gate's checks: parts to compose, expected output, and a source mutation that must be caught |
| `controls.tsv` | the gate's inventory controls: an input byte changed, and how the inventory must notice |
| `gate.om` | the gate, OMEGA-GPU-RUNTIME (OM-2) |
| `cfacts.om`, `cfacts-main.om` | the C facts scanner (OM-2) and its program: per C file of CUDApp `src/`, the lines a default build compiles, the lines kept only behind a pending flag, and the lines of functions that hand work to Omega, call the chip or the operating system, or do host logic |
| `devwords.txt` | input of `cfacts.om`: the call names that reach the GPU, the driver or the operating system |
| `cudapp-cfacts.tsv` | the output of `cfacts-main.om` on CUDApp at the source commit, committed (CUDApp is not in this tree, so the gate cannot rerun it) |
| `check/cfacts-check.om`, `check/cfacts-fixture-*.txt`, `check/cfacts-fixture.sha256.txt`, `check/cfacts.expect.txt` | the gate's check of `cfacts.om`: two test inputs of C text (data, never compiled) and the facts they must give |
| `classes.om` | the classes program (OM-2): reads `INVENTORY.tsv` and `cudapp-cfacts.tsv` and gives each unrecorded file a class |
| `CLASSES.tsv` | the output of `classes.om`, committed; the gate requires the program to reproduce it byte for byte |

The headers of `inventory.om` and `gate.om` define their columns, fields and exit codes.

## The inventory at this base

The last summary lines of `INVENTORY.tsv` give the counts. They are the source; this file does not restate them.
Every file has one of these origins:

- `record`: an `.ident` file.
- `bridge`: emitted by the Omega Bridge. The row says whether its parts are in this tree and compose to the
  recorded source (`same`), compose to something else (`changed`), or are missing here (`absent`).
- `unrecorded`: no `.ident` record names it. The row says whether it has been `rewritten` (with the Omega path), or
  `none`. Not all of them were written by hand. For example, CUDApp `om/native-freest.sh` generates
  `src/cudapp_freest_pathcopy.c` from `om/components/pathcopy.om` (here `gpu/nvidia/om/components/pathcopy.om`),
  and CUDApp `om/units.sh` generates `src/cudapp_native.h`. Neither writes a record, so both are `unrecorded`. The
  inventory cannot tell these apart from hand-written files, because it reads only the lists, never CUDApp's files.

To list the unrecorded files that are not yet rewritten:

    awk -F'\t' '$4=="unrecorded" && $5=="none"' gpu/runtime/INVENTORY.tsv

The `omega_src` column compares each CUDApp path with the file of the same path in this repository's base list
(`identical`, `diverged` or `cudapp-only`). This repository's own `src/` holds older copies of many CUDApp files.
`scanref.om` replaces CUDApp's `src/omega_gpu_scan_ref.c`, the oracle below. It does not replace this repository's
own `src/omega_gpu_scan_ref.c`, which is one of those older copies (`diverged` from CUDApp's) and stays as it is.

## Regenerating the inputs

Run these from a directory that holds a CUDApp checkout `cudapp/` at the source commit and this repository
`omega-mv/` (`BASE` is the base commit of this repository):

    (cd cudapp && find src -type f | LC_ALL=C sort | xargs sha256sum) > omega-mv/gpu/runtime/cudapp-src.sha256.txt
    (cd cudapp && find src -name '*.ident' -type f | LC_ALL=C sort | xargs cat) > omega-mv/gpu/runtime/cudapp-ident.txt
    (cd omega-mv && git ls-tree -r --name-only BASE src gpu | LC_ALL=C sort | xargs sha256sum) > omega-mv/gpu/runtime/omega-base.sha256.txt

The committed lists came from CUDApp `84b524cadaaa8bc9b556adfaea9d6dd2e0d67a66` and omega-mv base
`f7a068ec54d67ccad504cf5e5887376916158b7b`. That is recorded here only. The lists themselves carry no commit, and
the gate cannot check the CUDApp commit, because CUDApp is not in this repository.

Then rebuild the inventory and write its output:

    { printf 'om2\n'; cat seed/ng/sha256.om gpu/runtime/zsha.om gpu/runtime/inventory.om; } | seed/out/omc > inventory
    ./inventory > gpu/runtime/INVENTORY.tsv

The inventory hashes the files of this tree that it names, and it refuses to run (exit 3) when any of them no longer
matches `omega-base.sha256.txt`. That covers every Bridge source part and every file at a CUDApp path (`identical`
or `diverged`). It also refuses when a `cudapp-only` path now exists in the tree. When that happens, the list is
stale: regenerate it.

## What blocks each unrecorded file

`CLASSES.tsv` has one row per `unrecorded` file of `INVENTORY.tsv`, with a class that says what stands between it
and an Omega rewrite: `r` rewritten; `c` a generator wrote it; `d` C kept only behind a pending flag, as a reference;
`b` a C entry point over Omega or over the chip; `a` C host logic that a rewrite can be checked against now. The
header of `classes.om` gives the exact rule, and the header of `cfacts.om` the facts it is applied to. The last lines
of `CLASSES.tsv` give the counts; this file does not restate them.

A class `b` file is waiting for Omega to produce a library that C can call: its functions are thin C over an Omega
unit or over a device call. A class `d` file holds bodies that a default build drops. A default build is CUDApp's
Makefile build: every `CUDAPP_MIGRATION_PENDING_*` flag is 0 or undefined there, so is `OMEGA_GPU_NO_POSIX` (the
freestanding build, which keeps C where it cannot call Omega yet), and so is every name a file defines only under
one of them (for example a `*_C_PRIMARY` name). CUDApp keeps those bodies as the old implementation to compare
against.

To list the files a rewrite can start on, with their host-logic lines:

    awk -F'\t' '$3=="a"{print $10, $1}' gpu/runtime/CLASSES.tsv | sort -n

`cudapp-cfacts.tsv` is regenerated from a CUDApp checkout `../cudapp` at the commit of `cudapp-src.sha256.txt`:

    { printf 'om2\n'; cat seed/ng/sha256.om gpu/runtime/zsha.om gpu/runtime/cfacts.om gpu/runtime/cfacts-main.om; } \
      | seed/out/omc > cfacts
    ./cfacts ../cudapp > gpu/runtime/cudapp-cfacts.tsv
    { printf 'om2\n'; cat gpu/runtime/classes.om; } | seed/out/omc > classes
    ./classes > gpu/runtime/CLASSES.tsv

The committed `cudapp-cfacts.tsv` has sha256 `b013c30574aa4fc42cc467a94431d3757ece00c291dc553e015b15fc32dce407`.
The lane that wrote this slice also wrote the same rules separately, outside this repository, as a reference
program in Python (`cfacts_ref.py`, sha256 `0dcd595e9d12362370c8a18cfcf73ecc1dc8794a23d72fe387b2808abb51f596`), and
its output on CUDApp was byte for byte the same file. On the two test inputs it gives `check/cfacts.expect.txt`.

## The scanref oracle

`check/scanref.expect.txt` is the output of the old C. A driver kept outside this repository by the lane that wrote
this slice produced it, and its sha256 is its identity:

- `scanref_driver.c`: sha256 `0861c617842414d024db4ae95de0d45fb8f0cd74ca8037c43940d6aedb3b6fa7`.
- its output: byte for byte `check/scanref.expect.txt`, sha256
  `554788ac49ceb590feec937dc223a9befd15ef6ba4488936395b589d5e7a9958`.

The driver was built against CUDApp `src/` at the commit above:

    cc -std=c11 -O1 -ffp-contract=off -Icudapp/src scanref_driver.c cudapp/src/omega_gpu_scan_ref.c \
       cudapp/src/cudapp_om_av_scan.c cudapp/src/cudapp_om_ar_carry.c -lm -o scanref_oracle
    ./scanref_oracle > scanref.expect.txt

The Omega check prints the same lines, built from the same inputs in the same order. The C was compiled and run
only to produce that file; it is not part of this repository.

The oracle and the check share code. `cudapp_om_av_scan.c` and `cudapp_om_ar_carry.c` are Bridge output of
`scan.om` and `scancarry.om`, and the check composes `gpu/nvidia/om/apiviews/scan.om` itself. So the comparison
proves the rewritten driver logic only: levels, carries, the radix passes and the handling of bad arguments. It does
not independently check the 32-wide tile scan, which both sides take from the same Omega source.

## The gate

    tests/gates/run.sh gpu-runtime

Or, by hand, from the repository root:

    { printf 'om2\n'; cat seed/ng/sha256.om gpu/runtime/zsha.om gpu/runtime/gate.om; } | seed/out/omc > gate
    ./gate seed/out/omc SCRATCH        # SCRATCH must not exist yet

The gate takes these steps:

1. It checks the compiler against `seed/out/omc.sha256`.
2. It runs each row of `checks.tsv`: compose the parts, compile, run, and compare the output with the expected file.
   It then applies the row's mutation, which must change the output or the exit status.
3. It checks that each `rewrites.tsv` row's Omega file is one of the parts of some check row. As a control, a path
   that is only a prefix of that Omega file must not match.
4. It reruns the inventory on an unchanged copy of its inputs, which must reproduce `INVENTORY.tsv`.
5. It runs each row of `controls.tsv`, each on a copy with one byte changed.
6. It checks that a compiler one byte longer is refused.

Its last line is `OMEGA-GPU-RUNTIME PASS|FAIL checks=N controls=C caught=K hardware=NOT_RUN`. A PASS needs at least
one check, no FAIL line, and K equal to C.

Names and table rows have no length limit of the gate's own; its memory grows with the input. A name is never a file
name: the gate's scratch files are `SCRATCH/uK.*` and `SCRATCH/uKd/`, K the number of the name in reading order. The
one fixed limit is the Linux path limit (PATH_MAX, 4096 bytes with the terminating zero): a compiler path, or a
`SCRATCH/` that with one of those file names would reach 4096 bytes, is refused with exit 2 before any system call
is made with it.

That is all the gate checks. It does not check the CUDApp commit, or that a file of `INVENTORY.tsv` is really
hand-written. It does not rerun the C oracle. It does not check that a rewrite covers every function of the C file,
beyond what its check program prints. It checks the rules of `cfacts.om` on its two test inputs only; that
`cudapp-cfacts.tsv` is what those rules give on CUDApp is checked outside this tree, as "What blocks each unrecorded
file" says.

A new rewrite slice adds four things:

- the Omega file;
- its check program and the oracle's output;
- at least one row in `checks.tsv` whose parts include the Omega file;
- one row in `rewrites.tsv`.

It then regenerates `INVENTORY.tsv` and `CLASSES.tsv`.

Hardware: none of this opens a device. The runtime's device paths have not run on hardware from this tree; every
hardware tier is NOT_RUN.
