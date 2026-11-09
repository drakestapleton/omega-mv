#!/bin/sh
# extract.sh REPO OUTDIR : write the 29 row sources to OUTDIR/ROW.om from corpus.pack of REPO tree
R=$1; O=$2; mkdir -p "$O"
P=$R/seed/qualification/om2/c2/corpus.pack
for id in $(cat ~/work/L1041/rows29.txt); do
  spec=$(grep "^$id " $R/seed/qualification/om2/manifest-c2.txt | awk '{print $3}')
  off=$(echo $spec | cut -d: -f3); len=$(echo $spec | cut -d: -f4)
  tail -c +$((off+1)) "$P" | head -c $len > "$O/$id.om"
done
