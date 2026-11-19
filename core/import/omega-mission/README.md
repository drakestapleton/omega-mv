# How `core/mission/` came from `omega-mission` (2026-11-18)

Source: `omega-mission` (`rad:z6HYc7ot5JZD8FSfvU77pWdMUdru`) main `87705b4bc7d564af0d83e38500d92111882b4e6a`, from a fresh clone of `https://interplane.io/projects/omega-mission/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (6 commits, 3 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `omega-mission` commit reachable from `87705b4bc7d5`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
