#!/bin/sh
# Resolve a rebase step: main's size ledger + this commit's retained KFD rows, reseed omc, append the
# row tests/kfd/check.py --record-history writes for the new compiler (same formula).
set -eu
git show :2:seed/omc/size-history.tsv > /tmp/kfdrebase/ours.tsv
git show :3:seed/omc/size-history.tsv > /tmp/kfdrebase/theirs.tsv
cp /tmp/kfdrebase/ours.tsv seed/omc/size-history.tsv
grep -vxF -f /tmp/kfdrebase/ours.tsv /tmp/kfdrebase/theirs.tsv >> seed/omc/size-history.tsv || true
git checkout --ours seed/out/omc seed/out/omc.sha256
flock /home/drakestapleton/handoffs/hive/queen/pool-16-18.lock taskset -c 16-18 nice -n 10 sh seed/omega-from-seed.sh > /tmp/kfdrebase/seed-$(git rev-parse --short REBASE_HEAD).log 2>&1
tail -3 /tmp/kfdrebase/seed-$(git rev-parse --short REBASE_HEAD).log
d=$(sha256sum < seed/out/omc | cut -c1-64)
lines=$(wc -l < seed/omc/omc.om); fns=$(grep -c '^fn ' seed/omc/omc.om); words=$(( ($(wc -c < seed/out/omc) - 176) / 4 ))
tail -1 seed/omc/size-history.tsv | grep -q "	$d\$" || printf 'kfd-uapi\tKFD checked records and aligned reservations on Linux AArch64/x86\t%s\t%s\t%s\t%s\n' "$lines" "$fns" "$words" "$d" >> seed/omc/size-history.tsv
git status --short | grep -v '^[AM] ' || true
tail -4 seed/omc/size-history.tsv | cut -f1,3-6
