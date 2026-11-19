# Omega LLM Frozen-Core Specialists & Swappable Packs (`spec.om`)

Pure seeded Omega extensions in [native/spec.om](../native/spec.om) (with hooks in `model.om`, `adam.om`, and `cli.om`) that let `ollm` learn new specialist capabilities (such as tool calling) **without overwriting or degrading the base model**.

## Commands

### 1. Frozen-Core Specialist Training (`trainf`, `fcache`, `fcachem`, `trainfc`, `growpro`)
```sh
ollm growpro INPUT.ck OUTPUT.ck LAYERS TOTAL LRMICRO
ollm trainf CK TOKS UNTIL EVERY FREEZE_LAYERS [BATCH]
ollm fcache BASE.ck TOKS W OUT.hc
ollm fcachem BASE.ck TOKS MASK W OUT.hc
ollm trainfc CK CACHE.hc UNTIL EVERY FREEZE_LAYERS [BATCH]
```
- **`growpro` (LLaMA-Pro block-expansion growth)** clones the last base layer's trained `(g1, Wq, Wk, Wv, g2, W1)` into each added specialist layer while zeroing only `(Wo, W2)`. Step-0 output remains bit-identical to the base checkpoint (`GP OLD_L NEW_L P`), while starting at the base layer's operating weight scale (`~44×` sharper initial `Q*K` logits than random `oinit` on `omega-v2.ck`).
- Freezes embeddings (`W_e`, `W_p`) and layers `0 .. FREEZE_LAYERS - 1` **bit-identically**:
  - `ofzlay` in `model.om` skips `olayb` for layers `< FREEZE_LAYERS` and skips `obwde` (cutting backward compute proportionally to frozen depth while preserving identical gradients for unfrozen layers).
  - `ofreeze` in `adam.om` zeroes frozen gradients before global-norm clipping and skips Adam updates for `i < ofreeze`.
- **`fcache` / `fcachem` / `trainfc` (format `OLLMFH01`)** precomputes the frozen base's output hidden states `HF[0..T*D)` + targets `y[0..T)` once for `W` windows (binding `T, D, base_L, base_hash` with FNV-1a 64; mismatched base refused `rc=62`) and trains unfrozen specialist layers (`flay .. L-1`) directly from the cache, skipping layers `0..flay-1` in both forward and backward (**bit-identical** to `trainf`, verified on `L2→3` and `L2→4` via `cmp`). `fcachem` applies a 1-byte-per-token completion-only mask (`y | 65536` when masked), skipping `oheadr` and `ohbwd` on prompt/padding tokens.
- Optional `[BATCH]` (`1..64`) overrides batch size during host CPU training and restores the checkpoint's original `B` and `G` before saving.
- Prints `F STEP FREEZE_LAYERS LOSS_MICRONATS` (`trainf`) or `FC STEP FREEZE_LAYERS LOSS_MICRONATS` (`trainfc`) at each save point.

### 2. Swappable Specialist Layer Packs (`spext`, `spapp`, `spsamp`, `speval`, format `OLLMSP01`)
```sh
ollm spext BASE.ck SPEC.ck PACK.sp
ollm spapp BASE.ck PACK.sp OUT.ck
ollm spsamp BASE.ck PACK.sp N TEMPMILLI PROMPT SEED [MERGES]
ollm speval BASE.ck PACK.sp HELD W [MERGES]
```
- **`spext`** hashes `BASE.ck`'s shapes (`V,T,D,H,F,base_L`) and all frozen base weights `ow[0 .. lay0 + base_L * lstr)` with FNV-1a 64, verifies `SPEC.ck` has `L > base_L` and a **bit-identical** frozen base, and writes only the added specialist layers + final norm gain `gf` into `PACK.sp` (for 1 specialist layer on v2 `D=384, F=1536`, ~14.1 MB vs 403 MB full checkpoint).
- **`spapp`** verifies `PACK.sp` magic, exact size, base FNV-1a 64 hash, and payload FNV-1a 64 hash, attaches the specialist weights onto `BASE.ck`, and saves `OUT.ck`.
- **`spsamp`** / **`speval`** verify and attach `PACK.sp` onto `BASE.ck` directly in memory and run sampling or held-out evaluation with zero temporary checkpoint write.

