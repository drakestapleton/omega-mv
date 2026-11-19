# How `si/architecture/` came from `aien-architecture-mv` (2026-11-18)

Source: `aien-architecture-mv` (`rad:z37zcFYooiuCCZsf5L74eeFJYiwWM`) main `a692b38a28d45dea15edd4efe5d8121a01b8206d`, from a fresh clone of `https://interplane.io/projects/aien-architecture-mv/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (23 commits, 27 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `aien-architecture-mv` commit reachable from `a692b38a28d4`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
