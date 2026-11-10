# ΩIR: the Omega next-generation intermediate representation

```text
Document:   seed/ng/IR.md (ΩIR wire version 9, tag omega.ng.ir.v1)
Status:     PROPOSED draft v0.1 (ng-ir lane, Hive NG M0). Witness: seed/ng/ngcheck.om (own reader).
            Text tools: seed/ng/ngas.om, ngdis.om. Reference interpreter: seed/ng/ngrun.om. Random
            programs: seed/ng/ngrand.om. In-memory form and the one ng reader/writer: seed/ng/src/ir.om (s14).
Decisions:  Hive NG D1b, D2 + D2b + D2c, D3, D7, D10, D11 (2026-11-07).
Family:     spec/one-layer-format.md (OSC binary IR). Versions 1..8 are untouched by this document.
Pin:        omega-mv 943d955531b9d4d9f70deb41756c0b46441dd5e0, omc sha256 5f90edea…6df.
```

ΩIR is the one program form inside the `ng` compiler (D1b: one binary built from `seed/ng/src/`
`ir.om front.om opt.om a64.om gpu.om main.om`): the front end writes it, the passes rewrite it, the
AArch64 and sm_121 back ends read it. It is typed, in SSA form with block parameters,
target-neutral, and carries the exact Omega meaning: every trap a program can raise is an explicit
check op naming its trap code, every host word is an effect op, an ordering token makes trap order
relative to every observable effect a dataflow edge, and only checked contracts become facts.

## 1. Principles

1. **One meaning per byte string, one byte string per unit.** Fixed-width little-endian fields, no
   padding, every unused field is 0, every enumeration has a closed set of values. A reader refuses
   anything else; it never repairs, skips or guesses (OSC canonical law, one-layer-format s2).
2. **Arithmetic is total.** No arithmetic or conversion op has undefined behaviour or traps. Traps
   come only from check ops (`chk.*`), `trap`, and the stack (s7.9). Removing a check can change
   which value a program computes; it can never make the program's behaviour undefined.
3. **Trap order is dataflow (D2c, D7).** One ordering token threads every check, every effect
   (store, atomic, host word, call, launch, barrier) and every terminator (s6.4). A check can move
   only where its token edge lets it; the two legal ways to remove one are s15.
4. **Memory access is covered.** Every memory access op must be dominated by a bounds check or a
   bounds fact on the same SSA values, and read the token at or after it (s8). The validator
   enforces this, so an optimizer deletes a check only by putting a fact in its place.
5. **Facts carry authority only when checked (D2c).** A front-end fact must sit under the runtime
   check that establishes it; a pass-made fact names the pass whose proof it is (s7.10).
6. **Target facts are not IR.** Calling convention, register classes, clobbers, subgroup width
   offered, shared memory budget, feature sets: these belong to a target descriptor checked by the
   backend. The IR states what a kernel *requires* (s6.3), never what a chip *offers*.
7. **Limits are implementation limits with an exit code** (s12), never silent truncation.

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
| | | 20 | tok, the ordering token (s6.4) |

Ids 0..9, 13, 14 equal the OSC scalar tags (one-layer-format s3.4, s10.3). Ids 10, 11, 12, 15 and
21..31 are reserved and refused (they carry OSC ref/bytes/cells/GEDIT meanings in other versions).
*int* below means ids 2..9; *float* means 13, 14, 16, 17; *arith* means int or float; *num* also
includes the fp8 ids. `tok` is a value type only for token values: it is never a function parameter
or result, a table type's element, an operand of a non-token op, or a `const`.

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
Block 0 (the entry) has no parameters and is never a branch target. Every other block has at least
one parameter, and its parameter 0 has type `tok` (s6.4); no other parameter is `tok`.

Any function may call any non-kernel function, including itself and later ones. A kernel's result
is void; a kernel calls no function and no function calls a kernel except through `launch` (s7.7).

**Program entry (D11).** A unit is a program: exactly one function has kind 2 (export), no
parameters and result i32. It is the process entry (Omega `fn main to int`), and its result is the
exit status. Other exports (with parameters or another result) are entries a host calls in
function mode. A unit with no such function, or with several, is refused ENTRY (exit 30).

### 6.2 Values (SSA)

Every value is defined exactly once. Value ids are implicit, never stored. In each function:
value 0 is the entry token (type `tok`), values 1 .. nparams are the parameters, then, block by
block in order, each block's parameters, then each op's definitions in op order. A token op (s6.4)
defines its new token first and then its result if `ty` != 0; any other op defines one value when
`ty` != 0 and none otherwise (checks and facts take `ty` as a parameter and define only the token
or nothing, s7.1). A use names a value id.

- A use in block B at op j is valid when the definition is earlier in B (a parameter of B, or an op
  before j), or in a block that strictly dominates B, or is value 0 or a function parameter.
- A use of an id at or past the function's value count, or of a later op in the same block, is
  USE_BEFORE_DEF; a definition in a non-dominating block is DOMINANCE.
- Every block must be reachable from block 0 (UNREACHABLE).
- Values passed to a block's parameters come only from `br` and `cbr` (s7.6); merges are block
  parameters, there are no phi ops.

### 6.3 Kernels (one form for CPU and GPU)

