# How `si/editors/vscode/` came from `vscode-omega` (2026-11-18)

Source: `vscode-omega` (`rad:z2cJRW4NtoaUva2wZCPiqxXpMBktn`) main `74ac113b48bba427d6b2cba5452a1f6a02d9eac8`, from a fresh clone of `https://interplane.io/projects/vscode-omega/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (1 commits, 3 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `vscode-omega` commit reachable from `74ac113b48bb`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
