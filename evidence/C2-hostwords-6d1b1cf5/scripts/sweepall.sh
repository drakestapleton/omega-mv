#!/bin/sh
for c in $(cat ~/work/L1041/all.txt); do sh ~/work/L1041/sweep1.sh $c; done
echo SWEEPDONE
