# How `si/rosetta/` came from `omega-rosetta` (2026-11-18)

Source: `omega-rosetta` (`rad:z3ZYVx6LRT6gkwLc13zR94wtENPn3`) main `54e42583435b63644a99ffe715aa03dd74575505`, from a fresh clone of `https://interplane.io/projects/omega-rosetta/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (3 commits, 367 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `omega-rosetta` commit reachable from `54e42583435b`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