#### `OLLMSP01` Binary Layout (little-endian)
| Offset | Size | Field |
|---|---|---|
| `0` | 8 | Magic `"OLLMSP01"` (`3544421225449933903`) |
| `8` | 8 | `base_L` (frozen base layer count) |
| `16` | 8 | `spec_L` (total layer count, `> base_L`) |
| `24` | 8 | `base_hash` (FNV-1a 64 over `V,T,D,H,F,base_L` + `ow[0 .. fz)`) |
| `32` | 8 | `n_spec_params` (`P_spec - fz`) |
| `40` | 8 | `pack_hash` (FNV-1a 64 over payload bytes) |
| `48` | `8 * n_spec_params` | Raw f64 LE specialist weights `ow[fz .. P_spec)` |

#### Refusal Exit Codes
- `60`: malformed magic, truncated, or overlong `.sp` file
- `61`: `.sp` payload FNV-1a 64 mismatch (corrupted pack)
- `62`: base checkpoint mismatch (shape, layer count, or frozen base weights differ from `base_hash`)

### 3. Pure-Omega Specialist Fusion & Ensembling (`spmerge`, `spstack`, `spens`)
```sh
ollm spmerge BASE.ck MODE OUT.sp W1 P1.sp W2 P2.sp [W3 P3.sp [W4 P4.sp]]
ollm spstack BASE.ck P1.sp P2.sp S1_MILLI S2_MILLI OUT.sp
ollm spens BASE.ck P1.sp P2.sp W1_MILLI PROMPT N TEMPMILLI SEED [MERGES]
```
- **`spmerge`** verifies all input packs against `BASE.ck`'s `base_hash` (`rc=62` on mismatch) and merges 2–4 same-depth packs into a fresh `OLLMSP01` pack (`W_k` in milli-units):
  - `MODE=0`: Weighted Linear Soup (`(1000, 0)` reproduces `P1` bit-for-bit).
  - `MODE=1`: Task-Arithmetic Sum over exact `grow` init `W_0`.
  - `MODE=2`: TIES Trimmed Sign-Consensus (`0.5×RMS` delta trim + sign election + agreeing weighted mean).
- **`spstack`** vertically stacks `P1`'s layers followed by `P2`'s layers (`L_out <= 16`) with per-pack `(Wo, W2)` residual scaling (`S_MILLI / 1000.0`) and averaged final norm gain `gf`.
- **`spens`** runs frozen base layers `0..base_L-1` once per step and evaluates `P1` and `P2` in parallel over the shared `H_base`, fusing `w1 * log_softmax(z1) + (1 - w1) * log_softmax(z2)` (Product-of-Experts, works across different initialization basins such as `grow` ⊕ `growpro`).

### 4. Multi-Link Merkle Specialist Chains & DNA-Style Multi-Helix Clipping (`spchainapp`, `spchaineval`, `spchainsamp`, `spclip`)
```sh
ollm spchainapp BASE.ck OUT.ck K P1.sp ... PK.sp
ollm spchaineval BASE.ck HELD W MERGES K P1.sp ... PK.sp
ollm spchainsamp BASE.ck N TEMPMILLI PROMPT SEED MERGES K P1.sp ... PK.sp
ollm spclip BASE.ck MODE PROMPT N TEMPMILLI SEED MERGES S W1 K1 A1..AK1 W2 K2 B1..BK2 [W3 K3 C1..CK3 [W4 K4 D1..DK4]]
```
- **Multi-link Merkle chains (`spchainapp`, `spchaineval`, `spchainsamp`)** load `BASE.ck` and sequentially verify and attach `K` (`1..8`, total `L <= 16`) `OLLMSP01` packs in memory:
  - Link `i` verifies `P_i.base_L == cur_L`, `P_i.base_hash == FNV1a64(shapes, ow[0..cur_fz))`, exact `n_spec_params`, and `P_i.pack_hash` (`rc=60/61/62` on refusal), then updates `ow[cur_fz .. new_P)` and `cur_L = P_i.spec_L` so Link `i+1` cryptographically pins the exact chain `0..i` beneath it.
  - Pass `-` for `MERGES` when `V <= 256` (loaded via `obload` when `V > 256`).
  - `spchainapp` prints `SPCHAPP BASE_L FINAL_L K P` and saves `OUT.ck`; `spchaineval` prints `E step W loss_micro bpb_micro` matching `eval`; `spchainsamp` streams decoded tokens directly from memory.
