# ΩIR: the Omega next-generation intermediate representation

```text
Document:   seed/ng/IR.md (ΩIR wire version 9, tag omega.ng.ir.v1)
Status:     PROPOSED draft v0 (ng-ir lane, Hive NG M0). Tools: seed/ng/ngcheck.om, ngas.om, ngdis.om.
Decisions:  Hive NG D1, D2 + D2b (accepted 2026-11-07), D3.
Family:     spec/one-layer-format.md (OSC binary IR). Versions 1..8 are untouched by this document.
Pin:        omega-mv 943d955531b9d4d9f70deb41756c0b46441dd5e0, omc sha256 5f90edea…6df.
```

ΩIR is the one program form every NG tool reads and writes: `ngfront` (Omega to ΩIR), `ngopt`
(ΩIR to ΩIR), `nga64` (ΩIR to AArch64) and `ngsm121` (ΩIR kernels to sm_121). It is typed, in SSA
form with block parameters, target-neutral, and carries the exact Omega meaning: every trap a
program can raise is an explicit check op naming its trap code, every host word is an effect op,
and contracts and analysis results are non-executing facts.

## 1. Principles

1. **One meaning per byte string, one byte string per unit.** Fixed-width little-endian fields, no
   padding, every unused field is 0, every enumeration has a closed set of values. A reader refuses
   anything else; it never repairs, skips or guesses (OSC canonical law, one-layer-format s2).
2. **Arithmetic is total.** No arithmetic or conversion op has undefined behaviour or traps. Traps
   come only from check ops (`chk.*`), `trap`, and the stack (s7.4). Removing a check can change
   which value a program computes; it can never make the program's behaviour undefined.
3. **Memory access is covered.** Every memory access op must be dominated by a bounds check or a
   bounds fact on the same SSA values (s8). The validator enforces this, so an optimizer deletes a
   check only by putting a fact in its place.
4. **Target facts are not IR.** Calling convention, register classes, clobbers, subgroup width
   offered, shared memory budget, feature sets: these belong to a target descriptor checked by the
   backend. The IR states what a kernel *requires* (s6.3), never what a chip *offers*.
5. **Limits are implementation limits with an exit code** (s12), never silent truncation.

## 2. Encoding primitives

`u8 u16 u32 u64`: unsigned little-endian, exactly that many bytes. There are no variable-length
integers. A *type id*, *value id*, *block id*, *function id* and *global id* are each a `u32`.

## 3. Module

| bytes | field |
|---|---|
| 7 | magic `4F 53 43 31 49 52 00` (`OSC1IR\0`, the OSC family) |
| 1 | version `9` |
| 16 | domain tag: the 14 bytes `omega.ng.ir.v1` then two `00` |
| 4 | `ntypes`, then `ntypes` type entries (s4.2) |
| 4 | `nglobals`, then `nglobals` global entries (s5) |
| 4 | `nfuncs`, then `nfuncs` function records (s6) |

Nothing follows the last function record. **Identity** = SHA-256 of the whole byte string. ΩIR has
no name table: names are debug information and are not carried in v1 (a later tag may add a side
table outside identity, as OSC v6 did).

Version discipline: a ΩIR reader refuses versions 1..8 and any tag other than the exact 16 bytes;
OSC readers of versions 1..8 refuse version 9 by its version byte. A later ΩIR revision changes the
tag (`omega.ng.ir.v2`), never the meaning of v1 bytes.

## 4. Types

### 4.1 Built-in scalar types (ids 0..31; no table entry)

| id | type | id | type |
|---|---|---|---|
| 0 | void (result only; "no result") | 8 | i32 |
| 1 | bool | 9 | i64 |
| 2 | u8 | 13 | f32 (IEEE binary32) |
| 3 | u16 | 14 | f64 (IEEE binary64) |
| 4 | u32 | 16 | f16 (IEEE binary16) |
| 5 | u64 | 17 | bf16 |
| 6 | i8 | 18 | fp8 e4m3 (OCP FP8, storage and MMA input only) |
| 7 | i16 | 19 | fp8 e5m2 (storage and MMA input only) |

Ids 0..9, 13, 14 equal the OSC scalar tags (one-layer-format s3.4, s10.3). Ids 10, 11, 12, 15 and
20..31 are reserved and refused (they carry OSC ref/bytes/cells/GEDIT meanings in other versions).
*int* below means ids 2..9; *float* means 13, 14, 16, 17; *arith* means int or float; *num* also
includes the fp8 ids.

