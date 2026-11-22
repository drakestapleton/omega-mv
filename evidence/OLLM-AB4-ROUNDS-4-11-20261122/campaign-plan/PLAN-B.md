# Follow-up rounds, registered before they run (2026-11-22, after review 1 of head 0c6b702c)

Written before any of these rounds started. Criteria are fixed here.

Baseline R0: geval (2,475 windows of held.tok) of the pre-campaign looped checkpoint
~/work/ollm-loop-20261121/run/loop/ck6000.bin with today's ollm-helix-gb10. train/omega-llm/docs/LOOP.md
records 2.144233 for it; this checks that today's binary reproduces that.

Every round: 1,400 gtrainf steps, lrmicro 350, same binaries (rounds/pins.sha256), greedy frozen
benchmark and full geval afterwards.

- r8 (ablation, from loop_r3.ck): round 4's exact task sources and weights; rehearsal = wide draw
  from repo-train.om at 50% of the mix.
- r9 (ablation, from loop_r3.ck): same as r8, except rehearsal = the small repo slice of round 4's
  own mix replayed until it is 50% of the mix.
  Reading: r8 and r9 differ only in how many distinct repo documents the rehearsal holds.
  r9 and r4 differ in rehearsal share (50% vs 29.3%) and in file size, not in which repo documents.
  If held(r9) - held(r8) > 0.3 nats: the breadth of the rehearsal draw is the cause of the drift.
  If |held(r9) - held(r8)| <= 0.1: the share, not the breadth, is what mattered.
  Between: both contribute; report the numbers without naming a single cause.
- r10 (from loop_r6.ck) and r11 (from loop_r10.ck): round 6's configuration again (same sources and
  weights, wide rehearsal at 50%), new shuffle seeds.

Benchmark gain criterion: a round counts as a gain only with 8 or more greedy passes of 159 (round
3 has 6; rounds 4 to 7 gave 3 to 5; single-pass moves are not counted). If none of r8..r11 reaches
8, the frozen benchmark is at diminishing returns for this model and this data: eight rounds after
round 3 without a gain.
Held-out plateau criterion: |held(r11) - held(r10)| < 0.05 nats and both within 0.15 of R0 means
the rehearsal change has recovered what it can; otherwise report the trend as still moving.
