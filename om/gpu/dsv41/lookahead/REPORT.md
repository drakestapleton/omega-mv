# DeepSeek conversational lookahead

**Experiment status: NOT_RUN.** The native decoder trace, exclusive predictor timings and per-arm payload audits are required for a verdict.

| Policy | Track A | Track B | Track C |
|---|---|---|---|
| Demand-LRU | NOT_RUN | NOT_RUN | NOT_RUN |
| ST-MoE | NOT_RUN | NOT_RUN | NOT_RUN |
| Arboris prefill, exact FP16 | NOT_RUN | NOT_RUN | NOT_RUN |
| Arboris decode, exact FP16 | NOT_RUN | NOT_RUN | NOT_RUN |
| Arboris decode, Q4 and cubic gate | NOT_RUN | NOT_RUN | NOT_RUN |

For a qualified comparison, PROMOTE requires at least 10% net stall reduction against ST-MoE on B or C, read amplification at most 1.25, and at least 98% protected hits on B's first returning coding tokens. Also report the paired Track A rate, zero protected evictions during each detour, payload integrity and predictor cost against the decode budget. A completed comparison that fails the promotion rule yields DECOUPLE. Missing observations leave the empirical decision open.

## Baseline and trace inputs

The ST replay takes one pass over the ordered native gate stream per horizon. Run each arm from the same initial cache state. The six runs target 1, 2, 3 or 4 successive gates, or the same layer 1 or 2 generated tokens later. Each source layer owns its own correlation table. An observation increments the Cartesian product of the earlier source route and the just-observed target route. Each expert in the most recent observed destination-layer route receives one history vote. The scorer returns up to six positive-score hints. The projection reads a separate CSV copy of the native gate record. Gate weights stay in that CSV.

From an exact, clean checkout on AArch64 Linux with the seeded compiler:

```sh
dir=om/gpu/dsv41/lookahead
out=$(mktemp -d)
for unit in check st-stream; do
    (echo om2 && cat "$dir/replay.om" "$dir/$unit.om") | seed/out/omc > "$out/$unit" || exit 1
    chmod +x "$out/$unit"
done
"$out/check" && python3 "$dir/check-stream.py" "$out/st-stream"
```

Capture one CSV row per generated token and native routed layer. Use zero-based turn-local token and layer indices and consecutive turn IDs. Supply columns `turn_id,token_idx,layer_id,top_k_experts,gate_weights,gate_ready_ns,expert_need_ns`. Encode the six IDs and six corresponding weights as two space-delimited fields in the native router's order. Timestamp gate completion and the first expert consumer on a shared monotonic timeline. Timeline and workload provenance come from the capture executor.

```sh
python3 "$dir/trace-input.py" track-b.csv 2 > "$out/routes.bin" &&
    "$out/st-stream" < "$out/routes.bin" > "$out/hints.bin"
```

Each output record is six little-endian u32 expert IDs for the target gate. Unused entries are 0xffffffff. Drop hints past the end of the track. Preserve prompt/prefill boundaries in the original capture when scheduling decode hints across turns.

For calibration, use an immutable pack with an independently verified digest and an idle local NVMe. The pack ABI is pinned to cache adapter 89e206d01. Each CSV row records the complete direct-read service interval and extent. Queue the real slab sizes against the measured deadlines. The arrival helper serializes requests on a single FIFO and accounts for both outstanding reads and the issue timestamp.

```sh
python3 "$dir/calibrate.py" "$pack" "$verified_pack_sha256" > "$out/nvme.csv"
```

The host controls exercise LRU eviction, causal correlation learning, hint ordering and serialization of read service. They do not qualify a conversational prediction, a physical DMA path, or a payload audit.

## Conversation stimuli

`turns.csv` supplies ten shared coding prompts, three rotating one-turn detours and ten technical-writing prompts. For A, retain the generated conversation and verify that its observed token count meets the 10k to 20k target. For B, reuse A's coding prompt order. Insert one detour at the nearest coding-turn boundary to each 1,500-token milestone from A where another coding turn follows. Record the actual positions. Pair the first generated token of each returning coding turn with the same coding ordinal in A. For C, follow the ten coding turns with the ten writing turns. Keep domain and coding ordinal in evaluation metadata outside the predictor input. Record actual model responses, token IDs and native gate records independently for each conversation.

## Per-arm accounting

`audit.py JOURNAL_DIRECTORY` reduces gate, physical read, per-layer stall, per-token timing, hint, payload and eviction CSVs from one run. Use the same causal demand-only shadow cache for all arms' cold-miss denominator. A prefetched slab counts toward effective lead only if its matching ticket completed strictly before the consumer deadline and the requested slab was still resident. Record one wall-clock stall per layer across the six demands so overlapping waits are counted once. Account for the predictor's critical-path delay in the comparison.

The reducer emits rates as fractions. Adjusted hit rate is one minus all physical slab reads divided by routed expert requests. Loads per token includes speculative reads. CPU p50 and p95 use nearest rank over total predictor CPU nanoseconds per token. Log an explicit timing row for each token, including zero when the reactive arm did no predictor work. Inventory resident keys for each hint and supply source, before and after digests for each inventoried key. Capture Zone 2 evictions independently, including during prefill. CSV reduction presupposes that the trace collector witnessed these events.
