#!/bin/sh
# Experimental scalar IR checkpoint; not the completed R6 gate.
# Requires C-built omegese/omega_emit/checker2 as comparison oracles only.
set -eu
cd "$(dirname "$0")/../.."
B=build/seed/ir
mkdir -p "$B"
fail() { printf 'FAIL %s\n' "$*"; exit 1; }
seed/rung4/om4.bin < seed/omc/omc.om > "$B/stage1"
chmod +x "$B/stage1"
"$B/stage1" < seed/omc/omc.om > "$B/stage2"
chmod +x "$B/stage2"
"$B/stage2" < seed/omc/omc.om > "$B/stage3"
cmp "$B/stage1" "$B/stage2"
cmp "$B/stage2" "$B/stage3"
echo "PASS fixpoint $(sha256sum "$B/stage3")"
n=0
for f in tests/one_layer/omegese/dev/*.omegese; do
 id=$(basename "$f" .omegese)
 build/omegese/omegese emit "$f" "$B/$id.json"
 build/omega_emit/omega_emit emit "$B/$id.json" "$B/$id.oracle"
 { printf 'ir\n'; cat "$f"; } > "$B/$id.input"
 timeout 5 "$B/stage2" < "$B/$id.input" > "$B/$id.got"
 cmp "$B/$id.oracle" "$B/$id.got" || fail "$id byte mismatch"
 build/checker2/checker2 check "$B/$id.got" > "$B/$id.check"
 grep -q '^checker2=ACCEPT ' "$B/$id.check" || fail "$id checker refusal"
 echo "PASS $id identical; checker2 ACCEPT"
 n=$((n+1))
done
[ "$n" = 10 ] || fail "ran $n expected 10"
# Exercise the result comparison: change the arithmetic operation while preserving a valid program.
sed 's/ret mul a b/ret add a b/' tests/one_layer/omegese/dev/dev05.omegese > "$B/mut.om"
{ printf 'ir\n'; cat "$B/mut.om"; } > "$B/mut.input"
timeout 5 "$B/stage2" < "$B/mut.input" > "$B/mut.ir"
if cmp -s "$B/mut.ir" "$B/dev05.oracle"; then fail 'mutant did not change IR'; fi
echo 'PASS mul-to-add mutant differs'
# IR mode must refuse what it cannot lower, never skip a declaration silently.
ir_refuse() { # name expected-error source
    printf '%s\n' "$3" > "$B/$1.om"
    set +e
    timeout 5 "$B/stage2" < "$B/$1.om" > "$B/$1.out" 2> "$B/$1.err"
    crc=$?
    set -e
    [ "$crc" = "$2" ] || fail "$1: exit $crc, wanted $2"
    echo "PASS $1 refused $2"
}
ir_refuse global_decl 9 'ir
global g uchar 4
fn main to int
ret 0
end'
ir_refuse text_decl 9 'ir
text t "x"
fn main to int
ret 0
end'
# Float words are accepted (wire version 7). The cases are the float section below.
ir_refuse continue_use 3 'ir
fn main to int
continue
end'
# Contract lines are not IR v1 statements: refuse with 30, never read them as a local (#791).
ir_refuse requires_line 30 'ir
fn f x uint to uint
requires lt x 10
ret x
end'
ir_refuse ensures_line 30 'ir
fn f x uint to uint
ensures lt x 10
ret x
end'
ir_refuse invariant_line 30 'ir
fn f x uint to uint
invariant lt x 10
ret x
end'
# Integer constants fold to the IR of their literal. Float constants fold in the float section.
printf 'ir\nconst N uint 5\nfn f to uint\nret N\nend\n' > "$B/c1.om"
printf 'ir\nfn f to uint\nret uint 5\nend\n' > "$B/c2.om"
timeout 5 "$B/stage2" < "$B/c1.om" > "$B/c1.ir"
timeout 5 "$B/stage2" < "$B/c2.om" > "$B/c2.ir"
cmp -s "$B/c1.ir" "$B/c2.ir" || fail 'integer constant IR differs from its literal'
echo 'PASS integer constant folds to the literal IR'
# Constants in trap, bound and for positions fold to the same IR as literals.
ir_fold() { # name const-source literal-source
    printf '%b\n' "$2" > "$B/$1c.om"
    printf '%b\n' "$3" > "$B/$1l.om"
    timeout 5 "$B/stage2" < "$B/$1c.om" > "$B/$1c.ir"
    timeout 5 "$B/stage2" < "$B/$1l.om" > "$B/$1l.ir"
    cmp -s "$B/$1c.ir" "$B/$1l.ir" || fail "$1 constant IR differs from its literal"
    echo "PASS $1 constant folds to the literal IR"
}
ir_fold trap_const 'ir\nconst T uint 2\nfn f to uint\ntrap T\nend' 'ir\nfn f to uint\ntrap 2\nend'
ir_fold bound_const 'ir\nconst B ulong 3\nfn f to uint\nx = uint 0\nwhile lt x uint 2 bound B\nx = add x uint 1\nend\nret x\nend' 'ir\nfn f to uint\nx = uint 0\nwhile lt x uint 2 bound 3\nx = add x uint 1\nend\nret x\nend'
ir_fold for_const 'ir\nconst K ulong 4\nfn f to uint\nx = uint 0\nfor i ulong K\nx = add x uint 1\nend\nret x\nend' 'ir\nfn f to uint\nx = uint 0\nfor i ulong 4\nx = add x uint 1\nend\nret x\nend'
# for ... bound N: a constant N folds to its literal; an explicit bound 1000000 is the unbounded default.
ir_fold for_bound_const 'ir\nconst B ulong 3\nfn f a uint to uint\nx = uint 0\nfor i uint a bound B\nx = add x uint 1\nend\nret x\nend' 'ir\nfn f a uint to uint\nx = uint 0\nfor i uint a bound 3\nx = add x uint 1\nend\nret x\nend'
ir_fold for_bound_default 'ir\nfn f a uint to uint\nx = uint 0\nfor i uint a bound 1000000\nx = add x uint 1\nend\nret x\nend' 'ir\nfn f a uint to uint\nx = uint 0\nfor i uint a\nx = add x uint 1\nend\nret x\nend'
ir_refuse for_bound_zero 8 'ir
fn f a uint to uint
for i uint a bound 0
end
ret a
end'
ir_refuse for_bound_over 8 'ir
fn f a uint to uint
for i uint 3 bound 9223372036854775808
end
ret a
end'
# A number count with a bound gets the counter guard, which checker2 proves terminating.
printf 'ir\nfn f a uint to uint\ns = uint 0\nfor i uint 7 bound 5\ns = add s a\nend\nret s\nend\n' > "$B/forbn.om"
timeout 5 "$B/stage2" < "$B/forbn.om" > "$B/forbn.ir"
build/checker2/checker2 check "$B/forbn.ir" > "$B/forbn.check"
grep -q '^checker2=ACCEPT ' "$B/forbn.check" || fail 'for_num_bound checker refusal'
echo 'PASS for_num_bound guarded; checker2 ACCEPT'
# IR bound range = the C oracle's (omegese.c, 1..1000000) = the guard range checker2 proves
# (c2_check.c "loop bounds"): bound 1000000 is emitted and accepted, bound 1000001 is error 8.
printf 'fn f a uint to uint\nx = uint 0\nwhile lt x a bound 1000000\nx = add x uint 1\nend\nret x\nend\n' > "$B/wbmax.omegese"
build/omegese/omegese emit "$B/wbmax.omegese" "$B/wbmax.json" > /dev/null
build/omega_emit/omega_emit emit "$B/wbmax.json" "$B/wbmax.oracle" > /dev/null
{ printf 'ir\n'; cat "$B/wbmax.omegese"; } > "$B/wbmax.om"
timeout 5 "$B/stage2" < "$B/wbmax.om" > "$B/wbmax.ir"
cmp -s "$B/wbmax.oracle" "$B/wbmax.ir" || fail 'while_bound_max differs from the oracle'
build/checker2/checker2 check "$B/wbmax.ir" > "$B/wbmax.check"
grep -q '^checker2=ACCEPT ' "$B/wbmax.check" || fail 'while_bound_max checker refusal'
echo 'PASS while_bound_max identical; checker2 ACCEPT'
printf 'fn f a uint to uint\nx = uint 0\nwhile lt x a bound 1000001\nx = add x uint 1\nend\nret x\nend\n' > "$B/wbover.omegese"
if build/omegese/omegese emit "$B/wbover.omegese" "$B/wbover.json" > /dev/null 2>&1; then fail 'oracle accepted while bound 1000001'; fi
ir_refuse while_bound_over 8 'ir
fn f a uint to uint
x = uint 0
while lt x a bound 1000001
x = add x uint 1
end
ret x
end'
printf 'ir\nfn f a uint to uint\nx = uint 0\nfor i uint a bound 1000000\nx = add x uint 1\nend\nret x\nend\n' > "$B/fbmax.om"
timeout 5 "$B/stage2" < "$B/fbmax.om" > "$B/fbmax.ir"
build/checker2/checker2 check "$B/fbmax.ir" > "$B/fbmax.check"
grep -q '^checker2=ACCEPT ' "$B/fbmax.check" || fail 'for_bound_max checker refusal'
echo 'PASS for_bound_max guarded; checker2 ACCEPT'
ir_refuse for_bound_c2 8 'ir
fn f a uint to uint
x = uint 0
for i uint a bound 1000001
x = add x uint 1
end
ret x
end'
# IR count range = the C oracle's (omegese.c for_line, 0..1000000), so an unguarded loop over a number never
# counts past what checker2 proves: count 1000000 is emitted identical to the oracle and accepted; 1000001 and a
# minus sign (-1, -0) are refused by both; an integer constant count is held to the same range (error 8).
printf 'fn f to ulong\ns = ulong 0\nfor i ulong 1000000\ns = add s i\nend\nret s\nend\n' > "$B/fcmax.omegese"
build/omegese/omegese emit "$B/fcmax.omegese" "$B/fcmax.json" > /dev/null
build/omega_emit/omega_emit emit "$B/fcmax.json" "$B/fcmax.oracle" > /dev/null
{ printf 'ir\n'; cat "$B/fcmax.omegese"; } > "$B/fcmax.om"
timeout 5 "$B/stage2" < "$B/fcmax.om" > "$B/fcmax.ir"
cmp -s "$B/fcmax.oracle" "$B/fcmax.ir" || fail 'for_count_max differs from the oracle'
build/checker2/checker2 check "$B/fcmax.ir" > "$B/fcmax.check"
grep -q '^checker2=ACCEPT ' "$B/fcmax.check" || fail 'for_count_max checker refusal'
echo 'PASS for_count_max identical; checker2 ACCEPT'
for v in 1000001 -1 -0; do
    printf 'fn f to long\ns = long 0\nfor i long %s\ns = add s i\nend\nret s\nend\n' "$v" > "$B/fcbad.omegese"
    if build/omegese/omegese emit "$B/fcbad.omegese" "$B/fcbad.json" > /dev/null 2>&1; then fail "oracle accepted for count $v"; fi
done
ir_refuse for_count_over 8 'ir
fn f to ulong
s = ulong 0
for i ulong 1000001
s = add s i
end
ret s
end'
ir_refuse for_count_neg 8 'ir
fn f to long
s = long 0
for i long -1
s = add s i
end
ret s
end'
ir_refuse for_count_negzero 8 'ir
fn f to long
s = long 0
for i long -0
s = add s i
end
ret s
end'
ir_refuse for_count_const_over 8 'ir
const K ulong 1000001
fn f to ulong
s = ulong 0
for i ulong K
s = add s i
end
ret s
end'
ir_refuse call_self 3 'ir
fn f to uint
ret f
end'
ir_refuse call_forward 3 'ir
fn f to uint
ret g
end
fn g to uint
ret uint 1
end'
ir_refuse call_nonvoid_stmt 7 'ir
fn inc a uint to uint
ret add a uint 1
end
fn f to uint
inc uint 4
ret uint 2
end'
ir_refuse call_void_value 7 'ir
fn sink a uint to void
ret
end
fn f to uint
x = sink uint 1
ret uint 2
end'
ir_refuse call_arg_type 7 'ir
fn inc a uchar to uint
ret uint 1
end
fn f to uint
ret inc uint 4
end'
ir_refuse call_arg_local 7 'ir
fn inc a uchar to uint
ret uint 1
end
fn f to uint
x = uint 4
ret inc x
end'
ir_refuse call_result_type 7 'ir
fn inc a uint to uint
ret add a uint 1
end
fn f to uchar
ret inc uint 4
end'
ir_refuse break_outside 9 'ir
fn f to uint
break
end'
ir_refuse after_break 17 'ir
fn f to uint
while lt uint 1 uint 2 bound 3
break
ret uint 0
end
ret uint 0
end'
ir_refuse bin_type_local 7 'ir
fn f to uint
s = uint 1
i = ulong 2
x = add s i
ret uint 0
end'
ir_refuse bin_bool 7 'ir
fn f to uint
x = add bool true true
ret uint 0
end'
ir_refuse bin_shift_bool 7 'ir
fn f to ulong
ret shl ulong 1 true
end'
ir_refuse bin_result_type 7 'ir
fn f to uchar
ret add uint 1 uint 2
end'
ir_refuse cmp_assign_type 7 'ir
fn f to uint
x = uint 1
x = eq x x
ret x
end'
ir_refuse bool_result 7 'ir
fn f to uint
ret true
end'
ir_refuse neg_bool 7 'ir
fn f to uint
ret neg true
end'
ir_refuse cond_type 7 'ir
fn f to uint
x = uint 1
if x
ret 1
end
ret 0
end'
ir_refuse ret_type_local 7 'ir
fn f to uchar
x = uint 1
ret x
end'
ir_refuse neg_bool_local 7 'ir
fn f to uint
x = neg true
ret uint 0
end'
# Validation: every word of a line is read, names follow scope, and what IR v1 cannot lower is refused.
ir_refuse trailing_value 5 'ir
fn f a uint to uint
x = add a 1 7
ret x
end'
ir_refuse untyped_new 11 'ir
fn f a uint to uint
foo 1 a 0 1
ret a
end'
ir_refuse missing_operand 4 'ir
fn f a uint to uint
x = add a
ret x
end'
ir_refuse bare_neg 11 'ir
fn f to ulong
ret neg 5
end'
ir_refuse end_trailing 5 'ir
fn f a uint to uint
if eq a 0
ret 1
end a
ret a
end'
ir_refuse while_trailing 5 'ir
fn f to uint
x = uint 0
while lt x uint 3 x
x = add x uint 1
end
ret x
end'
ir_refuse ret_missing 4 'ir
fn f to uint
ret
end'
ir_refuse ret_void_value 5 'ir
fn f to void
ret uint 1
end'
ir_refuse keyword_name 16 'ir
fn f to uint
add = uint 1
ret uint 0
end'
ir_refuse stmt_number 16 'ir
fn f to uint
5
ret uint 0
end'
ir_refuse shadow_param_for 10 'ir
fn f n uint to uint
for n uint 3
end
ret n
end'
ir_refuse shadow_nested_for 10 'ir
fn f n uint to uint
s = uint 0
for i uint n
for i uint 2
s = add s i
end
end
ret s
end'
ir_refuse param_dup 10 'ir
fn f a uint a uint to uint
ret a
end'
ir_refuse param_fn_name 10 'ir
fn g to uint
ret uint 1
end
fn f g uint to uint
ret g
end'
ir_refuse param_self_name 10 'ir
fn f f uint to uint
ret f
end'
ir_refuse scope_if 3 'ir
fn f n uint to uint
if gt n 0
y = uint 3
end
ret y
end'
ir_refuse scope_else 3 'ir
fn f n uint to uint
if gt n 0
y = uint 3
ret y
else
ret y
end
ret n
end'
ir_refuse scope_for 3 'ir
fn f to uint
for i uint 3
end
ret i
end'
ir_refuse fallthrough 18 'ir
fn f a uint to uint
if eq a 0
ret 1
end
end'
ir_refuse float_ret 7 'ir
fn f a uint to f64
ret a
end'
ir_refuse else_twice 15 'ir
fn f a uint to uint
if eq a 0
ret 1
else
ret 2
else
ret 3
end
end'
ir_refuse else_outside 15 'ir
fn f to uint
else
ret uint 0
end'
ir_refuse eof_in_fn 15 'ir
fn f to uint
ret uint 0'
ir_refuse range_typed 8 'ir
fn f to uchar
ret 300
end'
ir_refuse range_bare 8 'ir
fn f a uchar to uchar
ret add a 300
end'
ir_refuse range_bare_left 8 'ir
fn f a uchar to uchar
ret sub 256 a
end'
ir_refuse range_negative 8 'ir
fn f to uint
ret uint -1
end'
# Locals, parameters and for counters are at most 8 bytes (13, as native); a word over 8 bytes is never a
ir_refuse cast_lit_range 8 'ir
fn f to uchar
ret uchar 256
end'
ir_refuse cast_opnd_range 8 'ir
fn f c uchar to ulong
ret ulong sub c 300
end'
ir_refuse cast_signed_range 8 'ir
fn f c byte to long
ret long sub c -129
end'
ir_refuse cast_bool_num 9 'ir
fn f c uchar to bool
ret bool c
end'
ir_refuse cast_num_bool 9 'ir
fn f b bool to ulong
ret ulong b
end'
ir_refuse cast_cmp_bool 9 'ir
fn f a uint b uint to ulong
ret ulong eq a b
end'
ir_refuse long_local 13 'ir
fn f n uint to uint
counterxy = add n uint 1
ret counterxy
end'
ir_refuse long_param 13 'ir
fn f counterxy uint to uint
ret counterxy
end'
ir_refuse long_for 13 'ir
fn f to uint
for counterxy uint 3
end
ret uint 0
end'
ir_refuse long_prefix_ref 3 'ir
fn f n uint to uint
counterx = add n uint 1
ret counterxy
end'
# Same IR from two spellings: a note after the path ended is skipped like any note.
ir_same() { # name source-a source-b
    printf '%b\n' "$2" > "$B/$1a.om"
    printf '%b\n' "$3" > "$B/$1b.om"
    timeout 5 "$B/stage2" < "$B/$1a.om" > "$B/$1a.ir"
    timeout 5 "$B/stage2" < "$B/$1b.om" > "$B/$1b.ir"
    cmp -s "$B/$1a.ir" "$B/$1b.ir" || fail "$1 IR differs between the two spellings"
    echo "PASS $1 same IR"
}
ir_same note_dead 'ir\nfn f to uint\nret uint 1\nnote after the path ended\nend' 'ir\nfn f to uint\nret uint 1\nend'

# Multi-function units with calls: byte-identical to the C oracle and checker2 ACCEPT.
ir_multi() { # name source
    printf '%b\n' "$2" > "$B/$1.omegese"
    build/omegese/omegese emit "$B/$1.omegese" "$B/$1.json"
    build/omega_emit/omega_emit emit "$B/$1.json" "$B/$1.oracle"
    { printf 'ir\n'; cat "$B/$1.omegese"; } > "$B/$1.input"
    timeout 5 "$B/stage2" < "$B/$1.input" > "$B/$1.got"
    cmp -s "$B/$1.oracle" "$B/$1.got" || fail "$1 multi-function IR differs"
    build/checker2/checker2 check "$B/$1.got" > "$B/$1.check"
    grep -q '^checker2=ACCEPT ' "$B/$1.check" || fail "$1 checker refusal"
    echo "PASS $1 IR identical; checker2 ACCEPT"
}
ir_multi call_value 'fn inc a uint to uint\nret add a uint 1\nend\nfn f to uint\nret inc uint 4\nend'
ir_multi call_void 'fn sink a uint to void\nret\nend\nfn f to uint\nsink uint 1\nret uint 2\nend'
ir_multi call_zero 'fn z to uint\nret uint 1\nend\nfn f to uint\nret z\nend'
ir_multi call_two 'fn add2 a uint b uint to uint\nret add a b\nend\nfn f to uint\nret add2 uint 3 uint 4\nend'
ir_multi call_long 'fn increment_one a uint to uint\nret add a uint 1\nend\nfn f to uint\nret increment_one uint 4\nend'
ir_multi call_nested 'fn inc a uint to uint\nret add a uint 1\nend\nfn f to uint\nret inc inc uint 4\nend'
ir_multi call_expr 'fn inc a uint to uint\nret add a uint 1\nend\nfn f to uint\nret add inc uint 1 inc uint 2\nend'
ir_multi call_loop 'fn add1 a uint to uint\nret add a uint 1\nend\nfn f to uint\nx = uint 0\nwhile lt x uint 3 bound 8\nx = add1 x\nend\nret x\nend'
ir_multi call_six 'fn sum6 a uint b uint c uint d uint e uint f uint to uint\nret add add add add add a b c d e f\nend\nfn f to uint\nret sum6 uint 1 uint 2 uint 3 uint 4 uint 5 uint 6\nend'
ir_multi break_while 'fn f to uint\nx = uint 0\nwhile lt x uint 10 bound 100\nif eq x uint 3\nbreak\nend\nx = add x uint 1\nend\nret x\nend'
ir_multi break_for 'fn f to uint\ns = uint 0\nfor i ulong 10\nif eq i ulong 3\nbreak\nend\ns = add s uint i\nend\nret s\nend'
ir_multi break_nested 'fn f to uint\nx = uint 0\nwhile lt x uint 5 bound 20\ny = uint 0\nwhile lt y uint 5 bound 20\nif eq y uint 2\nbreak\nend\ny = add y uint 1\nend\nx = add x y\nend\nret x\nend'
ir_multi shift_mixed 'fn f to ulong\nret shl ulong 1 uint 3\nend'
ir_multi cmp_assign 'fn f to bool\nx = lt uint 1 uint 2\nx = eq uint 1 uint 1\nret x\nend'
ir_multi cast_ret 'fn f to uchar\nret uchar uint 1\nend'
ir_multi cast_wide 'fn f c uchar to ulong\nret ulong sub c 48\nend'
ir_multi cast_left 'fn f c uchar to ulong\nret ulong sub 255 c\nend'
ir_multi cast_u2s 'fn f c uchar to long\nret long sub c 48\nend'
ir_multi cast_s2s 'fn f c byte to long\nret long add c 1\nend'
ir_multi cast_s2u 'fn f c byte to ulong\nret ulong sub c 1\nend'
ir_multi cast_narrow 'fn f x ulong to uchar\nret uchar sub x 1\nend'
ir_multi cast_narrow_s 'fn f x long to byte\nret byte add x 1\nend'
ir_multi cast_same_ty 'fn f x uint to uint\nret uint add x 1\nend'
ir_multi cast_un 'fn f c uchar to ulong\nret ulong not c\nend'
ir_multi cast_call 'fn g a uchar to uchar\nret add a 1\nend\nfn f c uchar to ulong\nret ulong g c\nend'
ir_multi cast_assign 'fn f c uchar to ulong\nx = ulong sub c 48\nret x\nend'
ir_multi cast_nested 'fn f c uchar to ulong\nret ulong uint mul c 2\nend'
ir_multi cast_arg 'fn g a ulong to ulong\nret add a 1\nend\nfn f c uchar to ulong\nret g ulong sub c 48\nend'
ir_multi cast_lit_var 'fn f to uint\nx = uint 5\nret uint x\nend'
ir_multi cast_nest_var 'fn f x uint to uint\nret uint uint x\nend'
ir_multi cast_same_assign 'fn f x uint to uint\ny = uint x\nret y\nend'
ir_multi cast_same_param 'fn f x uint to uint\nret uint x\nend'
ir_multi cast_neg_lit 'fn f c byte to long\nret long sub c -128\nend'
ir_multi cast_ulong_max 'fn f to ulong\nret ulong 18446744073709551615\nend'
ir_multi cast_cond 'fn f c uchar to uint\nif lt ulong c 10\nret 1\nend\nret 0\nend'
# A same-type cast of an integer or bool constant is the constant itself (the oracle's konst rule), not a mov.
ir_multi cast_same_konst 'fn f to uint\nret uint uint 5\nend'
ir_multi cast_same_bool 'fn f to bool\nret bool true\nend'
ir_multi cast_same_arg 'fn g a ulong to ulong\nret add a 1\nend\nfn f to ulong\nret g ulong ulong 7\nend'
ir_multi bool_and 'fn f a bool b bool to bool\nret and a b\nend'
ir_multi bool_or 'fn f a bool b bool to bool\nret or a b\nend'
ir_multi bool_xor 'fn f a bool b bool to bool\nret xor a b\nend'
ir_multi void_fall 'fn sink a uint to void\nend\nfn f to uint\nsink uint 1\nret uint 2\nend'
ir_multi for_reuse 'fn f to uint\ns = uint 0\nfor i uint 3\ns = add s i\nend\nfor i uint 2\ns = add s i\nend\nret s\nend'
ir_multi for_value 'fn f n uint to uint\ns = uint 0\nfor i uint n\ns = add s i\nend\nret s\nend'
ir_multi for_value_expr 'fn f n uchar to uint\ns = uint 0\nfor i uchar add n uchar 1\nif eq i uchar 3\nbreak\nend\ns = add s uint 1\nend\nret s\nend'
ir_multi scope_reuse 'fn f a uint to uint\nif gt a 1\ny = add a 1\nret y\nend\ny = add a 2\nret y\nend'
ir_multi call_long_prefix 'fn increment_one a uint to uint\nret add a uint 1\nend\nfn increment_two a uint to uint\nret add a uint 2\nend\nfn f to uint\nret increment_two uint 4\nend'
# A contract word followed by = is an assignment to a local of that name, as in the C oracle (only the clause form is error 30).
ir_multi ensures_assign 'fn f to ulong\nensures = ulong 1\nret ensures\nend'
ir_multi requires_assign 'fn f to ulong\nx = ulong 1\nrequires = add x x\nrequires = add requires x\nret requires\nend'
# Random two-function programs with a call: differential against the oracle.
rm -f "$B"/fz*
awk -v dir="$B" 'BEGIN{
    M = 65536;
    split("add sub mul xor and or", O, " ");
    split("eq ne lt le gt ge", C, " ");
    for (p = 0; p < 30; p++) {
        s = 1000 + p * 37;
        s = (s * 25173 + 13849) % M; o1 = O[1 + (s % 6)];
        s = (s * 25173 + 13849) % M; o2 = O[1 + (s % 6)];
        s = (s * 25173 + 13849) % M; o3 = O[1 + (s % 6)];
        s = (s * 25173 + 13849) % M; cm = C[1 + (s % 6)];
        s = (s * 25173 + 13849) % M; n1 = 1 + (s % 9);
        s = (s * 25173 + 13849) % M; n2 = 1 + (s % 9);
        s = (s * 25173 + 13849) % M; n3 = 1 + (s % 9);
        s = (s * 25173 + 13849) % M; n4 = 1 + (s % 9);
        s = (s * 25173 + 13849) % M; o4 = O[1 + (s % 6)];
        s = (s * 25173 + 13849) % M; n5 = 1 + (s % 9);
        f = sprintf("%s/fz%02d.omegese", dir, p);
        print "fn h a ulong b ulong to ulong" > f;
        print "x = " o1 " a b" > f;
        print "y = " o2 " x " n1 > f;
        print "if " cm " y " n2 > f;
        print "y = " o3 " y " n3 > f;
        print "end" > f;
        print "ret y" > f;
        print "end" > f;
        print "fn f to ulong" > f;
        print "p = ulong " n4 > f;
        print "q = ulong " n4 > f;
        print "r = h p q" > f;
        print "z = " o4 " r " n5 > f;
        print "ret z" > f;
        print "end" > f;
        close(f);
    }
}'
fzn=0
for f in "$B"/fz*.omegese; do
    fzn=$((fzn + 1))
    b=${f%.omegese}
    build/omegese/omegese emit "$f" "$b.json" > /dev/null
    build/omega_emit/omega_emit emit "$b.json" "$b.oracle" > /dev/null
    { printf 'ir\n'; cat "$f"; } > "$b.input"
    timeout 5 "$B/stage2" < "$b.input" > "$b.got"
    cmp -s "$b.oracle" "$b.got" || fail "fuzz $b differs from the oracle"
    build/checker2/checker2 check "$b.got" > "$b.check"
    grep -q '^checker2=ACCEPT ' "$b.check" || fail "fuzz $b checker refusal"
done
[ "$fzn" = 30 ] || fail "fuzz ran $fzn of 30 programs"
echo "PASS 30 random two-function call units identical; checker2 ACCEPT"
# Integer-only IR stays version 1. A float unit is version 7 and runs through irwasm.
python3 - "$B/c2.ir" <<'PY'
import sys
b = open(sys.argv[1], "rb").read()
if b[7] != 1:
    raise SystemExit("integer unit version %s" % b[7])
PY
echo 'PASS integer unit stays version 1'
command -v node >/dev/null || fail 'float section needs node'
nice -n 19 "$B/stage2" < seed/wasm/irwasm.om > "$B/irwasm"
chmod +x "$B/irwasm"
ir_bool() { # name expr expect
    printf 'ir\nfn f to bool\nret %s\nend\n' "$2" > "$B/$1.om"
    printf 'fn main to int\nif %s\nret 1\nend\nret 0\nend\n' "$2" > "$B/$1.nat.om"
    timeout 10 "$B/stage2" < "$B/$1.om" > "$B/$1.ir" 2> "$B/$1.err" || fail "$1 compile $(cat "$B/$1.err")"
    python3 - "$B/$1.ir" <<'PY'
import sys
b = open(sys.argv[1], "rb").read()
if b[7] != 7:
    raise SystemExit("version %s" % b[7])
PY
    timeout 10 "$B/irwasm" < "$B/$1.ir" > "$B/$1.wasm" 2> "$B/$1.wasm.err" || fail "$1 irwasm $(cat "$B/$1.wasm.err")"
    got=$(node -e 'const fs=require("fs"); const m=new WebAssembly.Module(fs.readFileSync(process.argv[1])); const i=new WebAssembly.Instance(m); process.stdout.write(String(i.exports.f()));' "$B/$1.wasm") || fail "$1 wasm run"
    [ "$got" = "$3" ] || fail "$1 wasm $got wanted $3"
    timeout 10 "$B/stage2" < "$B/$1.nat.om" > "$B/$1.nat" 2> "$B/$1.nat.err" || fail "$1 native compile $(cat "$B/$1.nat.err")"
    chmod +x "$B/$1.nat"
    set +e
    "$B/$1.nat" >/dev/null
    nrc=$?
    set -e
    [ "$nrc" = "$3" ] || fail "$1 native $nrc wanted $3"
    echo "PASS $1 wasm=$got native=$nrc"
}
ir_bool f_add 'eq add f64 1.5 f64 2.5 f64 4.0' 1
ir_bool f_nan_ne 'ne div f64 0.0 f64 0.0 f64 0.0' 1
ir_bool f_nan_eq 'eq div f64 0.0 f64 0.0 f64 0.0' 0
ir_bool f_negzero 'eq f64 -0.0 f64 0.0' 1
ir_bool f_inf 'gt div f64 1.0 f64 0.0 f64 1.0' 1
ir_bool f_neginf 'lt div f64 -1.0 f64 0.0 f64 0.0' 1
ir_bool f_neg 'eq neg f64 1.5 f64 -1.5' 1
ir_bool f_round 'ne add f64 0.1 f64 0.2 f64 0.3' 1
ir_bool f_cast_int 'eq f64 uint 3 f64 3.0' 1
ir_bool f_trunc 'eq uint f64 3.9 uint 3' 1
ir_bool f_promote 'eq f64 f32 1.5f32 f64 1.5' 1
ir_bool f_demote 'eq f32 f64 1.5 f32 1.5f32' 1
printf 'ir\nfn g a f64 to f64\nret add a f64 1.0\nend\nfn f to bool\nret eq g f64 2.0 f64 3.0\nend\n' > "$B/f_call.om"
printf 'fn g a f64 to f64\nret add a f64 1.0\nend\nfn main to int\nif eq g f64 2.0 f64 3.0\nret 1\nend\nret 0\nend\n' > "$B/f_call.nat.om"
timeout 10 "$B/stage2" < "$B/f_call.om" > "$B/f_call.ir"
timeout 10 "$B/irwasm" < "$B/f_call.ir" > "$B/f_call.wasm"
got=$(node -e 'const fs=require("fs"); const m=new WebAssembly.Module(fs.readFileSync(process.argv[1])); const i=new WebAssembly.Instance(m); process.stdout.write(String(i.exports.f()));' "$B/f_call.wasm")
[ "$got" = 1 ] || fail "f_call wasm $got"
timeout 10 "$B/stage2" < "$B/f_call.nat.om" > "$B/f_call.nat"
chmod +x "$B/f_call.nat"
set +e; "$B/f_call.nat" >/dev/null; nrc=$?; set -e
[ "$nrc" = 1 ] || fail "f_call native $nrc"
echo 'PASS f_call wasm=1 native=1'
printf 'ir\nconst A f64 1.5\nfn f to f64\nret A\nend\n' > "$B/f_const.om"
printf 'ir\nfn f to f64\nret f64 1.5\nend\n' > "$B/f_const_lit.om"
timeout 10 "$B/stage2" < "$B/f_const.om" > "$B/f_const.ir"
timeout 10 "$B/stage2" < "$B/f_const_lit.om" > "$B/f_const_lit.ir"
cmp -s "$B/f_const.ir" "$B/f_const_lit.ir" || fail 'float constant IR differs from its literal'
echo 'PASS float constant folds to the literal IR'
printf 'ir\nfn f to f64\nret f64 1.0\nend\n' > "$B/f_one.om"
printf 'ir\nfn f to f64\nret f64 0.1\nend\n' > "$B/f_tenth.om"
printf 'ir\nfn f to f64\nret f64 -0.0\nend\n' > "$B/f_nzero.om"
timeout 10 "$B/stage2" < "$B/f_one.om" > "$B/f_one.ir"
timeout 10 "$B/stage2" < "$B/f_tenth.om" > "$B/f_tenth.ir"
timeout 10 "$B/stage2" < "$B/f_nzero.om" > "$B/f_nzero.ir"
python3 - "$B/f_one.ir" "$B/f_tenth.ir" "$B/f_nzero.ir" <<'PY'
import sys
pairs = [
    (sys.argv[1], bytes.fromhex("000000000000f03f"), "1.0"),
    (sys.argv[2], bytes.fromhex("9a9999999999b93f"), "0.1"),
    (sys.argv[3], bytes.fromhex("0000000000000080"), "-0.0"),
]
for path, needle, name in pairs:
    b = open(path, "rb").read()
    if b[7] != 7 or needle not in b:
        raise SystemExit("missing %s bits" % name)
PY
echo 'PASS f64 1.0 is 3ff0000000000000; 0.1 is 3fb999999999999a; -0.0 keeps the sign bit'
ir_refuse f_mix 7 'ir
fn f to f64
ret add f64 1.0 uint 1
end'
ir_refuse f_bool 9 'ir
fn f to f64
ret f64 true
end'
ir_refuse f_rem 7 'ir
fn f to f64
ret rem f64 1.0 f64 1.0
end'
ir_refuse f_bare 11 'ir
fn f to int
x = 1.0
ret 0
end'
ir_refuse f_intlit 7 'ir
fn f to f64
ret add f64 1.0 1
end'
ir_refuse f_for 7 'ir
fn f to int
for i f64 3
end
ret 0
end'
ir_refuse f_sqrt 3 'ir
fn f to f64
ret fsqrt f64 1.0
end'
ir_refuse f_fma 3 'ir
fn f to f64
ret fma f64 1.0 f64 2.0 f64 3.0
end'
ir_refuse f_suffix 7 'ir
fn f to f64
ret f64 1.0f32
end'
ir_refuse f_shl 7 'ir
fn f to f64
ret shl f64 1.0 f64 1.0
end'
ir_refuse f_not 7 'ir
fn f to f64
ret not f64 1.0
end'
ir_refuse f_const_int 16 'ir
const N f64 1
fn f to f64
ret N
end'
path_refuse() { # name ir-source native-source ir-exit native-exit
    printf '%s\n' "$2" > "$B/$1.om"
    printf '%s\n' "$3" > "$B/$1.nat.om"
    set +e
    timeout 10 "$B/stage2" < "$B/$1.om" > "$B/$1.out" 2> "$B/$1.err"
    irc=$?
    timeout 10 "$B/stage2" < "$B/$1.nat.om" > "$B/$1.nat" 2> "$B/$1.nat.err"
    nrc=$?
    set -e
    [ "$irc" = "$4" ] || fail "$1 ir exit $irc wanted $4 ($(cat "$B/$1.err"))"
    [ "$nrc" = "$5" ] || fail "$1 native exit $nrc wanted $5 ($(cat "$B/$1.nat.err"))"
    echo "PASS $1 ir=$irc native=$nrc"
}
path_refuse f_for_const 'ir
const N f64 1.0
fn main to int
for i uint N
end
ret 0
end' 'const N f64 1.0
fn main to int
for i uint N
end
ret 0
end' 7 7
path_refuse f_trap_const 'ir
const N f64 1.0
fn main to int
trap N
ret 0
end' 'const N f64 1.0
fn main to int
trap N
ret 0
end' 16 16
path_refuse f_while_const 'ir
const N f64 1.0
fn main to int
while bool 1 bound N
ret 0
end
end' 'const N f64 1.0
fn main to int
while bool 1 bound N
ret 0
end
end' 16 16
path_refuse f_fma_bare 'ir
fn main to f64
ret fma 1.0 2.0 3.0
end' 'fn main to f64
ret fma 1.0 2.0 3.0
end' 3 11
path_refuse f_fma_mix 'ir
fn main to f64
ret fma f64 1.0 uint 1 f64 2.0
end' 'fn main to f64
ret fma f64 1.0 uint 1 f64 2.0
end' 3 7
path_refuse f_fsqrt_bare 'ir
fn main to f64
ret fsqrt 1.0
end' 'fn main to f64
ret fsqrt 1.0
end' 3 11
agg_run() { # name expect ir-source native-source
    printf '%s\n' "$3" > "$B/$1.om"
    timeout 10 "$B/stage2" < "$B/$1.om" > "$B/$1.ir" 2> "$B/$1.err" || fail "$1 ir $(cat "$B/$1.err")"
    timeout 10 "$B/irwasm" < "$B/$1.ir" > "$B/$1.wasm" 2> "$B/$1.werr" || fail "$1 irwasm $(cat "$B/$1.werr")"
    got=$(node -e 'const fs=require("fs"); const m=new WebAssembly.Module(fs.readFileSync(process.argv[1])); const i=new WebAssembly.Instance(m); process.stdout.write(String(i.exports.f()));' "$B/$1.wasm") || fail "$1 wasm run"
    [ "$got" = "$2" ] || fail "$1 wasm $got wanted $2"
    printf '%s\n' "$4" > "$B/$1.nat.om"
    timeout 10 "$B/stage2" < "$B/$1.nat.om" > "$B/$1.nat" 2> "$B/$1.nat.err" || fail "$1 native $(cat "$B/$1.nat.err")"
    chmod +x "$B/$1.nat"
    set +e
    "$B/$1.nat" >/dev/null
    nrc=$?
    set -e
    [ "$nrc" = "$2" ] || fail "$1 native $nrc wanted $2"
    echo "PASS $1 wasm=$got native=$nrc"
}
agg_run a_idx 7 'ir
fn f to uint
a = new uint 4 0
put a 1 7
ret get a 1
end' 'fn main to uint
a = new uint 4 0
put a 1 7
ret get a 1
end'
agg_run a_nest 9 'ir
struct S a uint 3 end
fn f to uint
s = new S 1
put s a 2 9
ret get s a 2
end' 'struct S a uint 3 end
fn main to uint
s = new S 1
put s a 2 9
ret get s a 2
end'
agg_run s_field 4 'ir
struct S a uint b uint end
fn f to uint
s = new S 3 4
put s a 9
ret get s b
end' 'struct S a uint b uint end
fn main to uint
s = new S 3 4
put s a 9
ret get s b
end'
agg_run s_copy 3 'ir
struct S a uint b uint end
fn f to uint
s = new S 3 4
t = new S 3 4
put s a 9
ret get t a
end' 'struct S a uint b uint end
fn main to uint
s = new S 3 4
t = new S 3 4
put s a 9
ret get t a
end'
agg_run s_flt 2 'ir
struct S a f64 b uint end
fn f to uint
s = new S 1.5 2
ret get s b
end' 'struct S a f64 b uint end
fn main to uint
s = new S 1.5 2
ret get s b
end'
agg_run s_feq 1 'ir
struct S a f64 b uint end
fn f to bool
s = new S 1.5 2
ret eq get s a f64 1.5
end' 'struct S a f64 b uint end
fn main to int
s = new S 1.5 2
if eq get s a f64 1.5
ret 1
end
ret 0
end'
printf 'ir\nfn f i uint to uint\na = new uint 4 0\nput a 1 6\nret get a i\nend\n' > "$B/a_oob.om"
timeout 10 "$B/stage2" < "$B/a_oob.om" > "$B/a_oob.ir" 2> "$B/a_oob.err" || fail "a_oob ir $(cat "$B/a_oob.err")"
timeout 10 "$B/irwasm" < "$B/a_oob.ir" > "$B/a_oob.wasm" 2> "$B/a_oob.werr" || fail "a_oob irwasm $(cat "$B/a_oob.werr")"
got=$(node -e 'const fs=require("fs"); const m=new WebAssembly.Module(fs.readFileSync(process.argv[1])); const i=new WebAssembly.Instance(m); process.stdout.write(String(i.exports.f(1)));' "$B/a_oob.wasm") || fail 'a_oob in-bounds wasm'
[ "$got" = 6 ] || fail "a_oob in-bounds wasm $got"
set +e
node -e 'const fs=require("fs"); const m=new WebAssembly.Module(fs.readFileSync(process.argv[1])); const i=new WebAssembly.Instance(m); i.exports.f(4);' "$B/a_oob.wasm" >/dev/null 2>"$B/a_oob.trap"
trc=$?
set -e
[ "$trc" != 0 ] || fail 'a_oob wasm index 4 did not trap'
printf 'fn g i uint to uint\na = new uint 4 0\nput a 1 6\nret get a i\nend\nfn main to uint\nret g uint 4\nend\n' > "$B/a_oob.nat.om"
timeout 10 "$B/stage2" < "$B/a_oob.nat.om" > "$B/a_oob.nat" 2> "$B/a_oob.nat.err" || fail "a_oob native $(cat "$B/a_oob.nat.err")"
chmod +x "$B/a_oob.nat"
set +e
"$B/a_oob.nat" >/dev/null
nrc=$?
set -e
[ "$nrc" = 103 ] || fail "a_oob native $nrc wanted 103"
echo 'PASS a_oob wasm trap native=103'
printf 'ir\nstruct I a uint end\nstruct O b I c uint end\nfn f to uint\ns = new O 4 5\nret get s b a\nend\n' > "$B/s_nest.om"
timeout 10 "$B/stage2" < "$B/s_nest.om" > "$B/s_nest.ir" 2> "$B/s_nest.err" || fail "s_nest ir $(cat "$B/s_nest.err")"
timeout 10 "$B/irwasm" < "$B/s_nest.ir" > "$B/s_nest.wasm" 2> "$B/s_nest.werr" || fail "s_nest irwasm $(cat "$B/s_nest.werr")"
got=$(node -e 'const fs=require("fs"); const m=new WebAssembly.Module(fs.readFileSync(process.argv[1])); const i=new WebAssembly.Instance(m); process.stdout.write(String(i.exports.f()));' "$B/s_nest.wasm") || fail 's_nest wasm'
[ "$got" = 4 ] || fail "s_nest wasm $got wanted 4"
printf 'struct I a uint end\nstruct O b I c uint end\nfn main to uint\ns = new O 4 5\nret get s b a\nend\n' > "$B/s_nest.nat.om"
set +e
timeout 10 "$B/stage2" < "$B/s_nest.nat.om" > "$B/s_nest.nat" 2> "$B/s_nest.nat.err"
nrc=$?
set -e
[ "$nrc" = 16 ] || fail "s_nest native exit $nrc wanted 16 ($(cat "$B/s_nest.nat.err"))"
echo 'PASS s_nest wasm=4 native refuses 16'
path_refuse a_oob_const 'ir
fn main to uint
a = new uint 4 0
ret get a 4
end' 'fn main to uint
a = new uint 4 0
ret get a 4
end' 21 21
path_refuse s_assign 'ir
struct S a uint end
fn main to uint
s = new S 1
t = s
ret get t a
end' 'struct S a uint end
fn main to uint
s = new S 1
t = s
ret get t a
end' 7 7
path_refuse a_new_if 'ir
fn main to uint
if bool 1
a = new uint 2 0
end
ret 0
end' 'fn main to uint
if bool 1
a = new uint 2 0
end
ret 0
end' 9 9
path_refuse a_fidx 'ir
fn main to uint
a = new uint 4 0
ret get a f64 1.0
end' 'fn main to uint
a = new uint 4 0
ret get a f64 1.0
end' 7 7
path_refuse a_bidx 'ir
fn main to uint
a = new uint 4 0
ret get a bool 1
end' 'fn main to uint
a = new uint 4 0
ret get a bool 1
end' 7 7
path_refuse s_unk 'ir
struct S a uint end
fn main to uint
s = new S 1
ret get s z
end' 'struct S a uint end
fn main to uint
s = new S 1
ret get s z
end' 3 3
path_refuse a_free 'ir
fn main to uint
a = new uint 2 0
free a
ret 0
end' 'fn main to uint
a = new uint 2 0
free a
ret 0
end' 9 9
path_refuse a_put_scalar 'ir
fn main to uint
x = uint 1
put x 2
ret x
end' 'fn main to uint
x = uint 1
put x 2
ret x
end' 7 7
printf 'ir\nfn f to uint\na = new uint 4 0\nput a 2 7\nret get a 1\nend\n' > "$B/a_idx_mut.om"
timeout 10 "$B/stage2" < "$B/a_idx_mut.om" > "$B/a_idx_mut.ir" 2> "$B/a_idx_mut.err" || fail "a_idx_mut ir $(cat "$B/a_idx_mut.err")"
timeout 10 "$B/irwasm" < "$B/a_idx_mut.ir" > "$B/a_idx_mut.wasm" 2> "$B/a_idx_mut.werr" || fail "a_idx_mut irwasm"
mut=$(node -e 'const fs=require("fs"); const m=new WebAssembly.Module(fs.readFileSync(process.argv[1])); const i=new WebAssembly.Instance(m); process.stdout.write(String(i.exports.f()));' "$B/a_idx_mut.wasm") || fail 'a_idx_mut wasm'
[ "$mut" != 7 ] || fail 'mutant did not change the array result'
echo "PASS a_idx mutant wasm=$mut"
python3 - "$B/a_idx.ir" "$B/f_one.ir" <<'PY'
import sys
arr = open(sys.argv[1], "rb").read()
flt = open(sys.argv[2], "rb").read()
if arr[7] != 7 or arr[8] != 0:
    raise SystemExit("array header %s" % list(arr[:12]))
if flt[7] != 7 or flt[8] != 0 or flt[9] != 0 or flt[10] != 0:
    raise SystemExit("float header %s" % list(flt[:12]))
PY
echo 'PASS float header stays nstructs 0 nregions 0; array header is version 7'
path_refuse s_arr_scalar 'ir
struct I a uint 3 b uint end
struct O c I d uint end
fn f to uint
s = new O 1 2 3
put s c a 9
ret 1
end' 'struct I a uint 3 b uint end
struct O c I d uint end
fn main to uint
s = new O 1 2 3
put s c a 9
ret 1
end' 21 16
ir_wasm() { # name expect source
    printf '%s\n' "$3" > "$B/$1.om"
    timeout 10 "$B/stage2" < "$B/$1.om" > "$B/$1.ir" 2> "$B/$1.err" || fail "$1 ir $(cat "$B/$1.err")"
    timeout 10 "$B/irwasm" < "$B/$1.ir" > "$B/$1.wasm" 2> "$B/$1.werr" || fail "$1 irwasm $(cat "$B/$1.werr")"
    got=$(node -e 'const fs=require("fs"); const m=new WebAssembly.Module(fs.readFileSync(process.argv[1])); const i=new WebAssembly.Instance(m); process.stdout.write(String(i.exports.f()));' "$B/$1.wasm") || fail "$1 wasm run"
    [ "$got" = "$2" ] || fail "$1 wasm $got wanted $2"
    echo "PASS $1 wasm=$got"
}
ir_wasm s_arr_elem 9 'ir
struct I a uint 3 b uint end
struct O c I d uint end
fn f to uint
s = new O 1 2 3
put s c a 1 9
ret get s c a 1
end'
ir_wasm s_arr_keep 1 'ir
struct I a uint 3 b uint end
struct O c I d uint end
fn f to uint
s = new O 1 2 3
put s c a 1 9
ret 1
end'
ir_wasm s_arr_head 1 'ir
struct I a uint 3 b uint end
struct O c I d uint end
fn f to uint
s = new O 1 2 3
put s c a 1 9
ret get s c a 0
end'
lay() { # name source
    printf '%s\n' "$2" > "$B/$1.om"
    timeout 10 "$B/stage2" < "$B/$1.om" > "$B/$1.ir" 2> "$B/$1.err" || fail "$1 layout $(cat "$B/$1.err")"
}
lay lay_s 'ir
struct S a bool b f64 end
fn f to uint
ret 0
end'
lay lay_t 'ir
struct T a f32 b f32 end
fn f to uint
ret 0
end'
lay lay_u 'ir
struct U a uchar b uchar end
fn f to uint
ret 0
end'
lay lay_o 'ir
struct I a bool b f64 end
struct O c I d bool end
fn f to uint
ret 0
end'
lay lay_c 'ir
struct A x uint end
struct P q A end
struct C r P w uint end
fn f to uint
ret 0
end'
lay lay_z 'ir
struct Z z uchar end
struct A x uint end
struct P q A end
struct C r P w uint end
fn f to uint
ret 0
end'
python3 - "$B" <<'PY'
import sys
bdir = sys.argv[1]
def u16(b, i):
    return b[i] | (b[i+1] << 8), i + 2
def structs(path):
    b = open(path, "rb").read()
    if b[:7] != b"OSC1IR\x00" or b[7] != 7:
        raise SystemExit("not v7 %s" % path)
    i = 9
    out = {}
    for _ in range(b[8]):
        nl = b[i]; i += 1
        name = b[i:i+nl].decode(); i += nl
        nf = b[i]; i += 1
        size, i = u16(b, i)
        fields = {}
        for _k in range(nf):
            fl = b[i]; i += 1
            fn = b[i:i+fl].decode(); i += fl
            tag = b[i]; i += 1
            alen, i = u16(b, i)
            off, i = u16(b, i)
            fields[fn] = (tag, alen, off)
        out[name] = (size, fields)
    return out
def need(got, name, size, offs):
    st = got[name]
    if st[0] != size:
        raise SystemExit("%s size %s wanted %s" % (name, st[0], size))
    for fn, off in offs.items():
        if st[1][fn][2] != off:
            raise SystemExit("%s.%s off %s wanted %s" % (name, fn, st[1][fn][2], off))
need(structs(bdir + "/lay_s.ir"), "S", 16, {"a": 0, "b": 8})
need(structs(bdir + "/lay_t.ir"), "T", 8, {"a": 0, "b": 4})
need(structs(bdir + "/lay_u.ir"), "U", 2, {"a": 0, "b": 1})
o = structs(bdir + "/lay_o.ir")
need(o, "I", 16, {"a": 0, "b": 8})
need(o, "O", 24, {"c": 0, "d": 16})
c = structs(bdir + "/lay_c.ir")
need(c, "A", 4, {"x": 0})
need(c, "P", 4, {"q": 0})
need(c, "C", 8, {"r": 0, "w": 4})
z = structs(bdir + "/lay_z.ir")
need(z, "Z", 1, {"z": 0})
need(z, "C", 8, {"r": 0, "w": 4})
def place(st):
    size, fields = st
    return (size, {n: (tag, off) for n, (tag, _alen, off) in fields.items()})
if place(c["C"]) != place(z["C"]):
    raise SystemExit("leading struct moved C: %s vs %s" % (place(c["C"]), place(z["C"])))
# The length of a struct field is that struct's index plus one. Z takes the first
# slot, so the index moves and the offsets do not.
if c["C"][1]["r"][1] != 2 or z["C"][1]["r"][1] != 3:
    raise SystemExit("C.r names the wrong struct %s %s" % (c["C"][1]["r"][1], z["C"][1]["r"][1]))
PY
echo 'PASS struct layout offsets'
echo 'SCALAR_IR_CHECKPOINT 10/10 + 9 multi-call units + 3 break units + 2 for-value units + 1 shift unit + 4 bool units + 24 cast units + 2 contract-name units + 30 fuzz units + 1 guarded for-bound unit + 2 bound-range pairs (1000000 accepted, 1000001 error 8) + 1 count-range set (1000000 identical to the oracle; 1000001, -1, -0, const 1000001 error 8); validation: 38 refusals + 1 same-IR pair + 4 scope/fallthrough/long-name units; floats: 13 wasm=native bools, const fold, bits 1.0/0.1/-0.0; path codes f_for_const 7/7, f_trap_const 16/16, f_while_const 16/16, f_fma_bare 3/11, f_fma_mix 3/7, f_fsqrt_bare 3/11; aggregates a_idx 7, a_nest 9, s_field 4, s_copy 3, s_flt 2, s_feq 1, a_oob trap/103, s_nest wasm 4 native 16'
echo 'RC=0'
