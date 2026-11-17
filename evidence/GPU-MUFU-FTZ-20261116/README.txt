omega-mv f869644339234ef48aecee87803ee9bb09dc81dc, fresh clone, GB10 spark-window 20261116T231028Z-083cf5 (exclusive, quiet none: values only, no speed claim)
command: PHYSICS_DIR=build/pins/physics-src spark-window run sh tools/run_gpu_elementwise_chip.sh <out>; files below are that runner's output folder FB1-CUT4-f86964433 unchanged (SHA256SUMS is the runner's own)
Xid count before 0, after 0
result: PASS 43 checks, 0 failed; ex2_ftz_probe chip_differs_from_ieee=191 of 217; rsq_ftz_probe chip_differs_from_ieee=8 of 1029; every mutant CAUGHT
the earlier run evidence/GPU-MUFU-FTZ-ebbb089a-20261116 was made at ebbb089a, a pre-rebase commit of the same change (later 608b35c4, 00e83ec4); f8696443 is also a pre-rebase commit and is not kept on main. This run is bound to the landed head by the source sha256s in SHA256SUMS (omega_gpu_elementwise_api.c/.h, gpu_elementwise_test.c, bw_mufu_ftz.h), which equal that head's files; the test binary itself was not hashed in this run
