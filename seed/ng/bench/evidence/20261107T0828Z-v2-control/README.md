ngbench v2 contamination-scan control, untimed, 2026-11-07 ~08:27Z.
Command: taskset -c 1 nice -n 10 ngbench.v2 run 1 0 /tmp/ngb/pbd omc ngA -- fib38 (core 1 = the shared build core while another lane compiled; expected contaminated=1). Result: K 0 fib38 start=1 end=1 contaminated=1, foreign R task cc1 on cpu 1 in both scans; rc 0.
Unpinned control: taskset -c 1,2 -> H row core=unpinned, zero X/Y/K rows.
ngbench.v2 binary sha256 ba6351527ef844836776dbaff44b782c5957225f35a172205ae4d77904ff0200.
