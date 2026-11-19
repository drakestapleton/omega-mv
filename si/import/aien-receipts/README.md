# How `si/receipts/` came from `aien-receipts` (2026-11-18)

Source: `aien-receipts` (`rad:z4HXNamwwXyfN11ZBJXAQpdMKvojz`) main `53eefaaa3860676d0d844825ca5e097f2da2e4d5`, from a fresh clone of `https://interplane.io/projects/aien-receipts/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (1 commits, 1 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `aien-receipts` commit reachable from `53eefaaa3860`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
