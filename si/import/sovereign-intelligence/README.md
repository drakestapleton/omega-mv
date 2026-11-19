# How `si/front-door/` came from `sovereign-intelligence` (2026-11-18)

Source: `sovereign-intelligence` (`rad:z2JJz4RDfZZxKGBLn6UhmW5p9VJQj`) main `6e44b5cfc22cf2b9ba2c3a185d4f51c0db1d69cd`, from a fresh clone of `https://interplane.io/projects/sovereign-intelligence/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
Grandfathered copies (`harness/`, `gpu/`, `seed/`) were excluded because their canonical sources are imported directly; kept prefixes: `compiler/, tools/, tests/`.

The rewritten branch (29 commits, 27 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `sovereign-intelligence` commit reachable from `6e44b5cfc22c`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
