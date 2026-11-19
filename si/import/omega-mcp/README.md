# How `si/mcp/` came from `omega-mcp` (2026-11-18)

Source: `omega-mcp` (`rad:z3e8UBQVfwEcESJrcTWEbyMAHWFBZ`) main `bb2ba1e28668d5cccee3fb3a7cba631fc2b2746d`, from a fresh clone of `https://interplane.io/projects/omega-mcp/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (15 commits, 96 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `omega-mcp` commit reachable from `bb2ba1e28668`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
