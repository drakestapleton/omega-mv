# How `si/benchmarks/` came from `benchmarks-mv` (2026-11-18)

Source: `benchmarks-mv` (`rad:z2nYCN9XZAPjNohqT8bz46rcs9zvZ`) main `033d0149cbfee847636d825e193ed210f7867f11`, from a fresh clone of `https://interplane.io/projects/benchmarks-mv/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (10 commits, 31 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `benchmarks-mv` commit reachable from `033d0149cbfe`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
