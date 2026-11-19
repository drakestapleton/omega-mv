# How `bridge/omega-bridge/` came from `omega-bridge` (2026-11-18)

Source: `omega-bridge` (`rad:z3Hr9ZaiKHwwuNzPK5M8c7uw6pj7y`) main `1e24af598fb2c9847e53df8d264d1061c792ac16`, from a fresh clone of `https://interplane.io/projects/omega-bridge/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (100 commits, 181 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `omega-bridge` commit reachable from `1e24af598fb2`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
