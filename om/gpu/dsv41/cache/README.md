# DeepSeek V4.1 Flash expert slab and read-ring prototype

This seeded OM-2 prototype reads exact routed-expert bytes from the first decoder layer of the original DeepSeek checkpoint. One scheduler owns two protected slots, two FIFO scratch slots and a two-entry I/O ring. A child process uses buffered Linux `pread` to populate a fixed shared mapping while the scheduler accepts lookahead requests. The consumer returns the actual expert payload on each demand. The prototype runs on AArch64 Linux without opening the GPU.

## Record ABI

[slabs.om](slabs.om) defines four 64-byte OM-2 layouts. Every field is little-endian. Table bounds and arithmetic use the local rank's counts. Byte offsets are relative to the local arena or the open pack file.

| Record | Fields in offset order | Ownership |
| --- | --- | --- |
| `slabtab` | 0 ABI u32, 4 protected count u32, 8 scratch count u32, 12 stride u32, 16 FIFO index u32, 20 active domain u32, 24 candidate domain u32, 28 consecutive-turn count u32, 32 last turn u64, 40 pack epoch u64, 48 arena span u64, 56 reserved u64 | Scheduler. Protected slots occupy the first interval. Scratch slots follow it. |
| `slab` | 0 state u32, 4 expert key u32, 8 generation u64, 16 lease count u32, 20 zone u32, 24 destination offset u64, 32 length u32, 36 reserved u32, 40 epoch u64, 48 submission ticket u64, 56 reserved u64 | Scheduler publishes EMPTY (0), LOADING (1), then READY (2) after an exact-length completion. |
| `nvqueue` | 0 ABI u32, 4 capacity u32, 8 entry bytes u32, 12 reserved u32, 16 submitted u64, 24 retired u64, 32–63 reserved | Single producer. Tickets begin at one. Outstanding count is submitted minus retired. Ticket `n` occupies entry `(n-1) % capacity`. Retire the contiguous completed prefix. |
| `nvreq` | 0 ticket u64, 8 generation u64, 16 key u32, 20 slot u32, 24 file offset u64, 32 arena offset u64, 40 requested bytes u32, 44 completed bytes u32, 48 status i32, 52 phase u32, 56 pack-file ID u32, 60 reserved u32 | Scheduler sends phase 1. The worker returns the identity, byte count and status. The owner validates the ticket, slot, generation and extents before marking phase 2. |

Zero-initialize the record storage before opening a session. Use ABI 1 and 64-byte descriptor strides. Use `layer * 384 + expert` as the logical key. The replay accepts layer 0. File ID 0 denotes its one verified immutable pack. Positive tickets and generations are never recycled within their owner lifetime. A leased slab stays in place through consumer completion. A failed or short read leaves the slab empty and terminates the replay. A fully occupied ring drops a speculative request. A demand waits and loads its exact key.

A scratch miss uses `protected_count + fifo` and advances the FIFO only after successful submission. A protected hit keeps its slot across a one-turn detour, even after the scratch FIFO wraps. Three consecutive votes for the same new domain authorize a pack change. A repeated turn ID contributes once, a gap breaks the streak, and an unknown or current-domain vote clears it. Committing drains outstanding I/O and checks protected leases before advancing the epoch. Old protected slots then become invisible to lookup. Filling the new pack is explicit and can stall. The replay starts in domain zero and accepts domain IDs from its caller.

## Source bytes and budgets

The pinned layer-0 header lists three 5,898,240-byte packed weight tensors and three 368,640-byte scale tensors per expert. The expert slab is **18,800,640 bytes (17.9296875 MiB)**, exactly 4,590 pages of 4 KiB. The original header places the three matrices together and the three scale arrays together at a separate offset. Within each group, expert IDs are in decimal-string order. The packer verifies the source file size and SHA-256 of its JSON header before using that ordering. The qualification program first verifies the SHA-256 of the entire source shard. [Pinned release](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash/tree/314113f8a7dadb388215396ba5fbee2c610a04d6)

