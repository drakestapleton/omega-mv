#!/bin/sh
# gate.sh: rebuild lm1b from a clean checkout and judge it against the Rust reference.
# Existing-tool class (POSIX sh, awk, sha256sum, cmp, cargo for the reference). Prints RC=0 when
# every check passes, RC=1 otherwise, and RC=3 (NOT_RUN, never a pass) when the compiler pin is not
# 64 hex digits, the compiler or the model file is missing. Raw logs go to out/gate/ (not committed).
#   OMC    seed-born Omega compiler (default omega-mv's seed/out/omc; kernel/ is folded into omega-mv)
#   MODEL  pinned GGUF (default ~/models/aien-mail/Llama-3.2-1B-Instruct-Q4_K_M.gguf)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
OMC=${OMC:-$ROOT/../seed/out/omc}
MODEL=${MODEL:-$HOME/models/aien-mail/Llama-3.2-1B-Instruct-Q4_K_M.gguf}
# omega-mv's own pin (before the fold: 734f0a39319fbfa930bcc62cb30dbf06d47d78e126372b74f5baf478e6126b61)
OMC_SHA=$(head -n 1 "$ROOT/../seed/out/omc.sha256" 2>/dev/null | cut -c1-64)
notrun() { echo "NOT_RUN $1"; echo "RC=3"; exit 3; }
printf '%s\n' "$OMC_SHA" | grep -qxE '[0-9a-f]{64}' || notrun "compiler pin refused: no sha256 in $ROOT/../seed/out/omc.sha256"
[ -f "$OMC" ] || notrun "compiler pin refused: no compiler at $OMC"
# A compiler other than the pin stops here, before anything runs it (pin_controls in kernel/tests/gates/run.sh).
OMC_GOT=$(sha256sum "$OMC" | cut -d' ' -f1)
[ "$OMC_GOT" = "$OMC_SHA" ] || { echo "FAIL omc-sha: compiler pin mismatch: $OMC has sha256 $OMC_GOT, the pin is $OMC_SHA"; echo "RC=1"; exit 1; }
[ -f "$MODEL" ] || notrun "model $MODEL not present (set MODEL to the pinned GGUF)"
MODEL_SHA=3f5a22426976ab26cfe84dba63c1d08391717abb1af893e10f1b2968d862dcc1
EOS=128009
O=$HERE/out/gate
rm -rf "$O"
mkdir -p "$O"
FAILS=""
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1: $2"; FAILS="$FAILS $1"; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "want [$3] got [$2]"; fi; }

# 1. pinned inputs
check omc-sha "$(sha256sum "$OMC" | cut -d' ' -f1)" "$OMC_SHA"
check model-sha "$(sha256sum "$MODEL" | cut -d' ' -f1)" "$MODEL_SHA"

# 2. the committed program is exactly what the generator makes from the template
cp "$HERE/lm1b.om" "$O/lm1b.committed.om"
sh "$HERE/gen.sh" > "$O/gen.log" 2>&1 || fail gen "gen.sh failed"
if cmp -s "$HERE/lm1b.om" "$O/lm1b.committed.om"; then pass gen-in-sync; else fail gen-in-sync "lm1b.om differs from gen.sh output"; fi

# 3. no host words the boot fixture will not provide (arguments, environment, clocks, other services)
BAD=$(grep -v '^note' "$HERE/lm1b.om" | tr ' ' '\n' | grep -x -E 'argcnt|argread|envcnt|envread|monons|realns|sleepns|fopen|fclose|fsync|fdsync|memfd|fchmod|chmod|chown|faccess|getuid|geteuid|getgid|getegid|fchdir|getppid|setsid|getpgid|getsid|syncfs|shutdown|setpgid|umask|fseek|ftrunc|truncate|unlink|makedir|rmdir|cwd|chdir|readlnk|getdnts|fstat|stat|lstat|renames|link|symlnk|socknew|bind|connect|listen|accept|sockname|sockopt|recv|send|waitio|fork|getpid|killpid|waitpid|pipefds|dupfd|execprog|random|pwrite|devctl|mapnew|mapdrop|mapread|mapwrite' | sort -u | tr '\n' ' ')
check host-words "$BAD" ""

