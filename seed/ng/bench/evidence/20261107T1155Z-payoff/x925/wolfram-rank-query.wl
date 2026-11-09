s = <|{"LICM+ROT","bcopy"}->{0.6824,0.6742,0.7974},{"LICM+ROT","arith"}->{0.9962,0.9897,0.9971},{"LICM+ROT","branch"}->{0.9371,0.9359,0.9388},{"LICM+ROT","isort"}->{0.6835,0.6818,0.6869},{"LICM+ROT","sort"}->{0.6811,0.6786,0.6833},{"LICM+ROT","matmul"}->{0.7661,0.7588,0.7830},{"LICM+ROT","sieve"}->{0.7825,0.7781,0.7868},{"LICM+ROT","linear"}->{1.0242,1.0214,1.0264},{"BCE","bcopy"}->{0.7719,0.6647,0.7798},{"BCE","isort"}->{0.9775,0.9748,0.9795},{"BCE","sort"}->{0.9809,0.9796,0.9817},{"BCE","matmul"}->{1.0346,1.0156,1.0457},{"BCE","sieve"}->{0.9747,0.9663,0.9803},{"BCE","linear"}->{0.9875,0.9862,0.9889},{"VEC","bcopy"}->{0.0632,0.0623,0.0648},{"DIV","arith"}->{0.3333,0.3317,0.3344},{"IFC","branch"}->{0.8952,0.8939,0.8981},{"CALL","leafcall"}->{0.3631,0.3619,0.3650},{"INL","leafcall"}->{0.8369,0.8320,0.8456},{"ISEL","linear"}->{0.9077,0.9047,0.9092}|>;
aa = <|"bcopy"->{1.0005,0.9991,1.0015},"arith"->{1.0000,0.9951,1.0011},"branch"->{1.0003,0.9977,1.0016},"isort"->{0.9992,0.9970,1.0026},"sort"->{0.9995,0.9902,1.0008},"leafcall"->{0.9999,0.9985,1.0011},"matmul"->{0.9969,0.9867,1.0035},"sieve"->{0.9997,0.9969,1.0019},"linear"->{0.9995,0.9985,1.0004}|>;
fibA = <|"fib40"->0.578,"fib38"->0.591|>; fibE = <|"fib40"->0.35,"fib38"->0.357|>;
f = <|"bcopy"->{(18-11)/18,(11-7)/11},"arith"->{(17-11)/17,0},"branch"->{(18-12)/18,0},"isort"->{(28-14)/28,(14-7)/14},"sort"->{(24-14)/24,(14-7)/14},"matmul"->{(22-13)/22,(13-9)/13},"sieve"->{(19-9)/19,(9-4)/9},"linear"->{(20-17)/20,(17-13)/17}|>;
aaok = Select[Keys[aa], !(aa[#][[2]] <= 1 <= aa[#][[3]] || 0.99 <= aa[#][[1]] <= 1.01) &];
eL = Table[(1 - s[{"LICM+ROT", k}][[1]])/f[k][[1]], {k, {"bcopy","arith","branch","isort","sort","matmul","sieve","linear"}}];
eB = Table[(1 - s[{"BCE", k}][[1]])/f[k][[2]], {k, {"bcopy","isort","sort","matmul","sieve","linear"}}];
e = Median[Join[eL, eB]];
p = <|{"sha","LICM+ROT"}->9/3650, {"sha","BCE"}->136/3650, {"sha","CALL"}->52/3650, {"chacha","LICM+ROT"}->1072/6871, {"chacha","BCE"}->1902/6871, {"chacha","CALL"}->178/6871|>;
mod = Association[Table[k -> 1 - e p[k], {k, Keys[p]}]];
passes = {"LICM+ROT","BCE","VEC","DIV","IFC","CALL","INL","ISEL","REC"};
meas[P_] := Join[Table[s[k][[1]], {k, Select[Keys[s], #[[1]] == P &]}], If[P == "CALL", Values[fibA], {}], If[P == "REC", Table[fibE[c]/fibA[c], {c, {"fib40","fib38"}}], {}]];
modl[P_] := Table[mod[k], {k, Select[Keys[mod], #[[2]] == P &]}];
gm[x_] := 1/(Times @@ x)^(1/13);
nd = Select[Keys[s], s[#][[2]] <= 1 <= s[#][[3]] &];
slower = Select[Keys[s], s[#][[2]] > 1 &];
rank = SortBy[Table[{P, N[gm[meas[P]]], N[gm[Join[meas[P], modl[P]]]], Length[meas[P]], Length[modl[P]]}, {P, passes}], -#[[3]] &];
all = N[gm[Join[Flatten[Table[meas[P], {P, passes}]], Values[mod]]]];
{"aa_failing" -> aaok, "eL" -> N[eL, 4], "eB" -> N[eB, 4], "e" -> N[e, 4], "modeled" -> N[mod, 4], "no_difference" -> nd, "slower" -> slower, "rank {pass, gain measured, gain measured+modeled, n measured, n modeled}" -> rank, "all passes together (product of every factor)" -> all}