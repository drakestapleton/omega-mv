# How `train/omega-llm/docs/` came from `aien-train` (2026-11-19)

Source: `aien-train` main `f1bebdf3c5b08ec624005e5bc39d0427a87f9537`, fresh clone of the Spark mirror `~/git/aien-train.git`.

Tool: `git filter-repo` (`a40bce548d2c`), one pass, `filter-repo-command.txt`, with `paths.txt`: every `docs/omegallm/*.md` renamed to `train/omega-llm/docs/`. `docs/omegallm/.crumb` (retired crumb metadata, DRA-97) is left upstream.
The rewritten branch (130 commits, 15 Markdown files) was merged with `git merge --allow-unrelated-histories`.

- `commit-map`: "old new" for every `aien-train` commit reachable from `f1bebdf3c5b0`; forty zeros for commits touching no kept path.
- `ref-map`: the rewritten branch (`f1bebdf3c5b0` -> `1e3a4fb22a6f`).

Commit messages, authors and dates are kept (`--preserve-commit-hashes`). The upstream repository was not modified.
Drake and Omega Lead (2026-11-19): Omega LLM code and docs move into omega-mv; its shell/Python harness, evidence and the C++ UI bridge stay in aien-train.
