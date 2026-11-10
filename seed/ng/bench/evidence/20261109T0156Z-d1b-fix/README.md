# D1b fix: absent vs present-but-unusable files (HOST_TESTED, core 1)

Review finding F1 on 70168d58 (factory bay 6, MERGE_AFTER_FIX): `hashpb` returned 2^63 both for a file that is
absent and for one that is present but cannot be used, and run mode reads 2^63 as "absent". A stdin file
DIR/in/CASE of 16 MiB or more, or a directory there, silently lost its I row (rc 0); a present unlisted arm binary
of 16 MiB or more was silently skipped (rc 0).

Fix (one commit): `hashpb` (seed/ng/bench/ngbench-sha.om) returns 2^63 only when open fails with ENOENT (errno 2),
and 2^63 + 1 for every other open failure, a failed read (a directory: EISDIR) or 16 MiB or more. Run mode refuses
2^63 + 1 as `R input CASE` (stdin, ngbench.om `wants`) or `R label CASE ARM` (arm binary, `identone`). Callers that
test `ge 2^63` (sum, outok, recheck) are unchanged. This takes bay 6's proposal (8a9b6acd, which split only the
read and size failures) and closes the case it left open: a present file that open refuses (EACCES, mode 000) was
still reported as absent (rows `nc-*-mode000 bay6` below: rc 0, the I row or the pair silently gone).

Binaries (seed/out/omc cfd96b48, `cat seed/ng/ngbench.om seed/ng/sha256.om seed/ng/bench/ngbench-sha.om | omc`):
- fixed (this commit) c1c4412c333d758ddde56916878da0cc168020abca8fe71426687b93b4d35a9f
- D1b 70168d58 47f399c88fed6b8fa8034c8ffcd6cd645cf5699739b9e410414b1c3a4d194622 (= its READY)
- bay 6 proposal 06e729b348afd39e7856187ff5ffe454afc603913bf6a5be160ead4dfc52a9e1 (= bay 6's fixtest.log)

`controls.sh.txt` (sha256 a0d5ab40...) built the fixture and ran every case with all three binaries, uid 1000;
`controls-log.txt` (sha256 15a8ac54...) is its output. Result for the fixed binary:

| case | fixed | D1b | bay 6 |
|---|---|---|---|
| no stdin; 6-byte stdin; 16 MiB - 1 stdin | rc 0, I row as expected | same | same |
| stdin 16 MiB | rc 1 `R input` | rc 0, no I row | rc 1 |
| stdin is a directory | rc 1 `R input` | rc 0, no I row | rc 1 |
| stdin mode 000 | rc 1 `R input` | rc 0, no I row | rc 0, no I row |
| binary 16 MiB, listed | rc 1 `R label` | rc 1 `R missing` (wrong reason) | rc 1 `R label` |
| binary 16 MiB, unlisted | rc 1 `R label` | rc 0, pair skipped | rc 1 |
| binary mode 000, listed | rc 1 `R label` | rc 1 `R missing` | rc 1 `R missing` |
| binary mode 000, unlisted | rc 1 `R label` | rc 0, pair skipped | rc 0, pair skipped |
| binary absent, unlisted (allowed) | rc 0, pair skipped | same | same |
| binary absent, listed | rc 1 `R missing` | same | same |
| sum: 18 sizes 0..16 MiB-1 + 3 binaries | equals coreutils sha256sum (21 files) | same | - |
| sum: 16 MiB, missing, mode 000, directory | rc 1 each | same | - |

No timing round: hashing stays outside the fork..waitpid interval (runone), so timed numbers are unaffected.
