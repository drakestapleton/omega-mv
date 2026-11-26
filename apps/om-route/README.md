# `om-route` — Sovereign Intelligence 1.0 Universal Pure-Omega Local Model Router

> Dual OpenAI (`/v1/chat/completions`) + Anthropic (`/v1/messages`) local router with declarative `models.tsv`, non-blocking multi-client `pollfds` proxying, idle GPU auto-unload, fail-closed live thermal/Watt admission, and local-only `TY-4+` telemetry — written in 100% pure seeded Omega (`.om`) with zero C, zero Python, zero libc, and zero hardcoded user paths.

## 60-Second Omega Rosetta Card

New to Omega (`.om`)? Every unit is plain ASCII, one statement per line, **prefix operators**, explicit bounded loops, zero hidden allocation, and rebuilt from a 408-byte loader (`seed0 -> hex1 -> asm2 -> om4 -> omc`):

| If you know C / Rust / Python | Pure Seeded Omega (`.om`) |
|---|---|
| `// comment` or `# comment` | `note comment` |
| `uint64_t x = a + b;` | `x = add a b` |
| `v = buf[i];` / `buf[i] = v;` | `v = get buf i` / `put buf i v` |
| `fn f(a: u64) -> u64 { return a * 2; }` | `fn f a ulong to ulong` / `ret mul a 2` / `end` |
| `while (cond) { ... }` | `while cond bound N` ... `end` (trap 4 if exceeded) |
| `if (x == 0) { ... } else { ... }` | `if eq x 0` ... `else` ... `end` |
| `poll(fds, nfds, 50)` | `pollfds g_pfd 0 mul nfds 8 50000000` |
| `char msg[] = "ok\n";` | `text msg "ok\n"` |

## Build & Run in 2 Commands

```sh
# 1. Compile pure seeded-OM-2 router (pinned seed/out/omc)
seed/out/omc < apps/om-route/om_route.om > om_route && chmod +x om_route

# 2. Run against a declarative models.tsv table
./om_route apps/om-route/models.tsv 18090
```

## Declarative Configuration (`models.tsv`)

Zero hardcoded user directories or baked-in model names. Each non-comment line holds 7 TAB-separated fields:

| Column | Contract (fail-closed at startup, exit 2) |
|---|---|
| `model_id` | 1–96 chars (`A-Za-z0-9._:-`), unique across table |
| `backend_url` | Loopback origin ONLY (`http://127.0.0.1:<port>` or `http://localhost:<port>`); non-loopback URLs refused |
| `kind` | `gpu` or `cpu` |
| `idle_unload_s` | Seconds of inactivity before `SIGTERM` auto-unload of a spawned backend (`0` = never unload) |
| `max_watts` | Package power admission ceiling in Watts (`1..1000`) |
| `max_tgpu_mc` | Live TGPU admission ceiling in millidegrees C (`1000..120000`, e.g. `85000` = `85.0 °C`) |
| `launch_cmd` | `-` (externally managed backend) or safe argv command (no shell metacharacters or `..`) |

## Supported Endpoints

- **`GET /health`**: Live JSON health status including real Spark `tgpu_mc` (`/sys/class/thermal/thermal_zone5/temp`), `tsoc_mc` (`/sys/class/thermal/thermal_zone0/temp`), active poll slots, request counters, and thermal rejection count.
- **`GET /v1/models`**: Dynamic OpenAI-compatible model catalog emitted directly from `models.tsv`.
- **`POST /v1/chat/completions`** (OpenAI): Supports both string `"content"` and Open WebUI array-of-parts `"content": [{"type":"text","text":"..."}]` (automatically normalized), plus non-blocking live SSE `"stream": true`.
- **`POST /v1/messages`** (Anthropic): Translates Anthropic `system`, `messages` (string or content-block arrays), `max_tokens`, and `stream` into backend requests, and translates responses back into authentic Anthropic JSON (`"type":"message"`, `"stop_reason":"end_turn"`) or live Anthropic SSE (`message_start`, `content_block_start`, `content_block_delta`, `content_block_stop`, `message_delta`, `message_stop`).
- **Fail-closed safety**:
  - Exceeded live thermal or Watt budget (or unreadable `TGPU` sensor on a `gpu` model) -> HTTP `503 Service Unavailable` (`thermal_budget_exceeded` / `thermal_sensor_unavailable`).
  - Unknown model -> HTTP `404` (`model_not_found`).
  - Path traversal (`..`, `%2e`, `\`) or malformed HTTP -> HTTP `400`.
  - Disallowed HTTP verb -> HTTP `405`.

## Local-Only `TY-4+` Telemetry

Every completed or rejected request emits one structured line on local `stdout` (zero outbound network calls, zero external analytics):

```text
TY-4+ req_id=1 api=openai model=gpu-ok status=200 stream=0 lat_us=412 tgpu_mc=49500 tsoc_mc=56900 est_mw=24000 rx_b=148 tx_b=312
```

## Verification Gate (`gate_om_route.om`)

Compile and run the pure seeded-OM-2 verification gate on DGX Spark:

```sh
seed/out/omc < apps/om-route/gate_om_route.om > gate_om_route && chmod +x gate_om_route
./gate_om_route seed/out/omc . /tmp/om_sw_omroute
```

Expected summary: `OM_ROUTE_GATE PASS checks=10 controls=6 caught=6 hardware=HOST_THERMAL_LIVE` (exit `0`).
