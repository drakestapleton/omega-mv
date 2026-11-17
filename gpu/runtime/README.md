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
| `check/platrest-check.om`, `check/platrest.expect.txt` | the check of `gpu/nvidia/om/platform-linux/plat_rest.om` against CUDApp's `src/omega_gpu_platform_linux_rest_oracle.h` (the old C kept as its reference): every mode on xorshift64 inputs with boundary values, and the oracle's output it must match |
| `apiplan.om` | rewrite of CUDApp's `src/omega_api_plan.h` (`ap_plan`): one family number picks one of the six plan units of `gpu/nvidia/om/components/` (`api_mm_plan.om` to `api_rt_plan.om`), and its refusal becomes the C's return value |
| `check/apiplan-check.om`, `check/apiplan.expect.txt` | the check of `apiplan.om` and those six units against the header's C plans (`ap_c`, kept as the old implementation): every family and mode on xorshift64 inputs with boundary values, and the C's output it must match |
| `check/hostrest-check.om`, `check/hostrest.expect.txt` | the check of `gpu/nvidia/om/apiviews/hostrest.om` (`ah_rest`, ops 0 to 24) against CUDApp's `src/omega_gpu_api_hostrest.h` (`omega_ah_c`, the old C) |
| `check/platpolicy-check.om`, `check/platpolicy.expect.txt` | the check of `gpu/nvidia/om/platform-linux/plat_policy.om` against CUDApp's `src/omega_gpu_platform_linux_cpolicy.h` (`plat_c`, the old C) |
| `check/numeric-check.om`, `check/numeric.expect.txt` | the check of `numeric_ref` of `gpu/nvidia/om/numeric/numeric.om` (scalar codes 0 to 30) against the C reference functions of CUDApp's `src/omega_numeric.c` and `src/omega_numeric_reduce.c` |
| `nativeh.om`, `cudapp-units.ident` | the generator of CUDApp's `src/cudapp_native.h` (OM-2), in place of CUDApp `om/units.sh`, and its input: CUDApp `src/cudapp_om_units.ident` unchanged |
| `check/nativeh.expect.txt` | CUDApp's `src/cudapp_native.h` less the units whose Omega is not in this tree (see "The generated files") |
| `held.tsv` | a CUDApp file that is not rewritten because it waits on a decision, not a translation, and which decision |
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
  and CUDApp `om/units.sh` generates `src/cudapp_native.h`. Neither writes a record, so both are `unrecorded`
  (`nativeh.om` below now regenerates the second). The inventory cannot tell generated files from hand-written ones,
  because it reads only the lists, never CUDApp's files.

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
    cp cudapp/src/cudapp_om_units.ident omega-mv/gpu/runtime/cudapp-units.ident
    (cd omega-mv && git ls-tree -r --name-only BASE src gpu | LC_ALL=C sort | xargs sha256sum) > omega-mv/gpu/runtime/omega-base.sha256.txt

The committed CUDApp lists came from CUDApp `84b524cadaaa8bc9b556adfaea9d6dd2e0d67a66`. The slice was written on
omega-mv `f7a068ec54d67ccad504cf5e5887376916158b7b`; the merge that brought it into main regenerated
`omega-base.sha256.txt` and `INVENTORY.tsv` with `BASE` = that merge's first parent,
`d0f9bb23ac321915c987d58ea97cca0fc9392493`. The DRA-606 change (barrier 6 refusal in
`gpu/nvidia/om/codegen/bw_hazard.om`) regenerated them again with `BASE` =
`d7c70e4a969a85047630e85385c032a4b652dfba`, run in its own tree, so the list holds that change's files. That is
recorded here only. DRA-344 (MUFU flush in `src/omega_gpu_elementwise_api.c`/`.h`) and DRA-351 (seat diagnostics in
`src/runtime/rx_resident_gpu.c`) each regenerated `omega-base.sha256.txt` the same way in their own tree. The lists themselves carry no commit, and
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

