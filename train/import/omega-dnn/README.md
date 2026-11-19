# How `train/dnn/` came from `omega-dnn` (2026-11-18)

Source: `omega-dnn` (`rad:z3EEujVZkpBNXbCVdnrENJuoMKBdg`) main `4114cbff81f5f5042dd57f38f3ae3dadf7fd5812`, from a fresh clone of `https://interplane.io/projects/omega-dnn/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (1 commits, 1 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `omega-dnn` commit reachable from `4114cbff81f5`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
