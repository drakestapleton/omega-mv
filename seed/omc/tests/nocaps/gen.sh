#!/bin/sh
# gen.sh DIR -- write the gate-nocaps units into DIR, one NAME.om each, with NAME.want holding the
# exit status the compiled program must give. Each unit is far past a capacity of omc f4fa7951.
set -eu
D=$1
mkdir -p "$D"
# texts100k: 100,000 texts (the old name table held 8192 names, texts and globals together). The answer
# reads the first and the last: 1 + 3 = 4.
awk 'BEGIN { print "text t0 \"a\""; for (i = 1; i < 99999; i++) printf "text t%d \"xy\"\n", i
  print "text t99999 \"abc\""; print "fn main to int"; print "x = len t0"; print "y = len t99999"
  print "ret int add x y"; print "end" }' > "$D/texts100k.om"
echo 4 > "$D/texts100k.want"
# globals100k: 100,000 global pools; the first and the last keep their values apart: 5 + 7 = 12.
awk 'BEGIN { for (i = 0; i < 100000; i++) printf "global g%d uint 1\n", i; print "fn main to int"
  print "put g0 0 uint 5"; print "put g99999 0 uint 7"; print "ret int add get g0 0 get g99999 0"; print "end" }' > "$D/globals100k.om"
echo 12 > "$D/globals100k.want"
# calls100k: 100,000 calls in one OM-2 function (the old per-function emitted budget was 262144 bytes).
# 100000 mod 256 = 160.
awk 'BEGIN { print "om2"; print "fn inc x ulong to ulong"; print "ret add x 1"; print "end"
  print "fn main to int"; print "x = ulong 0"; for (i = 0; i < 100000; i++) print "x = inc x"
  print "ret int rem x 256"; print "end" }' > "$D/calls100k.om"
echo 160 > "$D/calls100k.want"
# view6553: the shape that failed at 6553 (omc f4fa7951 accepts 6552): a call statement passing a text to
# an unsized view uchar * parameter, 40 bytes each, in one OM-2 body. 6553 * 5 = 32765; mod 256 = 253.
vuse() { awk -v n="$1" 'BEGIN { print "om2"; print "global cnt ulong 1"; print "text t \"hello\""
  print "fn vuse a view uchar * to void"; print "put cnt 0 add get cnt 0 len a"; print "ret"; print "end"
  print "fn main to int"; for (i = 0; i < n; i++) print "vuse t"; print "ret int rem get cnt 0 256"; print "end" }'; }
vuse 6552 > "$D/view6552.om"
echo 248 > "$D/view6552.want"
vuse 6553 > "$D/view6553.om"
echo 253 > "$D/view6553.want"
# view100k: the same shape 100,000 times. 500000 mod 256 = 32.
vuse 100000 > "$D/view100k.om"
# vlen100k: 100,000 calls of a view uchar * function inside a value. 500000 mod 256 = 32.
awk 'BEGIN { print "om2"; print "text t \"hello\""; print "fn vlen a view uchar * to ulong"; print "ret len a"
  print "end"; print "fn main to int"; print "s = ulong 0"; for (i = 0; i < 100000; i++) print "s = add s vlen t"
  print "ret int rem s 256"; print "end" }' > "$D/vlen100k.om"
echo 32 > "$D/vlen100k.want"
echo 32 > "$D/view100k.want"
# traps100k: 100,000 trap sites in one plain (OM-1) function: each signed add can overflow (trap 1).
# 100000 mod 256 = 160.
awk 'BEGIN { print "fn main to int"; print "x = long 0"; for (i = 0; i < 100000; i++) print "x = add x long 1"
  print "ret int rem x long 256"; print "end" }' > "$D/traps100k.om"
echo 160 > "$D/traps100k.want"
# trapmid / traplate: the same 100,000 sites, starting 50,000 / 99,990 below the largest long, so the
# signed add overflows at the 50,001st / 99,991st line and the program stops with trap 1 (exit 101):
# a branch to a trap stub placed by an island in the middle of the function, and one near its end.
for v in mid:9223372036854725807 late:9223372036854675817; do
  n=${v%%:*}; s=${v#*:}
  awk -v s=$s 'BEGIN { print "fn main to int"; print "x = long " s; for (i = 0; i < 100000; i++) print "x = add x long 1"
    print "ret int rem x long 256"; print "end" }' > "$D/trap$n.om"
  echo 101 > "$D/trap$n.want"
