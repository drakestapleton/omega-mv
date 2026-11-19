# How `apps/aienos-site/` came from `aienos.com` (2026-11-18)

Source: `aienos.com` (`rad:z3iwnx2pktbGhnfBpJSsaFcTmKgHU`) main `fd9dd20cde24e72edd75d020609706cef9240726`, from a fresh clone of `https://interplane.io/projects/aienos.com/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (223 commits, 200 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `aienos.com` commit reachable from `fd9dd20cde24`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
