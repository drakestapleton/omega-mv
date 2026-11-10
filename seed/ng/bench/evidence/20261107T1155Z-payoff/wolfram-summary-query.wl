(* fractions removed per loop pass (section 1 loop sizes) and per sha/chacha block (census) *)
f = <|{"bcopy","L"}->(18-11)/18, {"bcopy","B"}->(11-7)/11, {"arith","L"}->(17-11)/17, {"branch","L"}->(18-12)/18, {"isort","L"}->(28-14)/28, {"isort","B"}->(14-7)/14, {"sort","L"}->(24-14)/24, {"sort","B"}->(14-7)/14, {"matmul","L"}->(22-13)/22, {"matmul","B"}->(13-9)/13, {"sieve","L"}->(19-9)/19, {"sieve","B"}->(9-4)/9, {"linear","L"}->(20-17)/20, {"linear","B"}->(17-13)/17|>;
Tsha = 1299+2279+72; Tch = 10*486 + (448-22+10*22) + (60-20+64*20) + 45;
p = <|{"sha","LICM+ROT"}->(3+3+2+1)/Tsha, {"sha","BCE"}->(128+8)/Tsha, {"sha","CALL"}->(23+29)/Tsha, {"chacha","LICM+ROT"}->(820+53+192+6+1)/Tch, {"chacha","BCE"}->(1280+40+576+6)/Tch, {"chacha","CALL"}->(130+31+17)/Tch|>;
{Tsha, Tch, N[f, 4], N[p, 4]}

(* residual gap: baseline omc/gccO2 geomean over all passes together *)
{N[2.846/2.062327136875912, 4], N[2.920/2.1491117089516494, 4], N[1 - 1/2.062327136875912, 4], N[1 - 1/2.1491117089516494, 4]}

(* residual gap with the ngA-based ranking (wolfram-rank-ngA-*), requested by omp-queen-ng 2026-11-07 *)
{N[2.846/2.0623125375090092, 4], N[2.920/2.1487863856419107, 4]}
