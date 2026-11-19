# How `core/cortex/` came from `cortex` (2026-11-18)

Source: `cortex` (`rad:zDrGjCcXxPwjWNYQj52Y9RYzBq1t`) main `2f5f763d79b2502cb97b9241014c7d3d46f9b16c`, from a fresh clone of `https://interplane.io/projects/cortex/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (10 commits, 45 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `cortex` commit reachable from `2f5f763d79b2`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