`src/omega_runtime_api.c` is held (`held.tsv`): it returns CUDApp's runtime API version, which its own
`src/omega_runtime_api.h` sets; this tree has a different `src/omega_runtime_api.h` and
`docs/runtime/omega_runtime_api.manifest` with their own version, so which version one Omega library reports is a
decision about the API, not a translation. `src/omega_gpu_platform_linux_rest_oracle.h` is itself the old C kept
to check `gpu/nvidia/om/platform-linux/plat_rest.om` against; `check/platrest-check.om` compares the two, so
`rewrites.tsv` names that unit. The oracle driver that printed `check/platrest.expect.txt` lives outside this tree,
with the lane's oracle notes: `platrest_driver.c`, sha256
`c999e5e64ad14c6a9ddbe90407350848af7bf480e7c055a7cf8c17f63103b925`; its output, byte for byte
`check/platrest.expect.txt`, sha256 `a721a22406576aac779e88fce138851d2136fb8b1ef422cdda3cf920c9be616f`.

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

## The api plan oracle

`check/apiplan.expect.txt` is the output of the C plans `ap_c` of CUDApp `src/omega_api_plan.h` (sha256
`3a572b497df46f1aeb036f02df078315541f48e6cc8eeb97e1603e1c2f31cd60`), the code its freestanding build still runs.
A driver kept outside this repository by the lane that wrote this slice produced it:

- `apiplan_driver.c`: sha256 `27f14850dca542c1c8fb17eb10c66f45bd62d1f9e35276db3086cac74a7f1b02`.
- its output: byte for byte `check/apiplan.expect.txt`, sha256
  `1b3ad963aae1ff8eb96da42b5f1e4c431d83daae734123ceaedf8fc4bcb97642`.

Built against CUDApp `src/` at the commit above; built again with `-fsanitize=undefined -fno-sanitize-recover=all`,
it printed the same bytes and exit 0:

    cc -std=c11 -O1 -ffp-contract=off -DOMEGA_GPU_NO_POSIX -Icudapp/src apiplan_driver.c -o apiplan_driver
    ./apiplan_driver > apiplan.expect.txt

Per family 0..5 the check runs every mode up to one past the last the C knows, and family 6; 4096 cases each.
Inputs `a[0..7]` come from xorshift64 and a list of boundary values, `a[8..15]` start as `0x9e3779b9 + i` (as in
CUDApp `tests/runtime/api_plan_unit.c`). The check prints the first two cases of each mode whole, and a line with
the count of refusals and an FNV-1a-64 digest of every refusal and all sixteen words.

Both sides then rewrite some inputs the same way (`akdom` in the check, `dom` in the driver), to stay in the
domain where the C is defined and the two are meant to agree. Divisors are made nonzero. The rules below go
further, and dropping any one of them makes the Omega check stop with the trap shown, in that mode (run against
this check, the rule replaced by a `note`):

| family, mode | rule | Omega without it | the C there |
| --- | --- | --- | --- |
| 1 (at), 1 | `a[0]` below 2^33 | trap 4: `at_log` has `bound 32`, a power of two of 2^33 or more needs more passes | returns its log, 33 to 63 |
| 1, 5 | `a[4]` below 2^33 | trap 4, the same `at_log` | the same |
| 1, 4 | `a[0]` 0..4 | trap 4: the loop has `bound 4` | loops `a[0]` times; a shift of 64 or more is undefined |
| 1, 7 and 1, 22 | `a[3]`, `a[1]` below 2^32 | trap 5: `uint get` is a checked conversion | keeps the low 32 bits of the float |
| 3 (bf), 0 | `a[0]` below 2^24 | trap 4: the divisor search has `bound 65536` | searches down from `a[0]/256`, up to 2^56 passes |

So the units agree with the C only inside these rules. CUDApp's own differential test of the units against `ap_c`
(`tests/runtime/api_plan_unit.c`) stays inside them too. The limits sit in the units of
`gpu/nvidia/om/components/`, which are Bridge source parts of CUDApp; changing them is outside this slice. The
comparison covers `ap_plan`'s dispatch and refusal mapping, and every family's plans on the domain above.

## The host-rest, platform policy and numeric oracles

These three checks compare units already in this tree, unchanged, with the old C that CUDApp keeps behind a pending
flag. Each expected file is the output of a driver kept outside this repository by the lane that wrote this slice,
built against CUDApp `src/` at the commit above; built again with `-fsanitize=undefined -fno-sanitize-recover=all`,
each printed the same bytes and exit 0.

