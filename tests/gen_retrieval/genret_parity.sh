#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# genret_parity.sh -- differential qualification of the pure OM-2 genret (tools/gen/retrieval/genret.om,
# the GEN-4 retrieval provider) against the C it replaced (tools/gen/retrieval/genret.c, retired by wave 31).
#
# Every case of every corpus runs genret in a fresh case directory and records, byte for byte: the exit
# status, stdout, stderr (the case directory and the pid in a .tmp.<pid> name normalized), each file of the
# --out directory (selected.tsv as bytes; every other file as bytes when at most 2048 long in the hand and
# record corpora, else as its length and sha256), and any .tmp.* directory left behind. The concatenation is compared with the committed
# golden tests/gen_retrieval/golden/<corpus>.out. The goldens were generated ONCE from the C genret at main
# commit 3f2c70dc5 (built from that commit's tools/gen/retrieval/genret.c, no dumper: the C tool itself is
# the generator); golden/MANIFEST records the commit, the generator commands, the C file's git blob and
# sha256, and the sha256 of every corpus, golden and fixture. This script needs no C compiler.
#
# Two builds of each implementation run: `any` (test-only binding, no built-in recheck pin; receipt claim
# "unverified"), and `prod` (built-in pin = the sha256 of tests/gen_retrieval/fake_recheck.sh, source claim
# GR_CLAIM below), which is how mk/gen-retrieval.mk binds the shipped genret to its recheck binary. The
# validator is the stand-in fake_recheck.sh (modes in its header), so the goldens do not depend on a
# compiler's recheck binary.
#
# Corpus lines (`#` and blank lines skipped): `<case name> <shell commands>`. Each case starts in a fresh
# directory holding c/ (a copy of the fixture record set), t/ (requirement and prompt of devq_clamp) and rc
# (the fake validator); the commands may change them and run genret through these helpers:
#   g any|prod <args...>   run genret and record the result
#   q [args...]            g ${V:-any} query with the usual options: --corpus c/MANIFEST, its sha256 (or
#                          $MSHA), --recheck ${RC:-rc} --recheck-sha256 sha256(rc) (or $RPIN), --kind
#                          ${KIND-raw} --k ${K-3} --cap-bytes ${CAP-4096} --requirement ${REQ:-t/requirement}
#                          --prompt ${PR:-t/prompt} --out ${OUTD:-o}, then the given args
#   corp base|syn          c/ := a copy of that record set (made for base unless the case starts with corp
#                          or corpl)                          corpl base|syn  c := a link to it (read-only cases)
#   reman                  rewrite c/MANIFEST from c/raw, c/abstraction
#   task <devq_*>          t/ := that fixture task            stask N  t/ := synthetic query N
#   fmode <mode>           the fake validator's mode for c/   recf <id>  path of record <id> in c/
#
# usage: tests/gen_retrieval/genret_parity.sh [OMC]
#          prints PARITY lines and GENRET_PARITY ...; exit 0 iff every corpus equals its golden
#        tests/gen_retrieval/genret_parity.sh --generate <C genret_any> <C genret_prod>
#          rewrites the goldens and the MANIFEST body from those binaries (keeps the header line)
#        GENRET_PARITY_ONLY=<OM genret_any>,<OM genret_prod> runs prebuilt binaries (the mutants use it)
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HERE=$ROOT/tests/gen_retrieval
GOLD=$HERE/golden
FXR=$ROOT/tools/gen/retrieval/fixtures
FAKE=$HERE/fake_recheck.sh
GR_CLAIM=9d7a3c74de404170d32eacbc0ab551e3b598a086d9b300a94825e70614533e6c
LC_ALL=C; export LC_ALL
GEN=""
if [ "${1:-}" = "--generate" ]; then
  GANY=${2:?usage: genret_parity.sh --generate <C genret_any> <C genret_prod>}
  GPROD=${3:?usage: genret_parity.sh --generate <C genret_any> <C genret_prod>}
  GEN=1
else
  OMC=${1:-$ROOT/seed/out/omc}
  case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
