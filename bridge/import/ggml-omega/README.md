# How `bridge/ggml/` came from `ggml-omega` (2026-11-18)

Source: `ggml-omega` (`rad:zZnK5QhLTtJTmhHuRi2BtRWQdMU4`) main `a30322c90191507c46c1b74783d722d617d4514c`, from a fresh clone of `https://interplane.io/projects/ggml-omega/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (2 commits, 24 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `ggml-omega` commit reachable from `a30322c90191`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
