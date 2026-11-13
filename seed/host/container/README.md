# Container words (keyword ids 207..214 and 202..206)

The words a daemonless container runtime needs and Omega lacked: namespaces, mounts, the root switch,
the hostname, parent-death and no-new-privileges control, and synchronous signal handling (for a pid 1
that reaps and forwards signals). Every word returns `long`: the kernel result or minus errno.
Program mode only, AArch64 Linux only for now (x86linux and x86efi refuse with error 25).

| word | id | Linux (AArch64) | operands |
|---|---|---|---|
| `unshare flags` | 207 | unshare 97 | int `CLONE_NEW*` bits |
| `mount A off n flags` | 208 | mount 40 | packed list of 3 or 4 nonempty records: source, target, fstype[, data]; int `MS_*` flags |
| `umount A off n flags` | 209 | umount2 39 | checked path; int flags (2 = `MNT_DETACH`) |
| `pivroot A off n` | 210 | pivot_root 41 | packed list of 2 records: new root, put old |
| `sethost A off n` | 211 | sethostname 161 | byte slice (the kernel refuses more than 64 bytes) |
| `prctl op arg` | 212 | prctl 167 | int op in {1 PDEATHSIG, 23 CAPBSET_READ, 24 CAPBSET_DROP, 36 CHILD_SUBREAPER, 38 NO_NEW_PRIVS, 39 GET_NO_NEW_PRIVS}; any other op is -22 with no kernel call |
| `sigmask how A off n` | 213 | rt_sigprocmask 135 | int how; set `A[off..off+n)`, n = 8 |
| `sigwait A off n` | 214 | rt_sigtimedwait 137 | set `A[off..off+n)`, n = 8; returns the signal number |
| `capget A off n` | 202 | capget 90 | 32-byte layout: header {u32 version 0x20080522, i32 pid} at A[off], data (two {effective, permitted, inheritable} u32 triples) at A[off+8]; n other than 32 is -22 with no call; writes A |
| `capset A off n` | 203 | capset 91 | same layout; A must be writable (a view or text is error 20): the kernel writes its preferred version into an unknown one before -22 |
| `opentree A off n flags` | 204 | open_tree 428 | checked path (AT_FDCWD); int flags (1 OPEN_TREE_CLONE, 0x80000 CLOEXEC, 0x8000 AT_RECURSIVE); returns a descriptor of a (detached) mount tree |
| `mntattr fd A off n` | 205 | mount_setattr 442 | (fd, "", AT_EMPTY_PATH, &A[off], n): struct mount_attr in A, applied to the tree fd names |
| `mntmove from to` | 206 | move_mount 429 | (from, "", to, "", F_EMPTY_PATH or T_EMPTY_PATH): attach the tree named by descriptor onto the place named by descriptor, no path resolved |

Packed lists use u16 count and u16-length records, as `link`/`symlnk` do, but these NEW
caller-owned mount/pivroot operations use input-sized private decode memory. Complete count, record
range, nonempty, NUL, exact-consumption and slice validation happens before any decode mapping or
requested host operation. Malformed framing traps3 (exit103) without a mapping. A valid large decode
may fail allocation (-12) before the requested syscall; mapped decode storage is unmapped after return.
No execpure mapping exception exists here: the six existing packed-list words retain main's existing
non-pool inputs, fixed-stack lowering, protective bounds, refusals and strict profile unchanged. The approved
pool extension additionally admits pool byte operands with the same packet bounds. A caller must retain every bound
on outsider-supplied data; these new words do not turn hostile packets into trusted inputs.
Legal long paths reach the kernel, whose own path rules still apply. Trusted argv/environment and
descriptor handoff tests now belong to `../execfds/`; `../fstatfs/` provides descriptor-based filesystem
statistics. Neither addition changes existing non-pool word bytes.

## Gate

`sh seed/host/container/check.sh [OMC]` (also run by `seed/host/check.sh`):

1. `container.cases` through the OM-2 conductor: `container.om user` without privilege must print
   exactly `user.want`; bad record counts trap 3; refusals (function mode 9, contract 30, x86linux 25,
   x86efi 25, long flags 7, ulong array 7); the two record-count mutants and framing-preflight-removal mutant are detected; a control run.
   capview/capw and the capset-view mutant: capset needs a writable header. offsets.om: the words at a nonzero offset
   through view and edit parameters with run-time lengths (capget, opentree, sigmask/sigwait, mount).
   Then `refusals.cases`, generated with its units by `mkrefusals.py` (check.sh regenerates and compares them): for
   every word target x86linux 25, target a64efi 25, function mode 9, a ulong array 7 where the word takes bytes,
   and a view or text 20 for capget and capset.
   Then the size alarm, and the oracle's fail-closed recorder: with `OBOX_ORACLE_FAIL=unshare` or `=private` it
   makes no system call and must stop at the failed step (exit 2, recorded call list checked).
2. `oracle.py user` (ORACLE: Python ctypes, the same syscalls; a test instrument, never on a product
   path) must still print `user.want`.
3. Root mode under `sudo -n`: `container.om root DIR` and `oracle.py root DIR` each unshare a mount and
   UTS namespace first, then exercise every word (tmpfs and bind mounts, `pivot_root` and a detached
   old root, hostname, parent-death signal seen as SIGKILL of a grandchild, no_new_privs and SigBlk in
   `/proc/self/status`, `sigwait` returning SIGUSR1). Outputs must match byte for byte; the host
   hostname and the scratch directories must be unchanged.
4. The mutants of `seed/omc/omc.om` listed in `check.sh`, each made by `subst.py` (exactly one site or exit 2, an explicit check that holds under PYTHONOPTIMIZE; check.sh first runs its 0-, 1- and 2-site controls) (each word's syscall number, the mount flags register,
   the prctl allowlist and its new ops, the capget size check, the move_mount flags): the root-mode fixture built by each mutant compiler must fail at its named check.

Without passwordless sudo, steps 3 and 4 print NOT_RUN and the script exits 3.
