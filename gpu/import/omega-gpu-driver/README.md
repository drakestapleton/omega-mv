# How `gpu/driver/` came from `omega-gpu-driver` (2026-11-18)

Source: `omega-gpu-driver` (`rad:z2xjD5kxUTTBNCryJ6rg9QXpemzei`) main `81b579e4c371cc6e5c1eba3c57bc93ef20040800`, from a fresh clone of `https://interplane.io/projects/omega-gpu-driver/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (16 commits, 88 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `omega-gpu-driver` commit reachable from `81b579e4c371`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
