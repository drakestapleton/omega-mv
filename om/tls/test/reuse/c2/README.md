# OMEGA-CRYPTO-REUSE-1: checker2 XOR and counter obligations

Issue #639. These are four seeded-Omega IR units (`ir` mode of `seed/out/omc`) plus `c2.plan`, which holds the rows
for the gate-3 runner `om/tls/test/reuse/aggregate.om` (contract CRYPTO-REUSE-AGGREGATE 1). Run it from the
repository root through the orchestration script, which builds the runner, prepares `build/tls/reuse/agg/` and
checks the receipt:

```
sh om/tls/test/reuse/agg.sh seed/out/omc om/tls/test/reuse/c2/c2.plan
```

## What checker2 proves here

`checker2 check` does not prove that a program never traps. It is a structural judge: types, CFG and loop
bounds. Its `checker2=ACCEPT` line only says the IR is well formed.

The property is proved by the no-trap pipeline used in `tests/checker2/lrat.sh`:

1. `checker2 prove-cnf X.ir f X.cnf` bit-blasts every path of `f`. It prints
   `property=no-trap-except-requires ... trap_sites=1`. Every unit has exactly one trap site, `trap 1`, so the
   property cannot hold vacuously.
2. `build/checker2/c2sat X.cnf X.lrat` is the untrusted solver (`src/checker2/untrusted/`).
3. `checker2 prove-check X.ir f X.lrat` re-blasts the IR and replays the proof with checker2's own LRAT checker.

Only `lrat=VERIFIED` (exit 0) counts as a proof. Each unit traps exactly when its property fails, so
VERIFIED means the property holds for every value of the inputs. That is 224 input bits, all of them free.

A SAT answer (`s SATISFIABLE`, exit 10) is the untrusted solver's claim, and checker2 does not check it. The mutant
rows count as killed only when two things are both observed: the solver finds a model, and checker2 then
refuses its output as a proof (`lrat=REFUSED rule=LRAT-NO-EMPTY-CLAUSE`). The models were also checked by hand
with Wolfram; see below.

These units state bit-level facts about two formulas. They make no claim about the security of any cipher,
and they do not show that the TLS code under `om/tls/` uses these formulas. They check the formulas themselves.

## Obligations

| Unit | Property | Mask | Expected |
| --- | --- | --- | --- |
| `xor-cancel.om` | for all ulong p1 p2 k: `xor (xor p1 k) (xor p2 k) == xor p1 p2`. Reusing a keystream leaks the XOR of the plaintexts. | - | UNSAT, VERIFIED |
| `xor-wrong-key.om` | mutant: the second keystream is `xor k 1` | - | SAT, REFUSED |
| `counter-distinct.om` | nonce = `or (shl base 32) (and c 4294967295)`; for any base and two 64-bit counter values whose low 32 bits (`and c 4294967295`) differ, the nonces differ | 2^32-1 | UNSAT, VERIFIED |
| `counter-truncated.om` | mutant: the nonce keeps `and c 2147483647`, 31 bits | 2^31-1 | SAT, REFUSED |

The masks were checked with Wolfram: `{2^32-1, 2^31-1, 2^6-1, 2^5-1} -> {4294967295, 2147483647, 63, 31}`.

### Bit-select form

Each unit takes a leading `i uint`. The selected bit is `j = and i 63` for XOR and `and i 31` for the counter,
and the unit traps only if bit j of the two sides differs. In the counter units, bit j of the two 32-bit
counters is tested under the condition `eq n1 n2`.

For all j, two words agree in bit j exactly when the words are equal. So "no trap for every i" is the same
statement as the direct equation, or, for the counter, the direct implication from distinct counters to
distinct nonces.

This form is needed because `c2sat` is plain DPLL: it decides the lowest variable first and learns no clauses.
The direct forms were run with a decision limit of 20000 in `build/tls/reuse/c2/direct/`. Both gave
`s UNKNOWN (decision limit)`, with exit 1:

- direct XOR: `inputs=192 paths=2 trap_sites=1 vars=1212 clauses=3633`
- direct counter: `inputs=192 paths=3 trap_sites=1 vars=953 clauses=2598`

With j as the first variables decided, every branch is a one-bit problem. The proofs have `steps=1023`
(XOR) and `steps=127` (counter).

## Observed results

checker2 was built at `checker2 1 (omega#446)`, with
`sources_sha256=c061a5edc68ed2df9355ee887662bc14a692c1ba1046c8750560e17c9c8993e5`, by `make -s -j2 checker2
build/checker2/c2sat`. A build from scratch with `-s` prints nothing. omc was `seed/out/omc`, with sha256
`6d1b1cf5a44803389a831b67f750ea4cd1c9f53edfde9d6d9241d7352887f1f8`.

| Unit | check | prove-cnf | c2sat | prove-check |
| --- | --- | --- | --- | --- |
| xor-cancel | ACCEPT `8ebb8da7…` | vars=2540 clauses=7206 | 20 UNSAT | 0 VERIFIED steps=1023 |
| xor-wrong-key | ACCEPT `0ebd34c0…` | vars=2540 clauses=7206 | 10 SAT | 1 REFUSED line=1003 |
| counter-distinct | ACCEPT `5706b91a…` | vars=1449 clauses=3835 | 20 UNSAT | 0 VERIFIED steps=127 |
| counter-truncated | ACCEPT `7a31400c…` | vars=1437 clauses=3794 | 10 SAT | 1 REFUSED line=1 |

The solver's models, decoded from the `v` line (variable 1 is TRUE; inputs are variables 2.., in parameter
order, least significant bit first):

- **xor-wrong-key:** i = 4294967232, so j = 0, and p1 = p2 = k = 2^64-1. Then x = 1 and y = 0, so bit 0
  differs.
- **counter-truncated:** i = 2^32-1, so j = 31. base = c1 = 2^64-1 and c2 = 2^64-1-2^31. The two nonces are
  equal while bit 31 of the counters is 1 and 0.

Both models were confirmed with Wolfram (`BitXor`/`BitAnd`/`BitOr`). The same counters with the full 2^32-1
mask give distinct nonces (`False` for equality).

## Rows

Mutant semantics: a surviving prove-check mutant exits 0 and prints its pass line `lrat=VERIFIED ...`. That
gives class FAIL. A surviving c2sat mutant would exit 20, which is neither its exit (10) nor 0, so that row
would be class INVALID rather than FAIL. The following prove-check row would then be NOT_RUN.

`prove-cnf` creates its output with O_EXCL, so `c2-clean` removes the `.cnf` and `.lrat` files of an earlier
run first. The runner does not create directories for `out`, so `c2-scratch` creates `build/tls/reuse/c2`.
The rows are chained with `after`: pin, build, id, scratch, clean, then each unit's ir, check, cnf, sat and
proof rows.
