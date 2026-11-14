# bridge/cuda: the frozen CUDA compatibility profile, in Omega

This directory is CUDApp's `compat/cuda/` (CUDApp main `84b524ca`), moved into omega-mv and
written only in Omega. It decides whether one CUDA application, built by an ordinary C compiler,
uses exactly the CUDA surface we have frozen for it, and nothing more. It never runs that
application and never opens a GPU.

## What the old directory did

CUDApp `compat/` held two C files, two shell scripts and a set of tables.

| Old file | What it does | Where it is now |
|---|---|---|
| `compat/cuda/fixture/vadd_drv.c` | A small CUDA Driver API program written as the test subject: one context, one PTX module, three buffers, one kernel launch, and a check of the result on the host. | Stays in CUDApp. It is the foreign application under test, not part of Omega; the gate's oracle tier compiles it with gcc outside the tree. |
| `compat/nvml/libnvidia-ml.c` (with `nvml.h`, `libnvidia-ml.map`) | A replacement for 11 functions of NVIDIA's monitoring library. It is generated C, emitted by the omega-bridge C-ABI emitter from the Omega unit that is already in this tree as `gpu/nvidia/native/nvml/api.om`. | Not copied: the Omega source is already here. The C exists only because `omc` cannot yet emit a shared library; see `EXTENSION-PROPOSAL.md`. |
| `compat/cuda/build.sh` | Builds the test program for AArch64 and x86-64 with gcc. To link it, it makes a placeholder `libcuda.so.1` that defines every `cu*` name the program uses as 0, with no code. | The placeholder library is written by `fixture.om` (mode `stub`), byte-exact with what `ld` makes, so the old gcc build linked against it gives the same executables. The gcc compile itself stays outside, run by the gate's oracle tier. |
| `compat/cuda/test.sh` | Rebuilds twice and requires the same bytes, checks the three profile generations list the same CUDA calls, admits both current profiles, then makes 14 broken variants and requires each to be refused. | `gate.om`, step for step, with the same transcript. |
| `compat/cuda/fixture/vadd_u32.ptx` | The GPU kernel (a vector add), written by hand in PTX. | Inside `fixture.om` (mode `ptx`), written out byte for byte; the gate checks its SHA-256 against the profiles. |
| `compat/cuda/profile-c0-{aarch64,x86_64}-v{1,2,3}.tsv` | The frozen profiles: which libraries, versioned C symbols, CUDA calls, PTX instructions and file hashes are allowed. v3 is current; v1 and v2 are kept unchanged as history. | Here, byte for byte (same git blob ids). |
| `compat/cuda/c0_check.om` | The checker that reads a profile, an executable and a PTX file and admits or refuses. Already Omega. | Here, unchanged. |

## Files

| File | Role |
|---|---|
| `c0_check.om` | The checker: `c0_check check PROFILE EXE PTX RUNISA` (exit 0 admitted, 1 refused) and `c0_check emit PROFILE EXE PTX` (prints what it read). Build: `cat gpu/nvidia/om/cache/digest.om bridge/cuda/c0_check.om \| seed/out/omc`. |
| `fixture.om` | Writes the test inputs. `fixture ptx OUT` writes the kernel. `fixture stub PROFILE OUT` writes the link-only `libcuda.so.1` for the profile's ISA, with its symbol table in the order GNU `ld` uses (GNU-hash bucket, then ld's own hash slot), which is what makes gcc's link reproduce the frozen hashes. `fixture exe TABLE PROFILE full\|nolib OUT` writes a small executable that the checker reads exactly as it reads gcc's (built from a `fixture-*.tsv` table), so the gate does not need a C compiler. Build: `seed/out/omc < bridge/cuda/fixture.om`. |
| `fixture-aarch64.tsv`, `fixture-x86_64.tsv` | What `c0_check emit` reads from the real gcc executables. They are derived, not typed: the gate's oracle tier recomputes them from gcc's output and refuses any difference. |
| `gate.om` | The gate (below). Build: `{ printf 'om2\n'; cat seed/ng/sha256.om bridge/cuda/gate.om; } \| seed/out/omc`. |
| `test-sh-84b524ca.txt` | The output of CUDApp's `test.sh` at `84b524ca`, run with omc `2c824805`. The gate's own transcript must equal it from line 3 on (lines 1 and 2 are the gcc build hashes, which only the oracle tier can reproduce). |
| `EXTENSION-PROPOSAL.md` | What `omc` would need to emit the NVML library itself. |

## The gate

`tests/gates/run.sh bridge-cuda` (manifest `tests/gates/omega-bridge-cuda.gate`) builds the three
programs with the in-tree `seed/out/omc` after checking its digest, and runs:

`gate SCRATCH C0CHECK FIXTURE [CUDAPP OLDOMC CC_AARCH64 CC_X86_64]`

Always, with no C compiler: writes the PTX; synthesises each executable twice and requires the
same bytes; requires the checker to read them as the `fixture-*.tsv` tables; checks the no-libcuda
variant has no CUDA import; pins copies of the v3 profiles to the synthetic hashes; checks the
v1/v2/v3 CUDA import lists are equal; admits both profiles; and refuses the 14 broken variants of
`test.sh` (wrong ISA, wrong executable, edited hash, dropped or added import, unsupported status,
wrong schema, libc floor, `dlsym`-style lookup, missing library, missing libcuda, barrier and
two-statement PTX). The lines it records must equal `test-sh-84b524ca.txt` from line 3.

With `BRIDGE_CUDA_CUDAPP` (a CUDApp checkout at `84b524ca`) and `BRIDGE_CUDA_OLDOMC` (omc
`2c824805…`) set, it also runs the old `test.sh` and requires its whole output to equal the
stored file; links gcc's objects against the Omega `libcuda.so.1` stub and requires the frozen v3
executable hashes; and requires the checker's reading of gcc's executables to equal the
`fixture-*.tsv` tables.

The run then rebuilds `c0_check` with its "missing row" refusal removed and requires the gate to
fail with it. The last line is `BRIDGE-CUDA PASS checks=N failed=0 oracle=NOT_RUN|PASS
hardware=NOT_RUN`.

| Tier | Verdict |
|---|---|
| Admission and refusal on synthetic executables | gated, every run |
| Old `test.sh`, gcc builds against the Omega stub | gated when the oracle inputs are given |
| Running the kernel on a GPU (`VADD_U32 PASS n=4099 …`) | NOT_RUN |

## Limits

The checker refuses, rather than truncates, a profile or PTX over 64 KiB and an executable over
1 MiB (exit 3), as the C-era checker did. The gate and fixture writer refuse cleanly when an input
passes their buffers (16 MiB for files, 2,097,152 import names).
