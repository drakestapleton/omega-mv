# How `core/sovereign-core/` came from `aien-sovereign-core-mv` (2026-11-18)

Source: `aien-sovereign-core-mv` (`rad:z44GqrPVAPjZkhoD2MWVjqy18ighN`) main `c030d36461338830bc9276cf97d2b065b9285edc`, from a fresh clone of `https://interplane.io/projects/aien-sovereign-core-mv/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (42 commits, 58 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `aien-sovereign-core-mv` commit reachable from `c030d3646133`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
