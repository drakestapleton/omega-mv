# How step 1 came from Aienux (2026-11-18)

Source: Aienux (`rad:z2Q6ob2gL6Qo5oUMpyehukayVF7mN`) main `1f12818d06ab0eb89cd592f83e13197477b36c07`, from a fresh clone of `https://interplane.io/projects/aienux/repo.git`.

Tool: `git filter-repo` (`filter-repo.version`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`:

| Kept (Aienux) | Renamed to | Files |
| --- | --- | ---: |
| `native/net/tcp/*.om` | `aienux/net/tcp/` | 5 |
| `native/disk/**/*.om` | `aienux/disk/` | 6 |
| `native/omega/allen/**/*.om` | `aienux/allen/` | 109 |
| `native/omega/platform/*.om` | `aienux/platform/` | 2 |
| `native/kernel/x86/**/*.om` | `aienux/kernel/x86/` | 4 |
| `native/om/lm1b/*.om` | `aienux/lm1b/` | 3 |
| `tools/spark-image/*.om` | `aienux/tools/spark-image/` | 1 |
| `tools/imac-image/*.om` | `aienux/tools/imac-image/` | 1 |
| `tools/hwgates/*.om` | `aienux/tools/hwgates/` | 1 |

The rewritten branch (22 commits, 132 `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history matches one of the kept `.om` patterns: pure Omega source only, with no C, Rust, assembly, shell, Python, or retired crumb files.

- `commit-map`: "old new" for every Aienux commit reachable from `1f12818d`; forty zeros for a commit that touched none of the kept paths. Look an Aienux hash up with `grep '^SHA' aienux/import/step1-om/commit-map`.
- `ref-map`: the one rewritten branch.

Commit messages, authors and dates are kept; an Aienux hash named in a message stays the Aienux hash (`--preserve-commit-hashes`). The Aienux repository itself was not changed.
