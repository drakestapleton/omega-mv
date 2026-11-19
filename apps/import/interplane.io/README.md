# How `apps/interplane-site/` came from `interplane.io` (2026-11-18)

Source: `interplane.io` (`rad:z399yKvnXcBQNkKoq86iBDgTvQ5QV`) main `4573e1d996e0c8673dba07bad861c4b25da392aa`, from a fresh clone of `https://interplane.io/projects/interplane.io/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (27 commits, 4 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `interplane.io` commit reachable from `4573e1d996e0`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
