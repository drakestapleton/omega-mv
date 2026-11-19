# How `train/aien-train/` came from `aien-train` (2026-11-18)

Source: `aien-train` (`rad:zKrfazKqYNFuXDDkYdptxJicGLEq`) main `b9bafc3c5a450b44fc5dd544805e0a94479501ca`, from a fresh clone of `https://interplane.io/projects/aien-train/repo.git`.

Tool: `git filter-repo` (`a40bce548d2c`), a host tool used once for this import. It is not part of any build or gate. One pass, `filter-repo-command.txt`, with the selections and renames in `paths.txt`.
The rewritten branch (162 commits, 158 pure `.om` files) was merged with `git merge --allow-unrelated-histories`. Every file in that history is pure Omega source (`.om`) outside `evidence/`.

- `commit-map`: "old new" for every `aien-train` commit reachable from `b9bafc3c5a45`; forty zeros for commits touching no kept `.om` path.
- `ref-map`: the rewritten branch.

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.

## Refresh to `f1bebdf3c5b0` (2026-11-19)

Source: `aien-train` main `f1bebdf3c5b08ec624005e5bc39d0427a87f9537`, fresh clone of the Spark mirror `~/git/aien-train.git` (same objects as Interplane main).
Tool: the same `git filter-repo` (`a40bce548d2c`, git-filter-repo commit `19b1cb69039a`), the same `paths.txt` and `filter-repo-command.txt`, unchanged.
The deterministic re-run reproduces every one of the 427 entries of the 2026-11-18 `commit-map` byte for byte, including `ac20cd497cdf` (rewritten history at `b9bafc3c5a45`, already in `main`), so the refresh is an ordinary merge (no `--allow-unrelated-histories`) adding two `.om` commits: `e993f179` -> `5d3fbd858232` (adds `native/omegallm/mio.om` and `spec.om`; changes `adam.om`, `cli.om`, `model.om`) and `464dffdd` -> `b39b5f8b4e92` (Merkle specialist chains, `spclip`).
`commit-map` now covers all 436 commits reachable from `f1bebdf3c5b0`; `ref-map` maps `refs/heads/main` `f1bebdf3c5b0` -> `b39b5f8b4e92`.

## Omega LLM moved to `train/omega-llm/` (2026-11-19)

Right after the refresh, one rename-only commit moved `train/aien-train/native/omegallm/` -> `train/omega-llm/native/`, `tests/omegallm/` -> `train/omega-llm/tests/` and `tools/omegallm/` -> `train/omega-llm/tools/` (46 `.om` files; `git log --follow` crosses it).
`docs/omegallm/*.md` (15 files, 130 commits) came in with their own history under `train/omega-llm/docs/`; recipe in `docs-omegallm/`.
omega-mv is now the source of truth for Omega LLM `.om` code and docs (Drake and Omega Lead, 2026-11-19). A later re-run of `paths.txt` would put those files back under `train/aien-train/`; any future refresh of the other aien-train `.om` must add `native/omegallm/`, `tests/omegallm/` and `tools/omegallm/` as exclusions first.

## `train/NOT-YET-OMEGA.tsv`

`not-yet-omega-command.txt` is the exact command that regenerates the aien-train rows (1391 at `f1bebdf3c5b0`); run on `b9bafc3c5a45` it reproduces the 1401 rows of 2026-11-18 byte for byte.
