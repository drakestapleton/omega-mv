# How step 3 came from CUDApp (2026-11-14)

Source: CUDApp (rad:z4RxD8vXigmWg61nM8miQ8DVPAXEP) main `84b524cadaaa8bc9b556adfaea9d6dd2e0d67a66`, from a fresh clone
of `https://www.aienos.com/rad/z4RxD8vXigmWg61nM8miQ8DVPAXEP.git`.

Tool: git filter-repo (`filter-repo.version`), a host tool used once for this import. It is not part of any build
or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`:

| Kept (CUDApp) | Renamed to |
| --- | --- |
| `om/**/*.om`, except `om/encoder/bw_enc_sm121.om`, `om/components/bw_alloc.om`, `om/cubin/cubin_elf.om` (step 2 has them at the lock commit) | `gpu/nvidia/om/` |
| `backend/spirv/*.om` | `gpu/spirv/` |
| `backend/hw/*.om`, `backend/hw/manifest.tsv` | `gpu/hw/` |
| `backend/targets.om` | `gpu/targets.om` |

The rewritten branch (356 commits) was merged with `git merge --allow-unrelated-histories`. Every file in that
history is one of the kept paths: Omega source and the one table `hwman` reads.

- `commit-map`: "old new" for every CUDApp commit reachable from the source commit; forty zeros for a commit that
  touched none of the kept paths. Look a CUDApp hash up with `grep '^SHA' gpu/import/step3-om-backend/commit-map`.
- `ref-map`: the one rewritten branch.

Commit messages, authors and dates are kept; a CUDApp hash named in a message is still the CUDApp hash
(`--preserve-commit-hashes`). CUDApp itself was not changed.
