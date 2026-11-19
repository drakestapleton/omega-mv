# How `core/rsi/` came from `spark-rsi-mv` (2026-11-18)

Source: `spark-rsi-mv` (`rad:z4AauBRPXzPNMiAoHZpRpyCee61A2`) main `2edaf6704304e089f6f50fcd3daedd71b2446840`, from a fresh clone of `https://interplane.io/projects/spark-rsi-mv/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (2 commits, 31 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `spark-rsi-mv` commit reachable from `2edaf6704304`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