# 4. compile; the ELF must hold only read 63, write 64, pread64 67 and exit 93 service numbers
"$OMC" < "$HERE/lm1b.om" > "$O/lm1b" 2> "$O/omc.err"
check compile "$?" 0
chmod +x "$O/lm1b"
sha256sum "$O/lm1b" | cut -d' ' -f1 > "$O/lm1b.sha256"
objdump -D -b binary -maarch64 "$O/lm1b" > "$O/lm1b.dis" 2>&1
SVC=$(awk '/mov\tx8, #/{split($0,a,"// #"); v=a[2]+0; last=NR} /\tsvc\t/{ if (NR-last<=4) print v; else print "unknown" }' "$O/lm1b.dis" | sort -u -n | tr '\n' ' ')
check svc-numbers "$SVC" "63 64 67 93 "

# 5. the pinned manifest agrees with the reference parser (an independent reader of the same file)
( cd "$HERE/oracle/manifest-dump" && cargo build --release -q ) > "$O/oracle-build.log" 2>&1
"$HERE/oracle/manifest-dump/target/release/lm1b-manifest-dump" "$MODEL" > "$O/manifest.ref.txt" 2>&1
if cmp -s "$O/manifest.ref.txt" "$HERE/manifest.txt"; then pass manifest-oracle; else fail manifest-oracle "reference parser output differs"; fi

# 6. reference runs (aienos-infer plain f32 path, logit bits on)
( cd "$ROOT" && cargo build --release -q --example model_probe -p aienos-infer ) > "$O/probe-build.log" 2>&1
P=$ROOT/target/release/examples/model_probe
for p in cow rainbow; do
  AIENOS_BITS=1 "$P" "$MODEL" "$HERE/prompts/$p.txt" 8 $EOS > "$O/ref-$p.txt" 2>&1
  awk '$1=="step"{t=t" "$3} $1=="bits"{b=b" "$3} END{print "tokens" t; print "bits" b}' "$O/ref-$p.txt" > "$O/ref-$p.want"
done

# helpers over lm1b output
jtok() { awk -v j="$2" '$1=="job" && $2==j && $3=="status" {f=1; s=""; for(i=7;i<=NF;i++) s=s" "$i; print "tokens" substr(s, index(s,"tokens")+6); next} f && $1=="bits" {print; f=0}' "$1"; }
jline() { awk -v j="$2" '$1=="job" && $2==j {print; exit}' "$1"; }

# 7. three jobs in one process: cow, rainbow, cow again
"$O/lm1b" 3< "$MODEL" < "$HERE/prompts/main-jobs.txt" > "$O/main.out" 2> "$O/main.err"
check main-exit "$?" 0
check main-load "$(head -1 "$O/main.out")" "load ok bytes 807694368 tensors 147 sha256 $MODEL_SHA passes 0"
check job1-vs-ref "$(jtok "$O/main.out" cow1)" "$(cat "$O/ref-cow.want")"
check job2-vs-ref "$(jtok "$O/main.out" rain)" "$(cat "$O/ref-rainbow.want")"
check job3-eq-job1 "$(jtok "$O/main.out" cow3)" "$(jtok "$O/main.out" cow1)"
check job1-status "$(jline "$O/main.out" cow1 | cut -d' ' -f3-6)" "status ok passes 26"
check job3-acct "$(grep '^acct job cow3' "$O/main.out" | cut -d' ' -f4-)" "$(grep '^acct job cow1' "$O/main.out" | cut -d' ' -f4-)"

