# ng-front reduced run copies: provenance

Each file is a copy of a kernel in `seed/ng/front/kernels/` (verbatim ng-bench copies, `kernels/PROVENANCE.md`)
with only loop counts and array sizes made smaller and the first note line rewritten to say so, so that
ngrun (an interpreter, 90-470x native, no step cap yet) finishes each `gate-front-ir` run case well inside
the gate's 600 s child deadline on a shared core. The lowering paths are the kernel's: no statement, type or
call changes. `diff kernels/K.om runs/K-s.om` shows every change. Native times on core 1 (one run each, ms):
all under 25.

| copy | from | change |
|---|---|---|
| arith-s.om | arith.om | i < 2000000 (was 40000000) |
| branch-s.om | branch.om | starts 1 .. 10000 (was 1000000) |
| leafcall-s.om | leafcall.om | 3000000 calls (was 30000000) |
| fib30.om | fib38.om | fib 30 (was 38) |
| fib31.om | fib40.om | fib 31 (was 40) |
| isort-s.om | isort.om | 4000 numbers (was 20000; 19999 -> 3999) |
| sieve-s.om | sieve.om | 2 passes (was 50) |
| sort-s.om | sort.om | 5000 numbers (was 40000; 39999 -> 4999); first note line added |
| linear-s.om | linear.om | 2 passes (was 40) |
| sha-s.om | sha.om | 1 update of the 1 MiB buffer (was 64); first note line added |

Written for gate-front-ir (not copies): `p-part.om` (unsized `view`/`edit` parameters, `part` into them, `len` of
a slice; its last `part` is one element too long and traps 3, exit 103) and `p-partok.om` (the same with that
`part` in range, exit 92).

sha256 (sha256sum):

```
7881ffebb8af67fe59ae7526d0fd2a125650c805492a44c54d887a823150d760  arith-s.om
55a3a142108450200ff7d5e399f14b632d85043321fde5e1ed8468adbe5e48d8  branch-s.om
45e96cac6f1c2948ab8d9f5e9609e7e6880254b8559f719f99c90be122fb310d  fib30.om
870aca6d4c746313ba7ce2ef8987c4aa362c3774af3f10dd448a644ad40d278c  fib31.om
8fdcbf3b96610f45ce4d16c9c0ce32beaf2813a9c94fcf65ae43a15b793854c0  isort-s.om
17cf33fa7a8599e206516e9702f384b0b938b92df28e8547bd1f17f5b66d4259  leafcall-s.om
0e398e277b0ed988b8b31f16a4f221cc08335c90ac5806471203df5615b94fb8  linear-s.om
eec1b9f555507fbb276cefb3ac0d447e8a9bbb65ca5224e75af044f066231623  sieve-s.om
9d3e32bec4292de304a1d9bd79876bb5f9cf7c3886e57d19424e80a9fbea3a7b  sort-s.om
42a63cefe625a0fd30e7a1360f01ca6e5fd4bfc3e92f6079851c2db154556062  sha-s.om
5c19c71da2d76d8e10cc29cae8694b508ba5c026572d7ecf5cdfdc574e1e10b8  p-part.om
75a757d55c8548ab2c75cc7f44b78124783b6c87e06d24751fccdf6f43a4cc9d  p-partok.om
```
