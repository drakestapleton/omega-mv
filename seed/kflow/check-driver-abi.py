"""Check 121-tk by-value parameter widths with the seeded packer, on the host."""
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

with tempfile.TemporaryDirectory() as directory:
    cubin = Path(directory) / "probe.cubin"
    subprocess.run([sys.argv[1], "121-tk", "probe", "seed/sm121/vecadd.bin",
                    cubin, "16", "0", "1", "2", "4", "8", "p8"], check=True)
    data = cubin.read_bytes()
    header = struct.unpack_from("<Q", data, 40)[0]
    count = struct.unpack_from("<H", data, 60)[0]
    sections = [struct.unpack_from("<IIQQQQIIQQ", data, header + 64*i) for i in range(count)]
    def payload(section):
        return data[section[4]:section[4]+section[5]]
    names = payload(sections[1])
    info = payload(next(s for s in sections if names[s[0]:].split(b"\x00",1)[0] == b".nv.info.probe"))
    found = {}
    i = 0
    while i < len(info):
        fmt, attr, size = struct.unpack_from("<BBH", info, i)
        i += 4
        if fmt == 4:
            if attr == 0x17:
                _, ordinal, offset, flags = struct.unpack_from("<IHHI", info, i)
                found[ordinal] = (offset, flags)
            i += size
    expected = dict(enumerate([(0,0x5f000), (2,0x9f000), (4,0x11f000),
                               (8,0x21f000), (16,0x21f500)]))
    if found != expected:
        sys.exit(f"KPARAM_INFO mismatch: {found!r}")
    print("PASS 121-tk scalar and pointer parameter offsets and widths")