done
# unroll57k / unrolltrap: 64 x 64 unrolled copies of 14 signed adds, 57,344 trap sites written by unrolled
# bodies (islands between their lines). From 5: 57349 mod 256 = 5. From 50,000 below the largest long:
# the 50,001st add overflows, trap 1, exit 101.
for v in 57k:5:5 trap:9223372036854725807:101; do
  n=${v%%:*}; r=${v#*:}; s=${r%%:*}; w=${r#*:}
  awk -v s=$s 'BEGIN { print "om2"; print "fn main to int"; print "x = long " s; print "for a ulong 64 unroll"; print "for b ulong 64 unroll"
    for (i = 0; i < 14; i++) print "x = add x long 1"; print "end"; print "end"; print "ret int rem x long 256"; print "end" }' > "$D/unroll$n.om"
  echo $w > "$D/unroll$n.want"
done
# fns50k: 50,000 functions; main calls the first and the last: 0 + 49999, mod 256 = 79.
awk 'BEGIN { for (i = 0; i < 50000; i++) printf "fn q%d to ulong\nret %d\nend\n", i, i
  print "fn main to int"; print "a = q0"; print "b = q49999"; print "ret int rem add a b 256"; print "end" }' > "$D/fns50k.om"
echo 79 > "$D/fns50k.want"
# nest5000: blocks nested 5000 deep (the old block stack held 512); the innermost returns 9.
awk 'BEGIN { print "fn main to int"; print "x = ulong 1"; for (i = 0; i < 5000; i++) print "if eq x 1"
  print "ret 9"; for (i = 0; i < 5000; i++) print "end"; print "ret 0"; print "end" }' > "$D/nest5000.om"
echo 9 > "$D/nest5000.want"
# breaks3000: 3000 loops in one function, each left by a break (the old break list held 1024 per
# function); every loop body runs once and x counts them: 3000 mod 256 = 184.
awk 'BEGIN { print "fn main to int"; print "x = ulong 0"; for (i = 0; i < 3000; i++) { print "while true"; print "x = add x 1"; print "break"; print "end" }
  print "ret int rem x 256"; print "end" }' > "$D/breaks3000.om"
echo 184 > "$D/breaks3000.want"
# value30000: a value nested 30000 deep (the old limit was 1024): 30000 conversions of y, which is 7.
awk 'BEGIN { print "fn main to int"; print "y = ulong 7"; printf "x = "; for (i = 0; i < 30000; i++) printf "ulong "
  print "y"; print "ret int rem x 256"; print "end" }' > "$D/value30000.om"
echo 7 > "$D/value30000.want"
# callnest10000: calls nested 10000 deep in one value: inc applied 10000 times to 0, mod 256 = 16.
awk 'BEGIN { print "fn inc a ulong to ulong"; print "ret add a 1"; print "end"; print "fn main to int"; print "y = ulong 0"
  printf "x = "; for (i = 0; i < 10000; i++) printf "inc "; print "y"; print "ret int rem x 256"; print "end" }' > "$D/callnest10000.om"
echo 16 > "$D/callnest10000.want"
# longnames20k: 20,000 distinct names of 9..63 bytes (the old long-name table held 4096): 5 + 7 = 12.
awk 'BEGIN { for (i = 1; i <= 20000; i++) printf "global long_global_name_%05d uint 1\n", i
  print "fn main to int"; print "put long_global_name_00001 0 uint 5"; print "put long_global_name_20000 0 uint 7"
  print "ret int add get long_global_name_00001 0 get long_global_name_20000 0"; print "end" }' > "$D/longnames20k.om"
echo 12 > "$D/longnames20k.want"
# in64m: a 64 MiB input (the old input buffer held 8 MiB): note lines, then a program giving 42.
awk 'BEGIN { p = "note "; for (i = 0; i < 94; i++) p = p "p"; n = int((64 * 1048576 - 47) / 100)
  for (i = 0; i < n; i++) print p; print "fn main to int"; print "x = int 41"; print "x = add x 1"; print "ret x"; print "end" }' > "$D/in64m.om"
echo 42 > "$D/in64m.want"
