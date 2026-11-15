#!/bin/sh
# test.sh -- tools/codebook checks: Lean differential, exhaustive 2-layer round trip, HMAC oracle,
# codebook validation, verify negatives, usage. Run from anywhere:  sh tools/codebook/test.sh
# BIN defaults to <repo>/build/codebook/codebook, else codebook.bin beside this script.
# KEYDIR (default $FIX/key) holds generated test keys; keys are never printed.
# Needs: sh, awk, sha256sum, python3 (HMAC oracle only: hmac+hashlib), optional lean (vectors).
set -u
D=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$D/../.." && pwd)
if [ -z "${BIN:-}" ]; then
  if [ -x "$ROOT/build/codebook/codebook" ]; then BIN=$ROOT/build/codebook/codebook
  elif [ -x "$D/codebook.bin" ]; then BIN=$D/codebook.bin
  else echo "test.sh: no codebook binary" >&2; exit 2
  fi
fi
CB=${CB:-$D/codebook.tsv}
FIX=${FIX:-${TMPDIR:-/tmp}/codebook-test.$$}
LEAN=${LEAN:-lean}
rm -rf "$FIX"; mkdir -p "$FIX"; chmod 700 "$FIX"
KEYDIR=${KEYDIR:-$FIX/key}; mkdir -p "$KEYDIR"; chmod 700 "$KEYDIR"
P=0; F=0; S=0
ok() { P=$((P+1)); }
no() { F=$((F+1)); echo "FAIL $1"; }
skip() { S=$((S+1)); echo "SKIP $1"; }
chk() { if [ "$2" = "$3" ]; then ok; else no "$1: got [$2] want [$3]"; fi; }
elf_em() { od -An -N2 -j 18 -t u2 "$1" | tr -d ' \n'; }
host_em() { case "$(uname -m)" in aarch64|arm64) echo 183;; x86_64|amd64) echo 62;; *) echo 0;; esac; }
pick_tracer() {
  TRC=
  if [ "$(elf_em "$1")" = "$(host_em)" ] && command -v strace >/dev/null 2>&1; then
    TRC=strace
  elif command -v qemu-aarch64-static >/dev/null 2>&1; then
    TRC=$(command -v qemu-aarch64-static)
  elif command -v qemu-aarch64 >/dev/null 2>&1; then
    TRC=$(command -v qemu-aarch64)
  fi
}
mkkey() { [ -s "$KEYDIR/$1" ] || (umask 077; head -c "$2" /dev/urandom > "$KEYDIR/$1"); chmod 600 "$KEYDIR/$1"; }
mkkey k32 32; mkkey k64 64; mkkey k65 65; mkkey k100 100; mkkey kother 32
K=$KEYDIR/k32

# 1. Lean differential on generated messages (vectors/gen.tsv = lean --run proof/CodebookProof.lean gen 1200)
G=$D/vectors/gen.tsv; DV=$D/vectors/dec.tsv
if command -v "$LEAN" >/dev/null 2>&1 && [ -f "$D/proof/CodebookProof.lean" ]; then
  "$LEAN" --run "$D/proof/CodebookProof.lean" gen 1200 > "$FIX/gen.tsv" 2>/dev/null
  "$LEAN" --run "$D/proof/CodebookProof.lean" dec 1000 > "$FIX/dec.tsv" 2>/dev/null
  "$LEAN" --run "$D/proof/CodebookProof.lean" exh > "$FIX/exh.tsv" 2>/dev/null
  chk lean-regenerates-gen "$(sha256sum < "$FIX/gen.tsv")" "$(sha256sum < "$G")"
  chk lean-regenerates-dec "$(sha256sum < "$FIX/dec.tsv")" "$(sha256sum < "$DV")"
  EXSRC=lean
else
  echo "note: $LEAN not found; using committed Lean vectors and an awk exhaustive list"
  awk 'BEGIN{for(t=0;t<900;t++)printf "%d\t%03d\n",t,t; for(e=900;e<1000;e++)for(t=0;t<900;t++)printf "%d.%d\t%03d%03d\n",e,t,e,t}' > "$FIX/exh.tsv"
  EXSRC=awk
