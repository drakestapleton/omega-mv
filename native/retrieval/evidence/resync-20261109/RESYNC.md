# L779 re-sync and replay, 2026-11-09

Recovery card t_1b575709 (run 261). Host spark-b87b, AArch64, cores 8-9 under the hive
pool lock `pool-8-9`. Nothing in this directory replaces an earlier receipt.

## Source movement

- Original candidate: branch `qualify/om-xerj-first` at
  `e1c05afe742f6c1013cc14ba8e6163d22d77eef9`, base `cd5897e3`, which is an ancestor of
  Radicle main `e63768a9958dbea47f1068beb37a8b034902ee1c` (1563 commits behind).
- This branch starts at `e63768a9`. Every `native/retrieval` source, test, vendor and
  evidence file is byte-identical to `e1c05afe` (`source.sha256` 16/16, `raw.sha256` 51/51),
  except: the five `.crumb` files and the candidate's root/`native/.crumb` edits are not
  carried (crumbs are retired for new work), and `REPLAY.md` gains the build composition of
  `qualify-final`, which the original record omitted.
- `tests/gates/run.sh native` now also exercises this module; `native/` was already an input of
  `tests/gates/omega-native.gate`, so changes here previously mapped to a gate that did not test them.

## Results

| Check | Result | Raw output |
| --- | --- | --- |
| Consumer compiler rebuilt from seed, omega-bridge `0fc7d866` | `191b776e…f6df098e9`, matches pin | `replay.out` line 1 |
| All six recorded executables rebuilt with that compiler | byte-identical to `binaries.sha256` | `replay.out` |
| Verifier suite | `{"checks":41,"failures":0}`, exit 0 | `replay.out` |
| Request, pack, replay, export, packet fixtures 1-4 | exit codes and bytes equal the recorded files | `replay.out` |
| Three recorded guard-removal mutants | compile; exit 1 with 4 / 3 / 1 failed checks | `replay.out` |
| New tamper controls: one text byte, one revision digit, one raw compiler-record byte | refused with codes 8, 3 and exit 9; no evidence bytes | `replay.out` |
| Main compiler `seed/out/omc` `0f2de851…` | same seven executables, byte for byte; same results | `replay-main-omc.out` |
| Export compiler rebuilt from seed at L408 `43f86be2` | `bcf3abc7…aeaf9d54be`, matches pin; regenerated `corpus-t1/t2.response` byte-identical | recovery record |
| Pinned Xerj `v1.0.0-rc.98` (`2ca1d9c1…`), fresh private node, auth on | bulk 200; scoped read 200; out-of-scope 403 (absent and existing index); scoped write 403; no key 401; corrupted key 401; admin write 201 / read 200; no-match 200 | `http.tsv`, `external.out`, `*.response` |
| Fresh scoped search through the unchanged native replay | verified and packed; equals `packet-3.json` | `search.packet` |
| Independent tokenizer oracle on the pinned `tokenizer.json` | 255 / 263 / 502 / 502 tokens, equal to the recorded receipts | `tokenizer-oracle.out` |
| `tests/gates/run.sh native` | exit 0, `RETRIEVAL PASS checks=41 mutants=3/3 …` | `gate-native.out` |
| Same gate with the identity mutant applied to `src/verify.om` | exit 1 | `gate-native-negative.out` |

The private Xerj node used loopback port 19280 and a temporary data directory, both removed
afterwards. Its keys were never written outside that directory. The tokenizer oracle is a
measuring instrument (Hugging Face `tokenizers` 0.23.3), not part of the build.

## Still NOT_RUN

- Held-out development-task comparison against the direct-search agent workflow, with complete
  lifecycle costs. It needs an admitted held-out task set (L775 full benchmark still open), a
  generating model for both arms, and an authorized model/GPU window. The model whose tokenizer
  is pinned here (`qwen3.6-35b-a3b-fp8`) was retired on 2026-11-06 (DRA-162); a replacement
  model needs new tokenizer receipts before any packet budget applies to it.
- Native authenticated transport, credential custody, deadlines and cancellation (L690, issue 648).
- No performance or quality claim is made.