The 4 KiB pack header starts with ASCII `DXP1`, version 1, expert count and slab stride as four u32s. An ordered array of u32 expert IDs follows at byte 16. The body begins at byte 4,096. Slab `i` contains W1, W2, W3 weights, then W1, W2, W3 scales, byte-for-byte in checkpoint order. A profiler can supply co-activated experts adjacently. The compact prototype has no learned classifier. The pack must be immutable and its complete checksum verified before reuse across a trust boundary.

| Deployment assumption, decimal GB | Protected slots | FIFO slots |
| --- | ---: | ---: |
| 1 Spark with 70 GB / 18 GB | 3,723 | 957 |
| Each of 2 Sparks with 82 GB / 13 GB | 4,361 | 691 |

These are payload capacities. Metadata and I/O buffers require additional space. Two rank-local protected arenas hold at most 8,722 distinct complete experts, about 56.8% of 15,360, when ranks own disjoint expert sets. Replicated experts reduce coverage. Zone 1, Zone 4, KV capacity and Engram row admission require their own measured budgets. CPU and GPU activity share the same physical memory bandwidth.

Keep neuron order for the strict-parity baseline. A later neuron-sliced pack has to permute W1/W3 rows with W2 columns and preserve scale-group membership, nibble order and the reduction order. All contributions must reach the original accumulation positions. Bit equality needs a matched arithmetic path and matched RNG state.

## Researcher replay

From the repository root on AArch64 Linux, with the original shard available locally:

```sh
sh seed/omega-from-seed.sh
sh om/gpu/dsv41/cache/build.sh build/dsv41-cache
python3 om/gpu/dsv41/cache/check.py /path/to/model-00003-of-00048.safetensors build/dsv41-cache
```

To build an ordered pack for a lane, pass distinct expert IDs as arguments. Publish the output only after the command exits successfully and its checksum has been recorded.

```sh
build/dsv41-cache/pack /path/to/model-00003-of-00048.safetensors 0 383 12 2 103 4 256 5 > layer0.pack
build/dsv41-cache/replay layer0.pack < events.bin > demands.bin
```

Events are eight bytes, `<u32 opcode, u32 value>`. Opcodes 1, 2 and 3 warm a protected slot, demand an exact expert, and offer a speculative scratch read. Opcode 4 records the next turn's domain vote. Opcode 5 commits the specified eligible domain. Each demand emits `<u32 key, u8 already_ready, u8 zone, u16 zero>` and the complete slab payload. The ready bit for a speculative load depends on when its completion arrives. Output bytes for a given expert are independent of arrival order. Domain classification, learned lookahead and QMD launch policy are outside this replay.

## Falsification gates

| Claim | Evidence required |
| --- | --- |
| Byte-identical inference | Run identical token IDs through a non-evicting and caching executor at the same checkpoint precision, arithmetic order, sampling settings and RNG seed. Compare every logit bit and sampled ID for 128 tokens. Compare a higher-precision reference separately with a stated tolerance. This prototype checks the packed and delivered weight bytes. |
| Detour immunity | Replay recorded route IDs and domain votes from the three-hour workload. Pair the first returning token with its no-detour counterfactual, and count protected hits, total requests and protected evictions separately. The supplied fixture covers one scratch wrap and the first return to two protected keys. |
| Sustained shift | Record the turn and epoch on commit. The fixture exercises the three-turn gate. Compare production tokens/s against the same run cold-booted in the new domain, including the pack-fill period and reporting steady state separately. |
| NVMe efficiency | Use the same route trace, usable byte capacity, initial state and storage-cache conditions for LRU and the proposed policy. Count device-level random 4 KiB reads, bytes per token, and token latency. Logical contiguous file extents can still fragment on the physical device. Buffered read calls cannot establish a threefold device IOPS reduction. |

The ring is a scheduler-to-I/O-worker ABI. Connecting it to an io_uring or native NVMe submission/completion backend requires registered buffers, block alignment, visibility fences, cancellation/drain semantics and measured overlap on the target. DoMoE describes prefill domain matching, and APEX describes confidence-based prefetch before attention. The two-to-four-layer horizon is an experiment parameter. [DoMoE](https://ijcai.org/proceedings/2026/657) · [APEX](https://arxiv.org/abs/2608.11688)