- **DNA-style multi-helix chain clipping (`spclip`, `S = 2..4` strands, e.g. double, triple, or quad helix):**
  - Detects the longest common prefix of identical verified packs across all `S` strands (verifying every strand's pack headers and payload FNV-1a 64 hashes) and runs the shared trunk layers `0..trunk_L-1` **once per token** into cached `H_trunk`.
  - Evaluates each strand's remaining layers (`trunk_L .. L_s - 1`, supporting asymmetric strand depths up to `L <= 16`) over `H_trunk`, computes `log_softmax` and Shannon entropy `H_s = -sum P_s log P_s`, and fuses all `S` strands in log-probability space:
    - `MODE=0`: Normalized prior Product-of-Experts (`alpha_s = w_s / sum(w)`).
    - `MODE=1`: Entropy-gated multi-helix (`u_s = w_s / (H_s + 0.001)`, `alpha_s = u_s / sum(u)`, fused `sum_s alpha_s * log P_s`) so whichever specialized strand is more confident on the current token dominates.

### 5. Bank-B KV Cache (`okvkv` in `model.om`) & Inference-Time Experiments (`ttteval`, `tttsamp`, `dolaeval`)
- **`okvkv` (`model.om`)** restores/saves only the `oak`/`oau` K/V slices in `oab` for bank-B layers (`l >= LAA`) without clobbering `oahin`, enabling exact KV-cached decode for `L = 8..16` (verified 0 mismatched logits via `ollm kvcmp` on `L=8` and `L=10`).
- `ollm ttteval CK HELD W PREFIX STEPS LRMICRO LAYER_FROM` — strictly-causal test-time fast-weight adaptation on `[0..PREFIX)`, scored on `[PREFIX..T)`, restoring base weights after every window.
- `ollm tttsamp CK SEED N TEMPMILLI PROMPT MERGES STEPS LRMICRO LAYER_FROM` — ephemeral test-time adaptation on `PROMPT` before sampling, then restoring base weights.
- `ollm dolaeval CK HELD W EARLY_LAYER BETA_MILLI` — layer-contrastive decoding evaluation (`log P_final - beta * log P_early`).

## Measured Host Results (Apple Silicon M2, Darwin 25.6.0 arm64, f64 CPU)
- **Cross-target build:** compiles cleanly to Darwin ARM64 Mach-O (`mio.om`, 247,840 B), Linux AArch64 static ELF (`lio.om`, 405,436 B), and `gb10` (`lio.om` + `gpu/*`, 706,536 B) with 0 errors. Linux/x86/UEFI execution and GB10 GPU execution remain `NOT_RUN`.
- **Multi-link Merkle chains & multi-helix `spclip` (`V=256, T=16, D=32, H=2, F=64, L=2→3→4`):**
  - Built 2-link chains (`base L=2` → `P1.sp L=2→3` → `P2_{a,b,c}.sp L=3→4` pinned to `base + P1`).
  - `spchainapp` (`SPCHAPP 2 4 2 41760`) and in-memory `spchaineval` matched the trained 4-layer checkpoint `eval` **bit-identically** (`E 5 4 5492684 7924269`); greedy (`TEMPMILLI=0`) and stochastic (`TEMPMILLI=800`) `spchainsamp` matched `sample` bit-for-bit via `cmp`.
  - Negative controls caught with exact refusal codes: swapped link order `P2 P1` (`rc=62`), skipped `P1` (`rc=62`), 1-bit flip in `P2` payload (`rc=61`), 1-bit flip in shared trunk `P1` on strand 2 in `spclip` (`rc=61`), truncated pack (`rc=60`), and invalid `S`/`MODE` (`rc=2`).
  - `spclip` identity & multi-helix checks: double-helix `S=2 (A,A)`, triple-helix `S=3 (A,A,A)`, quad-helix `S=4 (A,A,A,A)`, and zero-weight isolation `(A@1000, B@0)` all matched single-strand `spchainsamp` **bit-identically** in both `MODE=0` and `MODE=1`. Distinct `S=2 (A,B)`, `S=3 (A,B,C)`, `S=4 (A,B,C,trunk)`, asymmetric-depth `(L=3, L=4)`, and direct-base fork (`common_links=0`) all executed cleanly (`rc=0`, finite 32-byte outputs).
- **Frozen-core preservation (2→3 layer host test):** `trainf` kept 100% of embeddings + layers `0..1` bit-identical while updating layer 2 (`F 5 2 5486997`, identical before and after the `ofzlay` backward-skip optimization). Negative control: standard `train` mutated layers `0..1`.
- **`spext`/`spapp` round-trip & negative controls:** rebuilt checkpoint matched trained `eval` bit-for-bit (`E 5 5 5445549 7856267` vs `E 0 5 5445549 7856267`). Negative controls caught: wrong base (`rc=62`), 1-bit flipped payload (`rc=61`), truncated pack (`rc=60`), non-frozen checkpoint passed to `spext` (`rc=62`).
- **v2 (`omega-v2.ck`, 15.8M → 17.6M, 8→9 layers) tool-call specialist run (25 steps, `FREEZE_LAYERS=8`, `B=2`, `lr=0.005`):**
  - Held-out tool-call loss fell from `7.740902` (`E 0 3 7740902 7100033`) to `5.323565` nats/token (`E 25 3 5323565 4882828`) during initial warmup steps (`F 5..25: 7.771 -> 7.509 -> 6.983 -> 6.213 -> 5.357`).
  - `spext` verified all 8 base layers + embeddings bit-identical to `omega-v2.ck` and extracted a `14 MB` (`1,770,624` params) `OLLMSP01` pack vs `403 MB` full checkpoint; `spapp` re-applied it onto untouched `omega-v2.ck` with bit-identical held-out eval (`E 60000 3 5323565 4882828`).
- **v2 (`omega-v2.ck`, 15.8M → 17.6M, 8→9 layers) longer `growpro` + `fcachem` + `trainfc` tool-call run (150 steps, `W=160`, `FREEZE_LAYERS=8`, `B=1`, `lr=0.0035`):**
  - Full receipt in aien-train `evidence/OMEGALLM/specialists/tool-call-growpro-l9-150-20261119/README.md` (upstream, not in omega-mv): step-0 `growpro` matched base held-out eval bit-identically (`7.183552 nats/tok`, `W=9`); masked train loss fell `5.512 → 0.439 nats/tok`, unmasked held-out NLL reached `4.528072 nats/tok` (`-36.97%`) at step 50 and `4.954553 nats/tok` at step 150; `spext` (`14.17 MB` vs `422.49 MB` checkpoint, `29.8×` smaller), `speval`/`spapp` round-trip, independent `126.66 MB` frozen-base byte check, and negative controls (`rc=60/61/62`) all passed.
- **TTT-Omega (`ttteval`, `W=5`, `PREFIX=128`):** `steps=0` control `Δ=0`; in-distribution TinyStories plain SGD slightly overfit prefix (`+7` to `+3945` µnats); on an out-of-distribution tool prompt, `tttsamp` adapted format without altering base weights.
- **DoLa (`dolaeval`, `W=5`):** `beta=0` control `Δ=0`; `beta=0.05..0.10` worsened calibrated NLL (`+2755` to `+12260` µnats) on the 8-layer model.