### 4.2 Type table (ids 32 + k)

Entry k of the table has id 32 + k. An entry refers only to built-in ids and to entries before it
(no cycles). Two entries with identical bytes are refused (NONCANONICAL): type equality is id
equality. Each entry is a kind byte, then its fields:

| kind | name | fields | rules |
|---|---|---|---|
| 1 | VEC | `elem u32`, `lanes u32` | elem bool, int or float; lanes 2, 4, 8, 16, 32 or 64; lanes x element bytes <= 64 (bool counts 1 byte) |
| 2 | ARRAY | `elem u32`, `count u32` | elem num, VEC or STRUCT; count 1..16777216 |
| 3 | STRUCT | `size u32`, `nfields u32`, per field: `type u32`, `offset u32`, `order u8` | size 1..1073741824; nfields 1..64; field type num, ARRAY or STRUCT; fields strictly ascending by offset, non-overlapping, inside size; order 0 little-endian, 1 big-endian (only meaningful for int/float fields; 0 for ARRAY/STRUCT fields) |
| 4 | REF | `target u32`, `access u8`, `space u8` | a reference to one memory object of type target (ARRAY or STRUCT); length known from the type |
| 5 | SLICE | `elem u32`, `access u8`, `space u8` | a reference to a run of elements of type elem (num, VEC or STRUCT) with a run-time length |
| 6 | FRAG | `role u8`, `m u16`, `n u16`, `k u16`, `elem u32` | an MMA operand tile held by one subgroup (s7.8); role 0 A (m x k), 1 B (k x n), 2 C/D (m x n); m, n, k 1..256; elem num |

