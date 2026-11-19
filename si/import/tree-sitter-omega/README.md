# How `si/editors/tree-sitter/` came from `tree-sitter-omega` (2026-11-18)

Source: `tree-sitter-omega` (`rad:z3Jfv1utyaw4Nm83pgmJ4yQfVmpse`) main `7b9820da408f4320996bc9bf02f2040e4fdd44fb`, from a fresh clone of `https://interplane.io/projects/tree-sitter-omega/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (2 commits, 3 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `tree-sitter-omega` commit reachable from `7b9820da408f`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
