# Bookkeeping only (no statistics): writes the timed rounds of raw.json as Wolfram Language list
# literals so every statistic in the addendum is computed by the Wolfram evaluator.
# Output: wl-<stat>.txt  = <|"case" -> {{A r1..r31}, {B ...}, {C ...}}, ...|> for stat in med,p10,p90;
#         wl-minmax.txt  = <|"case" -> {{minA,maxA},{minB,maxB},{minC,maxC}}|> (selection, not arithmetic);
#         wl-cold.txt, wl-compile.txt, wl-rss.txt, wl-load.txt.
import json, sys
d = json.load(open(sys.argv[1])); out = sys.argv[2]
R = [r for r in d["rounds"] if not r["warmup"]]
cases = list(R[0]["A"].keys()); arms = ["A", "B", "C"]
def wl(x): return "{" + ",".join(wl(y) for y in x) + "}" if isinstance(x, list) else repr(x)
for st in ("med", "p10", "p90"):
    body = ",".join(f'"{k}"->' + wl([[r[a][k][st] for r in R] for a in arms]) for k in cases)
    open(f"{out}/wl-{st}.txt", "w").write("<|" + body + "|>")
body = ",".join(f'"{k}"->' + wl([[min(r[a][k]["min"] for r in R), max(r[a][k]["max"] for r in R)] for a in arms]) for k in cases)
open(f"{out}/wl-minmax.txt", "w").write("<|" + body + "|>")
cold = ",".join(f'"{a}:{n}"->' + wl([c["ns"] for c in d["cold"] if c["arm"] == a and c["n"] == n]) for a in arms for n in (64, 1048576))
open(f"{out}/wl-cold.txt", "w").write("<|" + cold + "|>")
comp = ",".join(f'"{a}"->' + wl([float(c["ns"]) for c in d["compile"] if c["arm"] == a]) for a in ("A", "B"))
open(f"{out}/wl-compile.txt", "w").write("<|" + comp + "|>")
rss = ",".join(f'"{a}"->' + wl([float(r["rss_" + a]) for r in R]) for a in arms)
open(f"{out}/wl-rss.txt", "w").write("<|" + rss + "|>")
load = [float(r["load_before"][0]) for r in R] + [float(r["load_after"][0]) for r in R]
open(f"{out}/wl-load.txt", "w").write(wl(load))
print("cases", len(cases), "rounds", len(R), "orders", sorted(set("".join(r["order"]) for r in R)))
