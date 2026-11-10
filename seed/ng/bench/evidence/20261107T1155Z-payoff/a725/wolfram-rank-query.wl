s = <|{"LICM+ROT","bcopy"}->{0.7414,0.7402,0.7469},{"LICM+ROT","arith"}->{1.0175,1.0132,1.0184},{"LICM+ROT","branch"}->{0.5984,0.5871,0.6012},{"LICM+ROT","isort"}->{0.6141,0.6037,0.6216},{"LICM+ROT","sort"}->{0.7314,0.7290,0.7346},{"LICM+ROT","matmul"}->{0.6930,0.6870,0.6962},{"LICM+ROT","sieve"}->{0.6777,0.6729,0.6791},{"LICM+ROT","linear"}->{0.8641,0.8625,0.8752},{"BCE","bcopy"}->{0.6116,0.6064,0.6125},{"BCE","isort"}->{0.7144,0.7056,0.7209},{"BCE","sort"}->{0.6993,0.6974,0.7023},{"BCE","matmul"}->{0.8812,0.8768,0.8847},{"BCE","sieve"}->{0.8698,0.8636,0.8849},{"BCE","linear"}->{1.1109,1.1039,1.1145},{"VEC","bcopy"}->{0.0964,0.0955,0.0979},{"DIV","arith"}->{0.3882,0.3854,0.3917},{"IFC","branch"}->{0.7630,0.7470,0.7696},{"CALL","leafcall"}->{0.4657,0.4642,0.4670},{"INL","leafcall"}->{0.8173,0.8146,0.8206},{"ISEL","linear"}->{0.7249,0.7225,0.7356}|>;
aa = <|"bcopy"->{1.0004,0.9993,1.0140},"arith"->{0.9997,0.9945,1.0045},"branch"->{0.9992,0.9913,1.0152},"isort"->{1.0002,0.9978,1.0082},"sort"->{1.0002,0.9917,1.0077},"leafcall"->{1.0004,0.9982,1.0013},"matmul"->{1.0006,0.9919,1.0084},"sieve"->{0.9989,0.9948,1.0056},"linear"->{0.9996,0.9851,1.0060}|>;
fibA = <|"fib40"->0.888,"fib38"->1.087|>; fibE = <|"fib40"->0.633,"fib38"->0.634|>;
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