`access`: 0 read-only (Omega `view`, `text`), 1 read-write (Omega `edit`, `out`, `fresh`, local arrays).
`space` (numbers 1..4 from omega-mv#883 E3): 0 HOST (CPU process memory: stack, globals, text),
1 GLOBAL (device global), 2 SHARED (block-shared), 3 CONSTANT (device constant, access must be 0),
4 PRIVATE (per-thread device memory). OM-1 cell structs are STRUCTs whose fields sit at multiples
of 8 bytes; OM-2 `layout`s are STRUCTs with their stated offsets and byte order.

Memory layout of ARRAY and SLICE elements is packed at the element's size (one-layer-format s10.2):
bool, u8, i8, fp8 1 byte; u16, i16, f16, bf16 2; u32, i32, f32 4; u64, i64, f64 8; VEC lanes x
element; STRUCT its size. Scalars in memory are little-endian unless a STRUCT field says big.

## 5. Globals

Entry: `type u32` (an ARRAY), `class u8`, then for class 1 the initial bytes:

| class | meaning | data |
|---|---|---|
| 0 | mutable, zero-filled once per program instance (Omega `global`) | none |
| 1 | read-only with initial bytes (Omega `text`, constant tables) | exactly the array's byte size |

Global ids are table indices. `gaddr` (s7.5) gives a REF to one; a REF with access 1 to a class 1
global is refused (TYPE).

## 6. Functions

### 6.1 Record

| bytes | field |
|---|---|
| 1 | `kind`: 0 function, 1 kernel, 2 export (an entry a host calls in function mode) |
| 1 | `flags`: bit 0 inline hint; other bits 0 |
| 4 | `nparams` 0..64, then `nparams` param type ids (`u32` each) |
| 4 | `result` type id (0 = void) |
| kernel only: 4+4+4 | `tx ty tz`: threads per block on each axis, each 1..4096, product 1..4096 |
| kernel only: 1 | `subgroup`: 0 any, else the required subgroup width 4, 8, 16, 32, 64 or 128 |
| 4 | `nblocks` 1..65536, then the blocks |

Block: `nbparams u32` 0..64, `nbparams` param type ids, `nops u32` >= 1, then the ops (s7.1).

Any function may call any non-kernel function, including itself and later ones. A kernel's result
is void; a kernel calls no function and no function calls a kernel except through `launch`
(s7.7). Block 0 is the entry: it has no block parameters and is never a branch target.

### 6.2 Values (SSA)

Every value is defined exactly once. Value ids are implicit, never stored: in each function the
parameters are values 0 .. nparams-1, then, block by block in order, each block's parameters,
then each op that has a result (ty != 0), in op order. A use names a value id.

- A use in block B at op j is valid when the definition is earlier in B (a parameter of B, or an op
  before j), or in a block that strictly dominates B, or is a function parameter.
- A use of an id at or past the function's value count, or a later op in the same block, is
  USE_BEFORE_DEF; a definition in a non-dominating block is DOMINANCE.
- Every block must be reachable from block 0 (UNREACHABLE).
- Values passed to a block's parameters come only from `br` (s7.6); merges are block parameters,
  there are no phi ops.

### 6.3 Kernels (one form for CPU and GPU)

A kernel describes the work of one thread; a launch runs it over a grid of blocks of `tx*ty*tz`
threads. The same kernel IR is lowered by `nga64` (threads as loops and NEON lanes) and by
`ngsm121` (threads as GPU threads). `subgroup` is what the kernel requires; the target offers its
own width in its descriptor, and the backend refuses a mismatch (omega-mv#883 E3 s1). Shared
memory budget, nesting depth, thread maximum and feature set are target-descriptor checks done
by the backend, not by ngcheck. The race, divergence and sync rules of `docs/omegese/GPU.md`
(s6, s8 on `c1/chip-fix`) are kernel-checker obligations of the GPU lane (M5); ngcheck checks the
structural rules of s9.

## 7. Ops

### 7.1 Encoding of an op

| bytes | field |
|---|---|
| 1 | `op` (s7.2 onward) |
| 4 | `ty`: the result type id, 0 when the op has no result. For a check, fact or op marked "ty is a parameter" it is that parameter, else 0 |
| 8 | `imm`, present only when the row has an imm column; 0 when its meaning says unused |
| 4 | `n`, present only for variadic rows (`br`, `call`, `host`, `launch`) |
| 4 each | operands: the row's fixed operands, then `n` variadic operands |

Operand kinds: `v` value id, `b` block id, `f` function id. Everything else is a value. Every
`ty`, `imm` and operand is checked against its row: a value outside the row's types is TYPE.

Terminators are `br cbr ret retv trap exit` (and nothing else). Each block ends with exactly one
terminator, and no terminator appears before its end (UNTERMINATED).

Notation in the tables: `T` the result type; operand types in parentheses; *same* means the same
type id as `T`.

### 7.2 Constants and selection (1..9)

| op | name | ty | imm | operands | meaning |
|---|---|---|---|---|---|
| 1 | `const` | num | bits | - | the value of type T whose bits are imm (canonical form below) |
| 2 | `select` | any value type | - | c (bool), a, b (same) | a if c else b |

Canonical `const` imm: bool 0 or 1; unsigned ints zero-extended (high bits 0); signed ints
sign-extended two's complement of the width; f32, f16, bf16, fp8 in the low 16/8/32 bits with the
rest 0; f64 all 64 bits. Any other imm is NONCANONICAL. Vectors are built with `vsplat`/`vinsert`.

### 7.3 Arithmetic, bitwise, comparison (10..39)

All operate on a scalar or on a VEC (lane by lane); the operands have type T unless stated.

| op | name | types | meaning (total) |
|---|---|---|---|
| 10 | `add` | arith | int: modulo 2^w. float: IEEE, round to nearest even |
| 11 | `sub` | arith | as add |
| 12 | `mul` | arith | as add |
| 13 | `div` | arith | int: toward zero; divisor 0 gives 0; signed MIN / -1 gives MIN. float: IEEE |
| 14 | `rem` | int | sign of the dividend; divisor 0 gives 0; MIN rem -1 gives 0 |
| 15 | `neg` | arith (1 operand) | int: 0 - a modulo 2^w. float: flip the sign bit only |
| 16 | `and` | bool, int | bitwise (bool: logical) |
| 17 | `or` | bool, int | as and |
| 18 | `xor` | bool, int | as and |
| 19 | `not` | bool, int (1 operand) | bitwise complement (bool: logical) |
| 20 | `shl` | int | amount b taken modulo w; bits shifted out are lost |
| 21 | `shr` | int | amount modulo w; arithmetic for signed, logical for unsigned |
| 22 | `rotl` | unsigned int | amount modulo w |
| 23 | `rotr` | unsigned int | amount modulo w |
| 24 | `min` | arith | int: by signedness. float: if one operand is NaN the other; -0 < +0 |
| 25 | `max` | arith | mirror of min |
| 26 | `fsqrt` | float (1 operand) | IEEE square root, correctly rounded |
| 27 | `fabs` | float (1 operand) | clear the sign bit |
| 28 | `fmath` | float (1 operand), imm | transcendental with accuracy class, below |
| 30..35 | `eq ne lt le gt ge` | operands int, bool (eq, ne only) or float; ty bool, or VEC of bool with the operands' lanes | int by signedness; float IEEE ordered: any NaN gives false except `ne` |
| 36 | `conv` | ty num; operand num of another type; imm | numeric conversion, below |
| 37 | `bitcast` | ty and operand of equal bit width | reinterpret bits (one-layer-format s10.2 sets, extended to f16/bf16 with u16/i16 and fp8 with u8/i8) |

Float arithmetic never contracts separate ops into a fused op; only `fma` is fused. A NaN produced
by arithmetic may have any quiet-NaN payload; `const`, memory ops, `select`, `bitcast`, `neg` and
`fabs` preserve every bit (one-layer-format s10.3). f16 and bf16 arithmetic rounds each op to the
type. fp8 types are refused by every op of this section except `conv` and `bitcast`.

`fmath` imm: bits 0..7 function (0 exp, 1 exp2, 2 log2, 3 inv (1/x), 4 rsq (1/sqrt x), 5 sin,
6 cos, 7 tanh); bits 8..15 accuracy class (0 CR correctly rounded, 1 ULP(n), 2 FAST target-stated
bound); bits 16..23 n for ULP (1..255, else 0); bit 24 denormal inputs and outputs may flush to
zero (0 = kept); other bits 0. The class is what the program requires; a backend that cannot meet
it refuses (omega-mv#883 E3 s4). Omegese GPU `exp`/`inv`/`root` lower to class FAST with bit 24.

`conv` imm: bits 0..1 rounding for a float destination (0 nearest even, 1 toward zero), bit 2
saturate to the largest finite value instead of infinity (float destinations only); other bits 0;
an int destination requires imm 0. Rules (one-layer-format s10.3): int to int keeps the low w bits
of the source value (sign- or zero-extended first by the source's signedness), so it never traps;
`chk.conv` (s7.9) gives Omega's trap 5. int to float rounds per imm. float to int truncates toward
zero and saturates to the destination range; NaN gives 0. float to float rounds per imm. bool is not
a conv operand or result: compare instead.

### 7.4 Fused multiply-add (46)

| op | name | ty | operands | meaning |
|---|---|---|---|---|
| 46 | `fma` | float or VEC of float | a, b, c (same) | a x b + c rounded once (OSC v8 MAD, number kept) |

### 7.5 Memory (42, 43, 47, 48, 50..59)

`r` is a REF or SLICE; `i` an index of type u32 or u64, counted in elements of the target array or
slice. All accesses are covered (s8). Opcode numbers 42, 43, 47 keep OSC v8's GLOAD, GSTORE and
ATOM, generalized to every space.

| op | name | ty | imm | operands | meaning |
|---|---|---|---|---|---|
| 42 | `load` | element type | - | r, i | element i |
| 43 | `store` | 0 | - | r (access 1), i, v (element type) | element i = v |
| 47 | `atom` | element type (u32, i32, u64, i64, f32) | op, scope, order | r (access 1), i, v | atomic read-modify-write; result is the old value |
| 48 | `atomcas` | element type | scope, order | r (access 1), i, expect, new | if element i == expect then store new; result is the old value |
| 50 | `alloca` | REF (access 1, space 0 or 4) to ARRAY or STRUCT | - | - | fresh zero-filled storage for this invocation; entry block only |
| 51 | `fill` | 0 | - | r (access 1, ARRAY or SLICE), v (element) | every element = v |
| 52 | `gaddr` | REF to the global's type, space 0 | global id | - | the global's storage |
| 53 | `len` | u64 | - | r (ARRAY REF or SLICE) | element count |
| 54 | `slice` | SLICE (same elem and space, access <= r's) | - | r, off (u64), n (u64) | elements off .. off+n-1; covered by a `chk.slice` or `fact.slice` on (r, off, n) |
| 55 | `fload` | the field's scalar type | field index | r (REF to STRUCT) | the field |
| 56 | `fstore` | 0 | field index | r (access 1), v | the field = v |
| 57 | `fref` | REF to the field's ARRAY or STRUCT, same access and space | field index | r (REF to STRUCT) | the sub-object |
| 58 | `vload` | VEC (lanes L of the element type) | - | r, i | elements i .. i+L-1 |
| 59 | `vstore` | 0 | - | r (access 1), i, v (VEC) | elements i .. i+L-1 = v |

`atom` imm: bits 0..7 op (0 add, 1 min, 2 max, 3 and, 4 or, 5 xor, 6 exch); bits 8..15 scope (0
subgroup, 1 block, 2 device, 3 system); bits 16..23 order (0 relaxed, 1 acquire-release); others
0. `atomcas` uses bits 8..23 the same way, bits 0..7 are 0. Integer add wraps; float add rounds to
nearest even. In a function (not a kernel) the only thread is the caller, so an atomic is its plain
read-modify-write.

### 7.6 Control (60..66)

| op | name | ty | imm | operands | meaning |
|---|---|---|---|---|---|
| 60 | `br` | 0 | - | b, then n values | jump to b; the n values (n = b's parameter count, same types in order) become its parameters (BLOCK_ARITY) |
| 61 | `cbr` | 0 | - | c (bool), bt, bf | jump to bt if c else bf; bt and bf have no parameters (BLOCK_ARITY) |
| 62 | `ret` | 0 | - | - | return from a void function or kernel |
| 63 | `retv` | 0 | - | v (the function's result type) | return v |
| 64 | `call` | the callee's result | - | f, then n arguments | call f (any non-kernel function; n and types equal f's parameters) |
| 65 | `trap` | 0 | code 1..14 | - | trap with code (Omega `trap N`, exit 100+code) |
| 66 | `exit` | 0 | - | v (i32) | end the process with status v (Omega `exit`); functions and exports only |

`trap` in a kernel ends the thread (s7.9 kernel traps).

### 7.7 Kernel ops (40, 41, 44, 45, 67)

| op | name | ty | imm | operands | meaning |
|---|---|---|---|---|---|
| 40 | `gpu.id` | u32 | which | - | 0 thread.x, 1 block.x, 2 blocks.x, 3 block.y, 4 blocks.y (OSC v8 THREAD, BLOCK, BLOCKS, BATCH, BATCHES), 5 thread.y, 6 thread.z, 7 block.z, 8 blocks.z, 9 lane in subgroup, 10 subgroup index in block |
| 41 | `shared` | REF (access 1, space 2) to ARRAY | - | - | block-shared storage, zero at kernel start; kernel entry block only |
| 44 | `sync` | 0 | - | - | block barrier |
| 45 | `shfl` | u32, i32, f32 (or u64, i64, f64) | mode | v (same), d (u32) | mode 1 DOWN, 2 UP, 3 XOR, 4 IDX (E3 numbers); d must be a `const`: 1..127 for DOWN/UP, 0..127 for XOR/IDX, and below `subgroup` when the kernel declares one. A source lane outside the subgroup gives the caller's own v |
| 67 | `launch` | 0 | - | f (a kernel), gx, gy, gz (u32), then n arguments | run kernel f on a grid of gx x gy x gz blocks and wait; functions and exports only |

`gpu.id`, `shared`, `sync` and `shfl` appear only in kernels; `launch` and `exit` only outside them
(EFFECT).

**Kernel traps.** A thread that fails a check or reaches `trap` records the code, and from then on
its stores and atomics have no effect. Whether it keeps running to the end (so other threads still
meet it at `sync`) is the backend's choice. When the launch ends, if any thread recorded a code,
`launch` traps in the caller with the lowest recorded code, and every location the kernel could
write has an unspecified value. Without a trap the launch returns normally.

### 7.8 Vectors and tiles (100..106)

| op | name | ty | imm | operands | meaning |
|---|---|---|---|---|---|
| 100 | `vsplat` | VEC | - | s (element) | every lane = s |
| 101 | `vextract` | element | lane | v (VEC) | lane `imm` (< lanes) |
| 102 | `vinsert` | VEC | lane | v (same), s (element) | v with lane `imm` = s |
| 103 | `vreduce` | element | op | v (VEC) | op 0 add, 1 min, 2 max, 3 and, 4 or, 5 xor. Pairwise order: lanes [0, L/2) combine with [L/2, L) lane by lane, repeated until one lane |
| 104 | `mmald` | FRAG (role 0, 1 or 2) | layout | r, i, ld (u64), e (u64) | load a tile from r: element (row, col) at i + row x ld + col for layout 0 (row-major), i + col x ld + row for layout 1; positions at or past i + e read as 0 |
| 105 | `mmast` | 0 | layout | r (access 1), i, ld, e, d (FRAG role 2) | store a tile, positions at or past i + e not written |
| 106 | `mma` | FRAG role 2 | class | a (role 0), b (role 1), c (role 2) with equal m, n, k | D = A x B + C. class 0: the reference, for each (row, col) c then k = 0 .. K-1 in order, each step one `fma` in D's element type; class 2 FAST: a target-stated bound, never compared bit for bit |

FRAG values are cooperative over one subgroup and appear only in kernels (EFFECT outside). Their
register layout is the backend's; ΩIR reaches them only through `mmald`, `mmast` and `mma`.

### 7.9 Checks (70..82): the only ops that trap

A check has no result. Its `imm` is the trap code, which must equal the code in the row (CHECK_CODE);
only `chk.true` takes any code 1..14. Code 0 is always CHECK_CODE. On failure the program traps with
that code (exit 100 + code); on success nothing happens. Operands have the type the row names.

| op | name | ty parameter | operands | code | fails when |
|---|---|---|---|---|---|
| 70 | `chk.add` | 0 | a, b (int, equal) | 1 | the exact a + b is outside the type |
| 71 | `chk.sub` | 0 | a, b | 1 | the exact a - b is outside the type |
| 72 | `chk.mul` | 0 | a, b | 1 | the exact a x b is outside the type |
| 73 | `chk.neg` | 0 | a | 1 | the exact -a is outside the type |
| 74 | `chk.divz` | 0 | b (int) | 2 | b = 0 |
| 75 | `chk.divovf` | 0 | a, b (signed int) | 1 | a = MIN and b = -1 (`div` only; `rem` does not trap) |
| 76 | `chk.shl` | 0 | a, b (signed int) | 1 | the exact a x 2^b is outside the type (b already in range) |
| 77 | `chk.shift` | 0 | b (int) | 7 | b < 0 or b >= the width of b's type (Omega shifts and rotates: amount and value share a type) |
| 78 | `chk.conv` | the destination type (int) | v (int or float) | 5 | v (truncated toward zero, if float) is NaN or outside the destination |
| 79 | `chk.bounds` | 0 | r, i, e (u64) | 3 | i + e > len r (exact, no wrap) or e = 0 |
| 80 | `chk.slice` | 0 | r, off (u64), n (u64) | 3 | off > len r or n > len r - off |
| 81 | `chk.fuel` | 0 | k (u64), m (u64) | 4 | k >= m (a loop about to run its (k+1)-th pass with bound m) |
| 82 | `chk.true` | 0 | c (bool) | any 1..14 | c is false (contracts: 9 requires, 10 ensures, invariant, holds) |

For unsigned operands `chk.add/sub/mul/neg` fail on any wrap; Omega functions wrap unsigned values
and never emit them, Omegese kernels trap on u32 overflow and do. Trap 6 (stack) is not a check op:
`call` and `alloca` may trap 6 when the backend's stack is exhausted, before any effect of the
callee or allocation.

### 7.10 Facts (90..93): non-executing

A fact has no result and no run-time effect. It states a property the producer has proven at that
point; consumers may rely on it. `imm` is the origin: 0 the front end, 1..255 the number of the pass
that proved it; other values NONCANONICAL. ngcheck checks typing and placement, not truth; every
pass that adds a fact carries its own translation-validation gate (M3).

| op | name | operands | states |
|---|---|---|---|
| 90 | `fact.true` | c (bool) | c is true |
| 91 | `fact.range` | v (int), lo, hi (same type, each defined by `const`, lo <= hi) | lo <= v <= hi |
| 92 | `fact.inbounds` | r, i, e (u64) | i + e <= len r and e >= 1 |
| 93 | `fact.slice` | r, off, n (u64) | off <= len r and n <= len r - off |

### 7.11 Effects (110): host words

| op | name | ty | imm | operands | meaning |
|---|---|---|---|---|---|
| 110 | `host` | i64, or 0 for class `cpu` | word id | n arguments | the Omega host word with that keyword id; result as OMEGESE s10: a count or minus the Linux errno |

`imm` is the keyword id of `seed/omc/genkw.awk` (`read` 53, `write` 54, `fclose` 100 .. `vfioirq`
232; `exit`, `const`, `qty`, `fma` and the x86efi word `efi` are not host words). The normative
table is `seed/ng/hostwords.tsv` (columns `id word args class`, 92 rows, extracted from OMEGESE s10,
`seed/host/MAPPING.md` and the typing code of `seed/omc/omc.om` at the pin); `ngcheck --table`
prints the table it compiles in and the gate requires those bytes to equal the file. Argument
letters, one per source argument:

| letter | operands | type |
|---|---|---|
| `i` | 1 | i32 |
| `l` | 1 | i64 |
| `L` | 1 | u64 |
| `u` | 1 | u32, defined by a `const` (Omega requires a literal request number) |
| `r` | 3: A, off, n | A a u8 SLICE or REF to a u8 ARRAY, any access; off, n u64 |
| `w` | 3: A, off, n | as `r`, access 1 |
| `S` | 3: A, off, n | `vfioctl` only: as `w`, except as `r` when the preceding `u` request is 15210 (`omc.om` 7610, 7660) |

Every slice is covered by `chk.slice`/`fact.slice` on the same three values (s8). The words of class
`cpu` (`cpufence`, `cpurelax`) have no result (ty 0); every other word has ty i64. `host` appears
only in functions and exports (EFFECT). Host effects happen in program order; an optimizer never
reorders, duplicates or removes a `host` op.

## 8. Coverage (the memory safety rule)

An access op is covered when a check or fact on the same SSA values dominates it (earlier in the
same block, or anywhere in a dominating block):

| access | needs `chk.bounds` or `fact.inbounds` on | with e |
|---|---|---|
| `load`, `store`, `atom`, `atomcas` | (r, i) | a `const` >= 1 |
| `vload`, `vstore` | (r, i) | a `const` >= the lanes |
| `mmald`, `mmast` | (r, i) | the op's own e value |
| `slice`, `host` slice | `chk.slice` or `fact.slice` on (r, off, n) | - |

A REF obtained from `gaddr`, `alloca`, `shared` or `fref` is still covered this way: the check is
explicit even when the bound is a constant, and ngopt replaces a proven check by a fact. An
uncovered access is UNCHECKED.

## 9. Structural rules ngcheck enforces

1. Every id names an existing object of the right kind: type, global, function, block, value (REF).
2. Types per row (TYPE); writes need access 1; CONSTANT space is read-only.
3. Block 0 has no parameters and is not a branch target (REF). `alloca` and `shared` only in block
   0 (EFFECT).
4. Every block reachable; SSA dominance (s6.2).
5. Terminators (s7.1); `br` arity and types; `cbr` targets without parameters.
6. `retv` only in non-void functions with the result type; `ret` only in void ones.
7. Kernel ops only in kernels, `host`, `exit`, `launch` and `call` only outside them; a kernel's
   result is void; `launch`'s callee is a kernel and `call`'s is not (EFFECT).
8. Check codes (CHECK_CODE); coverage (UNCHECKED).
9. Canonical fields (NONCANONICAL): reserved bits, `const` imm form, duplicate types, unused imm or
   ty nonzero, flags, `order` of a non-scalar field.

## 10. Canonical text form (D3)

`ngdis` prints, and `ngas` reads, exactly one text per unit. Byte-exact round trips are a gate:
`ngdis(ngas(t)) == t` for every fixture text and `ngas(ngdis(b)) == b` for every accepted binary.
ngas reads only canonical text: it refuses anything ngdis would not print (no comments, single
spaces, no trailing spaces, lines end with one LF, numbers in decimal without leading zeros unless
stated). The grammar, one item per line:

```
omegair 1
type %t32 = vec i32 4
type %t33 = array u8 64
type %t34 = struct 16 u64@0:le i32@8:be
type %t35 = ref edit host %t33
type %t36 = slice view host u8
type %t37 = frag a 16 8 16 f16
global @g0 %t33 zero
global @g1 %t33 data 68656c6c6f...
fn @f0 func flags 0 (i32 i32) -> i32
block ^0 ()
%2 = add i32 %0 %1
chk.add 1 %0 %1
retv %2
end
kernel @f1 flags 0 threads 256 1 1 subgroup 32 () -> void
...
```

- Type names: built-ins by their names in s4.1 (`void bool u8 u16 u32 u64 i8 i16 i32 i64 f32 f64 f16
  bf16 e4m3 e5m2`), table types `%tN` with N the type id. Access `view`/`edit`; space `host global
  shared constant private`; struct order `le`/`be`; frag role `a b c`.
- `global` data is lowercase hex of every byte; class 0 is `zero`.
- Function line: `fn` (kind 0), `kernel` (kind 1) or `export` (kind 2), `@fN`, `flags N`, kernel
  `threads X Y Z subgroup S`, the parameter types in parentheses separated by one space (empty
  `()`), ` -> ` and the result.
- `block ^N (types)`: the block's parameter types; their value ids are implicit and the op lines
  after it print `%N` ids that continue the count.
- Op line: `%N = ` when the op has a result, then the mnemonic, then `ty` when the row has a result
  or a ty parameter, then `imm` (decimal; for `const` signed decimal for signed ints, `true`/`false`
  for bool, `0x` and exactly 2/4/8/16 lowercase hex digits of the bits for floats), then operands
  (`%N` values, `^N` blocks, `@fN` functions, `@gN` in `gaddr`'s imm).
  Checks print their code as the imm: `chk.add 1 %0 %1`.
- `end` closes the function.

`seed/ng/tests/ir/` holds the fixtures; every fixture is canonical text.

## 11. Refusal classes and ngcheck exit codes

`ngcheck` reads binary ΩIR on stdin. Accept: exit 0 and one stdout line
`ACCEPT <sha256 hex> fns=N blocks=N ops=N`. Refusal: no stdout, exit code below, and one stderr
line `ngcheck: <CLASS> at <byte offset>` (offset of the field, op or record at fault, decimal).
Checks run front to back while reading (classes 10..15, 23), then per function (16..22, 24..27).

| exit | class | meaning |
|---|---|---|
| 10 | MAGIC | first 7 bytes are not `OSC1IR\0` |
| 11 | VERSION | version byte is not 9, or the tag is not exact |
| 12 | TRUNCATED | input ends inside a field |
| 13 | NONCANONICAL | a reserved bit or unused field nonzero, a duplicate type, a `const` imm not in canonical form, an enumeration outside its set |
| 14 | TRAILING | bytes after the last function |
| 15 | UNKNOWN_OP | an op byte with no row |
| 16 | TYPE | an operand, result or parameter type breaks its row |
| 17 | USE_BEFORE_DEF | a value used before its definition in the same block, or an id past the function's values |
| 18 | DOMINANCE | a value used in a block its definition does not dominate |
| 19 | BLOCK_ARITY | `br` arguments differ from the target's parameters; `cbr` to a block with parameters |
| 20 | UNTERMINATED | a block without a terminator at its end, or a terminator before its end |
| 21 | CHECK_CODE | a check without its exact trap code, or `trap`/`chk.true` code outside 1..14 |
| 22 | EFFECT | an op in a function kind that does not allow it (s9 rules 3 and 7), an unknown host word |
| 23 | LIMIT | a count over s12 |
| 24 | REF | an id names no object of its kind; a branch to block 0 |
| 25 | UNCHECKED | a memory access or slice without coverage (s8) |
| 26 | UNREACHABLE | a block not reachable from block 0 |
| 27 | IO | standard input could not be read |

## 12. Limits (implementation limits of the v1 tools)

| item | limit |
|---|---|
| input bytes | 16777216 |
| types | 65536 |
| globals | 65536 (sum of class-1 data within the input limit) |
| functions | 65536 |
| parameters (function, block) | 64 |
| blocks per function | 65536 |
| ops per block | 1048576 |
| values per function | 1048576 |
| `call`/`host`/`launch` arguments | 64 |
| struct fields | 64 |

A count above its limit is LIMIT (exit 23) at the count's offset, checked before reading what it
counts.

## 13. Mapping from Omega (for ngfront)

| Omega | ΩIR |
|---|---|
| signed `add x y` | `chk.add x y` (code 1), then `add` |
| `div a b` signed | `chk.divz b` (2), `chk.divovf a b` (1), `div` |
| `rem a b` | `chk.divz b`, `rem` |
| `shl a b` signed | `chk.shift b` (7), `chk.shl a b` (1), `shl` |
| `uchar x` (narrowing) | `chk.conv u8 x` (5), `conv u8 x` |
| `get A i` | `chk.bounds A i 1`, `load` |
| `while c bound N` | a counter block parameter k; `chk.fuel k N` (4) before each pass |
| `requires c` (om2 debug) | `chk.true 9 c` at entry, then `fact.true c` |
| `trap N` | `trap N` |
| host word | `chk.slice` on each slice, then `host` |
| Omegese GPU `kernel` | kind 1, `gpu.id`, `shared`, `sync`, `shfl`, `fma`, `fmath` FAST |
