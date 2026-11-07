# Jobs that ran beside the payoff rounds (recorded 2026-11-07 after the rounds, at omp-queen-ng's request)

Sources: `~/handoffs/BOARD.md` window lines (quoted times), `ps -eo pid,lstart` at about 12:18Z (start times,
local time UTC-6 converted to Z), and the rounds' own `cluster-start.txt` / `cluster-end.txt` (processes on the
timed core's cluster, with CPU number and %CPU, taken inside the lock just before and after the round). None of
these jobs ran on the timed core itself (core 9 / core 11: `core_foreign_runnable=0` in every Y row); what they share
with the round is the memory system (DRAM bandwidth, the system-level cache) and, for some, the cluster.

## A725 round, core 11, 11:54:55Z to 12:09:06Z

| job | evidence | overlap with the round |
|---|---|---|
| ownmodel own1-leg23 (ollm-gb10 gtrain4 on the GPU) | BOARD 11:50:10Z STARTING; closed 12:00:47Z (BOARD 12:02:18Z) | 11:54:55Z to 12:00:47Z |
| ownmodel own1-leg24 (ollm-gb10 gtrain4 on the GPU) | BOARD 12:00:47Z STARTING, 12:11:24Z DONE | 12:00:47Z to 12:09:06Z |
| wsp `ollm train` pid 2111398 (CPU) | ps lstart 12:02:53Z; a725/cluster-end.txt: CPU 19, 99.8% | 12:02:53Z to the end |
| an `ollm` pid 3809678 (CPU) | a725/cluster-start.txt: CPU 19, 99.4% | at the start (gone by the end) |
| ownmodel-gates6 `ollm serve` 18291/18292 (CPU, cores 4 and 6) | BOARD 11:48:40Z START, gate processes restarted through the round | whole round |
| wsp `wpolicy run` pid 860575 | ps lstart 10:21:30Z | whole round |

## X925 round, core 9, 12:09:07Z to 12:15:29Z

| job | evidence | overlap with the round |
|---|---|---|
| ownmodel own1-leg24 (ollm-gb10 gtrain4) | x925/cluster-start.txt: pid 2046461 on CPU 5, 50.9% | 12:09:07Z to 12:11:24Z |
| ownmodel own1-leg25 (ollm-gb10 gtrain4) | BOARD 12:11:24Z STARTING (opened 12:11:43Z per sched 12:13:00Z); x925/cluster-end.txt: pid 2631089 on CPU 5, 53.5% | 12:11:43Z to the end |
| ownmodel-gates6 `ollm serve` 18291/18292 | x925/cluster-start.txt: pids 2187739 (CPU 6, 79.7%), 2188194 (CPU 4); cluster-end.txt: 2776918, 2777356 (CPU 6) | whole round |
| wsp `ollm train` pid 2111398 (CPU) | ps lstart 12:02:53Z; sched BOARD 12:15:37Z lists it running | whole round |
| wsp `wpolicy run` pid 860575 | x925/cluster-start.txt and cluster-end.txt: CPU 3 | whole round |

Not available: GPU utilisation or memory traffic over time (no counters, no sampled telemetry for these minutes).
