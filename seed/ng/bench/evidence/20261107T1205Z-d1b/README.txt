build: cat seed/ng/ngbench.om seed/ng/sha256.om seed/ng/bench/ngbench-sha.om | taskset -c 1 nice -n 10 seed/out/omc  (rc 0)
seed/out/omc cfd96b48b0460ab5557853d6856f9c741b96ac8d0d624e06198defb4cbfa0d8a
ngbench (D1b) 47f399c88fed6b8fa8034c8ffcd6cd645cf5699739b9e410414b1c3a4d194622
ngbench (v2, built-in sha2, base da8b7e66) ba6351527ef844836776dbaff44b782c5957225f35a172205ae4d77904ff0200
files: 14 random sizes 0 1 55 56 63 64 65 119 120 127 128 1000 65536 65537, one of 16777215 bytes, the 47 payoff binaries = 62
new.txt = ngbench-d1b sum FILES; old.txt = ngbench v2 sum FILES; ref.txt = coreutils sha256sum FILES
cmp new ref: equal; cmp old ref: equal
negative: 16777216-byte file -> 'ngbench: cannot read toobig' rc 1 (v2 accepted any size; D1b refuses >= len sh_dat, documented in ngbench-sha.om)
negative: missing file -> 'ngbench: cannot read nosuch' rc 1
functional: run 1 0 fixture{omc,gccO2 arith} -> pos.rows S rows=4 ok=4 fail=0 refused=0 rc 0
negative: same fixture, manifest gccO2 hash first hex digit 0->f -> neg.rows 'R manifest arith gccO2', S refused=1, rc 1; v2 gives the same (negold.rows)
