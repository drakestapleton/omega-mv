# gpu/amd/rest: checks of the AMD leftovers, in Omega

This directory is one slice of the AMD gfx942 back end: the checks that CUDApp (main
84b524cadaaa8bc9b556adfaea9d6dd2e0d67a66) ran in C, Python, shell and assembly, written in Omega. `gate.om`
replays them against tables recorded from those old checkers. The old files stay in CUDApp as the oracles
that recorded the tables.

| part | old checker | table |
|---|---|---|
| 1 | `backend/amd/gfx942/*.s` with llvm-mc 18.1.3 | `llvm18-sections.tsv` |
| 2 | `tests/amd-kfd-launch/check.py` | `launch-verdicts.tsv` |
| 3 | `tests/amd/*.py`, `tests/amd/run.sh` | `writer-verdicts.tsv` |
| 5 | `tests/amd-kfd/oracle.py`, `tests/amd-kfd/run.sh` | `kfd-verdicts.tsv` |
| 6 | `tests/amd-kfd-launch/plan-check.py` (CPU cases) | `plan-verdicts.tsv` |

What the gate checks, per table: it builds the Omega units each table names with this repository's
`seed/out/omc`, compares the bytes and hashes the rows record (sections, objects, input files, unit
texts), runs each `run` row's command on the Omega-built binaries and compares its exit status, stdout and
stderr with what the old checker saw. Each header of a table says what its row kinds mean. Every case of
`check.py` and `plan-check.py` is either replayed or listed as a `notrun` row with its reason (a case
that needs the ptrace instrument `trace.c`, another CUDApp instrument such as `aql-oracle`,
`publication`, `cc` or `python3`, or a child with descriptor 2 closed); a `notrun` row prints NOT_RUN and
is counted in `not_run=`. Only the compiles of the unit binaries and the `hsaco` builds of the `obj`
rows have no row, because the gate does those itself. Hardware rows are NOT_RUN on every host.

The `guard` row of `kfd-verdicts.tsv` is not an oracle verdict: it is written by hand in `tables.py` and
states the gate's own control (records.om without its index guard must not refuse that index).

Before a source is composed, the gate drops each of its lines that starts with `note gate-pools:`. Those lines
are the pool declarations that `seed/omc/gate-pools.sh` (section 11) reads from the source itself, and the oracles
composed the sources without them, so the text hashed and compiled is still the oracle's. Any other change to a
source still differs and fails (control: an ordinary `note` line appended to `launch/plan.om` fails 15 rows).

The tables were generated outside this tree by the lane's oracle scripts `tables.py` (with `sections.py` and
`plan-keep.py`) from the old checkers' outputs. Those scripts and every input they read are kept outside the
repository by the lane, identified by sha256: `tables.py`
743733a4a260dd22263cc848a0e5eccf5d199ff27a95740610f110a28d526d79, `sections.py`
a7ba7e6a4e856973a0eec91a80216cd215a5953af3e41fee11482a26e6010b44, `plan-keep.py`
87b60ac43b437df63ac7f15583ef71d6bc0c37ce2246688edeb73a09a6216caf, and the `SHA256SUMS` list of every
file kept, 2333d37fbd7ccec4f6bc46be459954d41d07b14a0013c5614975adefc5306a01.

Run: `tests/gates/run.sh gpu-amd-rest` (or build by hand:
`{ printf 'om2\n'; cat seed/ng/sha256.om gpu/amd/rest/gate.om; } | seed/out/omc > gate; ./gate seed/out/omc SCRATCH`,
SCRATCH must not exist). The x86-64 launcher rows run under `/usr/bin/qemu-x86_64`. Without it, or on a
host where `/dev/kfd` exists (the launcher and plan rows would open the device), the gate prints
`OMEGA-GPU-AMD-REST NOT_RUN reason=...` and exits 3.

`classify.om` with `classes.tsv` generates `gpu/amd/NOT-YET-OMEGA.tsv`, the class of every leftover file:
(a) behaviour rewritten here, (b) kept in CUDApp as an oracle or instrument, (c) obsolete. An AMD path that
no rule covers is an error (exit 1):

    git -C CUDApp ls-tree -r --name-only 84b524cadaaa8bc9b556adfaea9d6dd2e0d67a66 \
      | classify gpu/amd/rest/classes.tsv > gpu/amd/NOT-YET-OMEGA.tsv
