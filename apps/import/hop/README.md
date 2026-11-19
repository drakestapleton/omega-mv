# How `apps/hop/` came from `hop` (2026-11-18)

Source: `hop` (`interplane:hop`) main `59208f4d3b4a2af63706526f390002df2fd1890c`, from a fresh clone of `https://interplane.io/projects/hop/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (38 commits, 28 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `hop` commit reachable from `59208f4d3b4a`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
