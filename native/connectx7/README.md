# Two-Spark FP32 AllReduce

`tp2.om` is a seeded OM-2 data path for two ranks with two reliable-connected mlx5 queue pairs per rank. Both ranks split an activation on the same FP32 element boundary. The first rail gets the extra element when the length is odd. Each sends its half-stripes directly from the registered activation into the peer's registered inbox. Both CPUs sum rank 0 plus rank 1 in place. The only CPU copy of tensor data in the hot path is the local reduction's pair of 256-byte scratch tiles and the result writeback.

For each rail, Omega encodes a signalled, single-SGE RDMA_WRITE in one 64-byte WQEBB. It publishes the producer DB record, then writes the first eight descriptor bytes to the alternating private BlueFlame doorbell halves. The device fetches the descriptor from the SQ. Ordered `mapset` provides AArch64 barriers around both stores. Polling reads the ownership byte, issues a CPU fence after acquisition, checks CQE format, opcode, SQ number and WQE counter, and publishes the CQ consumer DB. This implementation keeps one signalled write in flight per rail.

## Cold-path handoff

The caller supplies live resources in the **same Omega process and mapping context**. Linux mlx5 remains responsible for pinning, translation, QP setup and UAR mapping. A live uverbs resource adapter and Blackwell launch integration are outstanding. An integer address from a different process cannot stand in for an Omega mapping handle.

- Set up two exclusively owned RTS RC QPs to the other rank, one through each cable. Choose different PCIe domains as well as different physical ports. On the documented topology, `rocep1s0f0` and `roceP2p1s0f1` are one such pair. Verify the route and port correspondence on both hosts. [DGX Spark networking](https://docs.nvidia.com/dgx/dgx-spark/spark-clustering.html)
- Hand over fresh SQs, private doorbell apertures and dedicated polled send CQs with standard, uncompressed 64- or 128-byte entries. Disable WQE signatures. Only this polling thread may post, poll or use either UAR. The two rails may have the same QPN in different device namespaces. [mlx5 posting](https://github.com/linux-rdma/rdma-core/blob/v58.0/providers/mlx5/qp.c) and [mlx5 CQ polling](https://github.com/linux-rdma/rdma-core/blob/v58.0/providers/mlx5/cq.c)
- In each `CxQueue`, supply live read/write handles and byte offsets for `sq/sqoff`, `cq/cqoff`, `db[0]/dboff[0]` (send producer record) and `db[1]/dboff[1]` (CQ set-CI record). Supply the WQEBB count, physical CQ slot count, CQE stride, local QPN, and `bf/bfoff/half` from the provider. Both doorbell halves must be mapped. Start `pi`, `ci` and `busy` at zero, BF on its first half, and all CQEs initialized invalid. The adapter must verify the full mapping spans and exclusive ownership before handoff.
- Allocate one pinned, CPU-readable/writable arena per rank with ordinary ordered, coherent host DMA and aligned, indivisible four-byte notification writes. Register **the same pages** in both rails' protection domains for remote writes. Disable relaxed-ordering registration. Set `CxRank.arena` to the mapping handle and `capacity` to the common FP32 element capacity. Set each rail's `localva/lkey` and `peerva/rkey` to its actual registered IOVA/key pair. An IOVA may differ from the process address. Set each `limit` to the negotiated maximum single-message byte count.
- The arena contains `capacity * 4` activation bytes, the same size inbox, then five aligned little-endian uint32 words in order: outbound epoch, incoming ready on rails 0 and 1, incoming acknowledgment on rails 0 and 1. Initialize the five words, rank epoch and active state to zero **once** before admitting either endpoint. Keep the layout fixed for the QPs' lifetime. Set `rankid` to 0 or 1. Both peers must agree on capacity, element count, FP32 representation and collective sequence.
- For GPU-produced inputs, independently register or map these exact pages for the GPU and establish GPU producer completion and system visibility before starting. After the collective, establish visibility for the consuming kernel using the supported driver contract. Shared physical LPDDR5X alone does not establish these properties.

## Calling the collective

Concatenate `tp2.om` and the caller, then compile the combined source with seeded `omc`. Call `cxBegin rank left right elements` once per epoch. It returns 0 on admission and -1 on refusal. Repeatedly call `cxProgress rank left right` with the same objects. Return 0 means pending, 1 means the local result and both inboxes are reusable for this rank's next collective, and -1 means idle or failed. A CQ failure latches the rank in a failed state and retains the offending CQE. Quiesce both peers and reconstruct resources on a terminal failure or timeout. Never replay a partially posted epoch onto the same queues. Reinitialize the session before the 32-bit epoch would repeat.

On each rail, data writes precede a separate epoch write into the peer's ready word. An observed peer-ready word and retired local sends permit reduction. The receiver then writes its acknowledgment, permitting its peer to reuse that inbox. The two rails make independent progress. Empty stripes still participate in the handshake. The caller owns deadlines and cancellation and can insert `cpurelax` between progress calls.

## Host check

From the repository root on AArch64 Linux:

```sh
sh seed/omega-from-seed.sh
cat native/connectx7/tp2.om native/connectx7/host.om | seed/out/omc > /tmp/cx7-host
chmod +x /tmp/cx7-host
strace -qq /tmp/cx7-host
```

Success is exit 0. The trace contains exec, six anonymous setup mappings and exit. The fixture decodes posted wire bytes, checks both doorbell halves, copies data between the two rank arenas and produces matching CQEs. It exercises delayed delivery, inbox reuse, empty/odd/even lengths, multiple chunks, guard elements, SQ/CQ wrap, owner mismatch, error CQEs, wrong QPN, wrong counter and compressed format.

**Hardware qualification — NOT_RUN.** This host fixture cannot establish device acceptance, coherent GPU/NIC access to the same pages or link throughput. For a two-Spark qualification, record per-port traffic, a bitwise result check on a GPU-produced and GPU-consumed activation, and end-to-end time against NCCL with the same tensor, topology and synchronization boundaries.
