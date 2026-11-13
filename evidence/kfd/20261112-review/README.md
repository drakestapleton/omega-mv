# KFD review repairs

This directory supersedes no historical receipt. It records the changes requested
by the independent `grok-4.7` review of the preceding KFD head.
Commands and their actual exits live in the adjacent logs; an incomplete or
nonzero log is not a passing receipt. The compiler hash files are generated.

## Changes and controls

- RUNTIME_ENABLE is no longer admitted. The launcher needs no debugger runtime:
  Linux v6.18 `drivers/gpu/drm/amd/amdkfd/kfd_device_queue_manager.c`,
  `register_process` (1404–1441), calls `update_qpd`; its v9 implementation in
  `kfd_device_queue_manager_v9.c` initializes process SH_MEM_CONFIG (including
  F8_MODE for GC 9.4.3/9.4.4) and SH_MEM_BASES itself. This is a named upstream
  source, not a claim about an unobserved notebook kernel.
- The C header oracle enumerates every AMDKFD_IOC macro in the installed UAPI.
  Every sibling outside the explicit admitted list must compile with error 9 on
  both targets. A compiler mutant admitting DBG_TRAP demonstrates that the
  sibling control detects an expanded allowlist.
- kfdmap checks the descriptor's character-device class and number. It accepts
  a DRM render device or the same device number as `/dev/kfd`, never a regular
  file or another character device. Existing mapnew remains the ordinary-file
  test route. Native and QEMU refusal cases cover regular files, `/dev/null`
  and invalid descriptors. A compiler fd-class mutant must allow the otherwise
  refused regular file.
- Literal wrong header lengths are compile error 9. Computed wrong lengths
  remain trap 3 before the syscall. Separate compiler mutants remove the
  compile-time and runtime checks and must be detected.

`fdtrace.c` is an independent AArch64 ptrace instrument. It changes only stat
metadata at the syscall boundary; actual mmap backing is a memfd, never a GPU.
It exercises accepted DRM/KFD classes, wrong render minor, mismatched device
numbers, non-character KFD metadata, regular files and fstat failure. The
accepted cases touch the final word of a span above 64 GiB. These are synthetic
CPU trust-boundary checks, not device qualification. Every AMD device row is
NOT_RUN. The x86 refusal cases run through qemu-x86_64; successful real render
or KFD mappings on either architecture remain NOT_RUN.

The new stack pathname immediate is calculated, not typed from memory:
`Python: int.from_bytes(b'/dev/kfd', 'little') -> 7234587703011271727` (bytes).
The device-number masks and Linux stat layouts retain the preceding C/Wolfram
oracle provenance; the native trace writes `struct stat` from the installed C
headers rather than a duplicate byte layout.

## Invocation

CPU prefix:

```
flock ~/handoffs/hive/queen/pool-4-5.lock nice -n 10 taskset -c 4,5
```

Qualification command (the conjunction stops at its first nonzero exit):

```
sh seed/omega-from-seed.sh &&
python3 tests/kfd/check.py --record-history &&
PHYSICS_DIR=/nonexistent PHYSICS_LOCK_CHECK=0 tests/gates/run.sh seed
```

Compatibility and repository evidence checks are recorded separately. Historical
evidence stays unchanged. No GPU, service, sudo, remote write, merge or deployment
is authorized by or performed for this repair.
