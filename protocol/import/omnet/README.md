# How `protocol/omnet/` came from `omnet` (2026-11-18)

Source: `omnet` (`rad:z2Q1eD3rqPUGnsxnhd4dDzFDMQqu`) main `b8128f2dfff6b128f6d5d4c65dbc466073490eaa`, from a fresh clone of `https://interplane.io/projects/omnet/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (11 commits, 47 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `omnet` commit reachable from `b8128f2dfff6`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
