# How step 4 came from CUDApp (2026-11-14)

Source: CUDApp (rad:z4RxD8vXigmWg61nM8miQ8DVPAXEP) main `84b524cadaaa8bc9b556adfaea9d6dd2e0d67a66`, from a fresh clone
of `https://www.aienos.com/rad/z4RxD8vXigmWg61nM8miQ8DVPAXEP.git`.

Tool: git filter-repo (`filter-repo.version`), a host tool used once for this import. It is not part of any build
or gate. One pass, `filter-repo-command.txt`, with the selection and rename in `paths.txt`: CUDApp `native/**/*.om`,
except `native/blackwell/launch.om` and `native/nvrm/context.om` (step 2 has them at the lock commit), renamed to
`gpu/nvidia/native/`.

The rewritten branch (64 commits) was merged with `git merge --allow-unrelated-histories`. Every file in that
history is a kept `.om` file.

- `commit-map`: "old new" for every CUDApp commit reachable from the source commit; forty zeros for a commit that
  touched none of the kept paths. Look a CUDApp hash up with `grep '^SHA' gpu/import/step4-native/commit-map`.
- `ref-map`: the one rewritten branch.

Commit messages, authors and dates are kept; a CUDApp hash named in a message is still the CUDApp hash
(`--preserve-commit-hashes`). CUDApp itself was not changed.
