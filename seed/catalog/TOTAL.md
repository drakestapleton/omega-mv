# Total scalar operation: add_steps

Implementation: `total.om`. Signature: `add_steps(x int, k int, n uchar) -> long`.
It widens x to signed 64-bit, adds widened k exactly n times, and returns the
full signed 64-bit value. No arrays, host effects, dependencies, recursion, or
new optimizer are involved. The existing compiler and bounded inliner are used.
All declared inputs are admitted: signed 32-bit x/k and unsigned 8-bit n.
There are at most 255 additions, below the existing dynamic-for bound 1000000.
The caller's `int` narrowing in the example may trap; that cast is outside the
total operation. The result type is deliberately long, not int.

## Scoped machine arithmetic argument

Wolfram Language evaluated this exact query (2026-11-08), returning `{True,True}`:

```wl
lo=-2^31; hi=2^31-1;
{Resolve[ForAll[{x,k,j},
  Implies[lo<=x<=hi && lo<=k<=hi && 0<=j<=255,
    -2^63<=x+j*k<=2^63-1]],Reals],
 Simplify[(x+j*k)+k==x+(j+1)*k]}
```

The second identity is the loop induction step, with base s=x at j=0.
The first covers every intermediate real j and therefore every integer loop
iteration. Widening int to long is lossless; the ulong counter starts at zero
and ends by 255. There is no possible signed addition overflow on these inputs.
Wolfram evaluated the endpoint envelope as
`{-549755813888,549755813632}`. These are algebraic bounds, not timing measurements.
The loop invariant and type interpretation map to `s = long x`,
`for i ulong ulong n`, and `s = add s long k` in total.om.

This is an arithmetic argument checked by Wolfram, not a Lean certificate or
proof of the compiler, resolver, emitted machine code, operating system or CPU.
Those remain in the trusted base. No DRA-189 optimizer is claimed delivered.
The implementation retains the loop; multiplication appears only in the
independent test reference. Changes to types, loop body or bounds invalidate
this argument and the catalog identity.

## Reproduce

```sh
seed/catalog/check-total.sh NEW_OUTPUT_DIRECTORY
```

The gate builds the resolver with the selected compiler and records its SHA256,
checks locked identity,
compiles ordinary and inline units, compares full-width results against direct
long multiplication/addition for every uchar n and signed-int extrema, and
checks byte-identical source/map/accounting reproduction. A re-locked wrong
constant must compile successfully and then fail the reference comparison.
Further controls cover mixed-length documentation, reserved catalog bindings,
compiler type rejection after lexical admission, write failures, and explicit
target/header preservation. The independent reviewer additionally tested x/k
in `{INT_MIN,-1,0,1,INT_MAX}` for every uchar n with both pinned compilers and a
wrong expected result offset by 256, preventing low-exit-byte false agreement.
These finite executions are tests, not full-domain proofs.

The existing irequiv gate is retained for its supported scalar IR and bounded
input windows. It does not certify OM2 inlining or this full 32-bit input domain.
