#!/bin/sh
# mutate.sh -- each mutant breaks one round-4 rule in trit.om or the shared codebook.om; the fixture
# suite (test.sh) and the Lean differential test (difftest.sh, N=200 seed 3) must each kill it.
# Usage from the repo root: OMC=... LEAN=... sh tools/trit/mutate.sh   (needs perl)
set -u
R=$(pwd); W=${W:-${TMPDIR:-/tmp}/trit-mut.$$}; rm -rf "$W"; mkdir -p "$W"
k1=0; k2=0; n=0
m() {
  n=$((n+1)); f=$1; name=$2; expr=$3
  rm -rf "$W/r"; mkdir -p "$W/r/tools" "$W/r/seed/trace"
  cp -r tools/trit tools/codebook "$W/r/tools/"; cp seed/trace/sha256.om "$W/r/seed/trace/"
  perl -0pi -e "$expr" "$W/r/tools/$f"
  if cmp -s "$W/r/tools/$f" "tools/$f"; then echo "MUTANT $n $name: NOT APPLIED"; return; fi
  (cd "$W/r" && OMC=$OMC sh tools/trit/build.sh >/dev/null 2>&1 && OMC=$OMC sh tools/codebook/build.sh >/dev/null 2>&1) || { echo "MUTANT $n $name: build failed"; return; }
  t=survived; (cd "$W/r" && sh tools/trit/test.sh >/dev/null 2>&1) || { t=killed; k1=$((k1+1)); }
  d=survived; (cd "$W/r" && N=200 SEED=3 W="$W/d" sh tools/trit/proof/difftest.sh >/dev/null 2>&1) || { d=killed; k2=$((k2+1)); }
  echo "MUTANT $n $name: test.sh $t, difftest $d"
}
m trit/trit.om lvl-ignores-3xx 's/if and eq get vf 0 1 eq get ve 0 1/if eq get vf 0 1/'
m trit/trit.om verify-disabled 's/put vk 0 1\n/put vk 0 0\n/'
m trit/trit.om quota-counts-forged 's/if eq get vm 0 0\nret true\nend\n//'
m trit/trit.om quota-counts-replays 's/if seenc s n v\nret true\nend\n//'
m trit/trit.om unsigned-emergency-jumps 's/if eq open te 2\nmktok 1/if gt open te 0\nmktok 1/'
m trit/trit.om ack-no-counter-advance 's/ackv cur off\n//'
m trit/trit.om ack-advances-past-token 's/while lt p off bound BIG/while lt p get fbn 0 bound BIG/'
m trit/trit.om ack-no-lock 's/lk = lockst\n/lk = int 99\n/'
m trit/trit.om sig-not-stripped 's/ee = lp\nnf = sub nf 1\n//'
m trit/trit.om cursor-no-dir-fsync 's/ptext tcur\nsyncdir\n/ptext tcur\n/'
m codebook/codebook.om no-batch-table 's/vtput s sn ctr\n//'
m codebook/codebook.om counter-file-ignored 's/v = rdctf s n\n/v = ulong 0\n/'
m codebook/codebook.om stale-allows-equal 's/if le ctr rdctr s sn/if lt ctr rdctr s sn/'
m codebook/codebook.om counter-no-dir-fsync 's/ctrpath s n\nsyncdir\n//'
m codebook/codebook.om mac-not-checked 's/ret eq x 0\n/ret true\n/'
m codebook/codebook.om 1xx-is-emergency 's/if and ge g 300 lt g 400\nret true/if and ge g 100 lt g 400\nret true/'
echo "MUTANTS $n killed-by-test.sh=$k1 killed-by-difftest=$k2"
