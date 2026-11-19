# aienux: the OS layer of Sovereign Intelligence (SI)

Mirrors [gpu/README.md](../gpu/README.md) for Aienux, the operating system layer of Sovereign Intelligence (SI). Everything under `aienux/` is seeded Omega (`.om`) built by this repository's own compiler, `seed/out/omc`, plus the provenance tables describing what moved and what has not yet been rewritten in Omega.

The OS layer is moving here from Aienux (`https://interplane.io/drakestapleton/aienux`, `rad:z2Q6ob2gL6Qo5oUMpyehukayVF7mN`) one piece at a time. **Only pure Omega moves in**: C, assembly, Rust, Python, shell and other files are rewritten in Omega first, or stay in Aienux and are listed in `aienux/NOT-YET-OMEGA.tsv`.

## Layout

| Path | Contents |
| --- | --- |
| `aienux/net/tcp/` | Native TCP/IPv4/ARP/Ethernet stack (`tcp.om`, `tcpd.om`, `link.om`, `peer.om`, `corpus.om`). |
| `aienux/net/rtl8127/` | Native RTL8127 Ethernet driver (`rtl8127-omega`, `f53059a181a2`). |
| `aienux/supervisor/` | Native OS service supervisor replacing systemd (`spark-supervisor`, `60c0c046b629`). |
| `aienux/connector/` | Sovereign verification connector and runner (`spark-connector`, `f9b6d0b500d7`). |
| `aienux/disk/` | Native NVMe protocol engine, transport, CLI and test drivers (`omega_nvme*.om`). |
| `aienux/allen/` | Pure-Omega bare-metal UEFI graphical UI (`surface.om`, `paint.om`, `font*.om`, `look-*.om`, `scene*.om`, `efi-main.om`), bare-metal TCP/TLS/HTTP (`net.om`, `http.om`, `tls*.om`), runtime/memory/session/courier/intent/application, and `.om` test suites. |
| `aienux/platform/` | Platform telemetry and readback units (`readback.om`, `unit.om`). |
| `aienux/kernel/x86/` | Native x86-64 `.om` kernel model and tool units (`llama.om`, `arithmetic.om`, `system.om`, `text.om`). |
| `aienux/lm1b/` | Seeded `.om` Llama-1B runner and SHA-256 (`lm1b.om`, `lm1b.in.om`, `sha256.om`). |
| `aienux/tools/` | Seeded `.om` GPT/FAT32 UEFI image writers (`spark-image.om`, `imac-image.om`) and hardware-gate checker (`hwgates.om`). |
| `aienux/atlas/` | Pure-Omega Stage-0 boot verifier and SHA-256 contract engine (converted from `atlas`, `10b8ddfd6cbf`, 3 `.om` files). |
| `aienux/pi-register/` | Pure-Omega service registry parser, conflict detector and renderer (converted from `pi-register`, `4a7954c27b2a`, 3 `.om` files). |
| `aienux/debugger/` | Pure-Omega continuous watchdog, metric triage and JSON-RPC dispatcher (converted from `spark-debugger`, `f35b24e0e8e8`, 3 `.om` files). |
| `aienux/capability/` | Pure-Omega AIENOS 64-bit generation capability authority (converted from `aienux` `native/capability/aienos_capability.{h,c}` and `crates/aienos-capability`, 2 `.om` files). |
| `aienux/argus/` | Pure-Omega ARGUS v1.2 event ABI, class-gated admission ring, shadow-state hard-invariant detectors, and containment state machine I1..I5 (converted from `aienux` `native/argus/`, 4 `.om` files). |
| `aienux/units.tsv` | Unit table listing every composable pure-Omega unit and its ordered parts (75 units). |
| `aienux/units-gate.om` | Seeded-Omega compile-reproducibility gate (`OMEGA-AIENUX-UNITS`). |
| `aienux/NOT-YET-OMEGA.tsv` | Generated inventory of every non-Omega first-party file still in Aienux awaiting rewrite or retirement. |
| `aienux/import/` | How each slice came here: `git filter-repo` command, `paths.txt`, `commit-map` and `ref-map`. |

Moved files keep their Aienux Git history: `git log --follow aienux/net/tcp/tcp.om` shows its Aienux commits. Existing receipts stay in Aienux where they were written.

## One compiler

Every unit here is built by `seed/out/omc`, and `aienux/units-gate.om` refuses any other compiler before it builds anything. The digest is read from `seed/out/omc.sha256`. No moved unit carries a separate compiler pin.

## Gate

Build and run `aienux/units-gate.om` from the repository root (OM-2 program mode, mirroring `gpu/units-gate.om`):

```sh
{ printf 'om2\n'; cat seed/ng/sha256.om aienux/units-gate.om; } | seed/out/omc > aienux-units-gate
chmod +x aienux-units-gate
./aienux-units-gate seed/out/omc /tmp/aienux-units-scratch
```

Wiring `aienux-units` into `tests/gates/` is a separate operator-gated change (`AGENTS.md`). Host compilation checks prove deterministic compilation with `seed/out/omc`; they are never hardware, QEMU, or kernel qualification.
