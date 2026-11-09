#!/bin/sh
# sweep1.sh COMMIT : seed-born compiler of COMMIT, emit sha+exit of the 29 rows -> res/COMMIT8.tsv
C=$1; S=$(echo $C | cut -c1-8); W=~/work/L1041/b/$S; R=~/work/L1041/repo
rm -rf $W; mkdir -p $W; git -C $R archive $C seed | tar -x -C $W
cd $W
if sh seed/omega-from-seed.sh > birth.log 2>&1; then born=1; else born=0; fi
OMC=$W/seed/out/omc
[ -x $OMC ] || { echo "$S born=$born nocompiler" ; exit 0; }
echo "omc $(sha256sum < $OMC | cut -c1-64) born=$born" > ~/work/L1041/res/$S.hdr
: > ~/work/L1041/res/$S.tsv
for id in $(cat ~/work/L1041/rows29.txt); do
  $OMC < ~/work/L1041/src29/$id.om > out.$id 2> err.$id; rc=$?
  printf '%s\t%s\t%s\t%s\n' $id $rc $(sha256sum < out.$id | cut -c1-64) "$(cat err.$id | tr '\n' ' ')" >> ~/work/L1041/res/$S.tsv
done
cp -r seed/out/omc ~/work/L1041/res/$S.omc 2>/dev/null
cd ~/work/L1041; rm -rf $W/build $W/out.* 
