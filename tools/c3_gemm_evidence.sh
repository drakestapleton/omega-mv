#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# c3_gemm_evidence.sh: every derived fact of a C3 GEMM chip receipt, computed from the chip log written by
# tools/run_gpu_gemm_chip.sh, so no count, range, median or acceptance word is typed by hand (DRA-485 RCCA).
#   csv LOG                  the per-case table (per-shape.csv) from the log's "ok:" case lines
#   summary LOG [HIST...]    the markdown summary block of the evidence README: provenance, counts, the DRA-485
#                            acceptance read literally (a SHAPE is a distinct (M, N, K) triple), red checks, speed,
#                            and run-to-run repeat against each HIST log (an earlier chip log of the same tier)
# Output goes to stdout. tests/gates/run.sh evidence-generated reruns the command named in the README's
# "<!-- generated: ... -->" marker and fails on any difference.
# Measuring tool outside Omega's structure (POSIX sh + awk); the Omega replacement is recorded in REVIEW-LESSONS.md.
set -eu
mode=${1:?usage: c3_gemm_evidence.sh csv|summary LOG [HIST...]}; log=${2:?usage: c3_gemm_evidence.sh csv|summary LOG [HIST...]}
shift 2
[ -r "$log" ] || { echo "c3_gemm_evidence: cannot read $log" >&2; exit 2; }

# cases LOG: one line per case, "type M N K layout|checked|wrong|ms|tflops|frac|ptflops|pfrac", taken from the
# "ok:" lines that come before the "<n> cases (...): PASS|FAIL" line (later "ok:" lines are the reopen checks).
cases() {
  awk '
    /^[0-9]+ (cases|shapes)[ ,(]/ { exit }
    /^ok: / {
      t = $2; split($3, d, "x"); lay = $4 " " $5 " " $6 " " $7; sub(/:$/, "", lay)
      if ($8 != "OK,") { printf "c3_gemm_evidence: case line without OK: %s\n", $0 > "/dev/stderr"; exit 1 }
      if ($12 != "wrong;" || $13 != "kernel" || $21 != "ceiling,") { printf "c3_gemm_evidence: unexpected case line: %s\n", $0 > "/dev/stderr"; exit 1 }
      printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n", t, d[1], d[2], d[3], lay, $9, $11, $14, $16, $19, $24, $27
    }' "$1"
}

case "$mode" in
csv)
  echo "type,M,N,K,layout,checked,wrong,kernel_ms,kernel_tflops,fraction_of_ceiling,with_packs_tflops,fraction_with_packs"
  cases "$log"
  ;;
