# gpu/amd/rest: the AMD leftovers, checked in Omega

CUDApp (main 84b524cadaaa8bc9b556adfaea9d6dd2e0d67a66) kept AMD checkers in C, Python, shell and assembly.
Their behaviour is replayed here by `gate.om` against tables recorded from those old checkers. The old
files stay in CUDApp as the oracles that recorded the tables.

| part | old checker | table |
|---|---|---|
| 1 | `backend/amd/gfx942/*.s` with llvm-mc 18.1.3 | `llvm18-sections.tsv` |
| 2 | `tests/amd-kfd-launch/check.py` | `launch-verdicts.tsv` |
| 3 | `tests/amd/*.py`, `tests/amd/run.sh` | `writer-verdicts.tsv` |
| 5 | `tests/amd-kfd/oracle.py`, `tests/amd-kfd/run.sh` | `kfd-verdicts.tsv` |
| 6 | `tests/amd-kfd-launch/plan-check.py` (CPU cases) | `plan-verdicts.tsv` |

The tables were generated outside this tree by running the old checkers (oracle scripts kept with the lane,
not in the tree). Cases that need the ptrace instrument `trace.c` or a child with descriptor 2 closed are
listed as `notrun` rows and print NOT_RUN. Hardware rows are NOT_RUN on every host.

Run: `tests/gates/run.sh gpu-amd-rest` (or build by hand:
`{ printf 'om2\n'; cat seed/ng/sha256.om gpu/amd/rest/gate.om; } | seed/out/omc > gate; ./gate seed/out/omc SCRATCH`,
SCRATCH must not exist). The summary line counts `/dev/kfd` absent and `qemu-x86_64` present.

`classify.om` with `classes.tsv` generates `gpu/amd/NOT-YET-OMEGA.tsv`, the class of every leftover file:
(a) behaviour rewritten here, (b) kept in CUDApp as an oracle or instrument, (c) obsolete. An AMD path that
no rule covers is an error (exit 1):

    git -C CUDApp ls-tree -r --name-only 84b524cadaaa8bc9b556adfaea9d6dd2e0d67a66 \
      | classify gpu/amd/rest/classes.tsv > gpu/amd/NOT-YET-OMEGA.tsv
