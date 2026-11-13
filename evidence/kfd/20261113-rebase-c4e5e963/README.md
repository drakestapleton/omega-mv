# KFD words rebased onto Radicle main c4e5e963, reseeded and repinned

Host spark-b87b (aarch64, Linux 7.0.0-1019-nvidia), branch `amdserve/kfd-word`, CPU only.
No GPU, no AMD hardware, nothing on 18091. Every gate ran through `tools/gate.sh`:
`flock ~/handoffs/hive/queen/pool-16-18.lock taskset -c 16-18 nice -n 10 CMD`.

Status: IMPLEMENTED and EXERCISED on the host. Not independently reviewed, not MERGED,
not DEPLOYED. The KFD words have not run against an AMD GPU (NOT_RUN).

## Source

| | sha |
|---|---|
| base (Radicle main) | `c4e5e963d7f2e813ff88e61fe26c1f63d29ced22` |
| KFD head after rebase | `dbe8900433e19365af99ee26f212b8ba7becf0c9` |
| gated head (repin) | `5374214664f55507cde1b5b75c44894461ca6a94` |
| omc before (main) | `106558ba…` (`compiler-before.sha256`) |
| omc after (fixpoint) | `84ce3eb9906649d3fc39de30910093e695143b388031bcb1edff926631744c11` |
| `seed/omc/omc.om` | `92212c60a3d2649efd2992f83365bbd53eaa72be6b0d7be214df4bb3f9b5940c` |

`rebase-map.tsv` maps each of the six KFD commits (old sha, new sha, subject). The
pre-rebase line is kept on the local branch `kfd-word-pre-rebase-290ad5fe` (290ad5feb,
omc `ca20b6a5…`). At each conflicting commit `tools/resolve.sh` resolved the two
derived files. It merged `seed/omc/size-history.tsv` by taking main's rows and then
this commit's rows that are not already there. It reseeded `seed/out/omc` from the
merged `omc.om` with `seed/omega-from-seed.sh`. Finally it appended the size-history
row for the new compiler, using the formula of `tests/kfd/check.py --record-history`.

## Repin

The repin used a copy of the out-of-repo tool that landed a7260bed,
`~/work/hive/omega-pools/scratch/repin3.py`. `tools/repin3.diff` shows the copy's
changes: a PROFILES entry for this branch, and `seed/ng/front/README.md` removed from
FILES because main now derives that pin. Result: 30 files changed (26 text files and 4
regenerated `src/` files, regeneration byte-for-byte PASS), bridge pin 96292423
(`tools/repin3.log`).

## Gates

`exits.tsv` has one row per run (name, exit, start, end, command); the log for each row
is `logs/NAME.log`. `exits-pre-repin-dbe89004.tsv` and `logs-pre-repin-dbe89004/` record
gate18, semhash and kfd-check at dbe89004, before the repin (all exit 0).

The first full pass is `tools/allgates.sh` at 53742146 (1719 s). These exited 0:
gate18, semhash, kfd-check, seed (GATE5 PASS), gate-pools, a64efi, x86efi,
make-compiler, evidence-immutable, zero-disk-secrets, om-units, irwasm, orig4-shadow,
irequiv, json, parity-codec and prefetch-native.

Other exits in the first pass, and the reruns that settled them (each rerun is its own
row in `exits.tsv`):