summary)
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  for k in 'window ' 'git head ' 'binary ' 'exit '; do   # a final log must come from tools/run_gpu_gemm_chip.sh
    grep -q "^provenance: $k" "$log" || { echo "c3_gemm_evidence: $log has no 'provenance: $k' line (not written by tools/run_gpu_gemm_chip.sh)" >&2; exit 3; }
  done
  cases "$log" > "$tmp/final"
  i=0
  for h in "$@"; do
    [ -r "$h" ] || { echo "c3_gemm_evidence: cannot read $h" >&2; exit 2; }
    i=$((i + 1)); cases "$h" > "$tmp/hist$i"; printf '%s\n' "$h" > "$tmp/hist$i.name"
  done
  grep '^provenance: ' "$log" | sed -n '1,4p;$p' | sed 's/^provenance: /- provenance: /'
  awk -v nhist="$i" -v dir="$tmp" '
    function med(a, n,   i, j, t) {     # median of a[1..n] (mean of the two middle values when n is even)
      for (i = 2; i <= n; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]; a[j + 1] = t }
      return (n % 2) ? a[(n + 1) / 2] : (a[n / 2] + a[n / 2 + 1]) / 2
    }
    BEGIN { FS = ","; big = 1073741824; NT = split("bf16 e4m3", TL, " ") }  # 2^30 multiply-adds; types in a fixed order
    FILENAME ~ /final$/ {
      n++; key = $2 "x" $3 "x" $4; tri[key]++; ty[$1]++; ly[$5]++; cell[$1 "|" $5 "|" key]++
      for (k = 2; k <= 4; k++) { if (dmin == "" || $k + 0 < dmin) dmin = $k + 0; if ($k + 0 > dmax) dmax = $k + 0 }
      wrong += $7; if ($6 + 0 == ($2 + 0) * ($3 + 0)) full++; else samp++
      f = $10 + 0; c = $1 "|" $5 "|" key; fr[c] = f
      if (!($1 in best) || f > best[$1]) { best[$1] = f; bestc[$1] = key " " $5 }
      if ($2 == 8192 && $3 == 8192 && $4 == 8192) { if (!($1 in sqlo) || f < sqlo[$1]) sqlo[$1] = f; if (f > sqhi[$1]) sqhi[$1] = f }
      if (($2 + 0) * ($3 + 0) * ($4 + 0) >= big) {
        nb[$1]++; bf[$1, nb[$1]] = f
        if (!($1 in lo) || f < lo[$1]) { lo[$1] = f; loc[$1] = key " " $5 }
        if (f < 0.03) under[$1]++
      }
      next
    }
    { h = FILENAME; sub(/.*hist/, "", h); key = $2 "x" $3 "x" $4
      if (($2 + 0) * ($3 + 0) * ($4 + 0) >= big) hf[h, $1 "|" $5 "|" key] = $10 + 0 }
    END {
      nt = 0; for (k in tri) nt++; ntype = 0; for (k in ty) ntype++; nlay = 0; for (k in ly) nlay++
      miss = 0; for (k in tri) for (t in ty) for (l in ly) if (cell[t "|" l "|" k] != 1) miss++
      printf "- cases: %d = %d distinct (M, N, K) shapes x %d types x %d layouts; every shape in every type/layout cell exactly once: %s\n", n, nt, ntype, nlay, (miss == 0 && n == nt * ntype * nlay) ? "yes" : "NO (" miss " cells missing or repeated)"
      printf "- dimensions: smallest %d, largest %d; wrong outputs in all cases: %d; compared in full (checked = M*N): %d cases, on a sample: %d cases\n", dmin, dmax, wrong, full, samp
      ok = (nt >= 200 && dmin == 1 && dmax == 8192 && ("bf16" in ty) && ("e4m3" in ty) && nlay == 4 && miss == 0 && wrong == 0)
      printf "- DRA-485 acceptance, read literally (at least 200 shapes, each a distinct (M, N, K), dimensions 1 to 8192, BF16 and FP8, both layouts of A and B, 0 wrong): %s\n", ok ? "MET on the chip" : "NOT MET"
      for (ti = 1; ti <= NT; ti++) { t = TL[ti]; if (!(t in ty)) continue
        m = 0; for (j = 1; j <= nb[t]; j++) a[j] = bf[t, j]; m = med(a, nb[t])
        printf "- speed %s: best %.4f (%s); 8192^3 %.4f to %.4f; over the %d cases of at least 2^30 multiply-adds median %.4f, lowest %.4f (%s), %d below 0.03\n", t, best[t], bestc[t], sqlo[t], sqhi[t], nb[t], m, lo[t], loc[t], under[t] + 0
      }
      for (h = 1; h <= nhist; h++) {
        getline nm < (dir "/hist" h ".name")
        for (ti = 1; ti <= NT; ti++) { t = TL[ti]; if (!(t in ty)) continue
          q = 0; mx = 0
          for (c in fr) { split(c, p, "|"); if (p[1] != t || !((h, c) in hf) || hf[h, c] <= 0) continue
            r = fr[c] - hf[h, c]; if (r < 0) r = -r; r = r / hf[h, c]; q++; b[q] = r; if (r > mx) mx = r }
          if (q) printf "- repeat vs %s, %s: %d common cases of at least 2^30 multiply-adds, |final - earlier| / earlier median %.1f%%, max %.1f%%\n", nm, t, q, 100 * med(b, q), 100 * mx
        }
      }
    }' "$tmp/final" $(i=1; while [ -e "$tmp/hist$i" ]; do printf '%s ' "$tmp/hist$i"; i=$((i + 1)); done)
  grep -c '^chip red check: .* is caught (OK' "$log" | sed 's/^/- chip red checks caught: /'
  grep '^chip red check: .* mutant [45] .* is caught (OK' "$log" | sed 's/^chip red check: \([a-z0-9]*\) mutant \([45]\) (\(.*\)) is caught.*/\1 mutant \2 (\3)/' | paste -sd ';' | sed 's/;/; /g; s/^/- wrong-transpose controls caught on the chip: /'
  grep -E '^C3 gemm chip: (PASS|FAIL)' "$log" | sed 's/^/- last line: /'
  ;;
*) echo "c3_gemm_evidence: unknown mode $mode" >&2; exit 2 ;;
esac
