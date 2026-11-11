#!/bin/sh
# groups.sh DIR -- write one unit per arena group of omc into DIR, each driving its group past the first
# room the group is given (OMEGESE 9.6: a_isize gives names, long names, functions, calls and trap sites an
# input-sized first room of at most 8192 entries; every other group starts at 64 entries; the output starts
# at 65536 bytes). For each NAME.om:
#   NAME.grp   lines "GROUP MIN": in the unit's omc-use record, GROUP=N/H must have N >= MIN, a count past
#              that group's largest first room, so the group grew (N is what the group was asked to hold)
#   NAME.want  the exit status the compiled program must give (absent: the unit is compiled only)
#   NAME.run   how the program runs: "native" (AArch64, default) or "x86" (qemu-x86_64, EMULATED)
# gate-nocaps step 4 compiles every unit with seed/out/omc and with a checked twin of the same source (each
# inline table access a region-checked call: an index past its region is trap 3 there, exit 103).
set -eu
D=$1
mkdir -p "$D"
# names: 9,000 globals and the input past 64 KiB; the first and the last keep their values apart: 5 + 7 = 12.
awk 'BEGIN { for (i = 0; i < 9000; i++) printf "global g%d uint 1\n", i; print "fn main to int"
  print "put g0 0 uint 5"; print "put g8999 0 uint 7"; print "ret int add get g0 0 get g8999 0"; print "end" }' > "$D/names.om"
echo 12 > "$D/names.want"
printf 'names 8193\nnamehash 1025\ninp 65536\n' > "$D/names.grp"
# longnames: 9,000 names of 9..63 bytes (the long-name table and its hash): 5 + 7 = 12.
awk 'BEGIN { for (i = 0; i < 9000; i++) printf "global a_long_global_%05d uint 1\n", i; print "fn main to int"
  print "put a_long_global_00000 0 uint 5"; print "put a_long_global_08999 0 uint 7"
  print "ret int add get a_long_global_00000 0 get a_long_global_08999 0"; print "end" }' > "$D/longnames.om"
echo 12 > "$D/longnames.want"
printf 'long 8193\nlonghash 1025\n' > "$D/longnames.grp"
# fns: 9,000 functions (and the function hash); main calls the first and the last: 0 + 8999, mod 256 = 39.
awk 'BEGIN { for (i = 0; i < 9000; i++) printf "fn q%d to ulong\nret %d\nend\n", i, i
  print "fn main to int"; print "a = q0"; print "b = q8999"; print "ret int rem add a b 256"; print "end" }' > "$D/fns.om"
echo 39 > "$D/fns.want"
printf 'fns 8193\nfnhash 1025\n' > "$D/fns.grp"
# calls: 9,000 calls in one function, past 64 KiB of output: 9000 mod 256 = 40.
awk 'BEGIN { print "fn inc x ulong to ulong"; print "ret add x 1"; print "end"; print "fn main to int"; print "x = ulong 0"
  for (i = 0; i < 9000; i++) print "x = inc x"; print "ret int rem x 256"; print "end" }' > "$D/calls.om"
echo 40 > "$D/calls.want"
printf 'calls 8193\nout 65537\n' > "$D/calls.grp"
# traps: 9,000 trap sites (each signed add can overflow): 9000 mod 256 = 40.
awk 'BEGIN { print "fn main to int"; print "x = long 0"; for (i = 0; i < 9000; i++) print "x = add x long 1"
  print "ret int rem x long 256"; print "end" }' > "$D/traps.om"
echo 40 > "$D/traps.want"
printf 'traps 8193\n' > "$D/traps.grp"
# blocks: 300 blocks nested; the innermost returns 9.
awk 'BEGIN { print "fn main to int"; print "x = ulong 1"; for (i = 0; i < 300; i++) print "if eq x 1"
  print "ret 9"; for (i = 0; i < 300; i++) print "end"; print "ret 0"; print "end" }' > "$D/blocks.om"
echo 9 > "$D/blocks.want"
printf 'blocks 65\n' > "$D/blocks.grp"
# breaks: one loop with 300 breaks (the break list is per loop), each taken at x = 150; x counts up from 0.
awk 'BEGIN { print "fn main to int"; print "x = ulong 0"; print "while true"
  for (k = 0; k < 300; k++) { print "if eq x 150"; print "break"; print "end" }
  print "x = add x 1"; print "end"; print "ret int x"; print "end" }' > "$D/breaks.om"
