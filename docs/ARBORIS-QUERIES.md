# Arboris sparse queries and experimental gated inference

For a locked StateGraph, allocate three uint32 words per node for the cold locality plan. Pass a permutation of logical node IDs in community or observed coactivation order, or an empty view for logical order. `arboris_plan_locality` groups by incident arc count and preserves the supplied order within each power-of-two band. `arboris_pack_locality` rewrites node records and both endpoints into a separate buffer. Pass the result to the ordinary ontology/CSR loader. Use plan[i] to place a logical seed and plan[N+j] to restore a result or expert mapping from physical row j. Keep these permutations with the immutable graph.

`ar_prepare_sparse_wave(meta, request, leaves, hops)` prepares a batched max-product query. With leaves below N, the dense prefix runs one thread per destination and the suffix runs one warp per destination. This form takes one hop. With leaves equal to N, one CTA evaluates each independent query for the specified positive horizon. Its two FP32 score banks require 8N bytes of shared memory, up to 12,288 vertices. CSR and weights are read from device-visible memory each hop. The GPU writes the final result to the inactive bank once. One sealed query advances the publication epoch once. On the CPU the final bank is the selector returned in the state header. Include layout, horizon, graph, binary identity and math contract in the supervisor's authenticated workload key. A missing measurement takes the CPU path.

Workers sharing a GB10 must see the same compute-lock inode at `/tmp/omega-arboris-compute-v1.lock`. Run them in a supervisor-owned mount namespace with that inode protected against replacement. A busy routed call returns 8. Reprepare before retrying. GPU ownership extends through settlement or channel teardown.

The exact gated entry points use FP16 parameters and the v1 sigmoid. For the experimental profile, calculate the ParamSlab extent with `arboris_q4_bytes`, set header word 10, and plan the arena as usual. Use `arboris_pack_q4_params` to write into a disjoint destination from canonical FP16 parameters before sealing. Each 32-weight block occupies 20 bytes including its scale. The slab also carries 256 bytes of cubic coefficients, alignment padding, the FP16 bias/gate/prediction rows and a format tag. Pass true to both `ar_gated_open_profile` and `ar_gated_profile_hop`. The silicon gate compares every experimental output with an independent CPU oracle and reports the difference from exact v1.

## DeepSeek expert prefetch

`om/gpu/dsv41/build.sh` produces `arboris-expert-hints`. Its input starts with ASCII ARH1 followed by little-endian uint32 node count and hint budget (0 through 384). Each node contributes a uint32 layer-zero expert ID and a uint32 containing its settled FP32 score in [0,1]. Use 0xffffffff for an unmapped node. The program combines duplicate IDs by maximum, drops zero scores and breaks ties by ascending expert ID. For an in-process OM caller use `arboris_expert_hints` on the logical score plane and then `arboris_send_hints` on the cache event stream.

The cache replay at `codex/dsv41-cache-layout@89e206d01` accepts these eight-byte speculative read records on its regular event input. Send hints while earlier work is in flight, then send authoritative demand events on the same ordered stream. For an offline replay with prepared score and demand files:

```sh
hints=$(mktemp) || exit 1
trap 'rm -f "$hints"' EXIT
build/dsv41/arboris-expert-hints < scores.arh > "$hints" || : > "$hints"
cat "$hints" demands.bin |
  build/dsv41-cache/replay layer0.pack > delivered.bin
```

A demand returns the expert and payload regardless of whether the prefetch completed. Measure readiness and payload hashes separately. The replay accepts original layer-zero expert slabs. Predictive quality needs held-out conversational routing traces.

## Shared Online Co-Activation Core (`om/arboris_online.om`)

`om/arboris_online.om` provides the model-independent, zero-global, zero-heap OM-2 core extracted from `om/gpu/inkling2/arboris/prefetch.om` for caller-backed buffers (`cfg view ulong 6 = [n_trans, n_exp, top_k, n_slots, loop_from, loop_to]`):

- **Looped-core isolated transition resolution (`ao_resolve_step`, `ao_resolve_trans`)**: resolves adjacent `L -> L + 1` onto transitions `0 .. n_trans - 2` and looped wraps `loop_from -> loop_to` onto isolated transition `n_trans - 1` (`AO_NONE` disables wrap transitions), ignoring repeated or skipped layers and guarding cross-token boundaries via `ao_reset_token`.
- **Space-Saving edge tables (`ao_halve_row_span`, `ao_bump_row`, `ao_bump_edge`, `ao_stage_cur`, `ao_observe`)**: caller-owned `uint` co-activation tables packed as `(count << 16) | target_eid` with automatic row halving at `AO_DECAY_AT` (60000).
- **Multi-stream cross-batch deduplication & sum-over-paths ranking (`ao_dedup_batch`, `ao_score_src`, `ao_score_batch`, `ao_mask_resident`, `ao_pick_op3`)**: deduplicates active expert IDs across multi-stream batches, tracks batch multiplicity and inverse `slot_map`, scores next-layer candidates by sum-over-paths, skips resident experts (`resident >= 0`, or passes an empty `resident` slice), and emits deterministic `OP3` prefetch hints (`[3, eid]`) with lowest-expert-ID tie breaking.

Consumers and gates:

- `om/gpu/inkling2/arboris/prefetch.om` delegates packing, Space-Saving row updates/halving, looped-core transition resolution, score zeroing/accumulation, residency masking, and `OP3` emission to `om/arboris_online.om` while preserving its global single-stream ABI.
- `tests/arboris/online-core.om` (executed by `tests/arboris/host.sh`) exercises single-stream + looped-core isolation, multi-stream batch deduplication and ranking, and negative controls.
