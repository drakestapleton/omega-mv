# How `aienux/supervisor/` came from `spark-supervisor` (2026-11-18)

Source: `spark-supervisor` (`rad:z3HQENMJfT9o14N3oDQtY4YPFak73`) main `60c0c046b629f76b0bb736480a4fb44babf82230`, from a fresh clone of `https://interplane.io/projects/spark-supervisor/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (6 commits, 10 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `spark-supervisor` commit reachable from `60c0c046b629`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