A kernel describes the work of one thread; a launch runs it over a grid of blocks of `tx*ty*tz`
threads. The same kernel IR is lowered by `src/a64.om` (threads as loops and NEON lanes) and by
`src/gpu.om` (threads as sm_121 threads). `subgroup` is what the kernel requires; the target offers its
own width in its descriptor, and the backend refuses a mismatch (omega-mv#883 E3 s1). Shared
memory budget, nesting depth, thread maximum and feature set are target-descriptor checks done
by the backend, not by ngcheck. The race, divergence and sync rules of `docs/omegese/GPU.md`
(s6, s8 on `c1/chip-fix`) are kernel-checker obligations of the GPU lane (M5); ngcheck checks the
structural rules of s9.

### 6.4 The ordering token (D2c)

At every point of a block there is exactly one *current token*: value 0 at the start of block 0,
parameter 0 at the start of any other block. Ops are of three token classes (the `tk` column of
s7.12):

| class | ops | rule |
|---|---|---|
| E effect | every `chk.*`, `store fstore vstore fill atom atomcas mmast alloca sync call launch host` | operand 0 is the current token; the op defines a new token, which becomes current |
| R reader | `load fload vload mmald slice` | operand 0 is a token defined in this block at or before the current one, or one that dominates the block (the memory state it reads; s8 bounds which) |
| T terminator | `br cbr ret retv trap exit` | operand 0 of `br`'s arguments, and operand 0 of the others, is the current token |

All other ops take no token. A token value is used only as operand 0 of an E, R or T op (TOKEN,
exit 28, otherwise; also when an E or T op names a token that is not current). The token is
linear for E and T ops: on every path each token is consumed by exactly one E or T op (the one
right after it on the chain), because only the current token may be consumed and consuming it
replaces it. So the tokens of a function form one chain along every path, and every check, every
observable effect and every exit sits at a fixed place on it: a check cannot pass a store, a host
word, a call, a trap or another check without a rewrite that the validator sees. Reader ops (R)
read the chain without consuming it, so loads are not linear: an optimizer may give a load an older
token when it proves no store between the two writes the loaded element, and s8 rule 3 forbids an
older token than the check that covers it, so a load is never hoisted above its bounds check.
ngcheck checks the structural rule and s8, not alias proofs.

In the operand lists of s7 the token operand is not repeated: for E and R ops it is the first
operand on the wire, before the listed ones.

## 7. Ops

### 7.1 Encoding of an op

| bytes | field |
|---|---|
| 1 | `op` (s7.2 onward) |
| 4 | `ty`: the result type id, 0 when the op has no result; for `chk.conv` the destination type (s7.9) |
| 8 | `imm`, present only when the row has an imm column; 0 when its meaning says unused |
| 4 | `n`, present only for variadic rows (`br`, `call`, `host`, `launch`) |
| 4 each | operands: the token (E, R and T ops except `br`), the row's fixed operands, then `n` variadic operands |

Operand kinds: `b` block id (`br` operand 0, `cbr` operands 2 and 3), `f` function id (`call`
operand 1, `launch` operand 1); every other operand is a value id. Every `ty`, `imm` and operand is
checked against its row: a value outside the row's types is TYPE. The full row table, with the
field layout every reader uses, is s7.12.

Terminators are `br cbr ret retv trap exit` (and nothing else). Each block ends with exactly one
terminator, and no terminator appears before its end (UNTERMINATED).

Notation in the tables: `T` the result type; operand types in parentheses; *same* means the same
type id as `T`; the token operand is not listed (s6.4).

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
| 24 | `min` | arith | int: by signedness. float: IEEE minNum as Omega `fmin` (AArch64 FMINNM): one quiet NaN gives the other operand; a signaling NaN in either operand gives a quiet NaN; two NaNs give a quiet NaN; min(-0, +0) and min(+0, -0) are -0 |
| 25 | `max` | arith | float: as min, maximum (FMAXNM); max(-0, +0) and max(+0, -0) are +0 |
| 26 | `fsqrt` | float (1 operand) | IEEE square root, correctly rounded |
| 27 | `fabs` | float (1 operand) | clear the sign bit |
| 28 | `fmath` | float (1 operand), imm | transcendental with accuracy class, below |
| 30..35 | `eq ne lt le gt ge` | operands int, bool (eq, ne only) or float; ty bool, or VEC of bool with the operands' lanes | int by signedness; float IEEE ordered: any NaN gives false except `ne` |
| 36 | `conv` | ty num; operand num of another type; imm | numeric conversion, below |
| 37 | `bitcast` | ty and operand of equal bit width | reinterpret bits (one-layer-format s10.2 sets, extended to f16/bf16 with u16/i16 and fp8 with u8/i8) |

Float `min`/`max` (contract correction 2026-11-10, NgIrOracle head 2): the earlier draft rule "a
NaN operand gives the other" did not match the language. OMEGESE s9.9 defines `fmin`/`fmax` as
FMINNM/FMAXNM and the seeded compiler measures so: fmin(sNaN, 1.0f32) is the quiet NaN 0x7fc00001;
fmin(qNaN, 1.0) is 1.0; signed zeros as in the rows above. The quiet NaN's payload is unspecified,
like every arithmetic NaN. x86-64 back ends: MINSS/MAXSS do not implement this rule (they return
the second operand for any NaN and do not order signed zeros); they need an explicit NaN and
zero sequence.

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

**STRUCT elements are storage-only (v1).** An ARRAY or SLICE may have STRUCT elements (s4.2), and
`alloca`, `gaddr`, `len` and `slice` take such storage, but no value is ever a STRUCT or an ARRAY
(value types are scalar, VEC, REF, SLICE or FRAG). So `load`, `store`, `atom`, `atomcas`, `fill`,
`vload` and `vstore` need a scalar (or, for `load`/`store`, VEC) element and refuse a STRUCT element
with TYPE at the op, and no op yields a REF to one element. Fields are reached only through a REF to
the STRUCT itself (`gaddr`, `alloca`, or `fref` of an enclosing STRUCT) with `fload`, `fstore` and
`fref`; per-record data is laid out as a STRUCT of ARRAY fields: `fref` to the field's ARRAY, then
`load`/`store` element i under its `chk.bounds`. Omega has no arrays of structs (a struct is one
`new` object), so the front end needs no other route; an element-reference op is a later
extension. Fixtures: `r-struct-elem.oir` (TYPE), `k-soa.oir` (accepted).

### 7.6 Control (60..66)

| op | name | ty | imm | operands | meaning |
|---|---|---|---|---|---|
| 60 | `br` | 0 | - | b, then n values | jump to b; the n values (n = b's parameter count, same types in order; value 0 of them is the current token) become its parameters (BLOCK_ARITY) |
| 61 | `cbr` | 0 | - | c (bool), bt, bf | jump to bt if c else bf, passing the current token; bt and bf have exactly one parameter, the token (BLOCK_ARITY) |
| 62 | `ret` | 0 | - | - | return from a void function or kernel |
| 63 | `retv` | 0 | - | v (the function's result type) | return v |
| 64 | `call` | the callee's result | - | f, then n arguments | call f (any non-kernel function; n and types equal f's parameters) |
| 65 | `trap` | 0 | code 1..14 | - | trap with code (Omega `trap N`, exit 100+code) |
| 66 | `exit` | 0 | - | v (i32) | end the process with status v (Omega `exit`); functions and exports only |

`trap` in a kernel ends the thread (kernel traps below).

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

**Kernel traps (D10).** The trap state of a launch is one sticky code. A thread that fails a check or
reaches `trap` records its code (only its first; later checks of that thread record nothing). When
the launch ends, if any thread recorded a code, `launch` traps in the caller with the code of the
trapping thread with the lowest linear id: block linear id first, then thread linear id, that is
((block.z x blocks.y + block.y) x blocks.x + block.x) x (tx x ty x tz) + (thread.z x ty + thread.y)
x tx + thread.x. This is the code a sequential lowering that runs threads in linear order reports,
so `src/a64.om` and `src/gpu.om` agree. Kernel stores and atomics are unordered relative to traps:
after a trapping launch every location the kernel could write has an unspecified value. Obligation
on every back end: a trap never strands threads at a barrier. A trapped thread still arrives at
every `sync` it would reach (one way: it keeps running with its stores and atomics suppressed and
its loads reading 0, every loop being fuel-bounded; another: the barrier counts it as arrived);
`src/gpu.om` states which mechanism it uses. Without a trap the launch returns normally and every
kernel write is visible to the caller after `launch`. Inside a kernel the token orders a thread's
own checks and effects; it orders nothing between threads (only `sync` and atomics do).

`src/gpu.om` (ng-gpu, PROPOSED, `~/handoffs/hive-ng/gpu/IR-GPU-DRAFT.md`) takes the second way: a
trapping thread does a device-scope 64-bit unsigned atomic min of `(linear id << 4) | code` into
one per-launch trap word (initialised to all ones, CPU-visible and uncached) and exits; the host
reads the word after the launch, so the lowest linear id wins as above. Exited threads release
barriers (PTX ISA 9.4, `exit`; that `BAR.SYNC` on GB10 does the same is untested until ng-gpu's
chip check). Its target-descriptor limits: fewer than 2^60 threads per launch, and an encoder with
a 64-bit atomic min.

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

A check is an E op (s6.4): it reads the current token and defines the next one, and defines no other
value. Its `imm` is the trap code, which must equal the code in the row (CHECK_CODE); only
`chk.true` takes any code 1..14. Code 0 is always CHECK_CODE. On failure the program traps with
that code (exit 100 + code) and no later effect on the token chain happens; on success nothing
happens. Operands have the type the row names.

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
and never emit them, Omegese kernels trap on u32 overflow and do.

`chk.fuel` order: the front end emits a `while` loop the way omc runs it (`seed/omc/omc.om`
9469-9505, note at 9470-9471): at the loop head the condition is evaluated first; when it is false
the loop exits without a fuel check; when it is true `chk.fuel 4 k N` runs (k = passes completed),
then k + 1, then the body. So a loop that runs zero times never traps 4, and a loop whose
condition is still true after exactly N passes traps 4.

Trap 6 (stack) is not a check op: `call` and `alloca` may trap 6 when the back end's stack is
exhausted, before any effect of the callee or allocation. NG frames differ in size from omc's, so
the differential gate compares trap 6 only when both compilers trap 6, and records stack-depth
cases as BEYOND_OMC (D9).

### 7.10 Facts (90..93): non-executing

A fact has no result, no token and no run-time effect. It states a property that holds whenever
control reaches it; consumers (passes, back ends) may rely on it. `imm` is the origin. D2c gives a
fact authority only through a check or a proof:

- **origin 0 (front end):** the fact restates a check. It must be dominated by a check op with the
  same operands (`fact.true c` by `chk.true k c` for any code k; `fact.inbounds r i e` by
  `chk.bounds r i e`; `fact.slice r off n` by `chk.slice r off n`; `fact.range v lo hi` by
  `chk.true` on a value the front end built as `and (ge v lo) (le v hi)`, which ngcheck does not
  trace, so origin 0 `fact.range` is refused). An unchecked origin 0 fact is FACT (exit 29). This is
  how an Omega `requires`, `ensures`, `invariant` or `holds` reaches the optimizer: its `chk.true`
  runs first. A contract the build does not check produces no fact.
- **origin 1..255 (a pass):** the number of the pass whose proof it is (the pass table is in
  `src/opt.om`). ngcheck checks typing and placement, not truth; every such pass carries its own
  translation-validation gate and mutants (D7, D9).

Other origin values are NONCANONICAL.

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

`imm` is the keyword id of the pinned `seed/omc/omc.om` keyword lookup (`read` 53, `write` 54,
`fclose` 100 through `vfioirq` 232, `execenv` 233 and `prlimit` 235; `exit`, `const`, `qty`,
`fma` and the x86efi word `efi` are not host words). The normative
table is `seed/ng/hostwords.tsv` (columns `id word args class`, 94 rows, extracted from OMEGESE s10,
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

**Reference interpreter host policy.** `ngrun FILE.ir [STEPS] [--scratch NEW-DIR] [-- ARGS...]`
executes only host words whose effects are deterministic or confined, so a differential test can
compare stdout and exit status with a native run. `argcnt` and `argread` see FILE.ir as argument 0
and the ARGS after `--` as arguments 1.., so the count equals that of a native program given the
same ARGS; `envcnt`/`envread` read ngrun's own environment. `monons`, `realns`,
`getuid`, `geteuid`, `getgid`, `getegid`, `cpufence` and `cpurelax` execute natively; IR.md
defines no fixed-value clock mode, so clock results are live and a test may compare only their sign.
`sleepns 0` executes; any other interval is refused as nondeterministic.
File words run only with `--scratch`: ngrun creates NEW-DIR (mode 0700; it must not exist), opens it
with O_DIRECTORY|O_NOFOLLOW and makes it the working directory. Every path must be one component
(no `/`, no NUL, not `.` or `..`, 1..4095 bytes); opens add O_NOFOLLOW; `renames` and `link`
packets must hold exactly two such names. Descriptors are virtual: stdin (0) may be read and
stdout/stderr (1, 2) written; every other operation needs a descriptor created by an interpreted
`fopen` or `memfd`. A refused word prints `ngrun: refused host class C word W at OFFSET` on stderr
and exits C before any effect:

| exit | class | words |
|---|---|---|
| 115 | process | fork dupfd waitpid execprog execpure execenv killpid pipefds getpid getppid setsid getpgid setpgid getsid |
| 116 | limits | prlimit |
| 117 | device | devctl mapnew mapdrop mapread mapwrite devcall uvmctl mapaddr mapget mapset maphold mapbind vfioctl vfiomap vfiomapw eventfd vfioirq |
| 118 | network | socknew listen accept connect bind recv send waitio sockname sockopt shutdown peercred pollfds sendmsg peername |
| 119 | outside scratch | any path or descriptor word without `--scratch`, an absolute or multi-component path, `.`/`..`, a descriptor ngrun did not create (including pread/pwrite on 0..2) |
| 120 | nondeterministic | random, sleepns with a nonzero interval |
| 121 | unsafe filesystem | symlnk, syncfs, a blocking or shared-wait flock |
| 122 | unclassified | a host word id with no row here (unreachable for accepted units) |
| 123 | descriptor table | more than 256 live virtual descriptors |

These exits sit above the trap range 101..114 and below 124 (step limit), 125 (unsupported op) and
126 (access outside storage). They describe the reference interpreter, not program semantics:
native code may execute every word.

**Pending host words (not on main).** omega-mv `ham/om-threads` 652694b0 adds the affinity and
priority words `cpuset` 236, `cpuget` 237, `cpunow` 238, `setprio` 239 and `getprio` 240. Main
(82e536e1, omc 6d1b1cf5) does not have them, so they have no row in `hostwords.tsv` and no class
above; ngcheck refuses a unit naming one (`ngcheck: EFFECT`, exit 22). When that head lands and reseeds omc, the same change
adds their rows and refuses them by class: `cpuset`, `cpuget`, `setprio` and `getprio` as 115
process (they read or change scheduling state of the process), `cpunow` as 120 nondeterministic
(the CPU a thread runs on may change between calls).

### 7.12 Row table (the layout every reader uses)

`tk`: token class (s6.4): P none, E effect, R reader, T terminator. `imm`: y when the op carries
the 8-byte imm. `fix`: fixed operands after the token. `var`: y when a `u32 n` and n more operands
follow. `ty`: r a result type (nonzero), o optional result (0 = none), p a parameter (no result
value), 0 always 0.

| op | name | tk | imm | fix | var | ty |
|---|---|---|---|---|---|---|
| 1 | `const` | P | y | 0 | - | r |
| 2 | `select` | P | - | 3 | - | r |
| 10..14, 16..18, 20..25 | `add sub mul div rem and or xor shl shr rotl rotr min max` | P | - | 2 | - | r |
| 15, 19, 26, 27 | `neg not fsqrt fabs` | P | - | 1 | - | r |
| 28 | `fmath` | P | y | 1 | - | r |
| 30..35 | `eq ne lt le gt ge` | P | - | 2 | - | r |
| 36 | `conv` | P | y | 1 | - | r |
| 37 | `bitcast` | P | - | 1 | - | r |
| 40 | `gpu.id` | P | y | 0 | - | r |
| 41 | `shared` | P | - | 0 | - | r |
| 42 | `load` | R | - | 2 | - | r |
| 43 | `store` | E | - | 3 | - | 0 |
| 44 | `sync` | E | - | 0 | - | 0 |
| 45 | `shfl` | P | y | 2 | - | r |
| 46 | `fma` | P | - | 3 | - | r |
| 47 | `atom` | E | y | 3 | - | r |
| 48 | `atomcas` | E | y | 4 | - | r |
| 50 | `alloca` | E | - | 0 | - | r |
| 51 | `fill` | E | - | 2 | - | 0 |
| 52 | `gaddr` | P | y | 0 | - | r |
| 53 | `len` | P | - | 1 | - | r |
| 54 | `slice` | R | - | 3 | - | r |
| 55 | `fload` | R | y | 1 | - | r |
| 56 | `fstore` | E | y | 2 | - | 0 |
| 57 | `fref` | P | y | 1 | - | r |
| 58 | `vload` | R | - | 2 | - | r |
| 59 | `vstore` | E | - | 3 | - | 0 |
| 60 | `br` | T | - | 1 | y | 0 |
| 61 | `cbr` | T | - | 3 | - | 0 |
| 62 | `ret` | T | - | 0 | - | 0 |
| 63 | `retv` | T | - | 1 | - | 0 |
| 64 | `call` | E | - | 1 | y | o |
| 65 | `trap` | T | y | 0 | - | 0 |
| 66 | `exit` | T | - | 1 | - | 0 |
| 67 | `launch` | E | - | 4 | y | 0 |
| 70, 71, 72, 75, 76, 81 | `chk.add chk.sub chk.mul chk.divovf chk.shl chk.fuel` | E | y | 2 | - | 0 |
| 73, 74, 77, 82 | `chk.neg chk.divz chk.shift chk.true` | E | y | 1 | - | 0 |
| 78 | `chk.conv` | E | y | 1 | - | p |
| 79, 80 | `chk.bounds chk.slice` | E | y | 3 | - | 0 |
| 90 | `fact.true` | P | y | 1 | - | 0 |
| 91, 92, 93 | `fact.range fact.inbounds fact.slice` | P | y | 3 | - | 0 |
| 100 | `vsplat` | P | - | 1 | - | r |
| 101 | `vextract` | P | y | 1 | - | r |
| 102 | `vinsert` | P | y | 2 | - | r |
| 103 | `vreduce` | P | y | 1 | - | r |
| 104 | `mmald` | R | y | 4 | - | r |
| 105 | `mmast` | E | y | 5 | - | 0 |
| 106 | `mma` | P | y | 3 | - | r |
| 110 | `host` | E | y | 0 | y | o |

Every op byte not in the table is UNKNOWN_OP. `shfl`, `mma`, `mmald`, `mmast` and `sync` are
*convergent*: an optimizer never moves them into or out of a branch, and never duplicates them.

## 8. Coverage (the memory safety rule)

An access op A with token operand t is covered by a check or fact op C when

1. C has the operands the table names (same SSA ids), and
2. C dominates A (earlier in the same block, or in a block that dominates A's block), and
3. when C is a check, its defined token is t or dominates t on the chain (so A reads memory only
   after C has run; a fact has no token and needs only 2).

| access | covered by `chk.bounds` or `fact.inbounds` on | with e |
|---|---|---|
| `load`, `store`, `atom`, `atomcas` | (r, i, e) | e defined by a `const` >= 1 |
| `vload`, `vstore` | (r, i, e) | e defined by a `const` >= the lanes |
| `mmald`, `mmast` | (r, i, e) | e is the op's own e operand |
| `slice`, each `host` slice | `chk.slice` or `fact.slice` on (r, off, n) | - |

`fload`, `fstore` and `fref` need no coverage: the field lies inside the STRUCT by the type table.
A REF obtained from `gaddr`, `alloca`, `shared` or `fref` is still covered this way: the check is
explicit even when the bound is a constant, and a pass replaces a proven check by a fact (s15). An
uncovered access is UNCHECKED.

## 9. Structural rules ngcheck enforces

1. Every id names an existing object of the right kind: type, global, function, block, value (REF).
2. Types per row (TYPE); writes need access 1; CONSTANT space is read-only; `tok` only where s4.1
   allows it.
3. Block 0 has no parameters (BLOCK_ARITY, at the block's offset) and is not a branch target
   (REF); other blocks start with one `tok` parameter (BLOCK_ARITY). `alloca` and `shared` only in
   block 0 (EFFECT).
4. Every block reachable; SSA dominance (s6.2).
5. Terminators (s7.1); `br` arity and types; `cbr` targets with exactly the token parameter.
6. `retv` only in non-void functions with the result type; `ret` only in void ones.
7. Kernel ops (`gpu.id shared sync shfl mmald mmast mma` and FRAG values) only in kernels; `host`,
   `exit`, `launch` and `call` only outside them; a kernel's result is void; `launch`'s callee is
   a kernel and `call`'s is not (EFFECT).
8. The token chain (TOKEN, s6.4), check codes (CHECK_CODE), coverage (UNCHECKED), facts (FACT).
9. Canonical fields (NONCANONICAL): reserved bits, `const` imm form, duplicate types, `ty` not 0
   where the row says 0, flags, `order` of a non-scalar field, enumerations.
10. Exactly one program entry (ENTRY, s6.1).

## 10. Canonical text form (D3)

`ngdis` prints, and `ngas` reads, exactly one text per unit. Byte-exact round trips are a gate:
`ngdis(ngas(t)) == t` for every fixture text and `ngas(ngdis(b)) == b` for every assembled binary.
ngas reads only canonical text: it refuses anything ngdis would not print (no comments, single
spaces, no trailing spaces, every line ends with one LF, decimal numbers without leading zeros or
`+`). ngas checks syntax and numbering only; semantic refusals are ngcheck's, so a fixture for any
semantic class is canonical text. Example:

```
omegair 1
type %t32 = vec i32 4
type %t33 = array u8 64
type %t34 = struct 16 u64@0:le i32@8:be
type %t35 = ref edit host %t33
type %t36 = slice view host u8
type %t37 = frag a 16 8 16 f16
type %t38 = array u8 5
global @g0 %t33 zero
global @g1 %t38 data 68656c6c6f
fn @f0 flags 0 %1:i32 %2:i32 -> i32
block ^0
%3 = chk.add 1 %0 %1 %2
%4 = add i32 %1 %2
retv %3 %4
end
kernel @f1 flags 0 threads 256 1 1 subgroup 32 -> void
block ^0
%1 = gpu.id u32 0
ret %0
end
export @f2 flags 0 -> i32
block ^0
%1 = const i32 0
retv %0 %1
end
```

- Header line `omegair 1`. Then the type table, the globals, the functions, in wire order.
- Types: built-ins by name (`void bool u8 u16 u32 u64 i8 i16 i32 i64 f32 f64 f16 bf16 e4m3 e5m2
  tok`), every other id (table types and unnamed or absent ids alike) as `%tN` with N the type
  id; a named built-in is never spelled `%tN`. `vec E L`, `array E C`, `struct SIZE` then each
  field as `TYPE@OFFSET:ORDER` (`le`, `be`), `ref ACCESS SPACE T`, `slice ACCESS SPACE E`,
  `frag ROLE M N K E`; access `view`/`edit`; space `host global shared constant private`; role `a`
  `b` `c`. Type line N is `type %tN = ...` with N = 32 + its index.
- `global @gN TYPE zero` (class 0) or `global @gN TYPE data HEX` (class 1, lowercase hex of every
  byte). The data length is the byte size of TYPE (a scalar's width; VEC lanes x element; ARRAY
  count x element; STRUCT its SIZE; 0 for anything else, printed as `data` with no hex).
- Function line: `fn` (kind 0), `kernel` (kind 1) or `export` (kind 2), `@fN`, `flags N`, kernel
  `threads X Y Z subgroup S`, each parameter as ` %N:TYPE` (value ids from 1; the entry token %0 is
  implicit), then ` -> ` and the result type.
- `block ^N` then each parameter as ` %N:TYPE`.
- Op line: the defined values, if any, as `%N = ` or `%T %V = ` (token then result), the mnemonic,
  then `ty` when the row's ty column is r, o or p (`void` for ty 0), then imm when the row has one,
  then the operands. imm is decimal, except `const` of a scalar type: signed decimal for signed
  ints (`-0` is not canonical), `true`/`false` for bool, decimal for unsigned, and `0x` with exactly
  2, 4, 8 or 16 lowercase hex digits of the bits for floats; `const` of a non-scalar `ty` prints
  the imm in decimal. `gaddr` prints `@gN`. Operands: `%N` values, `^N` blocks, `@fN` functions;
  a variadic op's `n` is the operand count minus the row's fixed operands.
- `end` closes the function.

Ids are printed as stored, in range or not, so every semantic refusal has a text fixture. What the
text cannot spell, `ngdis` refuses with the s11 code and `ngdis: refused class C at OFFSET` on
stderr: MAGIC, VERSION, TRUNCATED, TRAILING, UNKNOWN_OP, LIMIT (below), IO, and NONCANONICAL for an
enumeration outside its set (type kind, access, space, field order, frag role, global class,
function kind), a nonzero `ty` on a row whose ty column is 0, or a `const` imm that is not canonical
for its scalar type. Its text is complete only on exit 0: a refusal found before 1 MiB of text
leaves stdout empty, one found later leaves the text already written. `ngas` refuses
non-canonical text with `ngas: syntax error at line N` and exit 3 (out of order or misnumbered type,
global, function, block or value ids; the wrong number of defined values for the row and `ty`; a
fixed-operand count that differs from the row; a `const` outside its type; a global's data length),
input or output over 16 MiB with exit 23, unreadable input with exit 27.

**Text tool capacities.** Both text tools hold what the text can spell, so their limits are the
table sizes, not ngcheck's semantic limits: input over 16777216 bytes is LIMIT (ngdis reads one
byte past the buffer: more input is `ngdis: refused class 23 at 16777216`, a read error class 27 at
the bytes read); more than 65536 types, globals, functions, blocks in one function, or parameters
of one function or block is LIMIT, `ngdis: refused class 23 at` the count's offset, checked before
the entries, and `ngas: limit at line N` (the line of the first item over) with exit 23. The
parameter limit stays 65536 in the text tools so that ngcheck's 64-parameter LIMIT keeps a text
fixture.

`seed/ng/tests/ir/` holds the fixtures: canonical text (`NAME.oir`), and the `cases` file that
`seed/ng/gate-ir.om` runs: text cases with their ngcheck class and offset, ngas syntax refusals,
byte mutations of assembled fixtures for what text cannot spell (MAGIC, VERSION, TRUNCATED,
NONCANONICAL, TRAILING, UNKNOWN_OP, counts over s12), each judged by ngcheck and ngdis alike and by
`ng ir-copy` as s14 states, and inputs the gate generates at the capacities (16777216 bytes and one
more, 65537 types, globals, functions, blocks and parameters).
Run pairs
(`x-NAME.oir` with `x-NAME.om`, the same program in Omega) are the D9 differential of this
document's semantics: `seed/ng/ngrun.om`, the reference interpreter of s7, runs the ΩIR, omc
compiles and runs the Omega, and exit status, stdout and stderr must be equal, traps at the exact
boundaries included (overflow at 2^63, fuel at exactly 1e6 passes, index == len, MIN div -1,
shift by the width, a conversion one past the range and one at the bottom of it, a signed shift
left that reaches the minimum). What Omega cannot state (u64 checked add and mul, `chk.bounds` with
e = 0, wrapping narrow `neg`, the trap 6 depth) the gate checks on ngrun alone (N cases).
Random programs (`seed/ng/ngrand.om`, the D9 differential source for back ends): `ngrand SEED`
writes a unit built with `src/ir.om` from a byte tape that SEED fills; every tape gives a unit
ngcheck accepts (typed SSA, one token chain, checks with their codes, diamonds joined by block
parameters, counted loops under `chk.fuel`, calls to lower helpers, i64 memory under `chk.bounds`,
host write), and byte 0 is always the smallest choice, so `ngrand shrink SEED STATUS OUT CMD...`
minimizes a unit by deleting and zeroing tape bytes while the predicate CMD exits STATUS. The gate
runs seeds 1..1000 (ngcheck's whole ACCEPT line, `ngas(ngdis(b)) == b`, ngrun ends cleanly), one
shrink with ngrun as the predicate, and a mutant ngrand that drops one token edge, which ngcheck
must refuse TOKEN. ngrun has no second oracle on these units: a back end diffing against ngrun is
the differential, and its disagreements judge both.

**Reference-interpreter float checks.** The supported scalar f32/f64 subset includes bitcast,
nearest-even and toward-zero conversions (imm 0, 1, 4, 5 for float destinations), and fused
FMA. Integer destinations still require imm 0: they already truncate toward zero and saturate;
the former unsupported rounding-mode defect concerned float destinations, not float-to-int.
Bitcasts retain the entire declared width, including the sign bit and NaN payload. FMA is
one operation at the declared precision, not a widened or multiply-then-add evaluation.

The IR gate builds `tests/ir/float-oracle.om` with the pinned seeded omc and runs it natively.
That independent executable emits a unit containing expected raw-bit checks computed with
native omc bitcasts, conversions and FMA. It links the IR writer, never ngrun. For each float
width it checks 18 signed special/boundary bit patterns (zeros, infinities, quiet and signaling
NaNs with payloads, minimum and maximum subnormals, minimum normals and maximum finite values)
and 1024 deterministic random patterns. It checks float-to-int for all eight integer widths,
16 probes at each destination's boundaries, integer-to-float in every defined mode at integer
range and precision boundaries, and f64-to-f32 in every defined mode. The native toward-zero
f64-to-f32 reference decodes the sign, exponent and significand as integers; it does not use
ngrun's predecessor-of-nearest algorithm. A separate mutant removes that predecessor step.
NaN conversions are
compared by NaN classification; bitcasts and FMA compare raw bits. FMA includes three explicit
witnesses and the same special/random sweep: two fused-versus-unfused cases and one f32 case
(`0x3f7ff001 * 0x33800800 + 1`, exactly 1 + 2^-24 + 2^-60) where an f64 FMA narrowed to f32
double-rounds to `0x3f800000` instead of `0x3f800001`. The oracle exits 3 unless native omc
reproduces the exact Wolfram-checked bits of all three. The native oracle prints
its measured check count and finite fused-versus-unfused difference count on stderr.
`tests/ir/intcv-oracle.om` independently exercises all 16 unsigned-to-signed width pairs at
eight boundary inputs each (128 native comparisons), including source MAX and MAX-1. Another
256 native comparisons check f32/f64 `chk.conv` at 16 boundary probes for each integer type,
using an independent integer decoder of the float sign, exponent and significand rather than
ngrun's float comparisons. It emits
the IR before performing the equivalent checked native conversion, so its native exit is the
expected IR exit (0 or trap 5). The gate compares exit, stdout and stderr. Sign-bit erasure,
RTZ refusal, unfused f32 and f64 FMA, f32 FMA widened to f64 then narrowed, and the former
unsigned-to-signed check each have a separately killed interpreter mutant. These are host semantic
checks, not hardware qualification
of either NG back end; the integer random-IR generator still has no second independent oracle.

## 11. Refusal classes and ngcheck exit codes

`ngcheck` reads binary ΩIR on stdin. Accept: exit 0 and one stdout line
`ACCEPT <sha256 hex> fns=N blocks=N ops=N`. Refusal: no stdout, exit code below, and one stderr
line `ngcheck: <CLASS> at <byte offset>` (offset of the field, op or record at fault, decimal).
The first fault ends the run. Phase 1 reads the unit front to back and checks every rule that needs
only the record at hand: header, type table and globals completely (a type-table or global fault
is reported at its entry's offset), function and block headers, op rows and every count against
s12 (at the count's offset); then the program entry (ENTRY: at the function count when there is
none, at the second entry's record otherwise). Phase 2 checks each function in order: terminators
(UNTERMINATED), branch targets and their arity (REF, BLOCK_ARITY), reachability (UNREACHABLE),
then each op in block and op order: operand ids, definitions and the token (REF, USE_BEFORE_DEF,
DOMINANCE, TOKEN), its `ty` against the row, placement (EFFECT), codes and origins (CHECK_CODE,
NONCANONICAL), typing (TYPE, and BLOCK_ARITY for `br` argument types), then coverage and facts
(UNCHECKED, FACT). Op faults are reported at the op's offset, block faults at the block's,
function faults at the function record's.

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
| 19 | BLOCK_ARITY | `br` arguments differ from the target's parameters; a `cbr` target with other than the token parameter; a non-entry block without its token parameter; an entry block (block 0) with parameters |
| 20 | UNTERMINATED | a block without a terminator at its end, or a terminator before its end |
| 21 | CHECK_CODE | a check without its exact trap code, or `trap`/`chk.true` code outside 1..14 |
| 22 | EFFECT | an op in a function kind or block that does not allow it (s9 rules 3 and 7), an unknown host word |
| 23 | LIMIT | a count over s12 |
| 24 | REF | an id names no object of its kind; a branch to block 0 |
| 25 | UNCHECKED | a memory access or slice without coverage (s8) |
| 26 | UNREACHABLE | a block not reachable from block 0 |
| 27 | IO | standard input could not be read |
| 28 | TOKEN | a token used outside operand 0 of an E, R or T op, an E or T op not using the current token, a reader using a token after the current one |
| 29 | FACT | an origin 0 fact without its dominating check (s7.10) |
| 30 | ENTRY | no program entry, or more than one (s6.1, D11) |

## 12. Limits (implementation limits of the v1 tools)

| item | limit |
|---|---|
| input bytes | 16777216 |
| types | 65536 |
| struct fields, whole module | 65536 (64 per struct) |
| globals | 65536 (class-1 data within the input limit) |
| functions | 65536 |
| parameters (function, block) | 64 |
| blocks per function | 65536; whole module 1048576 |
| ops per function | 1048576; whole module 4194304 |
| values per function | 2097152 |
| `call`/`host`/`launch` arguments | 64 |

A count above its limit is LIMIT (exit 23) at the count's offset, checked before reading what it
counts. ngcheck and `src/ir.om` share these numbers; the text tools use the capacities of s10
(65536 for every table, parameters included), which are never below them.

## 13. Mapping from Omega (for `src/front.om`)

`t` is the current token; each E op makes the next one.

| Omega | ΩIR |
|---|---|
| signed `add x y` | `t1 = chk.add 1 t x y`, then `add` |
| `div a b` signed | `chk.divz 2 b`, `chk.divovf 1 a b`, then `div` |
| `rem a b` | `chk.divz 2 b`, `rem` |
| `shl a b` signed | `chk.shift 7 b`, `chk.shl 1 a b`, `shl` |
| `uchar x` (narrowing) | `chk.conv u8 5 x`, `conv u8 x` |
| `get A i` | `chk.bounds 3 A i e1` (e1 a `const u64 1`), then `load` reading the new token |
| `while c bound N` | header block with counter k; evaluate c; on true `chk.fuel 4 k N` then the body (the condition before the fuel check, as `omc.om` 9469-9505) |
| `requires c` (om2, checked build) | `chk.true 9 c` at entry, then `fact.true 0 c` |
| `requires c` (unchecked build) | nothing: no check, no fact (D2c) |
| `trap N` | `trap N` |
| host word | `chk.slice` on each slice, then `host` |
| Omegese GPU `kernel` | kind 1, `gpu.id`, `shared`, `sync`, `shfl`, `fma`, `fmath` FAST |

## 14. In-memory ΩIR: `seed/ng/src/ir.om` (D1b)

`ir.om` holds ΩIR in global tables and owns the one binary reader and writer of the `ng` binary.
Its first code line is `om2` (D11), so the whole `ng` unit is om2: every lane file compiles as
part of an om2 unit (`at` is reserved there, error 16).
Stages build and read these tables directly; nothing is serialized between stages. Names follow
D1b: functions `ir_*`, globals `i_*` (at most 8 bytes). Other lanes read the tables and call the
`ir_*` functions; they never write a table directly.

**Handles.** Every handle is a `uint`, and 0 means none. Types use their wire type ids (s4).
Globals, functions, blocks, ops and values are numbered from 1 in creation order across the whole
module. The writer turns handles into wire ids: global g is wire id g-1, function f is f-1, a block
is its position in its function's block list, and values are numbered by s6.2 (`ir_num`).

**Tables** (index = handle; counters in `i_n`):

| table | contents |
|---|---|
| `i_n` | counters: 0 table types, 1 struct fields, 2 globals, 3 functions, 4 blocks, 5 ops, 6 values, 7 operand slots, 8 global data bytes |
| `i_tk i_t1 .. i_t5` | type id -> kind (s4.2, 0 for built-ins) and fields in wire order: VEC elem, lanes; ARRAY elem, count; STRUCT size, nfields, first field; REF target, access, space; SLICE elem, access, space; FRAG role, m, n, k, elem |
| `i_xty i_xof i_xor` | struct field -> type, offset, order |
| `i_gty i_gcl i_gd0 i_gdat` | global -> type, class, first data byte in the `i_gdat` pool |
| `i_fk i_ffl i_frs i_fnp i_ftk i_fp1 i_fb1 i_fbt i_fnb i_ftx i_fty i_ftz i_fsg` | function -> kind, flags, result type, parameter count, entry token value, first parameter value, first and last block, block count, kernel threads x, y, z, subgroup |
| `i_bf i_bnx i_bp1 i_bnp i_bo1 i_bot i_bno` | block -> function, next block, first parameter value, parameter count, first and last op, op count |
| `i_oop i_oty i_oim i_ona i_oa0 i_ob i_onx i_otk i_ors` | op -> opcode, ty, imm (`ulong`), operand count (token included), first slot in `i_arg`, block, next op, defined token value, defined result value |
| `i_arg` | operand slots: value handles, block handles (`br`, `cbr`), function handles (`call`, `launch`) |
| `i_vty i_vk i_vo i_vnx i_vno` | value -> type, kind (0 entry token, 1 function parameter, 2 block parameter, 3 op token, 4 op result), owner (function, block or op), next parameter in its list, wire id (after `ir_num`) |

**Builder** (each returns the new handle or type id; capacity overrun traps 3 at the table, the
front end refuses earlier):

| call | effect |
|---|---|
| `ir_init` | empty module |
| `ir_tvec e l`, `ir_tarr e c`, `ir_tref t a s`, `ir_tslc e a s`, `ir_tfrg r m n k e` | the type id, creating it once (equal types are one id) |
| `ir_tsb size`, `ir_tsf t off ord`, `ir_tse` | begin a struct, add a field, finish: the type id (deduplicated) |
| `ir_glob t cls`, `ir_gbyt g b` | a global; append one data byte to a class-1 global |
| `ir_fnew kind flags res` | a function, with its entry token value |
| `ir_fpar f t`, `ir_fker f x y z sg` | add a parameter value; set a kernel's threads and subgroup |
| `ir_blk f` | append a block; every block after the first gets its `tok` parameter 0 at once |
| `ir_bpar b t` | add a block parameter value |
| `ir_btok b`, `ir_ftok f` | a block's token parameter; a function's entry token |
| `ir_op b op ty imm n` | append an op with n operand slots (token included); defines its token and result values by the row (s7.12) |
| `ir_set o k h` | set operand slot k |
| `ir_res o`, `ir_otok o`, `ir_arg o k` | the op's result value, defined token, operand k |
| `ir_num f` | fill `i_vno` for f by s6.2; returns f's value count |

**Reader and writer**: `ir_read off stop` parses `i_in[off..stop)` into empty tables and returns 0
or a refusal class of s11, with `ir_badat` the absolute offset in `i_in`. It refuses what it needs
to build sound tables (classes 10..15, 23, and REF/USE_BEFORE_DEF/BLOCK_ARITY/UNTERMINATED/TYPE
where an id, a count or a global's data size cannot be resolved) and leaves every semantic rule to
ngcheck. `ir_wr` writes the tables to `i_out` and returns the byte count. `ir_wr` after `ir_read`
reproduces the input bytes exactly for every unit `ir_read` accepts. The gate runs `ng ir-copy` on
every fixture unit, every byte mutation and the generated binaries (full, over, types): where
ngcheck refuses with a structural class (MAGIC, VERSION, TRUNCATED, TRAILING, UNKNOWN_OP, LIMIT,
IO) ng must print the same class and offset with empty stdout; otherwise ng must give the bytes back
exactly or, where ngcheck refuses, refuse with a class of s11 and empty stdout. In the tables a
`gaddr` imm is the global's handle (the writer subtracts 1, the reader adds 1); every other imm is
the wire value.

Register budget: omc gives a function 16 registers, and each global array read in one expression
costs one. Keep table reads to two or three per statement (the `ir_*` code shows the pattern).

`main.om` reads the first input line (the mode, at most 63 bytes and its newline) apart, so the
payload after it fills `i_in` from offset 0 and may be the full 16777216 bytes of s12. `@ng ir-copy`
reads the ΩIR binary payload and writes it back (reader/writer round trip). A refusal prints `ng:
refused class C at OFFSET`, offset in the payload, empty stdout, and exits C: a payload over
16777216 bytes is class 23 at 16777216, an unreadable one class 27; an unknown mode is `ng:
unknown mode` and exit 2. Stage lanes add their modes (`@ng dump-ir <stage>` after the front end or
a pass, `@ng ingest-ir <stage>` before a back end) beside their code.

## 15. What a pass may do to a check (D7)

A check is never moved above an earlier effect, an earlier trap or a loop that may run zero times;
the token chain makes the first two visible to the validator, and the differential gate with
zero-trip mutants guards the third. A pass removes a check in exactly two ways:

1. **Delete** a check that a dominating fact or check proves cannot fail, replacing it by the fact
   (`chk.bounds` by `fact.inbounds` with the pass's origin), so the coverage rule still holds.
2. **Version** a loop: a guard on the loop entry tests that every index stays in range and the trip
   count stays below the fuel bound; the fast copy carries facts in place of the checks, and the
   original loop, checks intact, runs when the guard fails.

Every pass that does either has mutants that attack trap order and zero-trip hoisting (D9).
