# How `gpu/cuda-crack/` came from `cuda-crack` (2026-11-18)

Source: `cuda-crack` (`rad:z631r2JJiVT8it4tST7RK24hpowi`) main `8efa1bb3f4cfbc468e2a12c274c19d8a3990c870`, from a fresh clone of `https://interplane.io/projects/cuda-crack/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (3 commits, 3 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `cuda-crack` commit reachable from `8efa1bb3f4cf`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
