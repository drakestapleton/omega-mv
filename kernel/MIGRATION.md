# How aienux came into kernel/ (2026-11-17)

Aienux, the kernel of AienOS, is folded into omega-mv here (Drake 2026-11-17: fold the aienux kernel
repository into omega-mv instead of keeping a separate repository). It came from aienux main
`1f12818d06ab0eb89cd592f83e13197477b36c07`, taken from the aienux plain-Git store. The aienux page on
interplane.io (https://interplane.io/drakestapleton/aienux) served `d01b2f19` that day, an ancestor of
`1f12818d` 22 commits back.

## Method

The same method as the moves from CUDApp into `gpu/` (aien-architecture-mv ADR 0047, steps 1 to 4):
git filter-repo (`import/filter-repo.version`), a host tool used once for this import and not part of any
build or gate, in two passes over a single-branch clone of aienux main. The first pass
(`import/first-pass.txt`) changes only two documents ("Rebuilt import" below). The second
(`import/filter-repo-command.txt`) keeps every path except the ones listed below and renames the kept
tree under `kernel/`. The rewritten branch (666 of aienux's 701 commits; the other 35 touched only left-out paths) was merged
with `git merge --allow-unrelated-histories`, so `git log -- kernel/<path>` shows the aienux commits of
that file.

- `import/commit-map`: "old new" for every aienux commit reachable from `1f12818d`; forty zeros for a
  commit that touched only left-out paths. Look an aienux hash up with
  `grep '^SHA' kernel/import/commit-map`.
- `import/ref-map`: the one rewritten branch.

Commit messages, authors and dates are kept. An aienux hash named in a message, a receipt or a register
is still the aienux hash (`--preserve-commit-hashes`); its commit here is the one the commit map names.
Aienux itself was not changed. The tree at the merge holds the same blobs, path for path, as aienux
`1f12818d` minus the left-out paths, except `docs/PI5_AIENOS_MAP.md` and `docs/IMAC_AIENOS_MAP.md`.

### Rebuilt import, 2026-11-18

The first import of 2026-11-17, on branches that never landed, carried in the two aienux map documents
a description of what one operator machine runs, which is not public. The import was rebuilt before
landing so that no commit of this history holds it. The first pass gives the two files, in each of the 18
aienux commits that have them (`c9a56739` to `1f12818d`), a version without it: the Pi map takes the
wording omega-mv commit `8c9a195f3` gives it and the board table's Linux kernel row of a later aienux
commit; the iMac map takes only that commit's private-network paragraph. The same pass takes out of the
messages of `c9a56739` and `ea6130ce` the one clause each that described that machine; no other message
changed. `import/first-pass.txt` has the command and every replaced blob. Nothing else changed: for each
of the 666 commits the tree equals the
first import's path for path but for those two files, and the other 648 commits kept
their hashes (the locked `593c755e` and `b7c5e158` among them). Every omega-mv commit after the import
was then replayed on it with the same author, dates, message and tree, but for the two files and for
`import/commit-map` and `import/ref-map`, which are regenerated in the commit that adds them (`import/`
is additions only); the import merge's message names the two passes. Reviews cited as omega-mv
`c9e503afd` reviewed the first import's integration head, replayed here as `be64892fd`.

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
the cross compilers or the lean that `native/kernel/proofs/lean-toolchain` names. A NOT_RUN is not a pass
and fails the aggregate.

Each `kernel-<step>` goes through `kernel_step` in `tests/gates/run.sh` (CA3 of the 2026-11-18
root-cause analysis). It first needs git and a base ref (`AIEN_BASE_REF`, default `origin/main`) that is a
commit holding `kernel/`; otherwise the step is NOT_RUN, exit 3 [ctl:OMEGA-KERNEL-GATE-WIRING/base-without-kernel]. On a
clone whose `origin/main` predates the fold, set `AIEN_BASE_REF` to the branch the head lands on. Exit 3
or 127 from the step, or exit 0 with a verdict line saying NOT_RUN or SKIP (`LABEL: NOT_RUN`,
`SKIPPED: ...`), becomes NOT_RUN, exit 3 [ctl:OMEGA-KERNEL-GATE-WIRING/wrapper-127-pass] [ctl:OMEGA-KERNEL-GATE-WIRING/wrapper-verdict-ignored]
[ctl:OMEGA-KERNEL-GATE-WIRING/wrapper-skip-ignored]. When `tests/gates/controls/OMEGA-KERNEL-<STEP>.controls` exists, a run
that does not print `CONTROL OMEGA-KERNEL-<STEP>/<name> FAILED_AS_REQUIRED` for each name in it is FAIL,
exit 1 [ctl:OMEGA-KERNEL-GATE-WIRING/wrapper-controls-ignored]. Each arm of `kernel/tests/gates/run.sh` starts with
`need TOOL...`: a tool missing from PATH is NOT_RUN, exit 3, before anything runs
[ctl:OMEGA-KERNEL-GATE-WIRING/no-cargo-crypto-boundary].

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
fails unless each of aienux's 25 gates, the steps omega-mv added (make-test, gate-wiring, spinlock) and each
step of `kernel/tests/gates/run.sh` has such a manifest or a row in the table below, and not both
[ctl:OMEGA-KERNEL-GATE-WIRING/remove-manifest] [ctl:OMEGA-KERNEL-GATE-WIRING/kernel-step-added] [ctl:OMEGA-KERNEL-GATE-WIRING/migration-and-manifest]. It reads manifests with the grammar
of the judge's parser (aien-sovereign-core-mv `tools/aien-test/src/manifest.rs`): a duplicate key, an
unknown key, a tab or a CR is refused [ctl:OMEGA-KERNEL-GATE-WIRING/exec-duplicate] [ctl:OMEGA-KERNEL-GATE-WIRING/exec-decoy-notes] [ctl:OMEGA-KERNEL-GATE-WIRING/manifest-tab]. The
manifest must name gate `OMEGA-KERNEL-<STEP>`, exec `tests/gates/run.sh` and args `["kernel-<step>"]`,
expect exit 0 and verdict PASS, require host, qemu, portable or aarch64 and nothing else, and list
tracked inputs that cover each path the step's arm names [ctl:OMEGA-KERNEL-GATE-WIRING/requires-gb10] [ctl:OMEGA-KERNEL-GATE-WIRING/expects-exit-1] [ctl:OMEGA-KERNEL-GATE-WIRING/inputs-readme-only].
Routing is decided by bash, not by reading text: the kernel runner's case patterns come from bash itself
and each arm is dry-run under a DEBUG trap [ctl:OMEGA-KERNEL-GATE-WIRING/kernel-step-indented] [ctl:OMEGA-KERNEL-GATE-WIRING/kernel-step-underscore]; the root
runner is run against stub kernel runners that exit 0, 1, 3 or 127 or print NOT_RUN, SKIP or control
lines, and must give the exits `kernel_step` promises [ctl:OMEGA-KERNEL-GATE-WIRING/root-arm-shadow-indented] [ctl:OMEGA-KERNEL-GATE-WIRING/root-arm-or-true].
It also requires `.aien/always` to list OMEGA-EVIDENCE-IMMUTABLE, OMEGA-ZERO-DISK-SECRETS,
OMEGA-KERNEL-CRYPTO-BOUNDARY, OMEGA-KERNEL-GATE-WIRING, OMEGA-GATE-ANCHOR and OMEGA-GATE-CLAIMS, each with a
manifest [ctl:OMEGA-KERNEL-GATE-WIRING/always-anchor-dropped] [ctl:OMEGA-KERNEL-GATE-WIRING/always-claims-dropped], no gate name in two manifests
[ctl:OMEGA-KERNEL-GATE-WIRING/gate-name-twice], and no `omega-kernel-*.gate` naming a step nobody runs [ctl:OMEGA-KERNEL-GATE-WIRING/orphan-manifest].
It runs no gate itself. With `--self-test` (how the gate runs it) its mutant controls, and per step one run
with each tool of the step's `need` list removed from PATH, must give the result required; each prints
its CONTROL line.

### Aienux gates without a manifest

| Aienux gate | Here | Reason |
| --- | --- | --- |
| `zero-disk-secrets` | REPLACED; not run as its own gate | Omega-mv's always-run OMEGA-ZERO-DISK-SECRETS (`tests/gates/run.sh zero-disk-secrets`) looks for the same name pattern, `.env*`, in every tracked path and every untracked file of the whole checkout except `./.git` and `./build`. Aienux's step (`kernel/tests/gates/run.sh zero-disk-secrets`, still there) looked only in `kernel/`, to depth 4, and skipped `.git`, `target/` and `vendor/` at any depth, so everything it caught the root step catches. The controls in `omega_gate_wiring.sh --self-test` run the root step on a scratch repository with a `.env` file planted under `kernel/`: untracked at its top, tracked in a suite, at depth 6, under `vendor/` and under `target/`; each must FAIL, and the same repository without the plant must pass. |

### Run once, 2026-11-18

At the commit now `ef5843304` (run before the rebuild above, on its first-import twin, whose tree differs
only in `import/commit-map` and `import/ref-map`; with the root runner's `kernel-*` and `kernel-gate-wiring` arms of kernel/fix2-gates
applied), each step in a fresh clone through `tests/gates/run.sh <step>`, on an AArch64 Linux host at load
15 to 42. Exit 0: `kernel` (all six), `kernel-gate-wiring`, and the kernel steps ck-gate-selftest,
ck-hold-selftest, ck-owner-keys, crypto-boundary, native-capability, native-sig, native-crypto,
native-argus, native-net, native-disk, native-m5, store-native, infer-crate, ck-stage-tests, disk-qemu,
ck-b7b-probe, ck-qemu-gates (59 minutes) and verify-all (24 minutes). Exit 1, failing closed as they did
in aienux: infer-forward (its model file is not on that host) and ck-qemu-external (`ALLEN_MODEL`,
`LOCAL_MODEL_WEIGHTS` and `LOCAL_MODEL_TOKENIZER` unset). verify-all failed once beside a concurrent
ck-qemu-gates: `scripts/test_trust1_measurement_tools.sh` picks a random swtpm port and got "Address
already in use"; it passed alone. A run is an observation of that commit, not a qualification. Since
then the software-TPM tests start swtpm through `scripts/swtpm_start.sh`, which takes another port pair
while one is in use and only a pair its own swtpm listens on (control `scripts/test_trust1_swtpm_port.sh`,
run by verify-all). And infer-forward and ck-qemu-external now report a missing model file or input as
NOT_RUN, exit 3, which the judge does not take for a pass either.

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
  check in omega-mv. The gate now requires `aienux@COMMIT` to have exactly one `import/commit-map` row,
  naming a commit of the history the fold brought in (the rewritten main in `import/ref-map` or one of
  its ancestors); `import/` is additions only, so a row cannot be repointed. The rows keep their aienux
  hashes.
- Omega-mv's `aienos.lock` and `argus.lock` named aienux commits (`b84c0a67`, `b375dcaa`), both on aienux
  main. They now name those commits' omega-mv commits (`593c755e`, `b7c5e158`), whose
  `kernel/native/capability` and `kernel/native/argus` trees have the same ids as in aienux, and are read
  from `kernel/`, not from a sibling `../aienos` checkout: `tools/aienos_lock_source.sh` extracts and
  proves the subpaths from the locked commit's `kernel/` tree and reads no commit map, so the lock id
  alone names the bytes. `tests/gates/run.sh` (`aienos_pin`, `argus_pin`), the Makefile
  (`AIENOS_LOCK_REPO`, `ARGUS_REPO`, now empty by default) and the receipt tools (`AIENOS_REPO`) use it; a
  repository holding the locked commit can still be named.

## Still outside omega-mv

Content the kernel's tools name that is only on aienux side branches was not imported:

| What | Where | Here |
|---|---|---|
| The twenty Allen EFI sources `tools/imac-image/build-efi.sh` composes | aienux `feat/allen-imac-competition` `d4ffde3cac2e73b568c0f958a9cefe8cb21f2c07` | Fourteen equal `native/omega/allen`; `platform.om`, `surface.om`, `github.om`, `net.om`, `repository-screen.om` and `efi-main.om` differ. The script carries the sha256 of each at `d4ffde3c` and exits 3 (NOT_RUN) unless `ALLEN_SRC` holds exactly those. |