echo 150 > "$D/breaks.want"
printf 'breaks 65\n' > "$D/breaks.grp"
# conts: 300 continues in one loop that runs 3 times; each pass takes the continue at k = x and x counts
# them: 3.
awk 'BEGIN { print "fn main to int"; print "x = ulong 0"; print "i = ulong 0"; print "while lt i 3"; print "i = add i 1"
  for (k = 0; k < 300; k++) { printf "if eq rem x 300 %d\n", k; print "x = add x 1"; print "continue"; print "end" }
  print "end"; print "ret int rem x 256"; print "end" }' > "$D/conts.om"
echo 3 > "$D/conts.want"
printf 'conts 65\n' > "$D/conts.grp"
# inlret: an inline function with 300 rets, expanded once: it returns its argument, 150.
awk 'BEGIN { print "om2"; print "fn pick x ulong to ulong inline"; for (k = 0; k < 300; k++) { printf "if eq x %d\n", k; printf "ret %d\n", k; print "end" }
  print "ret 0"; print "end"; print "fn main to int"; print "y = pick 150"; print "ret int y"; print "end" }' > "$D/inlret.om"
echo 150 > "$D/inlret.want"
printf 'inlret 65\n' > "$D/inlret.grp"
# inledge: 1,000 inline edges and no call (12 leaves, a root expanding them, 76 functions expanding the
# root: 13 * 76 + 12); main returns the root, 12.
awk 'BEGIN { print "om2"; for (i = 1; i <= 12; i++) printf "fn b%d to int inline\nret 1\nend\n", i
  print "fn a to int inline"; print "x = int 0"; for (i = 1; i <= 12; i++) printf "x = add x b%d\n", i; print "ret x"; print "end"
  for (j = 1; j < 76; j++) printf "fn g%d to int\nret a\nend\n", j; print "fn main to int"; print "ret a"; print "end" }' > "$D/inledge.om"
echo 12 > "$D/inledge.want"
printf 'inledge 1000\n' > "$D/inledge.grp"
# depth: a value nested 300 deep (300 conversions of y, which is 7).
awk 'BEGIN { print "fn main to int"; print "y = ulong 7"; printf "x = "; for (i = 0; i < 300; i++) printf "ulong "
  print "y"; print "ret int rem x 256"; print "end" }' > "$D/depth.om"
echo 7 > "$D/depth.want"
printf 'depth 65\n' > "$D/depth.grp"
# site: an om2 diag unit with 300 trap sites (one omc-site record each on stderr): 300 mod 256 = 44.
awk 'BEGIN { print "om2 diag"; print "fn main to int"; print "x = long 0"; for (i = 0; i < 300; i++) print "x = add x long 1"
  print "ret int rem x long 256"; print "end" }' > "$D/site.om"
echo 44 > "$D/site.want"
printf 'site 65\n' > "$D/site.grp"
# kahn: a function-mode unit (no main) of 300 functions, each calling the one before it (ksettle).
awk 'BEGIN { print "fn k0 x ulong to ulong"; print "ret x"; print "end"
  for (i = 1; i < 300; i++) { printf "fn k%d x ulong to ulong\n", i; printf "ret k%d add x 1\n", i - 1; print "end" } }' > "$D/kahn.om"
printf 'kahnfn 65\nkahncall 65\n' > "$D/kahn.grp"
# x86addr: target x86linux, 300 globals each read at a variable index (an address fixup each): 300 mod 256 = 44.
awk 'BEGIN { print "target x86linux"; for (i = 0; i < 300; i++) printf "global g%d uint 1\n", i; print "fn main to int"; print "s = uint 0"
  print "i = ulong 0"; for (i = 0; i < 300; i++) printf "put g%d i uint 1\n", i; for (i = 0; i < 300; i++) printf "s = add s get g%d i\n", i
  print "ret int rem s 256"; print "end" }' > "$D/x86addr.om"
echo 44 > "$D/x86addr.want"
echo x86 > "$D/x86addr.run"
printf 'x86addr 65\n' > "$D/x86addr.grp"
# x86exit: target x86efi, 300 exit statements (each a branch to the shared firmware return): compiled only.
awk 'BEGIN { print "target x86efi"; print "fn main to int"; print "x = ulong 7"
  for (k = 0; k < 300; k++) { printf "if eq x %d\n", k; printf "exit %d\n", k; print "end" }
  print "ret 0"; print "end" }' > "$D/x86exit.om"
printf 'x86exit 65\n' > "$D/x86exit.grp"
