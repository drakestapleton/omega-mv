#!/bin/sh
# negative control: the c2-00014 source with its final "ret 0" changed to "ret 9", built by the new compiler, must differ from the old compiler's unmodified run
cd ~/work/L1041/nc || exit 2; OLD=~/work/L1041/res/474197e4.omc; NEW=~/work/L1041/res/a0d12c25.omc
d=$(mktemp -d); cd $d
$OLD < ~/work/L1041/src29/c2-00014.om > old.bin; chmod 700 old.bin; ./old.bin; echo "old unmodified exit=$?"
$NEW < ~/work/L1041/src29/c2-00014.om > new.bin; chmod 700 new.bin; ./new.bin; echo "new unmodified exit=$?"
$NEW < ~/work/L1041/nc/mutant.om > mut.bin; chmod 700 mut.bin; ./mut.bin; echo "new mutant exit=$?"