# 8. negative controls
# 8a. one flipped byte in the tensor data: load refused (digest)
cp "$MODEL" "$O/flipped.gguf"
printf '\377' | dd of="$O/flipped.gguf" bs=1 seek=400000000 count=1 conv=notrunc 2> /dev/null
"$O/lm1b" 3< "$O/flipped.gguf" < /dev/null > "$O/flip.out" 2>&1
RCF=$?
rm -f "$O/flipped.gguf"
check flip-refused "$(cat "$O/flip.out") rc=$RCF" "load refused reason sha256 rc=3"
# 8b. a copy of the program whose manifest names the wrong type for one tensor: load refused
sed 's/t blk.0.attn_k.weight 12 2 2048 512/t blk.0.attn_k.weight 14 2 2048 512/' "$HERE/lm1b.om" > "$O/wrongtype.om"
check wrongtype-edited "$(cmp -s "$HERE/lm1b.om" "$O/wrongtype.om"; echo $?)" 1
"$OMC" < "$O/wrongtype.om" > "$O/wrongtype" && chmod +x "$O/wrongtype"
"$O/wrongtype" 3< "$MODEL" < /dev/null > "$O/wrongtype.out" 2>&1
RCW=$?
check wrongtype-refused "$(cat "$O/wrongtype.out") rc=$RCW" "load refused reason manifest rc=3"
# 8c. refusals keep serving; a budget too small cancels at a step boundary; the next job is correct
C=$(sed 's/^ids //' "$HERE/prompts/cow.txt")
LONG=$(awk 'BEGIN{for(i=0;i<257;i++) printf " 9"; print ""}')
L250=$(awk 'BEGIN{for(i=0;i<250;i++) printf " 9"; print ""}')
{
  echo "job big gen 1 budget 9 stop $EOS fault 0 ids$LONG"
  echo "job ctx gen 8 budget 9 stop $EOS fault 0 ids$L250"
  echo "job bad gen 1 budget 9 stop $EOS fault 0 ids 128256"
  echo "job  two spaces"
  echo "hello"
  echo "job b1 gen 8 budget 5 stop $EOS fault 0 ids $C"
  echo "job b2 gen 2 budget 1000 stop $EOS fault 0 ids $C"
} > "$O/neg-jobs.txt"
"$O/lm1b" 3< "$MODEL" < "$O/neg-jobs.txt" > "$O/neg.out" 2> "$O/neg.err"
check neg-exit "$?" 0
check over-limit "$(jline "$O/neg.out" big)" "job big status refused reason toomany"
check over-context "$(jline "$O/neg.out" ctx)" "job ctx status refused reason context"
check bad-id "$(jline "$O/neg.out" bad)" "job bad status refused reason badid"
check malformed "$(grep -c '^job ? status refused reason syntax$' "$O/neg.out")" 2
check budget-cancel "$(jline "$O/neg.out" b1)" "job b1 status cancelled passes 5 tokens"
check after-cancel "$(jtok "$O/neg.out" b2)" "$(awk 'NR==1{print $1" "$2" "$3} NR==2{print $1" "$2" "$3}' "$O/ref-cow.want")"
# 8d. fault 1: the process traps in the middle of the job (exit 100 + 12)
echo "job f1 gen 2 budget 1000 stop $EOS fault 1 ids $C" > "$O/fault-jobs.txt"
"$O/lm1b" 3< "$MODEL" < "$O/fault-jobs.txt" > "$O/fault.out" 2> "$O/fault.err"
check fault-exit "$?" 112
check fault-no-reply "$(grep -c '^job f1' "$O/fault.out")" 0
# 8e. omc bounds-checks every get and put on a global in these bytes (aienux#481): rowcp's pool split assumes the next
# pool is long enough, and the fallback is Omega's per-access trap 3 (exit 103). Three copies of the program differ
# from lm1b.om in one line of fn mv: a row read past the end of the last pool (m48 holds 2,388,000 bytes), a row copy
# one byte longer than rb, and a control that rewrites the same line with the same value. The two out-of-range copies
# must trap with no reply; the control must answer like the reference.
bvar() {
  sed "s/^$2\$/$3/" "$HERE/lm1b.om" > "$O/$1.om"
  check "$1-edited" "$(cmp -s "$HERE/lm1b.om" "$O/$1.om"; echo $?)" 1
  "$OMC" < "$O/$1.om" > "$O/$1" 2> "$O/$1.err"
  check "$1-compile" "$?" 0
  chmod +x "$O/$1"
  echo "job $1 gen 2 budget 1000 stop $EOS fault 0 ids $C" | "$O/$1" 3< "$MODEL" > "$O/$1.out" 2>&1
}
bvar oob-get 'base = get tof ti' 'base = ulong 807694268'
check oob-get-exit "$?" 103
check oob-get-no-reply "$(grep -c '^job oob-get' "$O/oob-get.out")" 0
bvar oob-put 'rowcp add base mul r rbs rbs' 'rowcp add base mul r rbs 8193'
check oob-put-exit "$?" 103
check oob-put-no-reply "$(grep -c '^job oob-put' "$O/oob-put.out")" 0
bvar oob-ctl 'base = get tof ti' 'base = add get tof ti ulong 0'
check oob-ctl-exit "$?" 0
check oob-ctl-vs-ref "$(jtok "$O/oob-ctl.out" oob-ctl)" "$(awk 'NR==1{print $1" "$2" "$3} NR==2{print $1" "$2" "$3}' "$O/ref-cow.want")"

if [ -z "$FAILS" ]; then echo "RC=0"; exit 0; fi
echo "failed:$FAILS"
echo "RC=1"
exit 1
