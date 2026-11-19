# How `core/aien/` came from `aien` (2026-11-18)

Source: `aien` (`rad:zDTnULpiVMniD2etkbUozUP5mn6U`) main `db0cf3d29135b9ca618e74e820295f6541a11358`, from a fresh clone of `https://interplane.io/projects/aien/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (5 commits, 6 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `aien` commit reachable from `db0cf3d29135`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