fi
cut -f1 "$G" > "$FIX/g.msg"; cut -f2 "$G" > "$FIX/g.dig"
"$BIN" enc < "$FIX/g.msg" > "$FIX/g.enc"
"$BIN" dec < "$FIX/g.dig" > "$FIX/g.dec"
N=$(wc -l < "$G")
D1=$(paste "$FIX/g.enc" "$FIX/g.dig" | awk -F'\t' '$1==$2{c++} END{print c+0}')
D2=$(paste "$FIX/g.dec" "$FIX/g.msg" | awk -F'\t' '$1==$2{c++} END{print c+0}')
chk "lean-gen-count>=1000" "$([ "$N" -ge 1000 ] && echo y)" y
chk "diff-encode-vs-lean ($N)" "$D1" "$N"
chk "diff-decode-vs-lean ($N)" "$D2" "$N"
# random digit strings: Lean decode (some/none) vs binary dec
cut -f1 "$DV" > "$FIX/d.in"
"$BIN" dec < "$FIX/d.in" | sed 's/^ERR .*/ERR/' > "$FIX/d.out"
ND=$(wc -l < "$DV")
D3=$(cut -f2 "$DV" | paste - "$FIX/d.out" | awk -F'\t' '$1==$2{c++} END{print c+0}')
chk "diff-decode-random-vs-lean ($ND)" "$D3" "$ND"
NE=$(awk -F'\t' '$2=="ERR"{c++} END{print c+0}' "$DV")
chk "random-has-both-outcomes" "$([ "$NE" -gt 100 ] && [ "$NE" -lt $((ND-100)) ] && echo y)" y

# 2. exhaustive round trip: every code with 1 or 2 layers (900 + 100*900)
cut -f1 "$FIX/exh.tsv" > "$FIX/x.msg"; cut -f2 "$FIX/exh.tsv" > "$FIX/x.dig"
NX=$(wc -l < "$FIX/x.msg")
chk "exhaustive-count ($EXSRC)" "$NX" 90900
"$BIN" enc < "$FIX/x.msg" > "$FIX/x.enc"; "$BIN" dec < "$FIX/x.dig" > "$FIX/x.dec"
chk exhaustive-encode "$(cmp -s "$FIX/x.enc" "$FIX/x.dig" && echo same)" same
chk exhaustive-decode "$(cmp -s "$FIX/x.dec" "$FIX/x.msg" && echo same)" same
"$BIN" dec < "$FIX/x.enc" > "$FIX/x.rt"
chk exhaustive-roundtrip "$(cmp -s "$FIX/x.rt" "$FIX/x.msg" && echo same)" same
# a whole exhaustive layer concatenated is one message that decodes back to all its codes
tr -d '\n' < "$FIX/x.dig" | head -c 300000 > "$FIX/big.dig"; echo >> "$FIX/big.dig"
chk big-message-roundtrip "$("$BIN" dec < "$FIX/big.dig" | "$BIN" enc | cmp -s - "$FIX/big.dig" && echo same)" same

# 3. encoder/decoder edge cases
chk enc-edges "$(printf '901.12 345\n\n901\n1.2\n1000\n 5\n5 \n5..6\n0012\n999.999.0\nx\n' | "$BIN" enc | tr '\n' ,)" "901012345,,ERR range,ERR range,ERR syntax,ERR syntax,ERR syntax,ERR syntax,ERR syntax,999999000,ERR syntax,"
chk dec-bad-escape "$(printf '900\n999999\n300900\n' | "$BIN" dec | tr '\n' ,)" "ERR esc,ERR esc,ERR esc,"
chk dec-bad-len-digit "$(printf '12\n1234\n12a\n30 \n' | "$BIN" dec | tr '\n' ,)" "ERR len,ERR len,ERR digit,ERR digit,"

