#!/bin/sh
printf "6\n" > /tmp/helix_genome.cfg
"/home/drakestapleton/work/ollm-helix-rlvr-20261121/bin/ollm-helix-gb10" geval "/home/drakestapleton/work/ollm-loop-20261121/run/loop/ck6000.bin" "/home/drakestapleton/work/ollm-loop-20261121/data/held.tok" 2475 "/home/drakestapleton/work/ollm-loop-20261121/data/omega4096.bin" > "/home/drakestapleton/work/ollm-helix-rlvr-20261121/rounds/geval_loop_r0_ck6000.log" 2>&1
rc=$?
rm -f /tmp/helix_genome.cfg
exit $rc
