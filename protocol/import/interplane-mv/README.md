# How `protocol/interplane/` came from `interplane-mv` (2026-11-18)

Source: `interplane-mv` (`rad:zNhNbqYvgSBEHBq9vvE8xpbcBzGa`) main `0a468827d3e41523ce728812c8006badc640ad33`, from a fresh clone of `https://interplane.io/projects/interplane-mv/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (10 commits, 3 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `interplane-mv` commit reachable from `0a468827d3e4`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