fi
W=${GENRET_PARITY_WORK:-$(mktemp -d)}
case $W in /*) ;; *) W=$(pwd)/$W ;; esac
mkdir -p "$W"
sha() { if [ -f "$1" ]; then sha256sum "$1" | cut -d' ' -f1; else printf '%064d\n' 0; fi; }
treesha() { (cd "$1" && find . -type f | sort | xargs sha256sum | sha256sum | cut -d' ' -f1); }

# ---- fixture record sets ----
FIX=$W/fix
rm -rf "$FIX"; mkdir -p "$FIX/base" "$FIX/syn/raw" "$FIX/syn/abstraction" "$FIX/syn/receipts" "$FIX/synq"
cp -R "$FXR/corpus/records/." "$FIX/base/"
# syn: 300 records (three recheck batches) from a fixed LCG over a small vocabulary: both kinds, splits,
# validities, 1..3 families, fenced bodies and descriptions, mixed case, punctuation, long bodies; and 40
# synthetic queries over the same vocabulary.
awk -v D="$FIX" 'function rnd(n) { s = (s * 1103515245 + 12345) % 2147483648; return int(s / 65536) % n }
  function w() { return V[rnd(nv)] }
  function words(n,   i, o) { o = w(); for (i = 1; i < n; i++) o = o " " w(); return o }
  BEGIN { s = 7; nv = split("sat sub clamp add mul div digits count range sum dot vec norm max min abs " \
      "shift mask bits byte word hash mix fold scan sort pick tree node leaf path cost gain loss mean " \
      "ratio step loop bound zero one", V, " ");
    split("u8 u16 u32 u64 i8 i32 i64 bool", T, " ");
    for (r = 0; r < 300; r++) {
      kind = rnd(2) ? "raw" : "abstraction"; id = sprintf("syn-%03d", r)
      f = D "/syn/" kind "/" id ".rec"
      printf "gen-record 1\nid %s\nkind %s\n", id, kind > f
      x = rnd(10); printf "split %s\n", (x < 8 ? "corpus" : (x == 8 ? "heldout" : "dev")) > f
      nf = 1 + rnd(3); fam = "fam" rnd(10); for (i = 1; i < nf; i++) fam = fam " fam" rnd(10)
      printf "family %s\n", fam > f
      printf "entry %s_%s%d\n", w(), w(), r > f
      np = rnd(4); p = ""; for (i = 0; i < np; i++) p = p (i ? " " : "") T[1 + rnd(8)]
      if (np) printf "params %s\n", p > f; else printf "params\n" > f
      printf "ret %s\n", T[1 + rnd(8)] > f
      printf "signature fn %s\n", w() > f
      d = words(2 + rnd(12)); if (rnd(5) == 0) d = toupper(substr(d, 1, 1)) substr(d, 2) "."
      if (r % 97 == 13) d = d " ```"
      printf "desc %s\n", d > f
      x = rnd(12); printf "validity %s\n", (x < 10 ? "verified" : (x == 10 ? "unverified" : "refuted")) > f
      printf "body\n" > f
      nb = 1 + rnd(r % 50 == 0 ? 60 : 8)
      for (i = 0; i < nb; i++) printf "%s %s(%s, %d) %s;\n", w(), toupper(w()), w(), rnd(1000), words(1 + rnd(4)) > f
      if (r % 89 == 7) printf "```\n" > f
      printf "end\n" > f
      close(f) }
    for (qn = 0; qn < 40; qn++) {
      dd = sprintf("%s/synq/%02d", D, qn); system("mkdir -p " dd)
      f = dd "/requirement"
      printf "# synthetic query %d\nkind task\nentry %s_%s\n", qn, w(), w() > f
      np = rnd(4); p = ""; for (i = 0; i < np; i++) p = p (i ? " " : "") T[1 + rnd(8)]
      if (np) printf "params %s\n", p > f; else printf "params\n" > f
      printf "ret %s\n", T[1 + rnd(8)] > f; close(f)
      f = dd "/prompt"; printf "Write a function that %s. It should %s!\n", words(3 + rnd(10)), words(1 + rnd(6)) > f; close(f) } }'
(cd "$FIX/syn" && find raw abstraction -name '*.rec' | sort | xargs sha256sum > MANIFEST)

# ---- corpora ----
C=$W/corpus
rm -rf "$C"; mkdir -p "$C"
cp "$HERE/genret_corpus.txt" "$C/hand.txt"
# queries: every fixture task, both kinds, k 1 2 3 64, cap 1 300 700 1500 4096, modes normal, irrelevant and
# empty; then length-matched with targets 1 300 900 1500 2500 4096 under caps 1500 and 4096
awk 'BEGIN { nt = split("devq_clamp devq_digits devq_dot devq_none devq_twin", ts, " "); split("raw abstraction", ks, " ");
    nk = split("1 2 3 64", kk, " "); nc = split("1 300 700 1500 4096", cc, " "); split("normal irrelevant empty", ms, " ");
    ng = split("1 300 900 1500 2500 4096", tg, " ")
    for (t = 1; t <= nt; t++) for (k = 1; k <= 2; k++) for (j = 1; j <= nk; j++) {
      for (c = 1; c <= nc; c++) for (m = 1; m <= 3; m++)
        printf "q-%s-%s-k%s-c%s-%s corpl base; task %s; KIND=%s K=%s CAP=%s q --mode %s\n", ts[t], ks[k], kk[j], cc[c], ms[m], ts[t], ks[k], kk[j], cc[c], ms[m]
      for (c = 4; c <= 5; c++) for (g = 1; g <= ng; g++) if (tg[g] + 0 <= cc[c] + 0)
        printf "lm-%s-%s-k%s-c%s-t%s corpl base; task %s; KIND=%s K=%s CAP=%s q --mode length-matched --target-bytes %s\n", ts[t], ks[k], kk[j], cc[c], tg[g], ts[t], ks[k], kk[j], cc[c], tg[g] } }' > "$C/gen-queries.txt"
# synthetic set: 40 queries, both kinds, k 3 and 10, cap 4096 and 20000, normal and length-matched 6000
awk 'BEGIN { for (n = 0; n < 40; n++) for (k = 0; k <= 1; k++) {
      kind = k ? "abstraction" : "raw"; qq = sprintf("%02d", n)
      printf "syn-%s-%s-k3 corpl syn; stask %s; KIND=%s q\n", qq, kind, qq, kind
      printf "syn-%s-%s-k10 corpl syn; stask %s; KIND=%s K=10 CAP=20000 q --exclude-family fam%d\n", qq, kind, qq, kind, n % 10
      printf "syn-%s-%s-lm corpl syn; stask %s; KIND=%s K=2 CAP=20000 q --mode length-matched --target-bytes 6000\n", qq, kind, qq, kind
      printf "syn-%s-%s-irr corpl syn; stask %s; KIND=%s K=5 CAP=8000 q --mode irrelevant\n", qq, kind, qq, kind } }' > "$C/gen-syn.txt"
# record validation: one fault per field rule, on raw-clamp_sub (the manifest rewritten, so only the fault
# is reported)
awk 'function rec(name, perl) { printf "rec-%s perl -0pi -e %c%s%c \"$(recf raw-clamp_sub)\"; reman; q\n", name, 39, perl, 39 }
  BEGIN {
    rec("magic", "s/^gen-record 1/gen-record 2/"); rec("short", "$_ = \"gen-rec\"");
    rec("no-body", "s/\\nbody\\n.*//s; $_ .= \"\\n\""); rec("header-tab", "s/^desc /desc a\\tb /m");
    rec("header-del", "s/^desc /desc a\\x7f /m"); rec("key-repeat", "s/^kind raw\\n/kind raw\\nkind raw\\n/m");
    rec("key-novalue", "s/^ret u32$/ret/m"); rec("params-bare", "s/^params u32 u32$/params/m");
    rec("id-upper", "s/^id raw-clamp_sub$/id Raw-clamp_sub/m"); rec("id-65", "s/^id raw-clamp_sub$/\"id \" . (\"a\" x 65)/me");
    rec("id-64", "s/^id raw-clamp_sub$/\"id \" . (\"a\" x 64)/me"); rec("kind-other", "s/^kind raw$/kind rawx/m");
    rec("kind-abs", "s/^kind raw$/kind abstraction/m"); rec("split-space", "s/^split corpus$/split cor pus/m");
    rec("split-dev", "s/^split corpus$/split dev/m"); rec("family-2sp", "s/^family (.*)$/family $1  x/m");
    rec("family-upper", "s/^family (.*)$/family X/m"); rec("family-65", "s/^family (.*)$/\"family \" . (\"f\" x 65)/me");
    rec("family-trail", "s/^family (.*)$/family $1 /m"); rec("family-3", "s/^family (.*)$/family $1 a-b c_d/m");
    rec("validity-upper", "s/^validity verified$/validity Verified/m"); rec("validity-17", "s/^validity verified$/\"validity \" . (\"v\" x 17)/me");
    rec("validity-16", "s/^validity verified$/\"validity \" . (\"v\" x 16)/me"); rec("validity-dig", "s/^validity verified$/validity v1/m");
    rec("entry-digit", "s/^entry clamp_sub$/entry 1clamp/m"); rec("entry-dash", "s/^entry clamp_sub$/entry clamp-sub/m");
    rec("entry-65", "s/^entry clamp_sub$/\"entry \" . (\"E\" x 65)/me"); rec("entry-mixed", "s/^entry clamp_sub$/entry _Clamp9/m");
    rec("params-2sp", "s/^params u32 u32$/params u32  u32/m"); rec("params-17", "s/^params u32 u32$/\"params \" . (\"p\" x 17)/me");
    rec("params-upper", "s/^params u32 u32$/params U32/m"); rec("params-trail", "s/^params u32 u32$/params u32 /m");
    rec("ret-dash", "s/^ret u32$/ret u-8/m"); rec("ret-17", "s/^ret u32$/\"ret \" . (\"r\" x 17)/me");
    rec("desc-513", "s/^desc .*$/\"desc \" . (\"d\" x 513)/me"); rec("desc-512", "s/^desc .*$/\"desc \" . (\"D\" x 512)/me");
    rec("desc-fence", "s/^desc (.*)$/desc $1 ```x/m"); rec("missing-split", "s/^split corpus\\n//m");
    rec("missing-desc", "s/^desc .*\\n//m"); rec("body-empty", "s/\\nbody\\n.*/\\nbody\\n/s");
    rec("body-noeol", "s/\\n\\z//"); rec("body-tab", "s/^ret 0$/ret\\t0/m"); rec("body-high", "s/^ret 0$/ret \\xc3\\xa9/m");
    rec("body-cr", "s/^ret 0$/ret 0\\r/m"); rec("body-fence", "s/^ret 0$/```/m"); rec("unknown-key", "s/^kind raw$/kind raw\\nzzz anything at all/m");
    rec("key-prefix", "s/^kind raw$/kind raw\\nkindx raw/m"); rec("body-key", "s/^body$/bodyx 1\\nbody/m");
    rec("over-64k", "$_ .= (\"x\" x 70) . \"\\n\" for 1..1000");
    rec("at-64k", "$_ .= (\"y\" x (65536 - length($_) - 1)) . \"\\n\"");
    rec("over-by-1", "$_ .= (\"y\" x (65536 - length($_))) . \"\\n\"") }' > "$C/gen-records.txt"

