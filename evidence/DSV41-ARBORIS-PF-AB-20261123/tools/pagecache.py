#!/usr/bin/env python3
"""Measuring instrument: evict or report page-cache residency of checkpoint shards.
usage: pagecache.py evict|report FILE...
prints: resident_pages total_pages (summed over FILE...)"""
import ctypes, mmap, os, sys

libc = ctypes.CDLL("libc.so.6", use_errno=True)
PAGE = os.sysconf("SC_PAGE_SIZE")
libc.mmap.restype = ctypes.c_void_p
libc.mmap.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_long]
libc.munmap.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
libc.mincore.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p]


def resident(path):
    size = os.path.getsize(path)
    if size == 0:
        return 0, 0
    fd = os.open(path, os.O_RDONLY)
    try:
        addr = libc.mmap(None, ctypes.c_size_t(size), mmap.PROT_READ, mmap.MAP_SHARED, fd, ctypes.c_long(0))
        if addr in (None, ctypes.c_void_p(-1).value):
            raise OSError(ctypes.get_errno(), "mmap")
        try:
            n = (size + PAGE - 1) // PAGE
            vec = (ctypes.c_ubyte * n)()
            if libc.mincore(ctypes.c_void_p(addr), ctypes.c_size_t(size), vec) != 0:
                raise OSError(ctypes.get_errno(), "mincore")
            return sum(v & 1 for v in vec), n
        finally:
            libc.munmap(ctypes.c_void_p(addr), ctypes.c_size_t(size))
    finally:
        os.close(fd)


def main():
    mode, files = sys.argv[1], sys.argv[2:]
    if mode == "evict":
        for f in files:
            fd = os.open(f, os.O_RDONLY)
            os.posix_fadvise(fd, 0, 0, os.POSIX_FADV_DONTNEED)
            os.close(fd)
    elif mode != "report":
        sys.exit(2)
    r_tot = n_tot = 0
    for f in files:
        r, n = resident(f)
        r_tot += r
        n_tot += n
    print(r_tot, n_tot)


main()