# 4. codebook id and validation
CS=$("$BIN" sha "$CB")
chk sha-equals-sha256sum "$CS" "$(sha256sum < "$CB" | cut -d' ' -f1)"
mkcb() { cp "$CB" "$FIX/$1.tsv"; printf "$2" >> "$FIX/$1.tsv"; "$BIN" sha "$FIX/$1.tsv" >/dev/null 2>&1; echo $?; }
chk cb-dup-code "$(mkcb dup '300\temerg\tagain\n')" 4
chk cb-bad-type "$(mkcb bty '400\tword\tx\n')" 4
chk cb-emerg-outside-3xx "$(mkcb eo '400\temerg\tx\n')" 4
chk cb-3xx-not-emerg "$(mkcb en '399\tsig\tx\n')" 4
chk cb-four-fields "$(mkcb f4 '400\tsig\tx\ty\n')" 4
chk cb-empty-meaning "$(mkcb em '400\tsig\t\n')" 4
chk cb-dangling-escape "$(mkcb de '901\tsig\tx\n')" 4
chk cb-two-codes "$(mkcb tc '400401\tsig\tx\n')" 4
chk cb-no-final-lf "$(mkcb nl '400\tsig\tx')" 4
chk cb-blank-line "$(mkcb bl '\n')" 4
chk cb-tab-in-meaning-ctl "$(mkcb ct '400\tsig\ta\001\n')" 4
chk cb-missing-file "$("$BIN" sha "$FIX/nope.tsv" >/dev/null 2>&1; echo $?)" 4
chk cb-ext-valid "$(mkcb ext '900400\tsig\tlayer2-probe\n901902005\tinst\tlayer3-probe\n400\tsig\tprobe\n')" 0
EXT=$FIX/ext.tsv
chk ext-is-append-only "$(head -c "$(wc -c < "$CB")" "$EXT" | cmp -s - "$CB" && echo prefix)" prefix

# 5. sign: HMAC-SHA256 against python hmac (oracle), keys of 32/64/65/100 bytes
awk -F'\t' '!/^#/{print $1}' "$CB" > "$FIX/codes"
awk 'BEGIN{srand(7)} {c[NR]=$0} END{s[0]="omega-lead";s[1]="reviewer";s[2]="test-master";s[3]="drake"; for(i=1;i<=1000;i++){n=1+int(rand()*4); d=""; for(j=0;j<n;j++) d=d c[1+int(rand()*NR)]; printf "n|2026-11-15T12:40|%s|reviewer|task|t002|-|%d|%s\n", s[int(rand()*4)], i, d}}' "$FIX/codes" > "$FIX/s.in"
for kk in k32 k64 k65 k100; do
  "$BIN" sign "$CB" "$KEYDIR/$kk" < "$FIX/s.in" > "$FIX/s.$kk"
  python3 - "$KEYDIR/$kk" "$CS" "$FIX/s.in" "$FIX/s.$kk" > "$FIX/s.$kk.res" <<'PY'
import hmac, hashlib, sys
key = open(sys.argv[1], 'rb').read()
cs = sys.argv[2]
good = 0; tot = 0
for a, b in zip(open(sys.argv[3]), open(sys.argv[4])):
    lane, ts, frm, to, tag, text, ref, c, d = a.strip().split("|")
    m = hmac.new(key, f"ocb2|{cs}|{c}|{lane}|{ts}|{frm}|{to}|{tag}|{text}|{ref}|{d}".encode(), hashlib.sha256).hexdigest()
    tot += 1
    good += b.strip() == f"ocb2:{cs}:{c}:{d}:{m}"
print(good, tot)
PY
  chk "sign-hmac-oracle-$kk" "$(cat "$FIX/s.$kk.res")" "1000 1000"
