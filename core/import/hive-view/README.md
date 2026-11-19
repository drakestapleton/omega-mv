# How `core/hive-view/` came from `hive-view` (2026-11-18)

Source: `hive-view` (`rad:zimVqDToqH8NL2YvgM8fQBQrvgHa`) main `c9d2d6849f7bf37e864cea63bd8d69ed2faf9ae1`, from a fresh clone of `https://interplane.io/projects/hive-view/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (7 commits, 8 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `hive-view` commit reachable from `c9d2d6849f7b`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
