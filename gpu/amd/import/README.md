# How gpu/amd came from CUDApp (2026-11-14)

Source: CUDApp (rad:z4RxD8vXigmWg61nM8miQ8DVPAXEP) main `dc536882c06a692991be97dc65cd2d037d82b129`, fetched as a
fresh single-branch clone of `https://www.aienos.com/rad/z4RxD8vXigmWg61nM8miQ8DVPAXEP.git`.

Tool: git filter-repo (`filter-repo.version`), a host tool used once for this import. It is not part of any build
or gate. The command is `filter-repo-command.txt`, run in that clone. It keeps only Omega source and the tables the units
read (Drake, 2026-11-14: "make sure it's pure omega when it's in there"):

| Old path (CUDApp) | New path |
| --- | --- |
| `backend/amd/gfx942/*.om`, `backend/amd/gfx942/exec/*.om` | `gpu/amd/gfx942/` |
| `backend/amd/gfx942/*.isa` | `gpu/amd/gfx942/` |
| `backend/amd/kfd/*.om`, `backend/amd/kfd/launch/*.om`, `backend/amd/kfd/requests.tsv` | `gpu/amd/kfd/` |
| `backend/targets.om` | `gpu/targets.om` |
| `tests/amd-exec/*-probe.om` | `gpu/amd/tests/amd-exec/` |

The rewritten branch was merged into omega-mv with `git merge --allow-unrelated-histories`. Every file and every
commit of that history is one of the paths above; no C, Python, shell or LLVM assembly is in it.

Files here:

- `commit-map`: filter-repo's own map, "old new" for every CUDApp commit reachable from dc536882. A commit that
  touched none of the kept paths maps to forty zeros. To find the omega-mv commit for a CUDApp commit quoted in a
  receipt: `grep '^SHA' gpu/amd/import/commit-map`.
- `ref-map`: filter-repo's map of the one rewritten branch.
- `filter-repo-command.txt`, `filter-repo.version`: the command and the tool version.

Commit messages, authors and dates are kept as written; a CUDApp hash named in a message is still the CUDApp hash
(`--preserve-commit-hashes`); look it up in `commit-map`. CUDApp itself was not changed.
