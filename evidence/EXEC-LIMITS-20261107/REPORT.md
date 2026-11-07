# EXEC-LIMITS-20261107: exec argv packets to 1024 records / 65536 bytes

Agent: pearl (omp, Omega Pearl lane). Host: DGX Spark (aarch64), CPU pools 8-9 and 10-11, no GPU.
Base: #1074 `hive/execprog-env` 5d28878436 (execenv, omc `cfd96b48…`), itself on origin/main 943d95553.

## Why

omega-pearl's sandbox `sbx` (`tools/om/sbx.om`) replaces its own process with bubblewrap. The bubblewrap
argument list is about 101 records plus the sandboxed command. Under the 64-record exec limit the list had to
go through bwrap `--args FD`, and bwrap 0.9.0 closes that descriptor, so `echo hello | sbx -- cat` failed with
`cat: -: Bad file descriptor` where the shell predecessor printed `hello`. A missing Omega facility is built
in omega-mv (DIRECTIVE-20261107-pure-omega rule 5): the exec packet limits are raised.

## Change

| Packet | Count | Bytes | Frame |
|---|---|---|---|
| execprog 124, execpure 198, execenv 233 argv | 1..1024 | 2..65536 | 81920 (execenv 90112) |
| execenv 233 environment | 1..64 | 2..4096 | (in the 90112 frame) |
| renames, link, symlnk | 1..64 (as before) | 2..4096 (as before) | 8192 |

Frame layout, exec words: argv strings SP, argv pointers SP+65536 (at most 1025 words, to SP+73736); execenv
adds env strings SP+81920 (to SP+86016) and env pointers SP+86016 (at most 65 words, to SP+86536). Words
that are not exec keep an 8192-byte frame, so they gain no new stack-limit trap. `hpack` (AArch64) and
`xhpack` (x86linux) take the limits from three new helpers: `hexw` (1 for 124/198/233), `hnpass` (2 passes
for 233) and `hplim` (1024 for an exec argv pass, else 64). An earlier attempt with the same logic held in
locals failed om4 with error 12 (register pressure); the helpers keep `hpack` within 16 live registers.

## Status

| Stage | State |
|---|---|
| IMPLEMENTED | Yes |
| EXERCISED | Yes, on AArch64. x86linux runs under binfmt qemu-x86_64: emulator evidence only. |
| QUALIFIED | No |
| MERGED | No. CI NOT_RUN: GitHub Actions blocked org-wide since 08:16Z; pushes blocked (aien-spark suspended). |

## Compiler

| | omc sha256 | `seed/omc/omc.om` sha256 | Functions | Words |
|---|---|---|---|---|
| New | `ee5fc83e357c7285e20ae9246d8129cdf8833b74f7205242e17fa62382334dfa` | `37307721ae5306d58030a976f54b675d8e881577608f0f56ee9443d987bc0b06` | 511 | 165596 |
| #1074 | `cfd96b48b0460ab5557853d6856f9c741b96ac8d0d624e06198defb4cbfa0d8a` | | 508 | 165191 |

- `sh seed/omega-from-seed.sh`: rc=0, fixpoint `ee5fc83e…`; a second birth gives identical bytes (`birth.log`).
- Words, as in `size-history.tsv` (ELF header 64 bytes plus two 56-byte program headers, `readelf -h`):
  WolframLanguageEvaluator `{(660940 - (64 + 2*56))/4, (662560 - (64 + 2*56))/4}` -> `{165191, 165596}`.
- 511 of om4's 512 functions.

## Results

| File | What | Result |
|---|---|---|
| `packets-ee5fc83e.log` | `seed/qualification/security673/packets.cases` (OM-2 conductor) | `OM2GATE PASS cases=65 pass=65`: 16 fixtures equal the generator, 16 modes, 28 echo truncations, 5 new x86 rows |
| `negative-control-packets-omc-cfd96b48.log` | The same cases with #1074's compiler | `OM2GATE FAIL cases=65 pass=61 fail=4`: exactly p08-valid-1024, p11-size-65536 and their x86 rows, each exit 103 where 0 is expected |
| `packets-mutant-ee5fc83e.log` | `packets-mutant.cases` | `OM2GATE FAIL cases=3 pass=0 fail=3`: each mutant (byte bound, count bound, exact consumption removed) executes the one packet only its check refuses, as `check.sh` requires |
| `execenv-ee5fc83e.log` | #1074's `seed/host/execenv/execenv.cases` | `OM2GATE PASS cases=11 pass=11`, all 4 mutants detected. The envp mutants quote the moved offsets (`a64-envp.from`: ADD x2,SP,#21,LSL12 = `2436913122`; `x86-envp.from`: `xmem 141 2 4 86016`) |
| `old-vs-new-compile.tsv` | All 1382 tracked `.om` files under `cfd96b48` and `ee5fc83e` | 21 differ, each a program that uses an exec word; both compilers compile all 21. 1361 identical (bytes, exit, stderr). Of 30 files that mention an exec word, the other 9: 7 do not compile alone under either compiler (same error), 2 mention it only in notes |
| `seed-omc-gate17.log` | gate17 | `PASS gate17 300 programs byte-identical to the pinned compiler` |
| `seed-omc-gate18.log` | gate18 | `PASS gate18 169 literal packs, both computed entries and the x86efi-scoped efi entry match the committed chain` |
| `seed-semhash-check.log` | semhash | `SEMHASH PASS cases=269 controls=14` |
| `seed-json-tests-gate-json.log` | json gate | `JSONGATE PASS rows=8758 mutants=5` |
| `effects-branch.log` | `seed/effects/check.sh` | `SEMANTIC EFFECTS FAIL failed=2 checks=50`, the same failure set line for line as #1074's `evidence/EXECENV-20261107/effects-branch.log` (closure table lacks eventfd, fma, vfioctl, vfioirq, vfiomap, vfiomapw; 4 of 68 corpus files then fail verify). Pre-existing, not introduced here. |

Fixture sizes (WolframLanguageEvaluator `{2 + (2 + 9) + 1023*2, 2 + (2 + 9) + 1024*2}` -> `{2059, 2061}`):
p08 (`/bin/true` then 1023 empty records, 1024 in all) is 2059 bytes, p09 (`/bin/true` then 1024, 1025 in all) 2061; p10 and p11 are
65537 and 65536 bytes by construction and equal the generator output.

Other checks:
- `om/units.sh` regenerate then `--check`: `PASS ... regenerate byte for byte` (generator omega-bridge
  `96292423` `src/native.om`, sha256 = `NATIVE_PIN`). The 6 changed lines under `src/` are identical once the
  `omc=` identity is masked: no unit's machine code changed.
- Every other pin site (23 files) carries `ee5fc83e…`; `size-history.tsv` gains the row `exec-limits`.
- `crumb verify .`: OK, 188 crumbs current (crumb tool at aien-architecture d0f0b95d).

## Use in omega-pearl

With this compiler, omega-pearl's `sbx` keeps the caller's stdin (`printf 'hello\n'` into `sbx -- grep -qx
hello` exits 0, `/dev/null` exits 1) and its 19 controls pass; see omega-pearl `evidence/dra421/`.

## Foreign code touched

`seed/omc/x86_corpus_drivers.py`: the two corpus hashes of `packet-corpus.om` and `pkt-consumer.om` (minimal
edit to existing foreign code). Successor: the table as an Omega gate under the OM-2 conductor; tracking issue
to be filed when GitHub writes resume (held per the queen's 08:20:48Z and 08:24:41Z lines).