done
TS=2026-11-15T12:40
chk sign-rejects "$(printf 'n|%s|bad_s|reviewer|task|t002|-|1|300\nn|%s|omega-lead|reviewer|task|t002|-|01|300\nn|%s|omega-lead|reviewer|task|t002|-|0|300\nn|%s|omega-lead|reviewer|task|t002|-|3|555\nn|%s|omega-lead|reviewer|task|t002|-|3|900\nn|%s|omega-lead|reviewer|task|t002|-|3\nn|%s|omega-lead|reviewer|task|t002|-|3|300|x\n' "$TS" "$TS" "$TS" "$TS" "$TS" "$TS" "$TS" | "$BIN" sign "$CB" "$K" | tr '\n' ,)" "ERR sender,ERR counter,ERR counter,ERR unknown,ERR esc,ERR fmt,ERR fmt,"
chk sign-no-key-bytes-out "$(python3 -c "import sys;k=open(sys.argv[1],'rb').read().hex();d=open(sys.argv[2]).read();print(k in d)" "$K" "$FIX/s.k32")" False

# 6. verify: positives, demotion, negatives
ST=$FIX/state; mkdir -p "$ST"
sg() { echo "n|2026-11-15T12:40|$1|reviewer|task|t002|-|$2|$3" | "$BIN" sign "${4:-$CB}" "${5:-$K}"; }
vf() { printf '%s\n' "$1" | "$BIN" verify "${2:-$CB}" "${3:-$K}" "$ST"; }
L() { echo "2026-11-15T12:40|$1|reviewer|task|t002|-|$2"; }
E1=$(sg omega-lead 1 300); N2=$(sg omega-lead 2 101005)
chk verify-emergency-ok "$(vf "$(L omega-lead "$E1")")" "ok 2"
chk counter-stored "$(cat "$ST/omega-lead.ctr")" "1 2026-11-15T12:40"
chk verify-replay-same-counter "$(vf "$(L omega-lead "$E1")")" "stale 1"
chk verify-normal-ok "$(vf "$(L omega-lead "$N2")")" "ok 1"
chk verify-older-counter "$(vf "$(L omega-lead "$(sg omega-lead 2 300)")")" "stale 1"
chk verify-mixed-emerg "$(vf "$(L omega-lead "$(sg omega-lead 9 101300005)")")" "ok 2"
chk verify-unsigned-emergency-demoted "$(vf "$(L omega-lead "${E1%:*}")")" "unsigned 1"
chk verify-empty-mac "$(vf "$(L omega-lead "${E1%:*}:")")" "unsigned 1"
chk verify-no-field "$(vf "2026-11-15T12:40|omega-lead|reviewer|stop|STOP now|ref")" "unsigned 1"
chk verify-no-pipe "$(vf "345")" "unsigned 1"
E3=$(sg omega-lead 20 300)
chk verify-tampered-digits "$(vf "$(L omega-lead "$(echo "$E3" | sed 's/:20:300:/:20:301:/')")")" "badmac 1"
chk verify-tampered-counter "$(vf "$(L omega-lead "$(echo "$E3" | sed 's/:20:300:/:21:300:/')")")" "badmac 1"
chk verify-tampered-sender "$(vf "$(L reviewer "$E3")")" "badmac 1"
chk verify-wrong-key "$(vf "$(L omega-lead "$E3")" "$CB" "$KEYDIR/kother")" "badmac 1"
chk verify-tampered-mac "$(vf "$(L omega-lead "$(echo "$E3" | awk '{l=substr($0,length($0)); printf "%s%s\n", substr($0,1,length($0)-1), (l=="a"?"b":"a")}')")")" "badmac 1"
chk verify-wrong-cbsha "$(vf "$(L omega-lead "$(sg omega-lead 21 300 "$EXT")")")" "badcb 1"
chk verify-v1-line-under-ext-refused "$(vf "$(L omega-lead "$(sg omega-lead 23 300)")" "$EXT")" "badcb 1"
M=$(echo "$E3" | sed 's/.*://')
chk verify-bad-escape "$(vf "$(L omega-lead "ocb2:$CS:30:300900:$M")")" "badesc 1"
chk verify-bad-len "$(vf "$(L omega-lead "ocb2:$CS:30:3000:$M")")" "badlen 1"
chk verify-bad-digit "$(vf "$(L omega-lead "ocb2:$CS:30:30a:$M")")" "baddigit 1"
chk verify-unknown-code "$(vf "$(L omega-lead "ocb2:$CS:30:555:$M")")" "unknown 1"
chk verify-bad-sender "$(vf "$(L Omega_Lead "$E3")")" "badsender 1"
chk verify-mac-nonhex "$(vf "$(L omega-lead "ocb2:$CS:30:300:$(echo "$M" | sed 's/^./g/')")")" "badfmt 1"
chk verify-mac-short "$(vf "$(L omega-lead "ocb2:$CS:30:300:abc")")" "badfmt 1"
chk verify-extra-part "$(vf "$(L omega-lead "$E3:00")")" "badfmt 1"
chk verify-counter-zero "$(vf "$(L omega-lead "ocb2:$CS:0:300:$M")")" "badfmt 1"
chk verify-counter-leading-zero "$(vf "$(L omega-lead "ocb2:$CS:020:300:$M")")" "badfmt 1"
chk verify-cbsha-short "$(vf "$(L omega-lead "ocb2:abc:30:300:$M")")" "badfmt 1"
chk failures-did-not-move-counter "$(cat "$ST/omega-lead.ctr")" "9 2026-11-15T12:40"
chk verify-good-after-failures "$(vf "$(L omega-lead "$E3")")" "ok 2"
chk verify-ext-line-under-ext "$(vf "$(L omega-lead "$(sg omega-lead 22 900400300 "$EXT")")" "$EXT")" "ok 2"
chk verify-4xx-not-emergency "$(vf "$(L omega-lead "$(sg omega-lead 24 400 "$EXT")")" "$EXT")" "ok 1"
chk verify-tampered-mac-emerg-demoted "$(vf "$(L omega-lead "$(sg omega-lead 25 300 "$EXT" "$KEYDIR/kother")")" "$EXT")" "badmac 1"
chk no-tmp-left "$(ls "$ST" | tr '\n' ,)" "ctr.lock,omega-lead.ctr,"
chk counter-file-mode "$(stat -c %a "$ST/omega-lead.ctr")" 600
printf 'junk\n' > "$ST/reviewer.ctr"
chk malformed-counter-fails-closed "$(vf "$(L reviewer "$(sg reviewer 5 300)")")" "stale 1"
chk per-sender-counters "$(vf "$(L test-master "$(sg test-master 1 300)")")" "ok 2"
# batch: order matters, the second copy of a line is a replay
B1=$(L drake "$(sg drake 1 301)")
chk verify-batch-replay "$(printf '%s\n%s\n' "$B1" "$B1" | "$BIN" verify "$CB" "$K" "$ST" | tr '\n' ,)" "ok 2,stale 1,"

