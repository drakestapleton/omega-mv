# DDC650: diverse double compilation of `seed/omc/omc.om` (issue #650)

Status: **available qualification, not wired into the default gate**. The current
oracle source is checked in at `tools/omega_ref/omega_ref.c`; it executes the
current compiler's run-time pools and environment operations. All identities
are taken from the supplied files on each run. Results below under “Base run”
are historical, not qualification of a later source/binary pair. A final
integrated compiler must run this check and its controls again.

## Claim

`ddc.om` checks one thing: the committed `BIN` (`seed/out/omc`) is byte-identical to what two
independently built routes produce from the committed `SRC` (`seed/omc/omc.om`). A PASS supports
the correspondence between this source and this binary on this host, and nothing more. It does not
show that `SRC` is correct or safe, and it does not show that any shared component is honest.

## Routes

| Route | Trusted compiler | Built from | Diversity from `BIN` |
|---|---|---|---|
| S (seed) | `seed/rung4/om4.bin`, pinned by SHA-256 | seed0 → hex1 → asm2 → om4 (hand-written, holds no bytes of `BIN`) | different binary lineage; same project, author and spec |
| I (interpreter) | `omega_ref`, built by the host C compiler `CC` from `ORACLE_SRC` (pinned by SHA-256) | checked-in `tools/omega_ref/omega_ref.c`, hashed at execution | third-party toolchain (GCC 13.3.0, Ubuntu 13.3.0-6ubuntu2~24.04.1); interprets `SRC` from the spec, no Omega code generator in the path |

Route S computes `stage1 = om4 < SRC` and then `stage2 = stage1 < SRC`. Route I computes
`ref = oracle run SRC < SRC`. Each artifact is built twice and the two copies must be equal. The gate
then requires all of the following:

- `BIN < SRC == BIN` (self-regeneration, Wheeler's precondition);
- `stage2 == BIN`;
- `ref == BIN`;
- `stage2 == ref`.

As a built-in sensitivity check, a stage 1 made from `SRC` with one codegen change (`emit 3573751839`,
an AArch64 NOP, inserted before the only `emit or mop r` in `fn matconst`) must give a stage 2 that
differs from `BIN`. If it does not, the run is INVALID.

`WolframLanguageEvaluator: {FromDigits["D503201F",16], FromDigits["D2800000",16]} -> {3573751839, 3531603968}`
(the NOP word, and the `movz x0,#0` word the site emits).

## Run

From the repository root (host CPU only), with a fresh scratch directory on disk:

```sh
T=$(mktemp -d)
seed/out/omc < seed/qualification/ddc650/ddc.om > "$T/ddc" && chmod +x "$T/ddc"
OM4_SHA=$(sha256sum seed/rung4/om4.bin | cut -d' ' -f1)
ORACLE_SHA=$(sha256sum tools/omega_ref/omega_ref.c | cut -d' ' -f1)
"$T/ddc" seed/rung4/om4.bin "$OM4_SHA" \
  /usr/bin/gcc tools/omega_ref/omega_ref.c "$ORACLE_SHA" \
  seed/omc/omc.om seed/out/omc "$T/run"
# Repeat with a fresh scratch directory and each optional final argument:
# stage1 oracle source binary comparator
# Expected exits: 1 1 1 1 3. Every control must say CONTROL CAUGHT;
# INVALID (3) is not a substitute for a route-comparison FAIL (1).
```

Exit codes: 0 PASS, 1 FAIL, 3 INVALID, 4 CONTROL SURVIVED, 90 usage, 91 the scratch directory already
exists. The mutation buffer grows from the actual input instead of a fixed file-size ceiling.
Children run with an empty environment, have no PATH search and get a 300 s deadline. The C
compiler is called with `-B/usr/bin/` because gcc cannot find `ld` without PATH. The gate prints the
SHA-256 of every input and artifact. Cross-check those digests with coreutils `sha256sum` and `cmp`
(see below), because the conductor is itself compiled by the compiler under test.

## Base run (2026-10-30, base 62d1d0d6)

Full log: `base-run.log` in this directory. Conductor binary sha256 `933375a7…479194`.

| Artifact | sha256 | bytes |
|---|---|---|
| SRC `seed/omc/omc.om` | `96d51b63c8f451661ac715395078e04f39195e50c9e8fe37746cda121e4d7a1e` | 259939 |
| BIN `seed/out/omc` | `62775d2a391cfef7cde64e387655caa9809a267093112910ec76bfa568f3712b` | 477612 |
| OM4 `seed/rung4/om4.bin` | `d0da40e45f1fcc45d9a39c9c52c9d745b545e076970729e51c12d76ef519efab` | 14224 |
| CC `/usr/bin/gcc` (gcc-13 driver) | `a20520ee21543f243d40636a9181a142c45ecd989de31ab86b99a8ea5ada870d` | 990040 |
| ORACLE_SRC `omega_ref.c` @190130b7 | `52e747096c1d978103432460a2978b21a604cc5d3e961bbe4b253fcc7636290e` | 56012 |
| oracle (built) | `0b76b36c87e9051c4c7699aa771ddbb0bc9fe8ddb4b10a4be9e16c55e3d345e6` | 74688 |
| route S stage1, stage2 | `62775d2a…f3712b` | 477612 |
| route I ref | `62775d2a…f3712b` | 477612 |
| self = BIN(SRC) | `62775d2a…f3712b` | 477612 |
| sensitivity mstage2 | `a8d6f6d09ea8b173f46c23c8664e2ea2f4910663dfe626f54ac4b6580e38eeec` | 492056 |

Verdict: `VERDICT DDC650 PASS`, exit 0. The coreutils cross-check `sha256sum stage1 stage2 ref self`
printed `62775d2a…` for each, and `cmp stage2 seed/out/omc` and `cmp ref seed/out/omc` both exited 0.
In this tree `stage1 == BIN` as well; the gate prints that fact and does not require it.

## Negative controls (all EXERCISED at the same base)

| Control | Injection | Expected | Observed |
|---|---|---|---|
| `stage1` | route S stage 1 built from the NOP-mutated source | FAIL | FAIL exit 1: `stage2 == BIN` FAIL, `stage2 == ref` FAIL; CONTROL CAUGHT |
| `oracle` | oracle built with `return canon(t, x << s);` → `return canon(t, (x << s) ^ (s == 3));` (exactly once) | FAIL | FAIL exit 1: `ref == BIN` FAIL, `stage2 == ref` FAIL |
| `source` | wrong source: SRC replaced by the mutated source | FAIL | FAIL exit 1: self-regeneration, `stage2 == BIN` and `ref == BIN` all FAIL |
| `binary` | BIN with byte 1000 xor 1 | FAIL | FAIL exit 1: the same three checks FAIL |
| `comparator` | byte comparator always answers "equal" | INVALID | INVALID exit 3 at the comparator self-test |
| malicious binary (external) | BIN = a working compiler built from the mutated source (sha256 `0e665778…befc6aa`) | FAIL | FAIL exit 1: self-regeneration, `stage2 == BIN` and `ref == BIN` FAIL |
| nondeterminism (external) | OM4 = `nondet.om` built by omc (writes the ELF magic plus the clock), pinned to its own digest | INVALID | INVALID exit 3: "route S stage1 deterministic" INVALID, later route S checks "(route not run)" |
| stale seed (external) | OM4 = `om4.bin` from `dedfd93c2` (sha256 `03fc75d9…`), current pin | INVALID | INVALID exit 3 at input identity (pin MISMATCH), before anything runs |
| stale seed, own pin (external) | same old om4 pinned to its own digest | INVALID | INVALID exit 3: old om4 refuses current SRC (`om4: line 597: error 3`) |
| altered oracle input (external) | ORACLE_SRC pin set to 64 zeros | INVALID | INVALID exit 3 at input identity |

## Limitations (shared components; stated, not hidden)

- **Same host for both routes:** one Linux kernel, one CPU (GB10 AArch64), one filesystem, one run.
  No route runs on another OS or architecture, and there is no third independent toolchain (for
  example clang, or a non-Linux machine). That coverage is NOT_RUN.
- **Same project lineage:** route S (om4, seed chain, the printf loader `load0.sh`) and route I
  (`omega_ref.c`) were both written in this project from the same spec (OMEGESE). om4 shares omc's
  code-generation design, which is why `stage1 == BIN` here. Route I adds a third-party compiler and
  an interpreter that emits no machine code, but the oracle source was written by the project.
- **Oracle placement:** `omega_ref.c` is a qualification oracle outside the delivered closure. It is
  checked in beside its regression fixtures and pinned by the supplied SHA-256.
  GCC is a third-party oracle and is pinned only by the printed digest of the
  driver binary, not of `cc1`, `as` or `ld`.
- **Conductor:** `ddc.om` is compiled by `BIN` itself. The coreutils `sha256sum`/`cmp` cross-check
  above is the mitigation; a subverted conductor could misreport its own checks.
- **Scope:** one SRC/BIN pair at one commit. A PASS does not carry over to another commit,
  compiler binary or host.