| check | old C (sha256) | driver (sha256) | expected output (sha256) |
| --- | --- | --- | --- |
| hostrest | `src/omega_gpu_api_hostrest.h` (`41a018a75edf2d520d8d33c34becbf765ec41f3dff9f34782443fadc5340a4ba`) | `hostrest_driver.c` (`cec570043558cb59899ed7a7f7f0ad7b58eec9995cc442a25319929a6466693e`) | `b8cfe9930689a97e616008e9f66a9e02980a2c29b9ba89fbe5d1a07677408df4` |
| platpolicy | `src/omega_gpu_platform_linux_cpolicy.h` (`e9bbbcbdcc048e0b28e6b031660e4a35da4dcb34f6da73301328d7931a0fee68`) | `platpolicy_driver.c` (`a538ce143dac3c7ea5ad8512c8e0403c4f09def92758acbffa45b6231ab85801`) | `36abe9d62fe764c7084d8cc0305b41b0e4611dd6bc1683020162c75aa22c2540` |
| numeric | `src/omega_numeric.c` (`309d757a8a2aa76f3cfa3294b3adf7decc25cf7065b498debc4978cbfa7c46f2`), `src/omega_numeric_reduce.c` (`c16475c7b8d87b748a2e50a4198a1dbaebf448c855378fdb024450ea59c455c2`) | `numeric_driver.c` (`5bf3826bfd69141fe701339616571f0ba82ea212b8d4b2e3241e691f7e0944f8`) | `492c29649687c0f611b4376225ffa1fcb4282c96f13d733ef3ecca046cd29fba` |

    cc -std=c11 -O1 -ffp-contract=off -DCUDAPP_MIGRATION_PENDING_C_API_FP8_GDN_HOST -Icudapp/src hostrest_driver.c -o hostrest_driver
    cc -std=c11 -O1 -ffp-contract=off -Icudapp/src platpolicy_driver.c -o platpolicy_driver
    (cd cudapp && cc -std=gnu11 -O1 -ffp-contract=off -I. -Isrc -DCUDAPP_MIGRATION_PENDING_C_NUMERIC \
      -DCUDAPP_MIGRATION_PENDING_C_NUMERIC_REST ../numeric_driver.c src/omega_numeric_reduce.c -lm \
      -Wl,--unresolved-symbols=ignore-all -o ../numeric_driver)

(The numeric driver includes `src/omega_numeric.c` itself; the device builders that file names are never called and
are left unresolved.) All three use the xorshift64 generator, 4096 cases per op, the first two cases printed whole,
then a line with the count of nonzero answers and an FNV-1a-64 digest of every answer (for platpolicy, of the
answer and all sixteen output words).

hostrest: ops 0 to 24, inputs `p[0..8]` from xorshift64 and boundary values, `p[9..15]` zero. Both sides rewrite
the inputs the same way (`hkdom` in the check, `dom` in the driver): where the unit takes a word with `uint get`
(a checked conversion) the first five words keep their low 32 bits; divisors are made nonzero. Two rules go
further:

| op | rule | why |
| --- | --- | --- |
| 8 | `p[0]` below 2^24 | `ah_depth`'s divisor search is a `while` with the default bound of 1000000 passes; with `p[0]` 2^24 or more the Omega stops with trap 4 (observed), where the C searches on |
| 19 | `p[3]` 0 or 1 | the C answers 1 when the test holds and `ah_rest` answers `p[3]`; both callers in CUDApp (`src/omega_gpu_fp8_api.c`) pass `p[3]` = 1 and use the answer as a truth value |

Every other case of ops 8, 16 and 19 takes the shape of CUDApp `tests/api_hostrest_test.c` (`hkshape`, `shape`),
so that their accepting answers are reached. Ops 25 and up are not checked: there the C's default case rounds
`p[0]/p[1]` up (when `p[3]` is 0) and `ah_rest`'s last case rounds it down, and no `OMEGA_AH` use in CUDApp `src/`
passes an op above 24.

platpolicy: message kinds 0 to 15, `m[1..15]` from xorshift64 and boundary values. For kind 7 every other case
holds a short text of digits, blanks and signs packed eight bytes to a word from `m[2]`, its length in `m[1]`; for
kind 12 every other case has a slot that matches `m[2]` and `m[3]`. The output words `q` start at zero, as
`plat_decide` of CUDApp `src/omega_gpu_platform_linux.c` sets them before each call (the C clears them itself; the
unit writes only the words it answers in). The check is OM-1 because `plat_policy.om` is.

