# Independent Omega interpreter for compiler qualification

`omega_ref.c` is an external C test oracle. It interprets Omega values and
statements; it contains no Omega code generator and never invokes `omc`.
It is not part of the seed ladder or a production runtime. The DDC conductor
at `seed/qualification/ddc650/ddc.om` builds it with the host C compiler and
uses it to execute the current compiler source on that same source.

The starting interpreter is the unchanged file from
`190130b71d0a59b93f01c515218a5509b149a145`. The later abandoned candidate
`abdcd9c48509e81f7e3b7434863b60b262226ae9` contains the same C bytes.
Its shell drivers and historical result tables are intentionally not imported.
The original author derived it from the language specification. This update
also reads the current compiler to identify the language forms it uses;
no emitted instruction or compiler algorithm is copied into the interpreter.

This restoration replaces fixed source, function, scope-name and block storage
with checked growth. Function call edges use sparse lists. Native allocation
failure is an oracle failure, not evidence about a language refusal. Current
compiler semantics added here are run-time global pools (`*`, `enlarge`,
dynamic `len`, checked `get`/`put`/I/O), environment enumeration and reading,
long names, and explicit while bounds up to `INT64_MAX`.

The remaining constants describe the original language subset's fixed array,
parameter ABI, default loop and stack rules. They are not claimed to describe
all current Omega features. In particular this is **not** a general OM-2,
float, struct, FFI, device or network interpreter. Unsupported forms fail
explicitly. DDC establishes correspondence for the supplied compiler source,
not semantic completeness of the oracle or correctness of the compiler.

## Build and exercise

Run from the repository root on Linux AArch64, on an assigned CPU if shared:

```sh
make omega-ref
make test-omega-ref
```

Or directly with `seed/out/omc`:

```sh
T=$(mktemp -d)
seed/out/omc < tools/omega_ref/omega_ref.om > "$T/ref" && chmod +x "$T/ref"
"$T/ref" run seed/omc/omc.om < seed/omc/omc.om > "$T/ref-result"
cmp "$T/ref-result" seed/out/omc
```

`check SOURCE` parses without executing, `run SOURCE` interprets its `main`,
and `call SOURCE ENTRY INPUTS` runs the original scalar function-mode harness.
A parse refusal in run mode exits 125. Executed Omega `trap N` exits 100+N.
Oracle infrastructure errors exit 2. Host C, libc, pthreads, kernel and CPU
remain trusted dependencies. Deep interpreter recursion uses a pthread stack;
it is not a proof of native compiler stack-use equivalence.

The language regressions in `fixtures/` are compared against the seeded binary:

| Fixture | Compile/check | Execute both routes |
| --- | --- | --- |
| `pools` | 0 | 0 |
| `pool-refusal` | 0 | 0 under an 8 GiB address-space limit |
| `environment` | 0 | 0 under `env -i TOKEN=value` |
| `environment-index` | 0 | 103 under `env -i TOKEN=value` |
| `pool-bounds`, `pool-max-index` | 0 | 103 |
| `bound` | 0 | 0 |
| `enlarge-expression` | 9 | do not execute |
| `enlarge-fixed` | 7 | do not execute |

`environment` checks a short destination leaves the old bytes unchanged.
`pools` crosses page boundaries, checks retained/zeroed bytes, no shrinking,
overflow refusal with unchanged state, and a nested call that moves the pool
while a store is being evaluated. `pool-max-index` ensures a literal index on
a run-time pool remains a run-time bounds check.

`stress.om` generates its own source-size, table-growth and deep-block input;
no giant generated fixture is stored in the repository:

```sh
seed/out/omc < tools/omega_ref/stress.om > "$T/generate"
chmod +x "$T/generate"
"$T/generate" > "$T/stress.om"
seed/out/omc < "$T/stress.om" > "$T/native"
chmod +x "$T/native"
"$T/native"
"$T/ref" run "$T/stress.om"
```

Both executions must exit 0. The generated source exceeds the former 8 MiB
source ceiling, 512 functions and 512 nested blocks.

Passing an extra argument (`"$T/generate" names`) additionally emits more than
1024 simultaneously visible scalar names. The interpreter must execute that
input successfully; the native compiler currently refuses it with register
error 12. This is an oracle-storage test, not native acceptance equivalence.
The DDC gate and all its corruption controls are documented in its own README.
Run them against the final integrated compiler; an earlier pair's result does
not qualify a changed compiler.
