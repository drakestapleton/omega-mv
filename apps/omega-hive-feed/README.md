# Omega Hive Feed (`apps/omega-hive-feed`)

Pure seeded-OM-2 (`om2`) **Interplane Live Hive Feed & Historical Model-Usage SVG Graph Engine** designed for `https://interplane.io/hive/` (linked from `/how-it-works/` and `/mission/`).

- **Zero C / Python / Node / JavaScript** on the production path.
- **Zero-JS CSP:** `Content-Security-Policy: default-src 'none'; style-src 'self' 'unsafe-inline'; img-src 'self'`
- **Zero trackers & fail-closed privacy:** Only repositories explicitly marked `public` in the 5-column `catalog.tsv` allowlist may appear in the live pulse feed. Non-public repositories, `SKIP` log lines, and secret-shaped tokens (`sk-`, `ghp_`, `Bearer`, `token=`, `/Users/`, `/home/`) are dropped or refused fail-closed.
- **Live host telemetry (read-only):** Reads `/sys/class/thermal/thermal_zone5/temp` (`TGPU`) and `/sys/class/thermal/thermal_zone0/temp` (`TSOC`) when present, and falls back honestly to `thermal: host-only` when absent.

## Files

- `hive_feed.om`: Dual-mode pure-OM-2 static generator & loopback HTTP server.
- `sample_usage.tsv`: Sanitized 6-column sample dataset for self-contained verification.
- `gate_hive_feed.om`: Pure-OM-2 verification gate (positive render/HTTP tests + 5 privacy/security negative controls).

## Usage

### 1. Build with Seeded `omc` (DGX Spark Linux AArch64)

```sh
~/canon/omega-mv/seed/out/omc < apps/omega-hive-feed/hive_feed.om > /tmp/om_sw_hivefeed/hive_feed
chmod +x /tmp/om_sw_hivefeed/hive_feed
```

### 2. Static Site Build Mode (`--render`)

```sh
./hive_feed --render apps/omega-hive-feed/sample_usage.tsv /tmp/om_sw_hivefeed/site
# Optional 4-arg form including live public feed snapshot:
./hive_feed --render apps/omega-hive-feed/sample_usage.tsv /tmp/om_sw_hivefeed/site catalog.tsv sync.log
```

Writes `usage.svg`, `index.html`, and `status.txt` into `<out_dir>`.

### 3. Live Loopback HTTP Server Mode (`--serve`)

```sh
./hive_feed --serve 18495 apps/omega-hive-feed/sample_usage.tsv catalog.tsv sync.log
```

Binds strictly to `127.0.0.1:<port>` and serves:

- `GET /` and `GET /hive/` — HTML5 page embedding `usage.svg`, model/agent breakdowns, live thermal pulse, and public-only sync events.
- `GET /hive/usage.svg` — Standalone responsive pure-SVG stacked timeline & model-share graph (`#0a1224` background, 4-strand `#38bdf8` / `#a78bfa` / `#34d399` / `#fbbf24` palette).
- `GET /hive/status.txt` — Machine-readable plain-text status summary.
- `GET /health` — `ok\n` health probe.

Security controls enforced on every connection:
- Only `GET` and `HEAD` are accepted (`405 Method Not Allowed` otherwise).
- Path traversal (`..`, `%2e`, `%2f`, `\`, control chars) returns `400 Bad Request`.
- Requests larger than `8192` bytes return `413 Payload Too Large`.
- Unknown paths return `404 Not Found`.

## Sanitized Usage TSV Format

6 tab-separated columns (optional header row):

```text
date	agent	model_family	turns	sessions	tokens
2026-11-26	Antigravity	Gemini	142	8	9200000
```

- `date`: exact `YYYY-MM-DD`.
- `turns`, `sessions`, `tokens`: unsigned decimal integers.
- Malformed rows or secret-shaped strings in `usage.tsv` are refused fail-closed (`exit != 0`).
- All dynamic text emitted to HTML or SVG is XML-escaped and sanitized against `<script`, `on*=`, and `javascript:`.

## Gate Verification (DGX Spark)

```sh
~/canon/omega-mv/seed/out/omc < apps/omega-hive-feed/gate_hive_feed.om > /tmp/om_sw_hivefeed/gate_hive_feed
chmod +x /tmp/om_sw_hivefeed/gate_hive_feed
/tmp/om_sw_hivefeed/gate_hive_feed /tmp/om_sw_hivefeed/hive_feed apps/omega-hive-feed/sample_usage.tsv /tmp/om_sw_hivefeed/work
```