numeric: codes 0 to 30 of `numeric_ref` (the `OMEGA_NUMERIC_OM_*` codes of CUDApp `src/omega_numeric_om.h`), each
against the C function it stands for, with operands in the form the public wrappers at the end of
`src/omega_numeric.c` pass them: 32-bit FP32 words (special values, small integers, random words), 16 bits for the
half-precision widenings, a mode 0 to 4 for `compare_equal`, a 64-bit count for `reduce_levels` and
`launch_shape`, and for `fsetp_pred` one of the fourteen fsetp ops on the C side and its mask (`nk_fm`, the
`fsetp_mask` of `src/omega_numeric.c`) on the Omega side. Every fourth case of codes 27 and 28 compares an operand
with itself. This covers the scalar reference tier of `src/omega_numeric.c`, the part `rewrites.tsv` names;
its tile, reduction, patch and device-realization code (the units `tile.om`, `reduce.om`, `rest.om`, `patch.om`,
`check.om` of `gpu/nvidia/om/numeric/`) is not checked here.

## The generated files

CUDApp `src/` holds four files that no `.ident` record names but that look generated. This is what each one is and
what this tree does with it (all at CUDApp `84b524cadaaa8bc9b556adfaea9d6dd2e0d67a66`).

`src/cudapp_native.h` is written by CUDApp `om/units.sh`: a fixed head, one C declaration per unit of
`src/cudapp_om_units.ident` in that order, a fixed tail. `nativeh.om` writes the same bytes from the Omega source
in this tree, by the rule its header states (the root is the last `fn` of the unit's composed parts; its
parameters give the C types; the bridge runtime-views line goes before a `bridge-seeded-runtime` unit and before a
unit whose composition starts with the line `om2`). Its input `cudapp-units.ident` must hash to the row of
`src/cudapp_om_units.ident` in `cudapp-src.sha256.txt`, or it writes nothing and exits 3. Run from the repository
root:

    { printf 'om2\n'; cat seed/ng/sha256.om gpu/runtime/zsha.om gpu/runtime/nativeh.om; } | seed/out/omc > nativeh
    ./nativeh > cudapp_native.h

The units whose parts the inventory reports `absent` cannot be declared from this tree; `nativeh.om` stops at the
first absent part of such a unit, names that part on stderr and leaves the unit out. At this base that is unit
`c5` (CUDApp `tools/c5/policy.om` and
`tools/c5/runtime.om`, not moved here). `check/nativeh.expect.txt` is therefore CUDApp's header less that unit's
one line:

    grep -v '^uint32_t omega_native_c5(' cudapp/src/cudapp_native.h > omega-mv/gpu/runtime/check/nativeh.expect.txt

With the two `tools/c5` files copied to `gpu/nvidia/tools/c5/` in a scratch copy of this tree, the same program
printed CUDApp's whole header: sha256 `17fc48509d7089d34be4d9f5a5cd578b55b5fc83bcc0ca59e66b286201de0f46`, the row of
`src/cudapp_native.h` in `cudapp-src.sha256.txt`. When `tools/c5` moves into this tree, the expected file becomes
CUDApp's header unchanged. Controls: the three `nativeh` rows of `checks.tsv` change the spacing rule, the
runtime-views rule and the `f32` rule, and each is caught; one changed byte in `cudapp-units.ident` makes it exit 3
with nothing written (checked by hand; the gate has no input-byte control for this program).

`src/cudapp_freest_pathcopy.c` is written by CUDApp `om/native-freest.sh` through the Omega Bridge's native
backend (`tools/native --freestanding` of omega-bridge): the unit `gpu/nvidia/om/components/pathcopy.om` compiled
to AArch64 and x86-64 machine code by the compilers that script pins, and wrapped as C. This tree has neither that
backend nor those compilers (the script pins omc builds `734f0a39...` and `2c82480...`, an x86-64 build
`be8c5130...` and the native backend `14b2b51e...`, all outside this repository), so the file is not regenerated
here. Doing so needs that backend written in Omega in this tree, or this tree's `seed/out/omc` able to emit the
same freestanding objects.

`src/omega_core_om.inc` (added in CUDApp commit `a86d199f`, "feat(core): move utility computation and cubin
diagnostics to seeded Omega") and `src/omega_native_artifact_om.inc` (added in `4531d707`, "Move native artifact
format and admission into seeded Omega") were both written by hand. No Makefile rule, `mk/*.mk` file or script in
CUDApp writes them; they appear only as prerequisites. They hold the C side of two Omega units: argument
marshalling, `_Static_assert` checks of the layout, pointers and I/O. There is no generator to reproduce, so they
stay class `b`: C over Omega, waiting for Omega to produce a library that C can call.

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
