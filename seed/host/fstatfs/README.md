# fstatfs (keyword 215)

`r = fstatfs fd A off n` runs the Linux `fstatfs` system call (number 44) on descriptor `fd`. The result is
written into the writable uchar slice `A[off..off+n)`.

## Layout

On AArch64 Linux the kernel's `struct statfs` is 120 bytes, defined in `asm-generic/statfs.h`, which
`asm/statfs.h` includes unchanged:

| Bytes | Fields |
|---|---|
| 0..56 | `f_type`, `f_bsize`, `f_blocks`, `f_bfree`, `f_bavail`, `f_files`, `f_ffree` (seven longs) |
| 56..64 | `f_fsid` (two ints) |
| 64..88 | `f_namelen`, `f_frsize`, `f_flags` |
| 88..120 | `f_spare` (four longs) |

`oracle.py layout` derives this layout from the headers. It also measures what the kernel actually writes.

## Operands

- `fd` is an `int`.
- `n` below 120 traps 3, before the kernel is asked.
- A slice that runs past the array traps 3.
- Only `A[off..off+120)` is written, even when `n` is larger.
- `A` may be a run-time pool.

## Result

`long` 0 on success, or `-errno`.

## Refusals

| Case | Error |
|---|---|
| a text or a view (A is written) | 20 |
| a non-uchar array, or a descriptor that is not `int` | 7 |
| x86linux, x86efi or a64efi target | 25 |
| function mode, including OM-2 function units (unlike `fstat`) | 9 |
| inside a contract clause | 30 |

The word is AArch64 Linux, program mode only.

## Gate files

These are TEST INSTRUMENTS and never a product path.

- **`fstatfs.om`**
  - The seeded fixture runs 12 checks. Its exit is the number of the first failed check.
  - `dump` mode writes the 120 bytes for its stdin.
- **`fstatfs.cases`**
  - Run by the OM-2 conductor: the fixture, the refusals and two `omc.om` mutants.
  - `min119` admits 119 bytes and is killed at check 6.
  - `sysno` uses statfs 43 and is killed at check 1.
- **`oracle.py`** (**ORACLE**: Python ctypes, never shipped)
  - Derives the layout from the headers and measures the written size with sentinel fills.
  - Compares the fixture's dump against a raw `fstatfs` on the same descriptor, before and after the fixture
    runs.
  - Cross-checks against `os.fstatvfs` and the filesystem magic (`linux/magic.h`, or coreutils `stat -f` for
    `/`).
- **`check.sh`** runs, in order:
  1. the cases;
  2. the layout check;
  3. a self-test of the comparator;
  4. parity runs for a pipe, a memfd, `/` and `/sys/fs/cgroup`;
  5. a private tmpfs run as root through `sudo -n` (`size=1m,nr_inodes=64`).

  It exits 0 on PASS, 1 on FAIL, and 3 on NOT_RUN (no passwordless sudo, so the tmpfs row could not run).

## Volatile counts

`/` and the cgroup2 hierarchy are shared with every other process on the host. Their `f_bfree`, `f_bavail` and
`f_ffree` can change between any two calls. `check.sh` therefore:

- compares only the other fields on those two filesystems;
- prints the three free counts before, during and after the fixture runs, as `VOLATILE` snapshot lines, and
  never claims them equal.

The pipe, the memfd and the private tmpfs have nothing writing to them, so they are compared byte for byte.
