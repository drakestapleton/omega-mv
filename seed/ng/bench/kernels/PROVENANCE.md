# NG bench kernels: provenance (frozen 2026-11-07 before any timing run)

Every case is a self-contained Omega unit `CASE.om` (one `omc < CASE.om > bin` builds it) and, except
`x25519`, a C twin `CASE.c` that runs the same algorithm and prints the same bytes. The C twins are
**referees only** (gcc 13.3.0): they decide nothing about the build and are never part of it.
`want/CASE.sha256` is the sha256 of the expected stdout; `want/CASE.out` keeps the expected stdout where it
is short text. Nothing here may change after the freeze commit; a changed case is a new case name.

## Sources

| case | `.om` from | `.c` from |
|---|---|---|
| arith, branch, leafcall, sieve, isort, matmul | omega-mv `perf/omc-efficiency-baseline` @`d11a717735581353844a961ca031b97b637db884` `bench/omc_efficiency/kernels/CASE.om`, verbatim | same commit `kernels/CASE.c`, verbatim |
| fib38 | same commit `kernels/fib.om`, verbatim (renamed) | `kernels/fib.c` (renamed) |
| fib40, sort, bcopy | `~/handoffs/OmegaFast/bench/{fib,sort,bcopy}.om` (the omega-mv#832 bench twins), verbatim; fib40 renamed from fib.om | `~/handoffs/OmegaFast/bench/{fib,sort,bcopy}.c`, verbatim |
| sha | the line `om2`, then omega-mv @943d9555 `om/tls/sha2.om` (sha256 `5cf0f981…6fdb33`), then OmegaFast `bench/sha.om` (sha256 `e3f845ed…583150`) | OmegaFast `bench/sha.c` |
| chacha | `om2`, `om/tls/chacha.om`@943d9555 (`8431257b…37d3af`), OmegaFast `bench/chacha.om` (`64bb5dae…e7de90`) | OmegaFast `bench/chacha.c` |
| x25519 | `om2`, `om/tls/x25519.om`@943d9555 (`c2a3a01d…23f5`), OmegaFast `bench/x25519.om` (`4bc42366…263a98`) | none: an omc-only row, no ratio |
| linear | consts `M 64`, `K 256`, `N 256`, `MK`, `NK`, `MN`, then omega-bridge main `d8174eddf953ad53e16f19eb5841459df99e24bb` `pytorch/kernels/linear.om` (blob `f7d5231a`, sha256 `304a99a9…f06b8f`) verbatim, then a bench `main` written here (40 passes, checksum line) | written here as its twin |

The OMC-EFF kernels write their in-process nanoseconds as one decimal line on stderr (OMC-EFF-2); stdout
is unchanged and is the only checked output.

## File hashes (sha256)

```
d8700247b8d47e8cab2771b48a979a84615ef04acf40b975d6304af88ac25bb3  arith.om
1cfdf762543bf32f8680d825bedd06f7ce3a90e1c561e0f2b933502c81d51cd5  bcopy.om
022cb4d005ef7ecbe75686ac92459592a4ab388bf62f18fa5726171b454b4fa9  branch.om
fa305a4019b8aa77b87ad9bb061fd694f6b25c85c3fa8e058d15b0519ae05bcd  chacha.om
d7c4796143291f036e844c7976b5438821c168bfeffdf3984e371bad84b8bf6a  fib38.om
685fe9e2385578ef7ddd2ab8076e9b7d30513c707bfd50161a4205e63dfe2d08  fib40.om
18321ee3a4c91326ff4ad42d54f1c2988c403b2d81cb79938dbcdf5347ba7bce  isort.om
5451d14ac27c98005f190d381d94ca28e6614ad2a725189e4ec2112adf5bd2e0  leafcall.om
b03808d01b0b211a8f23f10485f6dbab767dfe13e98d8f5a047607cea0801a2e  linear.om
0c6df9678ab2e74aaeea5830924fddf6375333e67fbdaab4907826a04769a86f  matmul.om
7fb2ad5fecfab5c6369a7579f272d0aefc8933106aecb12c6fa6dc79437144dc  sha.om
3efdb30a8d072a08af9d91e13c9ea6b1509fc7fc4f676cc1960725d76429239a  sieve.om
bab33a8c66922a456fcb75f1d87d5a8eeef6242aea6f7b266d38c2ba939a723c  sort.om
aaf11ef1ab20a8db11664aa1c743991b2c503170ab9b068c30ee457a5b99ab03  x25519.om
6850039e6312dbe7b4ae043441f9edcb9a845c4d7dbdef6f065e571cb359ca26  arith.c
50fae2a94bf5cb3dd3df33f1ce4382059fd0f188ff9347ff33edd8d079d73017  bcopy.c
9d634eb6964081e202795d26146eeb3137076a6f6eafd82cf4fa9478b1fb0236  branch.c
c58df41a80223720839df8368beecf72a3deae59945b1d448da67dc43616cba4  chacha.c
858629de5d9fec21fa25d8499953de61060d2abaee84ce1b18cdcd964f02629d  fib38.c
70a9903f9e648c705033d84279d88fd44657bc4a6893398dce3005d07a06a7e2  fib40.c
e57a0c191921704aab5751ab5bf07215dbb2dbdbb8a41ee254547b64cf51967b  isort.c
85584fad743b22c87500b05ee80fe5063af4b12c07ddd7540cfbc64a9d15494a  leafcall.c
2f98013adcb843a5c284a9ed5f63f26aa93d357261dfe15d685ffbd40782ae18  linear.c
d076079bb5925db995a75ef0e6c950cd45bdfa22f63a7773e8ee09a7a4d5bea0  matmul.c
68e7d30d6df98509b2f097fa26b790b25c7ecdbad0af8b621d933fe4d7ee5249  sha.c
bf1c6cfaa5bd10a56ef9b01014ebd7dcfe7d25d12986c93d77e4bae29339e0fb  sieve.c
8b6317b0a57ff0d6d50f0884a267156b1eb754e78c1967f6cb1c72de72db6ff2  sort.c
```

## Expected outputs and how each was established

Each binary was run once (untimed) on core 1 at the freeze: omc 5f90edea, `gcc -O2 -static` and
`gcc -O0 -static` builds gave identical stdout sha256 on every case with a C twin.

| case | want | independent check |
|---|---|---|
| arith branch fib38 isort leafcall matmul sieve | `want/CASE.out` = OMC-EFF-1 `want/CASE.out` @d11a7177 | Wolfram, before that freeze (OMC-EFF-1 PROTOCOL.md section 2) |
| fib40 | `102334155` | WolframLanguageEvaluator: `Fibonacci[40]` -> `102334155` |
| sort | `2128411481385469 0 118 3999832` (four lines) | WolframLanguageEvaluator: LCG `x=Mod[x*1103515245+12345,2147483648]`, `Mod[x,4000000]`, 40000 values, `Sort`; `Total[s*Range[40000]]` -> 2128411481385469, unsorted neighbours 0, `First` 118, `Last` 3999832 |
| sha | digest `601fc533…8979d8834d` (32 raw bytes; want = their sha256 `70208af7…0b96204b`) | WolframLanguageEvaluator: `Hash[ByteArray[Flatten[ConstantArray[Mod[Range[0,2^20-1]*31+7,256],64]]],"SHA256","HexString"]` -> `601fc533f64b11042a9ae821c272064871306a99496652afb5758c8979d8834d` |
| bcopy | sha256 `483bf6a6…19007315` of the 65536-byte output | WolframLanguageEvaluator: `Hash[ByteArray[Reverse[BitXor[Mod[7 Range[0,65535],256],63]]],"SHA256","HexString"]` -> `483bf6a6f139c87d7dd22a5992036542619a4417669fab3161d87af319007315` |
| linear | `11166149387521163264` | WolframLanguageEvaluator: exact rational `a.Transpose[w]` plus bias, 40 passes, f32 bits by `ExportByteArray[...,"Real32"]`, checksum mod 2^64 -> `11166149387521163264` |
| chacha | sha256 `06b7bbfb…` of the 1 MiB output | C twin (independent RFC 8439 code) and omc agree; no third check |
| x25519 | sha256 of omc's own 32-byte output | **self-referenced**: no referee exists; the row only guards against a changed answer |
| omcself | `5f90edea…f6f6df` = sha256 of `seed/out/omc` | the seed fixpoint: omc(omc.om) == omc |

`omcself` is the compile-speed case: the arm binary is `seed/out/omc` itself and its stdin is
`seed/omc/omc.om` at the pinned commit.
