# seed/equiv/irwasm-v7.sed: the OSC IR v7 edits (PR #818, f2494481e/01521b462) that turn
# irequiv.om lines 43-496 (the v1 reader, byte-identical to irspirv.om) into irwasm.om lines
# 65-843. Line addresses are irequiv-range lines. POSIX sed: N a\ inserts after line N,
# N c\ replaces line N. gate-irequiv.sh requires the result to equal irwasm byte for byte.
54a\
fn isflt t ulong to bool\
ret or eq t 13 eq t 14\
end\
fn sgn t ulong to bool\
ret and ge t 6 le t 9\
end\
fn isint t ulong to bool\
ret and ge t 2 le t 9\
end\
fn feat to void\
put state 11 1\
end
56a\
if and eq get state 8 7 isflt t\
feat\
ret t\
end
66a\
fn rg to ulong\
v = rd 2\
need lt v get state 9\
ret v\
end
77c\
if or or eq t 4 eq t 8 eq t 13
81a\
note log2 of the element byte width: wasm alignment hint and index shift.\
fn lg t ulong to ulong\
w = width t\
if eq w 8\
ret 0\
end\
if eq w 16\
ret 1\
end\
if eq w 32\
ret 2\
end\
ret 3\
end
95c\
if sgn t
125a\
note Region names: 1..63 ASCII bytes, no NUL and no dot (spec 10.1).\
fn rsame a ulong b ulong to bool\
if ne get rnlen a get rnlen b\
ret false\
end\
for j ulong get rnlen a\
x = get input add get rname a j\
y = get input add get rname b j\
if ne x y\
ret false\
end\
end\
ret true\
end\
fn skip n ulong to void\
p = get state 0\
if gt n sub get state 1 p\
refuse 22\
end\
put state 0 add p n\
end\
note Every field is checked in byte order as it is read (spec 10.1 reader classes).\
fn region r ulong to void\
n = rd 1\
need and ge n 1 le n 63\
put rnlen r n\
put rname r get state 0\
for j ulong n\
v = rd 1\
need and and ne v 0 lt v 128 ne v 46\
end\
t = rd 1\
need or isint t isflt t\
put rtag r t\
c = rd 1\
if eq c 3\
refuse 24\
end\
need le c 2\
put rclass r c\
put rowner r rd 2\
k = rd 4\
put rcount r k\
need le k 16777216\
if ne c 2\
need ne k 0\
end\
n = rd 4\
if eq c 2\
need and eq t 2 eq n k\
else\
need eq n 0\
end\
put rdata r get state 0\
skip n\
end\
fn regions to void\
nr = rd 2\
need le nr 1024\
put state 9 nr\
if ne nr 0\
feat\
end\
for r ulong nr\
region r\
end\
end
201a\
if and eq get state 8 7 and ge o 30 le o 33\
insn7 i o\
ret\
end
203a\
note v7: 30 RLOAD dst region index, 31 RSTORE region index src,\
note 32 BITCAST dst src, 33 RINIT region init. Region id lives in immed.\
fn insn7 i ulong o ulong to void\
feat\
if eq o 30\
put dest i vr\
put immed i rg\
put arg0 i vr\
ret\
end\
if eq o 31\
put immed i rg\
put arg0 i vr\
put arg1 i vr\
ret\
end\
if eq o 32\
put dest i vr\
put arg0 i vr\
ret\
end\
put immed i rg\
put arg0 i vr\
end
278a\
if eq get state 8 7\
check7 i fi\
end\
end\
note BITCAST width sets {u8,i8} {u16,i16} {u32,i32,f32} {u64,i64,f64}; 0 = none.\
fn bclass t ulong to ulong\
if or eq t 2 eq t 6\
ret 1\
end\
if or eq t 3 eq t 7\
ret 2\
end\
if or or eq t 4 eq t 8 eq t 13\
ret 3\
end\
if or or eq t 5 eq t 9 eq t 14\
ret 4\
end\
ret 0\
end\
note A function-local region is accessible only by its owning function.\
fn regok r ulong fi ulong to void\
if eq get rclass r 1\
need eq get rowner r fi\
end\
end\
fn check7 i ulong fi ulong to void\
o = get ops i\
s = get subs i\
a = get arg0 i\
t = ulong 0\
if ne a 65535\
t = get types a\
end\
if and eq o 3 isflt t\
need le s 4\
end\
if and eq o 3 ge s 9\
need not isflt get types get arg1 i\
end\
if and eq o 4 isflt t\
need eq s 1\
end\
r = get immed i\
if eq o 30\
need isint t\
need eq get types get dest i get rtag r\
regok r fi\
end\
if eq o 31\
need isint t\
need eq get types get arg1 i get rtag r\
need ne get rclass r 2\
regok r fi\
end\
if eq o 32\
b = bclass t\
need and ne b 0 eq b bclass get types get dest i\
end\
if eq o 33\
need eq get rclass r 1\
regok r fi\
need eq t get rtag r\
end
292c\
term = and ge o 13 le o 15
380a\
if and ge o 30 le o 33\
use get arg0 i\
end\
if eq o 31\
use get arg1 i\
end
452a\
end\
end\
note v7 local-region initialization (spec 10.3): a block entry bit is the AND of\
note its reachable predecessors' exit bits; entry and unreachable blocks start false.\
fn mark b ulong to bool\
if eq get reach b 0\
put reach b 1\
ret true\
end\
ret false\
end\
fn reachall to void\
nb = get state 5\
for b ulong nb\
put reach b 0\
end\
put reach 0 1\
changed = true\
note Each changing round marks at least one of at most 512 blocks.\
while changed bound 513\
changed = false\
for b ulong nb\
if ne get reach b 0\
i = add get first b sub get counts b 1\
o = get ops i\
if or eq o 13 eq o 14\
if mark get immed i\
changed = true\
end\
end\
if eq o 14\
if mark get arg1 i\
changed = true\
end\
end\
end\
end\
end\
end\
fn rbit r ulong to bool\
ret ne and get rwork div r 64 shl ulong 1 rem r 64 0\
end\
fn rset r ulong to void\
k = div r 64\
put rwork k or get rwork k shl ulong 1 rem r 64\
end\
fn rtrans b ulong verify bool to void\
for k ulong 16\
put rwork k get rin add mul b 16 k\
end\
for j ulong get counts b\
i = add get first b j\
o = get ops i\
if and verify or eq o 30 eq o 31\
if eq get rclass get immed i 1\
need rbit get immed i\
end\
end\
if eq o 33\
rset get immed i\
end\
end\
end\
fn rmerge b ulong pred ulong to void\
i = add get first pred sub get counts pred 1\
o = get ops i\
target = false\
if or eq o 13 eq o 14\
target = eq get immed i b\
if eq o 14\
target = or target eq get arg1 i b\
end\
end\
if target\
for k ulong 16\
ix = add mul b 16 k\
v = get rout add mul pred 16 k\
put rin ix and get rin ix v\
end\
end\
end\
fn rentry b ulong to void\
live = and ne b 0 ne get reach b 0\
v = ulong 0\
if live\
v = 18446744073709551615\
end\
for k ulong 16\
put rin add mul b 16 k v\
end\
if live\
for p ulong get state 5\
if ne get reach p 0\
rmerge b p\
end\
end\
end\
end\
fn inited to void\
reachall\
nb = get state 5\
for b ulong nb\
for k ulong 16\
put rout add mul b 16 k 18446744073709551615\
end\
end\
changed = true\
note At most one of 512*1024 = 524288 (block,region) bits drops per changing round.\
while changed bound 524289\
changed = false\
for b ulong nb\
rentry b\
rtrans b false\
for k ulong 16\
ix = add mul b 16 k\
v = get rwork k\
if ne v get rout ix\
changed = true\
put rout ix v\
end\
end\
end\
end\
for b ulong nb\
rtrans b true
