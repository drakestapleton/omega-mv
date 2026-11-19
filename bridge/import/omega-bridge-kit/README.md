# How `bridge/kit/` came from `omega-bridge-kit` (2026-11-18)

Source: `omega-bridge-kit` (`rad:z3wKmtAMKXrdg4Lom9W5JeoPBp2iW`) main `3191f50d70ddb5bcff95ca865bce97a88bbcbf70`, from a fresh clone of `https://interplane.io/projects/omega-bridge-kit/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (1 commits, 2 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `omega-bridge-kit` commit reachable from `3191f50d70dd`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
