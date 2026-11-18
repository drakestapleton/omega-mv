# How aienux came into kernel/ (2026-11-17)

Aienux, the kernel of AienOS, is folded into omega-mv here (Drake 2026-11-17: fold the aienux kernel
repository into omega-mv instead of keeping a separate repository). It came from aienux main
`1f12818d06ab0eb89cd592f83e13197477b36c07`, taken from the aienux plain-Git store. The aienux page on
interplane.io (https://interplane.io/drakestapleton/aienux) served `d01b2f19` that day, an ancestor of
`1f12818d` 22 commits back.

## Method

The same method as the moves from CUDApp into `gpu/` (aien-architecture-mv ADR 0047, steps 1 to 4):
git filter-repo (`import/filter-repo.version`), a host tool used once for this import and not part of any
build or gate, in one pass over a single-branch clone of aienux main (`import/filter-repo-command.txt`).
The pass keeps every path except the ones listed below and renames the kept tree under `kernel/`. The
rewritten branch (666 of aienux's 701 commits; the other 35 touched only left-out paths) was merged
with `git merge --allow-unrelated-histories`, so `git log -- kernel/<path>` shows the aienux commits of
that file.

- `import/commit-map`: "old new" for every aienux commit reachable from `1f12818d`; forty zeros for a
  commit that touched only left-out paths. Look an aienux hash up with
  `grep '^SHA' kernel/import/commit-map`.
- `import/ref-map`: the one rewritten branch.

Commit messages, authors and dates are kept. An aienux hash named in a message, a receipt or a register
is still the aienux hash (`--preserve-commit-hashes`); its commit here is the one the commit map names.
Aienux itself was not changed. The tree at the merge holds the same blobs, path for path, as aienux
`1f12818d` minus the left-out paths.

## Left out, and why

| Path at aienux `1f12818d` | Why it did not come |
| --- | --- |
| `.github/` (workflows, Copilot instructions, dependabot, one workflow helper script) | Only GitHub reads it, and only at a repository root; Interplane is the only forge (Drake 2026-11-11). No step of `tests/gates/run.sh` uses it. |
| `.crumb`, `crumb.lock` | Crumbs are retired (DRA-97, 2026-11-07; omega-mv removed its own on 2026-11-08). They stay in aienux's history. |
| `.aien/` (`always`, `unmapped-ok`, `verify.pub`) | Aienux's Spark-judge configuration. The judge reads `.aien/` only at a repository root, where omega-mv's own `.aien/` applies. Aienux's always-list named AIENOS-CRYPTO-BOUNDARY and AIENOS-ZERO-DISK-SECRETS. Omega-mv's `.aien/always` now lists OMEGA-KERNEL-CRYPTO-BOUNDARY (the same `crypto-boundary` step) and OMEGA-KERNEL-GATE-WIRING; omega-mv's own always-run OMEGA-ZERO-DISK-SECRETS replaces the second (below, "Aienux gates without a manifest"). |
| `funding.json` | A fundingjson.org manifest for a repository root, holding personal contact details. It is not source and does nothing under `kernel/`. |

Everything else came, with its licence files: `LICENSE` (Apache-2.0), `NOTICE` and
`THIRD_PARTY_NOTICES` at `kernel/`, and each crate under `vendor/` keeps its own licence files. `vendor/`
came because cargo builds offline from it (`.cargo/config.toml` replaces crates-io with `vendor/`) and the
kernel's `ck-host-tests` step builds `allen-courier` with cargo; without it that step would need the
network or a machine's cargo cache.

## Compiler pin

Aienux's `PIN` and `REPIN` are gone. The kernel now compiles with omega-mv's own committed
`seed/out/omc`, whose SHA-256 is the first field of `seed/out/omc.sha256` at the omega-mv root. At the
fold that was the same compiler aienux pinned (`34d611ca…`, omega-mv `50feb135`). Moving omega-mv's
compiler moves the kernel's with it; there is no separate repin.

- `tests/gates/run.sh` (`omega_omc`, steps `hw-gates`, `omega-nvme`, `tcp-corpus`),
  `tools/hwgates/gate.sh`, `native/disk/tests/omega_nvme_test.sh` and `native/net/tcp/gate.sh` read that
  file instead of `PIN` and take `../seed/out/omc` (or an `AIEN_OMC` with the same hash).
- Units that pinned a compiler of their own now take omega-mv's by default and check its hash:
  `native/omega/allen/{gate,build-one,build-fw,build-local-model}.sh` (before: omc `2eeab514…` from the
  local branch `fix/imac-net-L974-snp`, and omc `3ad9f10f…` for the local-model build),
  `scripts/check_local_tools.sh` (before: omega-mv `bf54b19f`, omc `62775d2a…`; its `OMEGA_SOURCE` names
  where the compiler is and never supplies the pin, which is always this checkout's root file) and
  `native/om/lm1b/gate.sh` (before: omc `734f0a39…` at a home-directory path). Their READMEs say what was
  measured with the new compiler.
- Not changed: `native/omega/platform/gate.sh` takes the compiler and its hash as arguments;
  `tools/imac-image/build-efi.sh` takes `OMEGA_COMPILER` (its sources are outside omega-mv, below).
  Recorded receipts and their compiler digests are history and stay as written.

## Running the kernel's gates from the omega-mv root

`tests/gates/run.sh kernel` runs six steps: `kernel-make-test` (`make -C kernel/native/kernel test`),
`kernel-ck-host-tests`, `kernel-hw-gates`, `kernel-omega-nvme`, `kernel-tcp-corpus` and `kernel-spinlock`,
each of which is also a step of its own; the last five run `kernel/tests/gates/run.sh <step>`.
`kernel-spinlock` (the compiled order of `core/spinlock.h` and its Lean model) is NOT_RUN, exit 3, without
the cross compilers or the lean that `native/kernel/proofs/lean-toolchain` names; like every other step, a
NOT_RUN is not a pass and fails the aggregate.

Every other gate aienux had is wired the same way, one manifest each: `tests/gates/omega-kernel-<step>.gate`
runs `tests/gates/run.sh kernel-<step>`, whose `kernel-*` arm runs `kernel/tests/gates/run.sh <step>`. Each
keeps its aienux manifest's requirements, timeout and expected observations, with its inputs under
`kernel/`, so a change under `kernel/native/crypto/` selects OMEGA-KERNEL-NATIVE-CRYPTO and
OMEGA-KERNEL-CRYPTO-BOUNDARY as it selected their aienux twins. Aienux had 25 gates; 24 have a manifest
here (the six steps above less `make-test`, which is new, plus native-crypto, native-sig,
native-capability, native-net, native-disk, native-argus, native-m5, store-native, crypto-boundary,
ck-stage-tests, ck-gate-selftest, ck-hold-selftest, ck-owner-keys, ck-qemu-gates, ck-qemu-external,
ck-b7b-probe, disk-qemu, infer-crate, infer-forward and verify-all), and the 25th is below. The 25
manifests under `kernel/tests/gates/` are aienux's, read by no judge here, and kept as history.

`kernel/scripts/omega_gate_wiring.sh` (step `kernel-gate-wiring`, gate OMEGA-KERNEL-GATE-WIRING, always-run)
fails unless each of aienux's 25 gates and each step of `kernel/tests/gates/run.sh` has such a manifest, or
a row in the table below, and not both: the manifest names gate `OMEGA-KERNEL-<STEP>`, exec
`tests/gates/run.sh` and args `["kernel-<step>"]`; every input is a tracked path and one at least is under
`kernel/`; the first arm of `tests/gates/run.sh` that matches `kernel-<step>` runs the kernel runner, and
the kernel runner has the step. It also requires `.aien/always` to list the three always-run gates above
and no `omega-kernel-*.gate` to name a step nobody runs. It is static and runs no gate. With
`--self-test` (how the gate runs it) each of its mutant controls must then FAIL: a removed, renamed or
disabled manifest, args naming another step or commented out, another gate name, exec bypassing the root
runner, an input without `kernel/` or none under it, a root arm that shadows the step, the `kernel-*` arm
removed, a kernel step renamed or added without a manifest, an always line dropped, a table row dropped,
doubled with a manifest or without a reason, its own manifest removed, and an orphan manifest.

### Aienux gates without a manifest

| Aienux gate | Here | Reason |
| --- | --- | --- |
| `zero-disk-secrets` | REPLACED; not run as its own gate | Omega-mv's always-run OMEGA-ZERO-DISK-SECRETS (`tests/gates/run.sh zero-disk-secrets`) looks for the same name pattern, `.env*`, in every tracked path and every untracked file of the whole checkout except `./.git` and `./build`. Aienux's step (`kernel/tests/gates/run.sh zero-disk-secrets`, still there) looked only in `kernel/`, to depth 4, and skipped `.git`, `target/` and `vendor/` at any depth, so everything it caught the root step catches. The controls in `omega_gate_wiring.sh --self-test` run the root step on a scratch repository with a `.env` file planted under `kernel/`: untracked at its top, tracked in a suite, at depth 6, under `vendor/` and under `target/`; each must FAIL, and the same repository without the plant must pass. |

## What the fold changes for the kernel's own checks

- `scripts/native_package.sh` and `scripts/native_package_test.sh` (`make test`'s `package-test`) assumed
  the kernel was a repository root. The first now reads a source input from a commit as `$commit:./path`
  and the second clones the whole repository and works in its `kernel/` prefix; the checks are unchanged.
  Before that change `package-test` failed here with 23 of 117 checks.
- `scripts/ck_gates.sh --self-test` (step `ck-gate-selftest`) and `scripts/trust1_m5_qualify.sh --self-test`
  tested the dirty-tree refusal on a clone of the kernel's directory, which inside omega-mv is not a
  repository: `ck-gate-selftest` failed here ("could not make a private clone") and passed on aienux
  `1f12818d`. Both now clone the whole repository and work in the kernel's prefix (`git rev-parse
  --show-prefix`; empty in a standalone checkout), and inside omega-mv they also require an untracked file
  at the repository top, outside `kernel/`, to be refused: the receipt names an omega-mv commit.
- `scripts/check_local_tools.sh` read the pin from `$OMEGA_SOURCE/seed/out/omc.sha256`, beside the compiler
  it then ran, so a compiler with its own sha256 next to it was accepted. The pin is now always the first
  field of `seed/out/omc.sha256` at the root of this checkout; a compiler (from `OMEGA_SOURCE` or here) with
  another sha256 is refused, exit 3, before it runs. The `pin_controls` of `kernel/tests/gates/run.sh` try a
  compiler under `OMEGA_SOURCE` with its own pin file, with none, and through a symlink.
- `tools/hwgates/gate.sh` treated a register row whose source is `aienux@COMMIT` as naming "a commit of
  this repository" only when `git cat-file` found COMMIT. The aienux commits are here under their
  rewritten hashes (`import/commit-map`), not their own, so rows that cite aienux commits failed that
  check in omega-mv. The gate now resolves `aienux@COMMIT` through `import/commit-map` to a commit present
  here; the rows keep their aienux hashes.
- Omega-mv's `aienos.lock` and `argus.lock` name aienux commits (`b84c0a67`, `b375dcaa`), both on aienux
  main. They are read from `kernel/` now, not from a sibling `../aienos` checkout:
  `tools/aienos_lock_source.sh` maps the locked commit through `import/commit-map` (`593c755e`,
  `b7c5e158`) and extracts and proves the subpaths from that commit's `kernel/` tree, whose
  `native/capability` and `native/argus` trees have the same ids as in aienux. `tests/gates/run.sh`
  (`aienos_pin`, `argus_pin`), the Makefile (`AIENOS_LOCK_REPO`, `ARGUS_REPO`, now empty by default) and
  the receipt tools (`AIENOS_REPO`) use it; a repository holding the aienux commit can still be named.

## Still outside omega-mv

Content the kernel's tools name that is only on aienux side branches was not imported:

| What | Where | Here |
|---|---|---|
| The twenty Allen EFI sources `tools/imac-image/build-efi.sh` composes | aienux `feat/allen-imac-competition` `d4ffde3cac2e73b568c0f958a9cefe8cb21f2c07` | Fourteen equal `native/omega/allen`; `platform.om`, `surface.om`, `github.om`, `net.om`, `repository-screen.om` and `efi-main.om` differ. The script carries the sha256 of each at `d4ffde3c` and exits 3 (NOT_RUN) unless `ALLEN_SRC` holds exactly those. |
