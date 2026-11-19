# How `si/harness/` came from `omega-harness` (2026-11-18)

Source: `omega-harness` (`rad:z39gvwWsnkRZsAConQLjaKiNVLHfW`) main `041ba4d59f7471d0adcc082091dda6825b9c1402`, from a fresh clone of `https://interplane.io/projects/omega-harness/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (32 commits, 150 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `omega-harness` commit reachable from `041ba4d59f74`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