# 6b. round 4: ext (append-only check), flock during verify-and-advance, directory fsync
chk ext-append-ok "$("$BIN" ext "$CB" "$EXT"; echo "rc=$?")" "ok $(sha256sum < "$EXT" | cut -c1-64)
rc=0"
chk ext-reversed-refused "$("$BIN" ext "$EXT" "$CB"; echo "rc=$?")" "ERR notprefix
rc=6"
sed '7s/goal/gaol/' "$EXT" > "$FIX/edited.tsv"
chk ext-edited-line-refused "$("$BIN" ext "$CB" "$FIX/edited.tsv"; echo "rc=$?")" "ERR notprefix
rc=6"
{ cat "$CB"; printf '300\temerg\tduplicate\n'; } > "$FIX/dup.tsv"
chk ext-invalid-new-refused "$("$BIN" ext "$CB" "$FIX/dup.tsv" >/dev/null 2>&1; echo $?)" 4
chk ext-same-file-ok "$("$BIN" ext "$CB" "$CB" | cut -c1-2)" ok
chk ext-arity "$("$BIN" ext "$CB" >/dev/null 2>&1; echo $?)" 2
LK=$FIX/lockstate; mkdir -p "$LK"; chmod 700 "$LK"
if command -v flock >/dev/null 2>&1; then
  : > "$LK/ctr.lock"; flock "$LK/ctr.lock" sleep 2 & hp=$!; sleep 0.5
  t0=$(date +%s%N); r=$(L drake "$(sg drake 7 300)" | "$BIN" verify "$CB" "$K" "$LK"); t1=$(date +%s%N); wait $hp
  chk flock-waits-for-holder "$r $(( (t1 - t0) / 1000000 >= 1000 ))" "ok 2 1"
