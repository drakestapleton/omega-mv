# Current ABI and SHA qualification

`qualify.py` is an external testing instrument, outside the delivered Omega
closure. It orchestrates the existing seeded `omc`, the locked seeded bridge
`src/native.om`, the independent C callers in `../oracle/s5s7`, and the existing
`om/units.sh` identity checks. Python performs no production computation.

From a clean Omega checkout on Linux AArch64:

```sh
python3 seed/qualification/om2/current/qualify.py \
  --bridge /path/to/clean/locked/omega-bridge \
  --output /path/to/new/evidence-directory
```

The bridge checkout must be exactly the commit in `om/omega-bridge.lock`.
The compiler is this checkout's `seed/out/omc`. The command needs Python 3,
Git, `cc`, `nm`, and `sh`. Use the assigned CPU and low priority when running
on a shared host. The large SHA cases read more than 4 GiB each through a
read-only zero-page mapping; they do not allocate that much resident memory.

The output directory must not exist. It holds immutable input snapshots,
generated bindings, executables, every subprocess command and exit, stdout,
stderr, and their digests. `result.json` records the source and bridge heads,
compiler digest, individual cases and controls. A failed or interrupted run
keeps its evidence. A successful run hashes its complete artifact set.
Tracked source must be clean, and all snapshotted inputs plus source HEAD
are checked again before PASS.

Every `abi-*` and `sha-*` declared `notrun` case in
`../sec/s5s7/candidate.cases` must be exercised here. The inventory comparison
fails if a case is added, omitted, or duplicated. Each C driver's expected
case names are read from its explicit `check` calls and must appear once in
its output. The ABI symbol and stale-source/compiler/profile cases are
executed separately. The identity checker is copied into the evidence directory. Its staged
`seed/out/omc.sha256` is the digest of the snapshotted candidate compiler,
and `om/units.sh` derives `OMC_PIN` from that file. Bindings are freshly
generated there before the positive and negative identity checks. The
script digest and derived pin are recorded. Canonical pins, sources and
generated artifacts are unchanged. This is candidate checker qualification,
not a claim that the canonical generated bindings are current.

Wrong source identity, wrong compiler identity and a
wrong independent SHA digest must each fail for the expected reason.

Exit 0 means this ABI/SHA gate passed. Exit 1 means a check failed; exit 3
means required tools, the locked bridge, or a complete execution were
unavailable. A mismatched bridge is not silently substituted. Reusing an
output directory is refused.

This gate does not turn `gate.om`'s declared omissions into PASS. A release
must run this command as its own required check, then join its source-bound
result with the other qualification records. It is not the full RM7 gate:
all-language ABI-v2 trap propagation and the full `om-units` gate remain
separate obligations. It does not qualify leakage or physical x86. Leakage
requires all exported SHA entries, not only the first entry, to pass their
own scanner and independent decoder checks.