# ---- generate mode: write the goldens from the C genret, keep the MANIFEST header line ----
run_corpus() {   # run_corpus <any bin> <prod bin> <corpus file> <out file>
  RA=$1 RP=$2 cf=$3 of=$4
  : > "$of"
  case $(basename "$cf") in hand.txt|gen-records.txt) INL=2048 ;; *) INL=0 ;; esac
  R=$W/run
  while IFS= read -r line; do
    case $line in ''|'#'*) continue ;; esac
    name=${line%% *}; cmd=${line#* }
    rm -rf "$R"; mkdir -p "$R"
    # each case in a fresh `sh -e`, outside any || context, so a failing setup command stops it
    st=0
    (cd "$R" && R=$R RA=$RA RP=$RP FIX=$FIX FXR=$FXR FAKE=$FAKE INL=$INL name=$name sh -e -c '. "$1"; eval "$2"' sh "$W/helpers.sh" "$cmd") >> "$of" || st=$?
    [ "$st" -eq 0 ] || { echo "GENRET_PARITY FAIL case $name: its commands failed (exit $st)"; return 2; }
    grep -q "^== $name\$" "$of" || { echo "GENRET_PARITY FAIL case $name ran no genret"; return 2; }
    chmod -R u+rwx "$R" 2>/dev/null || true
  done < "$cf"
}
cat > "$W/helpers.sh" <<'EOF'
      sha() { if [ -f "$1" ]; then sha256sum "$1" | cut -d' ' -f1; else printf '%064d\n' 0; fi; }
      corp() { rm -rf c; mkdir c; cp -R "$FIX/$1/." c/; }
      corpl() { rm -rf c; ln -s "$FIX/$1" c; }
      reman() { (cd c && find raw abstraction -name '*.rec' 2>/dev/null | sort | xargs -r sha256sum > MANIFEST); }
      fmode() { printf '%s\n' "$1" > c/fake_mode; }
      task() { rm -rf t; mkdir t; cp "$FXR/tasks/$1/requirement" "$FXR/tasks/$1/prompt" t/; }
      stask() { rm -rf t; mkdir t; cp "$FIX/synq/$1/requirement" "$FIX/synq/$1/prompt" t/; }
      recf() { case $1 in raw-*) echo c/raw/$1.rec ;; *) echo c/abstraction/$1.rec ;; esac; }
      g() {
        if [ "$1" = prod ]; then b=$RP; else b=$RA; fi
        shift
        rc=0; "$b" "$@" > "$R/.so" 2> "$R/.se" < /dev/null || rc=$?
        printf '== %s\nexit %d\n-- stdout\n' "$name" "$rc"; cat "$R/.so"
        printf -- '-- stderr\n'; sed -e "s|$R|@CASE|g" -e 's/\.tmp\.[0-9][0-9]*/.tmp.PID/g' "$R/.se"
        o=${OUTD:-o}
        if [ -d "$o" ] && [ ! -L "$o" ]; then
          for f in $(cd "$o" && ls -A | sort); do
            n=$(wc -c < "$o/$f")
            if [ "$n" -le "$INL" ] || [ "$f" = selected.tsv ]; then printf -- '-- file %s %d\n' "$f" "$n"; cat "$o/$f"; printf '\n'
            else printf -- '-- file %s %d sha256 %s\n' "$f" "$n" "$(sha "$o/$f")"; fi
          done
        fi
        for l in $(ls -A | grep '\.tmp\.' || true); do printf -- '-- left %s\n' "$(echo "$l" | sed 's/\.tmp\.[0-9][0-9]*/.tmp.PID/')"; done
      }
      q() { g "${V:-any}" query --corpus c/MANIFEST --manifest-sha256 "${MSHA:-$(sha c/MANIFEST)}" --recheck "${RC:-rc}" \
              --recheck-sha256 "${RPIN:-$(sha "${RC:-rc}")}" --kind "${KIND-raw}" --k "${K-3}" --cap-bytes "${CAP-4096}" \
              --requirement "${REQ:-t/requirement}" --prompt "${PR:-t/prompt}" --out "${OUTD:-o}" "$@"; }
      case $2 in corp\ *|corpl\ *) ;; *) corp base ;; esac
      task devq_clamp; cp "$FAKE" rc; chmod 755 rc
