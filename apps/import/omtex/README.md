# How `apps/omtex/` came from `omtex` (2026-11-18)

Source: `omtex` (`rad:zcBSb6QfXYD2tVRHF6GmXBALFx66`) main `6f01dcf896a3f6433332acfd4d40a630a958241a`, from a fresh clone of `https://interplane.io/projects/omtex/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (1 commits, 5 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `omtex` commit reachable from `6f01dcf896a3`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
