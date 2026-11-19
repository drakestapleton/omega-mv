# How `train/blas/` came from `omega-blas` (2026-11-18)

Source: `omega-blas` (`rad:z47VdC9EFsF4dFyH1QJ1C2JNJK4JS`) main `20180faae23c7284e071e93ed96ef0a6490da8f5`, from a fresh clone of `https://interplane.io/projects/omega-blas/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (1 commits, 1 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `omega-blas` commit reachable from `20180faae23c`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