EOF

if [ -n "$GEN" ]; then
  for b in "$GANY" "$GPROD"; do [ -x "$b" ] || { echo "GENRET_PARITY FAIL $b is not an executable C genret"; exit 2; }; done
  case $GANY in /*) ;; *) GANY=$(pwd)/$GANY ;; esac
  case $GPROD in /*) ;; *) GPROD=$(pwd)/$GPROD ;; esac
  mkdir -p "$GOLD"
  hdr=$(head -n 1 "$GOLD/MANIFEST" 2>/dev/null | grep '^# generated once ' || true)
  [ -n "$hdr" ] || { echo "GENRET_PARITY FAIL write the MANIFEST header line (commit, generator command) first"; exit 2; }
  rm -f "$GOLD"/*.out
  { printf 'fixture fake_recheck %s\n' "$(sha "$FAKE")"
    printf 'fixture base %s\n' "$(treesha "$FIX/base")"
    printf 'fixture syn %s\n' "$(treesha "$FIX/syn")"
    printf 'fixture synq %s\n' "$(treesha "$FIX/synq")"
    for c in "$C"/*.txt; do
      b=$(basename "$c" .txt)
      run_corpus "$GANY" "$GPROD" "$c" "$GOLD/$b.out" >&2 || exit 2
      printf 'corpus %s %s\n' "$b" "$(sha "$c")"
      printf 'golden %s %s\n' "$b" "$(sha "$GOLD/$b.out")"
    done; } > "$W/MANIFEST.body"
  { printf '%s\n' "$hdr"
    printf '# goldens sha256 (of the fixture, corpus and golden lines below) %s\n' "$(sha "$W/MANIFEST.body")"
    cat "$W/MANIFEST.body"; } > "$GOLD/MANIFEST"
  echo "GENRET_PARITY generated $(grep -c '^golden ' "$GOLD/MANIFEST") goldens in $GOLD"
  exit 0
fi

# ---- the fixtures, corpora and goldens must be the ones the MANIFEST records ----
M=$GOLD/MANIFEST
[ -f "$M" ] || { echo "GENRET_PARITY FAIL missing $M"; exit 2; }
grep -q '^# generated once from the C at main commit 3f2c70dc5' "$M" \
  || { echo "GENRET_PARITY FAIL $M header line does not name the C reference commit"; exit 2; }
grep -v '^#' "$M" > "$W/MANIFEST.body"
[ "$(sed -n 2p "$M")" = "# goldens sha256 (of the fixture, corpus and golden lines below) $(sha "$W/MANIFEST.body")" ] \
  || { echo "GENRET_PARITY FAIL $M body does not match its recorded sha256"; exit 2; }
bad=0
for fx in fake_recheck base syn synq; do
  case $fx in fake_recheck) got=$(sha "$FAKE") ;; *) got=$(treesha "$FIX/$fx") ;; esac
  [ "$(awk -v b="$fx" '$1 == "fixture" && $2 == b { print $3 }' "$M")" = "$got" ] \
    || { echo "GENRET_PARITY FAIL fixture $fx is not the one the goldens were generated from"; bad=1; }
done
nc=$(ls "$C"/*.txt | wc -l | tr -d ' ')
[ "$nc" -eq "$(grep -c '^corpus ' "$M")" ] || { echo "GENRET_PARITY FAIL $nc corpora built, $(grep -c '^corpus ' "$M") in the MANIFEST"; bad=1; }
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  [ "$(awk -v b="$b" '$1 == "corpus" && $2 == b { print $3 }' "$M")" = "$(sha "$c")" ] \
    || { echo "GENRET_PARITY FAIL corpus $b is not the one the goldens were generated from (regenerate: --generate)"; bad=1; }
  want=$(awk -v b="$b" '$1 == "golden" && $2 == b { print $3 }' "$M")
  [ -f "$GOLD/$b.out" ] && [ "$want" = "$(sha "$GOLD/$b.out")" ] || { echo "GENRET_PARITY FAIL golden $b.out missing or not the recorded sha256"; bad=1; }
done
[ "$bad" -eq 0 ] || exit 2

# ---- the OM genret, both bindings, from the shipped source (as mk/gen-retrieval.mk GENRET_UNIT joins it) ----
if [ -n "${GENRET_PARITY_ONLY:-}" ]; then
  OA=${GENRET_PARITY_ONLY%,*}; OP=${GENRET_PARITY_ONLY#*,}
else
  OA=$W/genret_any_om; OP=$W/genret_prod_om
  printf 'text gr_bin_pin ""\ntext gr_src_claim "unverified"\n' > "$W/bind_any.om"
  printf 'text gr_bin_pin "%s"\ntext gr_src_claim "%s"\n' "$(sha "$FAKE")" "$GR_CLAIM" > "$W/bind_prod.om"
  for v in any prod; do
    (cd "$ROOT" && printf 'om2\n' && sed '/^om2$/d' seed/ng/sha256.om "$W/bind_$v.om" tools/gen/retrieval/genret.om) | "$OMC" > "$W/genret_${v}_om"
    chmod +x "$W/genret_${v}_om"
  done
fi

# ---- compare ----
mkdir -p "$W/out"
files=0; cases=0; diff=0
# cheapest corpora first; GENRET_PARITY_STOP=1 (the mutants) stops at the first corpus that differs
for b in hand gen-records gen-queries gen-syn; do
  [ "${GENRET_PARITY_STOP:-0}" = 1 ] && [ "$diff" -ne 0 ] && break
  c=$C/$b.txt
  run_corpus "$OA" "$OP" "$c" "$W/out/$b.om" || { diff=$((diff + 1)); continue; }
  n=$(grep -c '^== ' "$W/out/$b.om" || true)
  files=$((files + 1)); cases=$((cases + n))
  if cmp -s "$GOLD/$b.out" "$W/out/$b.om"; then
    echo "PARITY $b runs=$n same"
  else
    diff=$((diff + 1))
    echo "PARITY $b runs=$n DIFF"
    diff "$GOLD/$b.out" "$W/out/$b.om" | head -20 || true
  fi
done
echo "GENRET_PARITY files=$files runs=$cases diff=$diff reference=C@3f2c70dc5 (goldens) work=$W"
[ "$diff" -eq 0 ]
