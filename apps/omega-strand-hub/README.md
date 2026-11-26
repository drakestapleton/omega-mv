# Omega Helix Strand Exchange & Clip Studio (`om-strand-hub`)

Pure seeded-Omega (`om2`) zero-JS HTTP server implementing the **Interplane Open-Source Helix Strand Exchange** and **Strand Clip Editor (`spclip`)**. Compiles with `seed/out/omc` into a single static AArch64 Linux ELF (~186 KiB, zero libc, zero C, zero Python, zero CUDA, zero telemetry).

## Architecture & Security Boundaries

- **Zero JavaScript / Strict CSP:** Standard HTML `<form method="POST">` + dedicated external stylesheet (`/strands/hub.css`), zero `<script>` tags, zero inline styles — compatible with `interplane.io`'s `script-src 'none'; style-src 'self'` CSP.
- **Open-Source Default, Extensible Schema:** Upload UI defaults to `Apache-2.0` (`MIT`, `CC-BY-4.0`, `CC0-1.0`, `BSD-3-Clause`, `AGPL-3.0-only` selectable) while persisting extensible named metadata columns (`license`, `terms`, `provenance`, `parent_trunk`, `author`, `filename`, `description`, `downloads`, `uploaded_ns`) in versioned `omega.strand_hub.v1` / `omega.spclip_hub.v1` ledgers.
- **Bounded Upload Containment:** Requires explicit numeric `Content-Length`, refuses `Transfer-Encoding: chunked` request smuggling (`400`), enforces configurable upload ceiling (default `32 MiB`, overridable via `argv[3]`, immediate `413` before writing disk), handles `Expect: 100-continue` cleanly, and streams payloads in O(1) 64 KiB chunks.
- **Fail-Closed `OLLMSP01` Cryptographic Verification:** Before storing any blob or catalog entry, every upload is verified byte-for-byte against the exact `train/omega-llm/native/spec.om` `OLLMSP01` format:
  1. Strict filename validation (`[A-Za-z0-9._-]`, no `..`, `/`, `\`, leading `.`, or control bytes; storage paths are strictly content-addressed `<data_dir>/blobs/<sha256>.sp`).
  2. Exact 48-byte little-endian header: magic `"OLLMSP01"` (`3544421225449933903`), `1 <= base_L < spec_L <= 1024`, non-zero / non-empty-basis Merkle `base_hash`, overflow-safe `n_spec_params >= 1`, exact byte length `48 + 8 * n_spec_params`.
  3. Merkle parent lineage check: optional 16-hex `parent_trunk` must match binary `base_hash`; optional 64-hex `parent_trunk` matching an existing hub strand enforces `child.base_L == parent.spec_L`.
  4. Single-pass streaming payload verification: recomputes FNV-1a 64 over payload bytes `[48 .. pack_len)` and requires exact match with `pack_hash` (`ollm rc=61` equivalent), checks every IEEE-754 `f64` weight is finite (rejects `NaN`/`Inf`), computes full-file FIPS 180-4 SHA-256 (and verifies optional `expected_sha256` pin), and refuses duplicates (`409 Conflict`).
  5. Atomic persistence via `fdsync`/`fsync` + `renames` (never leaves partial files or stale staging files on refusal).
- **Strand Clip Editor (`/strands/clip`) & Deterministic `.spclip` Manifests (`OMSPCLIP01`):**
  - Lets users pick `2..4` compatible verified strands sharing the same `base_hash` trunk, edit signed/positive milli-weights (`w1..w4`), fusion mode (`MODE=0` Signed PoE / Anti-DNA vs `MODE=1` Entropy Gate), temperature `tau` (`0..5000`), branch order, `splice_layer`, and optional fine-tune metadata (`ft_seed`, `ft_steps`, `ft_lr_micro`).
  - Fail-closed rejects incompatible parent trunks, zero weights, negative weights in `MODE=1`, all-negative weights in `MODE=0`, `<2` or `>4` strands, invalid modes/tau/splice layers, and any 1-byte tamper of `.spclip` `body_sha256`.
  - Emits deterministic, SHA-256-verified `.spclip` manifests (`<data_dir>/clips/<clip_sha256>.spclip`), copy-ready `ollm spclip` + frozen-core fine-tune CLI commands, and 1-click links to publish fine-tuned child `OLLMSP01` strands linked back to their parent hashes.

## HTTP Routes & Agent API

| Method | Route | Purpose |
| --- | --- | --- |
| `GET`/`HEAD` | `/strands/` (or `/strands`) | Landing intro, 3-step visual flow, filterable catalog (`?trunk=<hex>&license=<lic>`), upload form |
| `GET`/`HEAD` | `/strands/hub.css` | Dedicated zero-JS stylesheet (`text/css`, `max-age=300`) |
| `GET`/`HEAD` | `/strands/health` | Liveness check (`200 ok\n`) |
| `GET`/`HEAD` | `/strands/strand/<sha256>` | Full cryptographic verification receipt, runnable `spapp`/`spchainsamp`/`spclip` commands |
| `GET`/`HEAD` | `/strands/pack/<sha256>.sp` | Verified `.sp` binary download (strict 64-hex guard, persisted download counter on `GET`) |
| `POST` | `/strands/upload` | Fail-closed upload (`multipart/form-data` browser/curl form OR raw `application/octet-stream` + `X-Strand-*` headers) |
| `GET`/`HEAD` | `/strands/index.tsv` | Deterministic agent catalog (`text/tab-separated-values`, supports `?trunk=` / `?license=`) |
| `GET`/`HEAD` | `/strands/index.json` | Deterministic RFC-8259 JSON catalog (`omega.strand_hub.v1`, supports `?trunk=` / `?license=`) |
| `GET`/`HEAD` | `/strands/clip` | Zero-JS Strand Clip Editor (`?trunk=`, `?s1=`, `?s2=`) |
| `POST` | `/strands/clip` | Compose & persist (`action=save`, `201`) or directly download (`action=download`, `200`) verified `.spclip` |
| `GET`/`HEAD` | `/strands/clip/<clip_sha256>.spclip` | Download stored deterministic `.spclip` manifest |
| `POST` | `/strands/clip/verify` | Standalone fail-closed `.spclip` manifest verifier (JSON receipt `200` / `400`) |
| `GET`/`HEAD` | `/strands/clips/index.tsv` | Deterministic `.spclip` catalog (TSV) |
| `GET`/`HEAD` | `/strands/clips/index.json` | Deterministic `.spclip` catalog (JSON, `omega.spclip_hub.v1`) |

## Build & Run (AArch64 Linux / DGX Spark)

```sh
seed/out/omc < apps/omega-strand-hub/main.om > om-strand-hub.tmp
chmod +x om-strand-hub.tmp && mv -f om-strand-hub.tmp om-strand-hub
./om-strand-hub /var/lib/omega-strand-hub 18491 33554432
```

Arguments (all optional):
1. `data_dir` (default `./strand-hub-data`)
2. `port` on `127.0.0.1` (default `18491`)
3. `max_upload_bytes` (default `33554432` = 32 MiB)

## Pure-Omega Verification Gate (`gate.om`)

Compiles and executes 44 live loopback end-to-end checks (positive uploads, trunk filtering, bit-exact downloads, restart persistence, XSS/JSON escaping, Clip Editor + Anti-DNA PoE + 3-strand compaction, real 14.17 MB GB10-trained `OLLMSP01` packs, plus adversarial negative controls for magic/truncation/trailing-byte/FNV-tamper/NaN-weight/Merkle-lineage/SHA256-mismatch/path-traversal/oversized/request-smuggling/incompatible-trunks/invalid-weights/tampered-`.spclip`):

```sh
seed/out/omc < apps/omega-strand-hub/main.om > /tmp/om-strand-hub
seed/out/omc < apps/omega-strand-hub/gate.om > /tmp/strand-hub-gate
chmod +x /tmp/om-strand-hub /tmp/strand-hub-gate
/tmp/strand-hub-gate /tmp/om-strand-hub /tmp/strand-hub-scratch 18499 \
  [optional_real_pack1.sp] [optional_real_pack2.sp]
```

Expected output: `STRAND_HUB_GATE pass=44 fail=0` (41 without optional real `.sp` pack arguments), exit `0`.

## Suggested Nginx Route Wiring (`/etc/nginx/sites-enabled/interplane.io`)

Place alongside the `/omega/compile/` proxy block (operator-applied; not auto-modified by this package):

```nginx
    # Helix Strand Exchange & Clip Studio (pure seeded-Omega om-strand-hub on 127.0.0.1:18491).
    location = /strands {
        return 301 /strands/;
    }
    location ^~ /strands/ {
        limit_except GET HEAD POST { deny all; }
        limit_req zone=forge_post burst=10 nodelay;
        limit_req_status 429;
        client_max_body_size 34m;
        proxy_http_version 1.1;
        proxy_connect_timeout 5s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        proxy_redirect off;
        proxy_set_header Host $host;
        proxy_set_header Connection close;
        proxy_pass http://127.0.0.1:18491;
    }
```

Recommended loopback daemon launch on DGX Spark (atomic ELF replacement + `setsid -f`):

```sh
setsid -f /home/drakestapleton/.local/bin/om-strand-hub \
  /home/drakestapleton/.local/share/omega-strand-hub 18491 33554432 \
  >/tmp/om-strand-hub.log 2>&1 </dev/null
```
