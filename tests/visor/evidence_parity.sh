#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# evidence_parity.sh -- differential qualification of the pure OM-2 evidence lane
# (src/visor/visor_evidence.om: vev_scan, vev_for_id, vev_load, vev_set_max_files,
# vev_format_text, vev_format_json: the strict JSON scanner, record extraction, scope law, the
# sorted capped walk and the renderings) against the C it replaced in the omega binary
# (src/visor/visor_evidence.c, retired at main commit 3f2c70dc5), on the same evidence trees.
#
# Each corpus holds tree lines (built here into a fresh directory before the dumper runs) and
# dumper commands. Every corpus runs through tests/visor/evidence_dump.om in that directory and
# is compared byte for byte with tests/visor/evidence_golden/<corpus>.out. The goldens were
# generated ONCE from the C at main commit 3f2c70dc5 by the reference-only C dumper
# tests/visor/evidence_dump.c (committed once, then removed); tests/visor/evidence_golden/MANIFEST
# records the commit, the generator and the sha256 of every corpus and golden. No C compiler.
#
# Tree lines (paths relative to the corpus directory, no spaces in paths):
#   F path content   file with printf %b content (\n, \t, \\, \0ddd octal)
#   Z path n         {"a":"<n x>"} (n + 8 bytes)        B path n   n bytes of x
#   A path k         {"a":[0,0,...]} with k zeros        D path     directory
#   N dir k          k receipts dir/f00000.json ..       K path target  symlink
#   H dir content    a file named <sha256 of content>.json
# Dumper commands: S root | I root hex64 | L path | M cap (see tests/visor/evidence_dump.om).
#   hand       the committed fixture tree tests/visor/fixtures/evidence: scan, for_id, load
#   gen-json   the strict JSON scanner: every literal, number, string escape and structure form,
#              depth 62..66 and the token pool limit, each file loaded
#   gen-fields record extraction: commit, physics, run, realization, machine, gates, claim,
#              tree state and every scope signal combination, each file loaded
#   gen-walk   walk and view: caps, the smallest-path heap, depth, long paths, links, hidden,
#              non-JSON, binary, oversize, truncation, unparsed listing, for_id mentions
#
# usage: tests/visor/evidence_parity.sh [OMC]
#        tests/visor/evidence_parity.sh --generate <C dumper binary>
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GOLD=$ROOT/tests/visor/evidence_golden
GEN=""
if [ "${1:-}" = "--generate" ]; then
  GEN=${2:?usage: evidence_parity.sh --generate <C dumper binary>}
  case $GEN in /*) ;; *) GEN=$(pwd)/$GEN ;; esac
  OMC=""
else
  OMC=${1:-$ROOT/seed/out/omc}
  case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
fi
W=${EVIDENCE_PARITY_WORK:-$(mktemp -d)}
mkdir -p "$W/corpus" "$W/out"
sha() { sha256sum "$1" | cut -d' ' -f1; }

# ---- corpora ----
cd "$ROOT"
C=$W/corpus
rm -f "$C"/*.txt
H0=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
H1=1111111111111111111111111111111111111111111111111111111111111111
H2=2222222222222222222222222222222222222222222222222222222222222222
# hand: the fixture tree as F lines (content escaped for printf %b), then the commands
{ find tests/visor/fixtures/evidence -type f | LC_ALL=C sort | while read -r f; do
    awk -v p="fix/${f#tests/visor/fixtures/evidence/}" 'BEGIN { RS = "\001" }
      { gsub(/\\/, "\\\\"); gsub(/\n/, "\\n"); gsub(/\t/, "\\t"); printf "F %s %s\n", p, $0 }' "$f"
  done
  printf 'S fix\nS fix/\nS fix/SILICON\nS fix/CA\nS nonexistent\nS\nS fix/digests.txt\n'
  printf 'I fix %s\nI fix %s\nI fix %s\nI fix 73d26b54634d017831a828cb5d83eb25948288be7b49270659cab38e274dd7d9\nI fix xyz\n' "$H0" "$H1" "$H2"
  printf 'I nonexistent %s\n' "$H0"
  find tests/visor/fixtures/evidence -type f | LC_ALL=C sort | sed -e 's|^tests/visor/fixtures/evidence/|L fix/|'
  printf 'L fix\nL nonexistent.json\nM 3\nS fix\nM 0\nM 0\nS fix\n'; } > "$C/hand.txt"

# gen-json: one file per form, each loaded
cat > "$W/json.txt" <<'EOF'
{}
{"a":1}
[]
[1]
"str"
1
true
null
 {"a":1}\n
{"a":1}x
{"a":1} {}
\n\t\r {"a":1}\r\n\t
{"a":}
{"a" 1}
{a:1}
{"a":1,}
{"a":[1,2,]}
{"a":[1 2]}
{"a":[1,,2]}
{"a":{"b":{"c":[true,false,null,[],{}]}}}
{"a":tru}
{"a":nul}
{"a":falsey}
{"a":nullx}
{"a":-}
{"a":-0}
{"a":0}
{"a":01}
{"a":-01}
{"a":1.}
{"a":1.5}
{"a":1.5.5}
{"a":1e}
{"a":1e+}
{"a":1e5}
{"a":1E-7}
{"a":-12.5e+3}
{"a":.5}
{"a":+1}
{"a":"\\""}
{"a":"\\\\"}
{"a":"\\/"}
{"a":"\\b\\f\\n\\r\\t"}
{"a":"\\u0041\\u00e9\\uFFFF"}
{"a":"\\u00g1"}
{"a":"\\u12"}
{"a":"\\u12"}
{"a":"\\x"}
{"a":"\\
{"a":"tab\there"}
{"a":"nl\nhere"}
{"a":"\001"}
{"a":"\037"}
{"a":"\177"}
{"a":"unterminated}
{"a":"x"
{"a":"x",
{"a":"x"
{"a":"\0303\0251"}
{"a":"\0377\0376"}
{"a":"x"}\0000
{"a":"\0000"}
{ "a" : "b" , "c" : [ 1 , 2 ] }
{"":"empty key"}
{"schema":"s","schema":"t"}
{"schema":"one"}
{"schema":"one","status":"PASS"}
{"schema":123}
{"status":"PASS"}
{"a":{"b":1},"c":[{"d":2}],"e":"f"}
{"k":[[[[[[[[[[1]]]]]]]]]]}
{"a":1}}
{"a":1]
{"a":[}
{"a":{]}
{
}
{"a":"\\u0000"}
EOF
{ awk '{ printf "F j/%03d.json %s\n", NR, $0 }' "$W/json.txt"
  awk 'BEGIN { for (d = 62; d <= 66; d++) { s = ""; e = ""; for (i = 0; i < d; i++) { s = s "["; e = e "]" }
         printf "F d/arr%02d.json {\"a\":%s1%s}\n", d, s, e
         s = ""; e = ""; for (i = 0; i < d; i++) { s = s "{\"k\":"; e = e "}" }
         printf "F d/obj%02d.json {\"a\":%s1%s}\n", d, s, e } }'
  printf 'A t/tok32765.json 32765\nA t/tok32766.json 32766\nA t/tok32767.json 32767\nA t/tok40000.json 40000\n'
  printf 'Z t/z262136.json 262136\nZ t/z262137.json 262137\nZ t/z300000.json 300000\nF t/empty.json \n'
  awk '{ printf "L j/%03d.json\n", NR }' "$W/json.txt"
  awk 'BEGIN { for (d = 62; d <= 66; d++) printf "L d/arr%02d.json\nL d/obj%02d.json\n", d, d }'
  printf 'L t/tok32765.json\nL t/tok32766.json\nL t/tok32767.json\nL t/tok40000.json\nL t/z262136.json\nL t/z262137.json\nL t/z300000.json\nL t/empty.json\n'
  printf 'S j\nS d\nS t\n'; } > "$C/gen-json.txt"

# gen-fields: record extraction, one file per case, each loaded
cat > "$W/fields.txt" <<'EOF'
{"candidate_commit":"0123456789abcdef0123456789abcdef01234567"}
{"run_commit":"0123456789abcdef0123456789abcdef01234567"}
{"git_commit":"0123456789ABCDEF0123456789abcdef01234567"}
{"candidate_git_commit":"0123456789abcdef0123456789abcdef01234567"}
{"qualified_implementation_commit":"0123456789abcdef0123456789abcdef01234567"}
{"git_commit":"0123456789abcdef0123456789abcdef0123456"}
{"git_commit":"0123456789abcdef0123456789abcdef012345678"}
{"git_commit":"0123456789abcdef0123456789abcdef0123456g"}
{"git_commit":12345,"run_commit":"1111111111111111111111111111111111111111"}
{"git_commit":"2222222222222222222222222222222222222222","candidate_commit":"1111111111111111111111111111111111111111"}
{"nested":{"git_commit":"0123456789abcdef0123456789abcdef01234567"}}
{"physics_commit":"0123456789abcdef0123456789abcdef01234567"}
{"physics_forge_commit":"0123456789abcdef0123456789abcdef01234567"}
{"x":{"physics_commit":"0123456789abcdef0123456789abcdef01234567"}}
{"x":{"y":{"physics_forge_commit":"0123456789abcdef0123456789abcdef01234567"}},"physics_commit":"bad"}
{"physics_commit":"bad","physics_forge_commit":"bad2"}
{"run_id":"run-42"}
{"run_id":42}
{"run_id":"0123456789012345678901234567890123456789012345678901234567890123456789"}
{"realization_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
{"selected_realization_identity":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}
{"x":{"promoted_realization_identity":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}}
{"compiler_realization_id":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}
{"realization_id":"short","compiler_realization_id":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}
{"machine_identity":{"node":"n1","architecture":"aarch64","release":"6.8"}}
{"machine_identity":{"node":"n1"},"host":{"sysname":"Linux"}}
{"machine_identity":"flat","host":{"sysname":"Linux","os":"Ubuntu","machine":"x86_64","arch":"amd64","release":"6.1","core_class_midr_part":"0xd4f"}}
{"host":{"os":"Darwin","arch":"arm64"}}
{"host":{"sysname":"Linux","machine":"aarch64","release":"0123456789012345678901234567890123456789012345678901234567890123456789"}}
{"host":{"sysname":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","machine":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","release":"ccccccccccccccccccc"}}
{"host":{"sysname":"","machine":5}}
{"host":"str"}
{"qualification_gates":{"total":10,"passed":9}}
{"qualification_gates":{"total":"10","passed":9,"gates":{"A_PASS":"PASS","B":"FAIL"}}}
{"qualification_gates":{"total":4294967295,"passed":0}}
{"qualification_gates":{"total":4294967296,"passed":0,"gates":{"A":"PASS"}}}
{"qualification_gates":{"total":-1,"passed":0}}
{"qualification_gates":{"total":1.5,"passed":0}}
{"qualification_gates":{"total":10}}
{"gates":{"build":"PASS","test":"FAIL","lint":"SKIP","x":1}}
{"gates":{"first":"FAIL","ROLLUP_PASS":"PASS","later":"PASS","LAST_PASS":"FAIL"}}
{"gate":{"g":"PASS"},"gates":{"h":"FAIL"}}
{"gates":["PASS"],"gate":"PASS"}
{"gates":{"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa_PASS":"PASS"}}
{"gates":{"_PASS":"PASS","X_PASS":"PASSED"}}
{"schema":"omega.run.v1","status":"PASS"}
{"milestone":"M7","status":"QUALIFIED"}
{"stage_title":"Stage","gates":{"a":"PASS"}}
{"contract_id":"c-1"}
{"schema":"","milestone":"M","status":"S"}
{"status":"only status"}
{"schema":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","status":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}
{"schema":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
{"status":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}
{"schema":5,"milestone":"M","status":7}
{"tree_dirty":true}
{"tree_dirty":false}
{"tree_dirty":"true"}
{"tree_dirty":null,"candidate_trees_clean":{"a":true,"b":false}}
{"candidate_trees_clean":{"a":true,"b":true}}
{"candidate_trees_clean":{}}
{"candidate_trees_clean":[false]}
{"tree_dirty":false,"candidate_trees_clean":{"a":false}}
{"claim":"x\\"y\\\\z\001"}
{"schema":"q\\"uote","status":"b\\\\s"}
{"run_id":"ctl\\u0001"}
EOF
{ awk '{ printf "F f/%03d.json %s\n", NR, $0 }' "$W/fields.txt"
  # every scope signal combination: silicon_observed (absent/true/false/"true"), gpu_uuid,
  # compute_class, a nested qemu_target, and hardware_scope / scope strings
  awk 'BEGIN { split("absent true false \"true\"", so, " ");
         split("Host build|HOST|hosted ci|no silicon claim here|Simulated run|simulator|QEMU virt|silicon|", hs, "|");
         n = 0
         for (a = 1; a <= 4; a++) for (g = 0; g <= 1; g++) for (c = 0; c <= 1; c++) for (q = 0; q <= 1; q++) for (h = 1; h <= 9; h++) for (k = 0; k <= 1; k++) {
           if (h > 1 && (g + c + q) > 1) continue
           s = "{\"schema\":\"scope\""
           if (a > 1) s = s ",\"silicon_observed\":" so[a]
           if (g) s = s ",\"gpu\":{\"gpu_uuid\":\"GPU-1\"}"
           if (c) s = s ",\"compute_class\":\"sm_121\""
           if (q) s = s ",\"run\":{\"cfg\":{\"qemu_target\":\"virt\"}}"
           if (h < 9) s = s ",\"" (k ? "scope" : "hardware_scope") "\":\"" hs[h] "\""
           else if (k) s = s ",\"hardware_scope\":\"simulated\",\"scope\":\"host only\""
           else s = s ",\"hardware_scope\":7,\"gates\":{\"QEMU_VIRT_PASS\":\"PASS\"}"
           printf "F s/%04d.json %s}\n", n++, s } }'
  awk '{ printf "L f/%03d.json\n", NR }' "$W/fields.txt"
  ls_n=$(awk 'BEGIN { split("absent true false \"true\"", so, " "); n = 0
         for (a = 1; a <= 4; a++) for (g = 0; g <= 1; g++) for (c = 0; c <= 1; c++) for (q = 0; q <= 1; q++) for (h = 1; h <= 9; h++) for (k = 0; k <= 1; k++) {
           if (h > 1 && (g + c + q) > 1) continue; n++ } print n }')
  awk -v n="$ls_n" 'BEGIN { for (i = 0; i < n; i++) printf "L s/%04d.json\n", i }'; } > "$C/gen-fields.txt"

# gen-walk: trees for the walk, the cap heap and the views
{ printf 'N many 40\nF many/z.txt not json\nF many/.hidden.json {"schema":"hidden"}\nD many/.hdir\nF many/.hdir/in.json {"schema":"in hidden dir"}\n'
  printf 'F many/sub/a.json {"schema":"sub a"}\nF many/sub/b.txt mentions %s\nK many/link.json f00000.json\nK many/dlink sub\n' "$H1"
  p=deep; for i in 1 2 3 4 5 6 7 8 9 10; do p=$p/d$i; printf 'F %s/r.json {"schema":"depth %d"}\n' "$p" "$i"; done
  L=lp/$(awk 'BEGIN { while (i++ < 121) printf "a" }')
  L2=$L/$(awk 'BEGIN { while (i++ < 121) printf "b" }')
  # the kept path is "lp/" + 121 + "/" + 121 = 246 bytes, then the name: 254, 255 (the longest
  # path the C keeps), 256 and 260 bytes (refused: the walk records an overflow)
  printf 'F %s/ab.json {"schema":"254"}\nF %s/abc.json {"schema":"255"}\nF %s/abcd.json {"schema":"256"}\nF %s/abcdefgh.json {"schema":"260"}\n' "$L2" "$L2" "$L2" "$L2"
  printf 'F lp/a.json {"schema":"a"}\n'
  # roots of 255..258 bytes: the C keeps no path under a root of 256 or more and records an
  # overflow when an entry (not a dot entry) is there
  printf 'F %s/cccccccc/x.json {}\nF %s/ccccccccc/.hid x\nF %s/cccccccccc/y.json {"schema":"%s"}\nD %s/ccccccccccc\n' "$L2" "$L2" "$L2" "$H1" "$L2"
  printf 'F mix/a.json {"schema":"mix a","note":"%s"}\nF mix/b.json {"schema":"mix b","x":"%s%s"}\nF mix/c.txt %s\nF mix/d.json {"bad":"%s"\n' "$H1" "$H2" "$H1" "$H1" "$H1"
  printf 'F mix/e.json {"schema":"e","realization_id":"%s"}\nF mix/f.bin \\0000%s\nF mix/g.json {"a":"\\0000%s"}\nZ mix/h.json 300000\nB mix/i.log 70\n' "$H1" "$H1" "$H1"
  printf 'F mix/j.json {"run":{"deep":{"id":"%s"}}}\nF mix/k.json {"short":"%s"}\n' "$(printf '%s' "$H1" | tr 1 A)" "$(printf '%s' "$H1" | cut -c1-63)"
  printf 'H ca {"schema":"hash named","run_id":"h1"}\\n\nH ca {"schema":"hash named 2"}\nF ca/%s.json {"schema":"name mismatch"}\n' "$H0"
  printf 'F ca/%s.json {"schema":"upper name"}\nF ca/%s.JSON {"schema":"upper ext"}\nF ca/%s0.json {"schema":"65 hex"}\n' "$(printf '%s' "$H0" | tr a A)" "$H0" "$H0"
  printf 'N unp 12\n'; for i in 0 1 2 3 4 5 6 7 8 9; do printf 'F unp/u%d.txt x\n' "$i"; done
  printf 'N cap 30\n'
  printf 'S many\nS many/\nS deep\nS lp\nS mix\nS ca\nS unp\nS cap\n'
  for c in cccccccc ccccccccc cccccccccc cccccccccc/ ccccccccccc; do printf 'S %s/%s\nI %s/%s %s\n' "$L2" "$c" "$L2" "$c" "$H1"; done
  printf 'I mix %s\nI mix %s\nI mix %s\nI many %s\nI ca %s\nI unp %s\n' "$H1" "$H2" "$H0" "$H1" "$H0" "$H1"
  printf 'I mix %s\nI mix %s\n' "$(printf '%s' "$H1" | tr 1 A)" "$(printf '%s' "$H1" | tr 1 a)"
  for c in 1 2 5 15 16 17 29 30 31; do printf 'M %s\nS cap\nI cap %s\n' "$c" "$H1"; done
  printf 'M 3\nS many\nS mix\nM 0\nS cap\n'
  printf 'L ca/%s.json\nL mix/h.json\nL mix/f.bin\nL mix/g.json\nL mix\nL many/link.json\n' "$H0"; } > "$C/gen-walk.txt"

# ---- build the trees of corpus $1 in a fresh directory $2 ----
build_tree() {
  rm -rf "$2"; mkdir -p "$2"
  while IFS= read -r line; do
    k=${line%% *}; rest=${line#* }
    case $k in
      F|H) p=${rest%% *}; body=${rest#* }; [ "$body" = "$rest" ] && body=""
           if [ "$k" = H ]; then
             mkdir -p "$2/$p"; printf '%b' "$body" > "$2/.h.tmp"
             mv "$2/.h.tmp" "$2/$p/$(sha "$2/.h.tmp").json"
           else
             mkdir -p "$(dirname "$2/$p")"; printf '%b' "$body" > "$2/$p"
           fi ;;
      Z) p=${rest%% *}; n=${rest#* }; mkdir -p "$(dirname "$2/$p")"
         { printf '{"a":"'; head -c "$n" /dev/zero | tr '\0' x; printf '"}'; } > "$2/$p" ;;
      B) p=${rest%% *}; n=${rest#* }; mkdir -p "$(dirname "$2/$p")"; head -c "$n" /dev/zero | tr '\0' x > "$2/$p" ;;
      A) p=${rest%% *}; n=${rest#* }; mkdir -p "$(dirname "$2/$p")"
         awk -v n="$n" 'BEGIN { printf "{\"a\":["; for (i = 0; i < n; i++) printf "%s0", (i ? "," : ""); printf "]}" }' > "$2/$p" ;;
      D) mkdir -p "$2/$rest" ;;
      N) p=${rest%% *}; n=${rest#* }; mkdir -p "$2/$p"
         awk -v n="$n" -v d="$2/$p" 'BEGIN { for (i = 0; i < n; i++) { f = sprintf("%s/f%05d.json", d, i)
           printf "{\"schema\":\"n\",\"run_id\":\"r%05d\",\"note\":\"1111111111111111111111111111111111111111111111111111111111111111\"}", i > f; close(f) } }' ;;
      K) p=${rest%% *}; t=${rest#* }; mkdir -p "$(dirname "$2/$p")"; ln -s "$t" "$2/$p" ;;
    esac
  done < "$1"
}

# ---- generate mode: write the goldens from the C dumper, keep the MANIFEST header line ----
if [ -n "$GEN" ]; then
  [ -x "$GEN" ] || { echo "EVIDENCE_PARITY FAIL $GEN is not an executable C dumper"; exit 2; }
  mkdir -p "$GOLD"
  hdr=$(head -n 1 "$GOLD/MANIFEST" 2>/dev/null | grep '^# generated once ' || true)
  [ -n "$hdr" ] || { echo "EVIDENCE_PARITY FAIL write the MANIFEST header line (commit, generator command) first"; exit 2; }
  rm -f "$GOLD"/*.out
  for c in "$C"/*.txt; do
    b=$(basename "$c" .txt)
    build_tree "$c" "$W/tree/$b"
    (cd "$W/tree/$b" && "$GEN" < "$c") > "$GOLD/$b.out" || { echo "EVIDENCE_PARITY FAIL the C dumper failed on $b"; exit 2; }
    [ -s "$GOLD/$b.out" ] || { echo "EVIDENCE_PARITY FAIL empty C output for $b"; exit 2; }
    printf 'corpus %s %s\n' "$b" "$(sha "$c")"
    printf 'golden %s %s\n' "$b" "$(sha "$GOLD/$b.out")"
  done > "$W/MANIFEST.body"
  { printf '%s\n' "$hdr"
    printf '# goldens sha256 (of the corpus and golden lines below) %s\n' "$(sha "$W/MANIFEST.body")"
    cat "$W/MANIFEST.body"; } > "$GOLD/MANIFEST"
  echo "EVIDENCE_PARITY generated $(grep -c '^golden ' "$GOLD/MANIFEST") goldens in $GOLD"
  exit 0
fi

# ---- the corpora and goldens must be the ones the MANIFEST records ----
M=$GOLD/MANIFEST
[ -f "$M" ] || { echo "EVIDENCE_PARITY FAIL missing $M"; exit 2; }
grep -q '^# generated once from the C at main commit 3f2c70dc5' "$M" \
  || { echo "EVIDENCE_PARITY FAIL $M header line does not name the C reference commit"; exit 2; }
grep -v '^#' "$M" > "$W/MANIFEST.body"
[ "$(sed -n 2p "$M")" = "# goldens sha256 (of the corpus and golden lines below) $(sha "$W/MANIFEST.body")" ] \
  || { echo "EVIDENCE_PARITY FAIL $M body does not match its recorded sha256"; exit 2; }
bad=0
nc=$(ls "$C"/*.txt | wc -l | tr -d ' ')
[ "$nc" -eq "$(grep -c '^corpus ' "$M")" ] || { echo "EVIDENCE_PARITY FAIL $nc corpora built, $(grep -c '^corpus ' "$M") in the MANIFEST"; bad=1; }
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  want=$(awk -v b="$b" '$1 == "corpus" && $2 == b { print $3 }' "$M")
  [ "$want" = "$(sha "$c")" ] || { echo "EVIDENCE_PARITY FAIL corpus $b is not the one the goldens were generated from (regenerate: --generate)"; bad=1; }
  want=$(awk -v b="$b" '$1 == "golden" && $2 == b { print $3 }' "$M")
  [ -f "$GOLD/$b.out" ] && [ "$want" = "$(sha "$GOLD/$b.out")" ] || { echo "EVIDENCE_PARITY FAIL golden $b.out missing or not the recorded sha256"; bad=1; }
done
[ "$bad" -eq 0 ] || exit 2

# ---- the OM-2 dumper, from the shipped modules (mk/visor-verify.mk VISOR_EVIDENCE_OM_SRCS) ----
OMS="src/visor/visor.om src/visor/visor_evidence.om tests/visor/evidence_dump.om"
(printf 'om2\n'; sed -e '/^om2$/d' -e 's/^export fn /fn /' $OMS) | "$OMC" > "$W/evidence_dump_om"
chmod +x "$W/evidence_dump_om"

# ---- compare ----
files=0; lines=0; diff=0
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  build_tree "$c" "$W/tree/$b"
  rc=0
  (cd "$W/tree/$b" && "$W/evidence_dump_om" < "$c") > "$W/out/$b.om" || rc=$?
  n=$(wc -l < "$c" | tr -d ' ')
  files=$((files + 1)); lines=$((lines + n))
  if [ "$rc" -eq 0 ] && cmp -s "$GOLD/$b.out" "$W/out/$b.om"; then
    echo "PARITY $b lines=$n same"
  else
    diff=$((diff + 1))
    echo "PARITY $b lines=$n DIFF exit=$rc"
    diff "$GOLD/$b.out" "$W/out/$b.om" | head -20 || true
  fi
done
echo "EVIDENCE_PARITY files=$files lines=$lines diff=$diff reference=C@3f2c70dc5 (goldens) work=$W"
[ "$diff" -eq 0 ]
