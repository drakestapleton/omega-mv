# FR-7 C ABI, first slice

Omega calls a C function, and C calls an Omega function, on the GB10. The
convention is AAPCS64 for scalar integers, `bool`, and pointers. The unit is
AArch64 only. A `target` line is error 25.

Floats and structs are refused here. They belong with the IR lane on
`omc/ir-aggregates-floats`, which is adding floats and aggregates. This slice
does not guess their register class.

## Unit

The first line is `cabi`. The next line is `om2` or `om2 release`.

```
cabi
om2
extern fn add2 a int b int to int
export fn om_add a int b int to int
ret add a b
end
```

`extern fn` is a C function with no body. `export fn` is an Omega function C
can call. A plain `fn` is private: it has code and no symbol.

## Declaration

```
extern fn NAME p1 T1 p2 T2 ... to TYPE
export fn NAME p1 T1 p2 T2 ... to TYPE
```

`TYPE` is an integer type (`uchar` through `ulong`, `byte` through `long`),
`bool`, or `void`. A parameter is one of those scalars, or `view T N`,
`edit T N`, `view T *`, or `edit T *`, with `T` an integer type or `bool`.

`f32`, `f64`, and `qty` are error 7. A struct parameter is error 7. `fresh`
is error 27. The name `main` is error 9, because the C program owns that
symbol. A unit with no `export fn` is error 9.

A call with fewer arguments than the declaration is error 4. A call with
more is error 5. A different type is error 7.

## Symbol names

The ELF symbol is the function name, byte for byte. There is no leading
underscore. `export` is a global function symbol in `.text`. `extern` is a
global function symbol with no section. A private function has no symbol.

## Registers

Arguments are the AAPCS64 integer class. Slot 0 is `x0`, then `x1`, `x2`,
`x3`, `x4`, and `x5`. A scalar takes one slot. A sized `view` or `edit`
takes one slot, the address. An unsized `view` or `edit` takes two: the
address, then the element count as `ulong`.

The result is in `x0`. `void` leaves `x0` unused. A pointer result is
declared `ulong`: the address comes back in `x0`.

A sized view of `int` matches a C `int *` when the C side already knows the
count. `int` is 4 bytes, `long` is 8, `uchar` is 1, the same widths as the
LP64 C compiler on this machine. An unsized view matches a pointer plus a
count, as in `p view int *` beside `int *p, unsigned long n`.

The low bits of the register hold a narrow integer. The C declaration uses
the same width (`int` with `int`, `long` with `long`).

AAPCS64 leaves the unused high bits of a value narrower than 64 bits
unspecified, in an argument and in a result. An exported function widens
each scalar parameter into the full register before its body: `byte`,
`short` and `int` are sign-extended, and `bool`, `uchar`, `ushort` and
`uint` are zero-extended. `long` and `ulong` already fill the register. A
call of an `extern` widens the value that comes back in `x0` the same way,
before Omega reads it.

`x16` is scratch. `x18` is left untouched. `x8`, `x9` through `x15`, and
`x17` are temporaries inside the function.

The compiler's function record holds six parameter slots, so this slice
emits `x0` through `x5` only. A seventh slot is error 9.

## Stack

At a call, the stack pointer is a multiple of 16. The save area and each
local array are rounded up to 16. There is no red zone.

AAPCS64 places the next integer or pointer argument after `x7` on the stack,
one 8-byte slot at a time, at `[sp]`, `[sp, #8]`, and so on. The caller
allocates those bytes before the branch and drops them after the return.
The callee finds them at the incoming stack pointer. This slice does not
emit that area. The arguments that would land in `x6`, in `x7`, and on the
stack wait until the function record grows past six slots.

## Callee-saved registers

`x19` through `x28`, and `x29`, stay as the caller left them. This slice
does not write them. `x30` is the link register. A call saves the live
argument and temporary registers and `x30`, then restores them.

`v8` through `v15` are callee-saved in their low 64 bits under AAPCS64.
This slice refuses floats, so it does not write those registers. Saving
them is part of the float follow-up.

A trap inside an exported function ends the process with status 100 plus
the trap number, by the exit system call. It does not return to C.

## Linking

The compiler writes an ELF64 relocatable file, little-endian, machine
AArch64, with no program headers. `.text` is the code. A call of an
`extern` is a `BL` with relocation `R_AARCH64_CALL26` (283) and addend 0.
A call inside the unit is already a resolved `BL`.

On this machine the system C compiler is only the fixture and the linker:

```
seed/out/omc < unit.om > unit.o
cc -o prog main.c unit.o
```

The C file provides `main` and the bodies of the `extern` names. The Omega
object does not ask the C library for anything of its own. The object format
`object` / `OMOBJ001` is a different file, for Omega modules, and is
unchanged.

## Follow-ups

- Float arguments and results, and the low halves of `v8` through `v15`,
  follow the IR float work on `omc/ir-aggregates-floats`.
- Struct passing under AAPCS64 follows the IR aggregate work on that branch.
  A struct parameter is error 7 in this slice, so it is not passed as a
  bare pointer.
- `x6`, `x7`, and stack arguments, once the function record has room.
- The x86-64 C convention is not this slice. `docs/X86-LINUX.md` describes
  a private Omega convention on that machine.
