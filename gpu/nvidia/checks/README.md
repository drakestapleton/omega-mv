# gpu/nvidia/checks: CUDApp tests and tools, in Omega

CUDApp kept its tests and tools in C, Python and shell (`tests/`, `tools/`). This directory holds what replaces them inside omega-mv, written only in Omega, plus the tables of expected values they read.

## What is here

| File | What it is |
|---|---|
| `INVENTORY.tsv` | One row for every file of CUDApp `tests/` and `tools/` that is not Omega, with its status. Generated; do not edit. |
| `ports.tsv` | The decision for each such file: `ported`, `retired` or `blocked`, with the reason. Written by hand; this is the only human input. |
| `inventory.om` | The program that writes `INVENTORY.tsv`. |
| `checks.tsv` | The checks the gate runs: name, table, then the Omega parts that make up the check program. |
| `gate.om` | The gate `OMEGA-GPU-CHECKS` (`tests/gates/run.sh gpu-checks`). |
| `lib.om` | The table reader every check shares. It is OM-1, so it composes with units of either dialect. |
| `lib-om2.om` | Helpers that take a text (`ckis`). OM-1 has no unsized view, so these exist only for checks whose first unit starts with `om2`; such a check lists it after `lib.om`. |
| `mutants.tsv` | Source mutants: one-line changes to a unit under test that its check must notice. |
| `NAME.om`, `NAME.tsv` | One check and its table of expected values. |

## How a check works

A check is one program made of parts joined in order: the `gpu/` Omega units under test, then `lib.om`, then the check itself. `lib.om` reads the table one line at a time and calls the check's `crow` for each case. A case is a line that is neither empty nor starts with `#`. The program prints one `FAIL line N:` line per failed case and ends with `NAME PASS rows=N`, exit 0, or `NAME FAIL rows=N failed=F`, exit 1. A table with no case fails. A field it cannot read gives exit 2.

The tables hold the old implementation's own answers. To make one, a small C driver was compiled against the old CUDApp sources at 84b524ca and run outside this repository. Its output was committed as the table; the C driver itself is not committed. The header lines of each table name the oracle and its commit.

Some units are function-mode units: they export their functions with `export fn` and have no `main`. The compiler refuses a program that has both `export fn` and a `main`. So, when the gate joins the parts, it turns any line that starts `export fn ` into `fn `. Nothing else in the unit changes, and the function bodies are tested exactly as committed.

The program's dialect is set by its first unit: `om2` must be the program's first line that is not a note. An OM-1 unit cannot always be forced into OM-2, because OM-2 reserves words some OM-1 units use as names (`gpu/nvidia/om/gdn/admit.om` defines `fn layout`). This is why `lib.om` is OM-1 and the text-taking helpers live in `lib-om2.om`.

## The gate

```
tests/gates/run.sh gpu-checks
```

The gate first checks that `seed/out/omc` matches `seed/out/omc.sha256`. Then, for each row of `checks.tsv`, it:

1. joins the parts;
2. compiles them twice and requires identical bytes and empty stderr;
3. runs the check on its table and requires exit 0;
4. runs it again on a copy of the table with one byte changed, and requires exit 1 (the table control);
5. for each row of `mutants.tsv` that names this check, joins the parts again with the first line of the named part that equals FROM replaced by TO, requires that to compile, and requires the check built from it to exit 1 on the true table (a source-mutant control). FROM is matched after the `export fn ` strip. A FROM that is no longer a line of its part, a mutant that does not compile, and a mutant the check does not notice each fail the gate.

A wrong-compiler control runs once. The summary must read `OMEGA-GPU-CHECKS PASS checks=N controls=C caught=C hardware=NOT_RUN`, where `run.sh` takes N from the rows of `checks.tsv` and M from the rows of `mutants.tsv`, and C = N + M + 1. Nothing here opens a device. Any hardware tier of an old test is recorded as NOT_RUN in `ports.tsv`.

## Regenerating INVENTORY.tsv

`INVENTORY.tsv` depends on the CUDApp files, which are not in this repository, so the gate does not rebuild it. Regenerate it after every change to `ports.tsv`, from a CUDApp checkout at the commit named in its second line:

```
seed/out/omc < gpu/nvidia/checks/inventory.om > inventory && chmod 700 inventory
git -C CUDApp ls-files tests tools > list.txt
git -C omega-mv ls-tree -r --name-only HEAD -- gpu > gpulist.txt
cd CUDApp && ../inventory ../list.txt ../gpulist.txt ../omega-mv/gpu/nvidia/checks/ports.tsv "LABEL" > ../omega-mv/gpu/nvidia/checks/INVENTORY.tsv
```

LABEL is the inputs line: copy it from the second line of the current `INVENTORY.tsv`, changing the commits if they moved. `inventory` exits 1 in two cases: a `ports.tsv` row names no CUDApp path, or a path appears twice. It exits 2 on a malformed row.

## Checks

| Check | Replaces | Units under test | Not ported |
|---|---|---|---|
| `leftovers` | `tests/leftovers_test.c` | `gpu/nvidia/om/components/pathcopy.om`, `leftovers.om` | The NULL-pointer cases, which exist only in the C binding (`omega_path_check.h`); Omega has no null view. |
| `gdn_admit` | `tests/gdn_admit_diff.c` | `gpu/nvidia/om/gdn/admit.om` (all eight ops: shape, alloc, layer, finite, multi, tokens, prefill layout, move) | Nothing: the table holds the C test's whole domain, 1276 cases, each with the C oracle's verdict and outputs. The C test's check that some but not all cases were admitted holds for the table (268 admitted, 1008 refused). |

`tests/pathcopy_mutants.py` became lines 5 to 9 of `mutants.tsv`. Each Python mutant is written as the one line of `pathcopy.om` it changes; the gate kills each one through the `leftovers` check, as the Python did through `tests/leftovers_test.c`.
