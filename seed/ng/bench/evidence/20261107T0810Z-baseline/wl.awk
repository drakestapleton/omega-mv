# reformat ngbench T rows (measured blocks only, warm=0) into a Wolfram association; no arithmetic
$1=="T" && $3==0 { k=$4 "|" $5; v[k, $2] = (v[k, $2] == "" ? $7 : v[k, $2] "," $7); keys[k]=1; if ($2>maxb) maxb=$2; if (minb=="" || $2<minb) minb=$2 }
END { printf "<|"; s=""; for (k in keys) { split(k, p, "|"); printf "%s{\"%s\",\"%s\"}->{", s, p[1], p[2]; t=""; for (b=minb; b<=maxb; b++) { printf "%s{%s}", t, v[k, b]; t="," } printf "}"; s="," } print "|>" }
