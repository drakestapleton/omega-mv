# Run the two-Spark transport experiment

**Result sought:** two ConnectX-7 queue pairs complete a bidirectional FP32 AllReduce across two direct cables, and both ranks verify every result bit. The supplied rank fills and checks a CPU-pinned arena on each host. GPU producer/consumer visibility requires the separate experiment below.

## Before the first run

Use two AArch64 DGX Sparks with two 200 Gb/s cables, a 4 KiB host page, active RoCEv2 routes on opposite physical ports and PCIe domains, and an operator-approved hardware window. The rank supports ConnectX-7 PCI device ID 0x1021, standard CQE v0, private alternating UARs, and Linux uverbs legacy write commands. It requires permission to open both uverbs devices and enough locked memory for the arena and both queue sets. It needs no CUDA, NCCL, libibverbs or libmlx5 in userspace. The kernel mlx5 drivers remain dependencies.

On each machine unpack the same archive into a user-owned directory. From its root:

```sh
sha256sum -c SHA256SUMS
./cx7-host && echo 'PASS device-free fixture'
getconf PAGESIZE
ulimit -l
ibdev2netdev
show_gids
```

Select one active **RoCE v2** GID index for `rocep1s0f0` (left port, PCI domain 0) and one for `roceP2p1s0f1` (right port, domain 2) **on each host**. Choose GIDs for the configured addresses on the corresponding direct links. Match left-to-left and right-to-right cables for this launcher. Verify link state, cable rate and routing independently. Keep those four indices for the command below. [NVIDIA port correspondence](https://docs.nvidia.com/dgx/dgx-spark/spark-clustering.html)

To rebuild both static executables from the included Omega source and compiler:

```sh
cat tp2.om host.om | ./omc > cx7-host.rebuilt
cat tp2.om rank.om | ./omc > cx7-rank.rebuilt
cmp cx7-host cx7-host.rebuilt && cmp cx7-rank cx7-rank.rebuilt
```

## Run one collective

Install `socat` on rank 0 and use an existing SSH login to rank 1. The example assumes the archive contents are in `~/cx7-lab` on both machines. Replace `spark-peer` and all four GID indices with the values for this setup. Run from Bash on rank 0. SSH carries only endpoint setup and synchronization. The Omega executable posts the tensor transfers through the NIC queues.

```bash
cd ~/cx7-lab
peer=spark-peer
left0=3; right0=3
left1=3; right1=3
elements=4097
log=$(mktemp)
socat "EXEC:timeout 90 ./run-rank.sh 0 $elements $left0 $right0" \
      "EXEC:ssh -T -o BatchMode=yes $peer timeout 90 ./cx7-lab/run-rank.sh 1 $elements $left1 $right1" 2>"$log"
cat "$log"
grep -q "^CX7 PASS host-pinned FP32 rank=0 elements=$elements elapsed_ns=" "$log" &&
grep -q "^CX7 PASS host-pinned FP32 rank=1 elements=$elements elapsed_ns=" "$log" &&
echo 'PASS both ranks'
```

Record both rank lines. Each time spans admission through remote acknowledgments. Initialization, final checking and SSH barriers lie outside that interval. The run uses one signalled write in flight per physical rail and reduces in CPU tiles. Use a fresh pair of processes after any timeout or error. Exit stages 10–17 cover context, identity, port, PD and MR setup. Stages 18–22 cover CQ, QP and UAR setup, 23–25 cover INIT/RTR/RTS and 26–30 cover peer exchange. Stage 32 signals a CQ failure and 33 reports the first incorrect element. Report the stage and signed kernel result or offending index. Permission, memlock, ABI, GID and path-MTU problems can surface before posting.

## Evidence to return

Record the archive digest, source commit, firmware, kernel, cable rates, selected Ethernet/RoCE devices and PCIe domains. Keep live endpoint records and MR keys inside the private control channel. Run empty, single-element, odd and representative production-size tensors. On an otherwise idle fabric, collect each selected port's `port_xmit_data` and `port_rcv_data` before and after the run from `/sys/class/infiniband/DEVICE/ports/1/counters/`. Save both times and both correctness verdicts. A successful host fixture alone establishes no hardware result.

For a throughput comparison, repeat each shape, retain the distribution and report the slower rank. Distinguish per-rank useful FP32 bytes from summed interface counters. Run the installed NCCL baseline at the same sizes, dtype, rank count, routes and synchronization boundaries. Report its memory path and warm-up separately.

For the unified GPU-buffer claim, integrate `tp2.om` with the Blackwell launcher's supported pinned-page registration and producer/consumer fences. Have the GPU write a known activation directly into the MR, retire that producer before `cxBegin`, then have the GPU consume and verify the in-place result after `cxProgress` returns 1. Record the CPU mapping, GPU registration and both NIC registrations as referring to the same allocation, without publishing live keys. Repeat with changing activation patterns. The supplied standalone binary exercises the host-pinned NIC transport only.
