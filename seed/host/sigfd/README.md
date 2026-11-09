# sigmask (keyword 241) and sigfd (keyword 242)

`sigmask how A off n` returns `long`: Linux `rt_sigprocmask(how, &A[off], NULL, 8)`
(AArch64 135, x86-64 14). `how` is `int`: 0 SIG_BLOCK, 1 SIG_UNBLOCK,
2 SIG_SETMASK; other values reach the kernel (-22). Returns 0 or the negative
errno.

`sigfd A off n` returns `long`: Linux `signalfd4(-1, &A[off], 8,
SFD_NONBLOCK|SFD_CLOEXEC)` (AArch64 74, x86-64 289). The result is the new
descriptor or the negative errno. A `read` of 128 bytes returns one
`signalfd_siginfo` whose first 4 bytes (little-endian) are the signal number;
with nothing pending it returns -11 (EAGAIN). Signals must be blocked with
`sigmask` to stay pending for the descriptor.

For both, A is a byte slice (readonly view or text allowed) checked like every
host slice (trap 3); then `n` must be 8, the kernel sigset size (trap 3). The
set is the 8 bytes at `A[off]`, bit `s-1` for signal `s` (SIGTERM 15: byte 1,
value 64). The mask is inherited across fork and kept across exec, so a child
that execs a measured command clears it first with `sigmask 1` (or `sigmask 2`
with an empty set). Program mode only: function mode is error 9, a contract
clause error 30, `target x86efi` error 25. AArch64 and x86linux.

## Gate

`sigfd.cases`, run by the OM-2 conductor from `seed/host/check.sh`.

- `fixture`: `sigfd.om` on AArch64, behavioral: TERM blocked (0); a sigfd at
  offset 8; an empty read -11; TERM to self is held and read back as signo 15,
  then -11; a forked child inherits the mask (survives its own TERM, reads 15);
  SIG_UNBLOCK delivers a held TERM (child dies by 15); a child that unblocks and
  then execx's keeping the sigfd finds it closed (SFD_CLOEXEC) and dies by its
  own TERM, while the negative control without the unblock survives it (the
  mask crosses exec); how 3 gives -22; n 16, n 7 and an out-of-range slice trap 3.
- `sigblk`: `sigblk.om` on AArch64 (and `x86-sigblk` through qemu-x86_64) reads the hexadecimal `SigBlk` of
  `/proc/self/status`: 0, 0x4000 (bit 14, TERM) after SIG_BLOCK TERM, 0x4000 in
  a forked child, 0 in the new image after SIG_UNBLOCK then execx, 0x4000
  without the unblock (negative control), 0 after SIG_UNBLOCK, SIG_SETMASK to
  TERM and back to empty.
- `x86-fixture`, `x86-sigblk`: `x86-target.om+sigfd.om` and `x86-target.om+sigblk.om`
  through binfmt qemu-x86_64: emulator evidence, not hardware qualification.
- refusals: `fnmode.om` and `fnmode-mask.om` (9), `x86-target.om+fnmode.om` (9),
  `contract.om` and `contract-mask.om` (30), `longhow.om` (7),
  `efi-target.om+use.om` (25).
- mutants:

| mutant | change | fixture exit |
|---|---|---|
| a64-size | rt_sigprocmask sigsetsize 16 | 1 |
| a64-ncheck | no trap for n other than 8 | 10 |
| a64-cloexec | signalfd4 without SFD_CLOEXEC | 7 |
| x86-size | rt_sigprocmask sigsetsize 16 | 1 |
| x86-ncheck | no trap for n other than 8 | 10 |
| x86-cloexec | signalfd4 without SFD_CLOEXEC | 7 |
