# How `bridge/babel/` came from `babel` (2026-11-18)

Source: `babel` (`rad:z3NKsT1A9VzBVsa5ycpHG2hKZTriE`) main `fa3206995222ef4bf328949bfe5d334cbe0b967a`, from a fresh clone of `https://interplane.io/projects/babel/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (5 commits, 10 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `babel` commit reachable from `fa3206995222`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