else echo "note: no flock(1); lock wait not checked"; ok; fi
TR=$FIX/strace.txt
pick_tracer "$BIN"
if [ -z "$TRC" ]; then
  echo "note: no strace/qemu tracer; syscall order not checked"
  skip strace-flock-ex-then-unlock
  skip strace-dir-fsync-after-rename
else
  if [ "$TRC" = strace ]; then
    L drake "$(sg drake 9 300)" | strace -f -o "$TR" "$BIN" verify "$CB" "$K" "$LK" > /dev/null 2> "$FIX/strace.err" || true
  else
    L drake "$(sg drake 9 300)" | "$TRC" -strace "$BIN" verify "$CB" "$K" "$LK" > /dev/null 2> "$TR" || true
  fi
  chk strace-flock-ex-then-unlock "$(grep -oE 'flock\([0-9]+, *(LOCK_EX|LOCK_UN|[0-9]+)' "$TR" | sed -E 's/.*LOCK_EX/2/; s/.*LOCK_UN/8/; s/.*, *//' | awk '{printf "flock op %s,", $1}')" "flock op 2,flock op 8,"
  chk strace-dir-fsync-after-rename "$(awk '
    /renameat2/ { started=1; printf "renameat2,"; next }
    started && /openat\(AT_FDCWD,/ {
      line=$0
      sub(/.*openat\(AT_FDCWD, *"/, "", line)
      sub(/".*/, "", line)
      printf "open \"%s\",", line
      next
    }
    started && /fsync\(/ { printf "fsync,"; next }
  ' "$TR")" "renameat2,open \"$LK\",fsync,"
fi

# 7. usage and key errors
chk usage-noargs "$("$BIN" >/dev/null 2>&1; echo $?)" 2
chk usage-mode "$("$BIN" frob >/dev/null 2>&1; echo $?)" 2
chk usage-sign-arity "$("$BIN" sign "$CB" </dev/null >/dev/null 2>&1; echo $?)" 2
chk key-missing "$(echo 'omega-lead 1 300' | "$BIN" sign "$CB" "$FIX/nokey" >/dev/null 2>&1; echo $?)" 5
: > "$FIX/empty.key"
chk key-empty "$(echo 'n|2026-11-15T12:40|omega-lead|reviewer|task|t002|-|1|300' | "$BIN" sign "$CB" "$FIX/empty.key" >/dev/null 2>&1; echo $?)" 5
cp "$K" "$FIX/wide.key"; chmod 644 "$FIX/wide.key"
chk key-world-readable "$(echo 'n|2026-11-15T12:40|omega-lead|reviewer|task|t002|-|1|300' | "$BIN" sign "$CB" "$FIX/wide.key" >/dev/null 2>&1; echo $?)" 5
mkdir -p "$FIX/boards"; cp "$K" "$FIX/boards/key"; chmod 600 "$FIX/boards/key"
chk key-inside-boards "$(echo 'n|2026-11-15T12:40|omega-lead|reviewer|task|t002|-|1|300' | "$BIN" sign "$CB" "$FIX/boards/key" >/dev/null 2>&1; echo $?)" 5

echo "PASS $P FAIL $F SKIP $S"
printf 'TOTAL pass=%d fail=%d skip=%d\n' "$P" "$F" "$S"
[ "$F" -eq 0 ]
