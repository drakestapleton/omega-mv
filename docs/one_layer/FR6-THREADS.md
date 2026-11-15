# FR-6 threads, first slice

This is the thread model for Omega on AArch64 Linux. The first slice is `thread`, `spawn`, `join` and `aadd`. It is lowered to Linux system calls. It does not use pthreads or any C library. The seed has no C library and no general "do this system call" word, and a pthread is more than a clone: it brings thread-local storage, cancellation and fork handlers the compiler does not have. The compiler emits the clone itself.

## What a thread is

A thread function is written:

```
thread fn worker to int
ret 1
end
```

It has no parameters and it returns an int. `spawn worker` starts it and returns a handle (a long). `join` of that handle waits until the thread has published its result, returns that int as a long, and frees the thread's stack. Handles are not numbers you invent. They are the address `spawn` returned.

`spawn` and `join` are program-mode words on AArch64 Linux only. Function mode, IR mode, and any other target refuse them.

## Owned and shared

A thread function owns its locals and its stack. Those are not shared.

A global is shared only when every access to it is `aadd`. `aadd cell N` adds N to element 0 of a ulong global and returns the old value. The add is one indivisible step. Two threads may `aadd` the same cell. The result is the sum of the adds, and each `aadd` observes the value the previous one left.

A plain `get` or `put` of a global, or of a run-time pool, is not shared. A thread function that does one is refused. So is any function it calls, unless that function is itself a `thread fn`. A global that is used both with `aadd` and with a plain access is refused too, from any function, whatever order the two uses are written in.

The same refusal covers every other word that stores into a named global or a run-time pool. The write set is `read`, `getdnts`, `waitpid`, `fstat`, `recv`, `argread`, `pipefds`, `sockname`, `cwd`, `readlnk`, `random`, `envread`, `stat`, `lstat`, `pread`, `devctl`, `mapread`, `devcall`, `uvmctl`, `efi`, `peercred`, `pollfds`, `peername`, `vfioctl`, `vfioirq`, `prlimit`, `cpuget`, `kfdctl` and `enlarge`. Two threads that store the same global by any of these are refused with error 9. A word that only reads the buffer (`write`, `send`, `pwrite`, `mapwrite`, `cpuset`) is not in that set.

This is conservative. A thread that only reads a global nobody writes is still refused. That program has no race, and this slice does not try to prove that. It refuses the access.

Two things this slice does not call a data race, and does not refuse:

- Two threads doing host words that happen to touch the same file or the same device, without storing a shared global. That is a host-effect question, not this memory model.
- A signal that kills a thread without entering the trap stub. `join` then waits. A bounds check or a divide by zero does enter the stub, and that path publishes.

A thread function whose own frame does not fit is refused at compile time. The mapping is 65536 bytes and the stack floor is at 4096, so 61440 bytes are usable. The frame is the stack arrays plus the scratch a host word uses inside that function. `new uchar 70000` is past that and is error 9. `new uchar 60000` fits, publishes, and joins.

## Memory order (OTM-1)

OTM-1 is acquire and release on one cell. It is not a single total order across every cell.

- `spawn` is a release by the parent and an acquire by the child. The child sees the parent's writes from before the `spawn`. The kernel's clone is that edge. The first slice still refuses a plain read of a global from the child, so this edge is stronger than the programs that compile.
- The child publishes in order: a release store of its result, then a release store of a done flag, then a wake, then `exit` of that thread only.
- `join` acquire-loads the done flag. A load that sees the flag sees the result store too. It then acquire-loads the result.
- `aadd` is one 64-bit acquire-and-release atomic add (`LDADDAL`). On one cell the adds are ordered. Two different cells are not a total order.

The done flag is the edge, not the kernel's tid word. The kernel writes that word with an ordinary store. An acquire load of it does not pair with the child's release of the result. A join that treated "tid is zero" as "the result is visible" was measured to drop the result. The same join, waiting on the done flag, held the result.

The parent's final exit is `exit_group`, and only in a program that used `spawn`. `exit` of one thread is the wrong process status: with this kind of clone, the last thread to finish supplies the status, so the child's `exit 0` can win over the parent's result. That was measured too. Programs that never spawn still end with `exit`, as they did before. Trap stubs and the `exit` word stay `exit`.

## What the compiler emits

One mapping per thread, 65536 bytes, private and anonymous. The handle is its address.

| offset | what |
| --- | --- |
| 0 | the result, 8 bytes, release-stored by the child and acquire-loaded by `join` |
| 8 | the tid word the kernel clears when the thread exits |
| 12 | the done flag, 4 bytes |
| 4096 | the stack floor |
| 65536 | the stack top, where the thread starts |

The stack grows down. If it reaches the floor, the existing stack check traps. That is the machine refusing, not a silent cut.

`spawn` is `mmap` (222), then `clone` (220) with flags `CLONE_VM | CLONE_FS | CLONE_FILES | CLONE_SIGHAND | CLONE_THREAD | CLONE_SYSVSEM | CLONE_CHILD_CLEARTID | CLONE_CHILD_SETTID` and no exit signal. The child sets its stack floor, writes the mapping address into `TPIDR_EL0`, calls the thread function, release-stores the result and the done flag, wakes one waiter (`futex` 98, `FUTEX_WAKE`), and `exit` (93). The parent returns the mapping address. `TPIDR_EL0` is per thread and this compiler does not otherwise use it. X18 through X26 stay available for pinned globals.

A trap in the child reads `TPIDR_EL0`. The main thread leaves that register zero, so its trap is still `exit` of 100 plus the trap code. A thread stores that same failure at offset 0, release-stores the done flag, wakes `join`, and exits the thread. `join` returns the failure. Bounds is trap 3, so the result is 103. Divide by zero is trap 2, so the result is 102.

`join` acquire-loads the done flag. If it is clear, it waits (`futex` 98, `FUTEX_WAIT`) and tries again. A wait that returns early is tried again. When the flag is set, `join` acquire-loads the result, `munmap` (215) the mapping, and returns the result.

A program that spawned ends with `exit_group` (94).

The instructions are the AArch64 ones in ARM DDI 0487, issue M.d: `LDADDAL` is C6.2.180, `LDAR` is C6.2.192, `STLR` is C6.2.402. This machine has the large-system atomics those instructions need.

## The proof program

`seed/omc/tests/fr6/sum.om` starts two threads. One adds 20, the other adds 22. After both joins, adding 0 returns the old value. That value is 42, and the process exits 42. If either add were lost, the value would be 20 or 22. `seed/omc/tests/fr6/stress.om` is eight threads adding 1, ten thousand times each. The old value is 80000. `seed/omc/tests/fr6/race.om` is a thread that `put`s a global. The compiler refuses it with error 9 (a word in a place that does not allow it). `seed/omc/tests/fr6/write/` is the same refusal for every word in the write set. `seed/omc/tests/fr6/stackbig.om` is the 70000-byte frame. `seed/omc/tests/fr6/bounds.om` reads one past an 8-byte array and `join` returns 103. `seed/omc/tests/fr6/div0.om` divides by zero and `join` returns 102. Both finish inside a few seconds. A compiler that drops the done-flag store in the trap path leaves `join` waiting, and the gate's timeout catches it.