| first run | exit | reason | rerun | exit |
|---|---|---|---|---|
| parity-aarch64, -evidence, -gpumath, -receipt | 3 | `OMEGA_OMC` unset | `*-omc`, with `OMEGA_OMC=$PWD/seed/out/omc OMEGA_BRIDGE=$PWD/build/pins/omega-bridge` | 0 (bindability NOT_RUN: bridge 96292423 is not the scripts' NATIVE_PIN) |
| same four | | bindability | `*-bind`, with `OMEGA_BRIDGE=build/pins/omega-bridge-94a83e8` (native.om 2c2c53f6…, the NATIVE_PIN) | 0 (28 / 13 / 15 / 5 units bindable) |
| parity-codec | 0 | | `parity-codec-mutants` (`--mutants`) | 0 (all 21 mutants change their stream's hash) |
| nl4 | 128 | lock names aien-protocols-mv commit 6fb728a1, absent from Radicle | `nl4-r2` (`tools/nl4.sh`) after fetching 6fb728a1 read-only from a local clone | 0 (OM2GATE PASS cases=63 fail=0 not_run=0) |
| irspirv | 3 | spirv-val absent | `irspirv-pocl`, environment from `~/work/E1Open/tools/env.sh` | 0 (cases=129 validated=18 refusals=16) |
| irnki | 3 | no NKI oracle | `irnki-oracle`, `NKI_ORACLE_DIR` from `seed/nki/setup-oracle.sh` (all downloads at its pins) | 0 (trn1 trn2 trn3) |
| irstablehlo | 3 | no IREE | `irstablehlo-oracle`, venv with the README's pinned wheels | 0 (7 cases, 23 negatives caught) |
| tensix | 3 | ttsim absent (C6) | `tensix-ttsim`, ttsim v1.15.0 at the gate's pins in `build/oracle/` | 0 (RESULT PASS) |
| vkspirv | 3 | spirv-val absent | `vkspirv-lvp`, lavapipe, Vulkan headers from libvulkan-dev 1.4.328 | 3 (all other rows PASS; portlab rows NOT_RUN: `bench/portlab` is not in the tree) |
| | | | `vkspirv-lvp-portlab`, `PORTLAB_DIR` = untracked PortLab worktree (tree hash in `oracles.tsv`) | 0 (modules=26 rows=176) |

`oracles.tsv` lists every oracle path and sha256. They are interop oracles, not Omega and
not hardware.

## KFD counts (`results.json`, from `tests/kfd/check.py`)

355 rows, 0 mismatches. Of these, 124 expect a nonzero exit (refusals: a64 61, x86 61,
keyword 2). The 8 compiler mutants (request, size, address, kind, function,
literal-size, map-fd, sibling) are all killed, across 30 killed rows. Both keyword
controls pass: coordinated removal is detected (exit 1 as expected), and so is the
reason it fails. Row names and outcomes are identical to `../20261112-keyword-review/`.

## Findings: hand-maintained copies

1. The compiler pin is typed into 30 files: AUDIT_SCOPE.md, native/orig4/orig4.pin,
   native/prefetch/{README.md,compiler.sha256}, neuralese/README.md,
   om/{aarch64,codec,evidence,gpumath,receipt}/parity/run.sh,
   om/{codec,gpumath,quantity,receipt,sha256}/README.md, om/units.sh,
   seed/equiv/gate-irequiv.sh, seed/json/tests/gate-json.sh, seed/nki/gate-irnki.sh,
   seed/semhash/{README.md,check.sh}, seed/spirv/{gate-irspirv.sh,gate-vkspirv.sh},
   seed/stablehlo/gate-irstablehlo.sh, seed/tensix/gate-tensix.sh, seed/wasm/gate-irwasm.sh,
   src/omega_native.h, src/omega_om_units.{c,ident}, src/omega_om_units_fs.c.
   - The source of truth is `seed/out/omc.sha256`.
   - These copies are kept true by `repin3.py`. That script is an out-of-repo scratch
     tool, and each landing patches it again.
   - Cure: read the pin from `seed/out/omc.sha256` the way `seed/ng/front` now does, or
     bring the repin into the repository as a seeded tool run by the landing.
2. `NATIVE_PIN` in the four parity scripts is 2c2c53f6 (bridge 94a83e8), while
   `om/omega-bridge.lock` and `om/units.sh` pin bridge 96292423 (native.om 2c1bf637).
   The same drift is on main.
3. The nl4 dependency lock names aien-protocols-mv commit 6fb728a1. That commit is
   GitHub-era history and is absent from Radicle; Radicle's 703eb1b carries the same
   `validator.om` blob (e85d1748…).
4. The vkspirv portlab rows read `bench/portlab`, which is in no Radicle commit. It exists
   only untracked in `~/handoffs/PortLab/work/omega-mv`.
