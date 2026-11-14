# How gpu/nvidia came from CUDApp (2026-11-14)

Source: CUDApp (rad:z4RxD8vXigmWg61nM8miQ8DVPAXEP) at `1988c50e93c4dd971bcb94e69692c8e57e53f54b`, the commit
`seed/ng/cudapp.lock` pins, from a fresh clone of `https://www.aienos.com/rad/z4RxD8vXigmWg61nM8miQ8DVPAXEP.git`.

Tool: git filter-repo (`filter-repo.version`), a host tool used once for this import. It is not part of any build
or gate. The command is in `filter-repo-command.txt`. It keeps exactly the five files the lock pins and renames them:

| Old path (CUDApp) | New path |
| --- | --- |
| `om/encoder/bw_enc_sm121.om` | `gpu/nvidia/om/encoder/bw_enc_sm121.om` |
| `om/components/bw_alloc.om` | `gpu/nvidia/om/components/bw_alloc.om` |
| `om/cubin/cubin_elf.om` | `gpu/nvidia/om/cubin/cubin_elf.om` |
| `native/blackwell/launch.om` | `gpu/nvidia/native/blackwell/launch.om` |
| `native/nvrm/context.om` | `gpu/nvidia/native/nvrm/context.om` |

The rewritten branch (27 commits) was merged into omega-mv with `git merge --allow-unrelated-histories`. Every file
in that history is one of these five Omega files.

- `commit-map`: filter-repo's map, "old new" for every CUDApp commit reachable from 1988c50e; a commit that touched
  none of the five files maps to forty zeros. Look up a CUDApp hash with `grep '^SHA' gpu/nvidia/import/commit-map`.
- `ref-map`: the one rewritten branch. `filter-repo-command.txt`, `filter-repo.version`: command and tool version.

Commit messages, authors and dates are kept; a CUDApp hash named in a message is still the CUDApp hash
(`--preserve-commit-hashes`). CUDApp itself was not changed.
