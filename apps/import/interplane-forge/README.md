# How `apps/interplane-forge/` came from `interplane-forge` (2026-11-18)

Source: `interplane-forge` (`interplane:interplane-forge`) main `3df50b9554ac999c45c6eaea50884e11e257bc45`, from a fresh clone of `https://interplane.io/projects/interplane-forge/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (241 commits, 158 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `interplane-forge` commit reachable from `3df50b9554ac`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
