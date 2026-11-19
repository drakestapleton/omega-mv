# How `protocol/synapse/map/` came from `synapse-map` (2026-11-18)

Source: `synapse-map` (`rad:z3p7NNQByiXZGsJC4cCifdTybaajY`) main `945934bb3277769236dd0623bad8ec929e20e942`, from a fresh clone of `https://interplane.io/projects/synapse-map/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (2 commits, 10 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `synapse-map` commit reachable from `945934bb3277`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
