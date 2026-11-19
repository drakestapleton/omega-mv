# How `train/aien-train/` came from `aien-train` (2026-11-18)

Source: `aien-train` (`rad:zKrfazKqYNFuXDDkYdptxJicGLEq`) main `b9bafc3c5a450b44fc5dd544805e0a94479501ca`, from a fresh clone of `https://interplane.io/projects/aien-train/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (162 commits, 158 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `aien-train` commit reachable from `b9bafc3c5a45`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
