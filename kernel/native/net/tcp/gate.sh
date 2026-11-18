#!/bin/sh
# gate.sh: L232 gates for the Omega TCP stack (verification rig, not product code).
# Usage: gate.sh corpus OMC OUTDIR
#        gate.sh OMC IMAGE BUSYBOX OUTDIR [PROFILES] [SCENARIOS]
#   OMC      pinned seeded omc (sha256 checked against omega-mv's seed/out/omc.sha256)
#   IMAGE    arm64 Linux Image for the guest (needs virtio-net, AF_PACKET)
#   BUSYBOX  static aarch64 busybox (guest init, sha256sum, and the g2h payload)
#   PROFILES default "clean loss reorder hostile"; SCENARIOS default "echo h2g g2h"
# corpus: checks its tables (mutants.tsv; the rows mutgen.awk makes of each tcp.om function,
# their count and sha256; unasserted.tsv, the generated rows no check kills, with their
# class) against the pins in corpus_gate; trnd must refuse without a key (nokey.om) and
# tcpd's key path must hold (tcpd key mode); the corpus (tcp.om + corpus.om) at fuzz 0 must
# run exactly the pinned checks, check ids and case groups, then at FUZZ seeded frames
# (default and minimum 2000000) pass with that fuzz count. Then the controls, each printing
# CONTROL OMEGA-KERNEL-TCP-CORPUS/NAME FAILED_AS_REQUIRED when its input failed as it must:
# NOT_RUN for a missing or wrong compiler, changed copies of this directory that must fail
# their own gate, and the kill and list rules on fixed inputs. Each mutants.tsv row must fail
# its own check (control mutant-NAME, the row name in lower case). Each generated row is
# built and run at fuzz 0 and with nokey.om: killed (a CORPUS_FAIL check line, or nokey
# failed), survived (both passed), trapped (the corpus ended without passing and without a
# failed check; a trap is not a kill) or not_built; the rows not killed, with their class,
# must equal unasserted.tsv. The last line, with exit 0 when those hold:
#   TCP_CORPUS_GATE PASS checks=N fuzz=F groups=G mutants=M killed=M generated=X
#   gen_killed=Y survivors=Z controls=C
# (generated counts the rows that built; survivors those of them survived or trapped).
# The QEMU mode runs the corpus mode first, then boots a fresh guest per run whose only
# TCP/IP stack is tcpd (tcp.om + tcpd.om),
# routes its NIC through link.om (seeded drop / reorder / duplicate / hostile
# injection) to QEMU slirp, and talks to peer.om on the host. Exit 0 only when
# every run passes every check. Requires qemu-system-aarch64 with KVM.
# Exit 3 (NOT_RUN, never a pass) when the gate cannot run: missing pin, missing or
# wrong compiler, missing QEMU, KVM, IMAGE or BUSYBOX. Exit 2: a unit did not build
# with the pinned compiler. Exit 1: a check failed.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
# The compiler pin is omega-mv's own (kernel/ is folded into omega-mv): seed/out/omc.sha256 at its root.
PINFILE=$HERE/../../../../seed/out/omc.sha256
notrun() { echo "$1 NOT_RUN $2"; exit 3; }
# pincheck TAG OMC: the compiler must exist and carry the pinned sha256, else NOT_RUN.
pincheck() {
  PIN=$(cut -c1-64 "$PINFILE" 2>/dev/null)
  printf '%s\n' "$PIN" | grep -qxE '[0-9a-f]{64}' || notrun "$1" "no sha256 in $PINFILE"
  [ -f "$2" ] && [ -x "$2" ] || notrun "$1" "no executable compiler at $2"
  have=$(sha256sum "$2" | cut -d' ' -f1)
  [ "$have" = "$PIN" ] || notrun "$1" "omc sha256 $have is not the pin $PIN"
}
# ctlok NAME / ctlbad NAME WHY: a control's result line. The root runner requires the
# FAILED_AS_REQUIRED line of each name in tests/gates/controls/OMEGA-KERNEL-TCP-CORPUS.controls.
ctlok() { echo "CONTROL OMEGA-KERNEL-TCP-CORPUS/$1 FAILED_AS_REQUIRED"; ctl_ok=$((ctl_ok + 1)); }
ctlbad() { echo "CONTROL OMEGA-KERNEL-TCP-CORPUS/$1 FAIL ($2)"; ctl_bad=$((ctl_bad + 1)); }
# control NAME WANT_RC CMD...: run a negative control; it must exit WANT_RC and print NOT_RUN.
control() {
  cn=$1 cw=$2; shift 2
  "$@" > "$OUT/control-$cn.log" 2>&1; cr=$?
  if [ $cr -eq "$cw" ] && grep -q 'NOT_RUN' "$OUT/control-$cn.log"; then
    ctlok "$cn"
  else
    ctlbad "$cn" "rc=$cr, wanted rc=$cw and NOT_RUN"
  fi
}
# mutapply SRC FN OCC OLD NEW DEST: SRC with the OCC-th line equal to OLD inside fn FN
# replaced by NEW, written to DEST; exit 7 when there is no such line.
mutapply() {
  awk -v F="$2" -v N="$3" -v O="$4" -v R="$5" '
    $1 == "fn" { infn = ($2 == F) }
    infn && !done && $0 == O { seen++; if (seen == N) { print R; done = 1; next } }
    { print }
    END { exit done ? 0 : 7 }' "$1" > "$6"
}
# corpus_kills LOG RC ID: the corpus failed on check ID: nonzero exit, no CORPUS_PASS, and
# a CORPUS_FAIL check=ID line (a trap alone, or a failure of another check, is no kill).
corpus_kills() {
  [ "$2" -ne 0 ] && ! grep -aq '^CORPUS_PASS' "$1" && grep -aqx "CORPUS_FAIL check=$3" "$1"
}
# nokey_ok BIN LOG: trnd without a key refuses: exit 108 (trap 8), no NOKEY_RETURNED.
nokey_ok() {
  "$1" > "$2" 2>&1; nr=$?
  [ $nr -eq 108 ] && ! grep -aq NOKEY_RETURNED "$2"
}
# tcpdkey_ok BIN DIR: tcpd's key path (tcpd key mode). Two runs asking getrandom(2) for 16
# bytes each print one line TCPD_KEY k0 k1 1 0 r: both key words nonzero, the key installed,
# the buffer wiped, and k0, k1 and r differ between the runs. Asking 15 bytes exits 7
# before any TCPD_KEY line (a short read starts nothing).
tcpdkey_ok() {
  "$1" key 0 - - 16 > "$2/key1.log" 2>&1 || return 1
  "$1" key 0 - - 16 > "$2/key2.log" 2>&1 || return 1
  "$1" key 0 - - 15 > "$2/key15.log" 2>&1; [ $? -eq 7 ] || return 1
  ! grep -aq TCPD_KEY "$2/key15.log" || return 1
  awk 'NF == 6 && $1 == "TCPD_KEY" && ($2 "") != "0" && ($3 "") != "0" && ($4 "") == "1" && ($5 "") == "0" {
         n++; a[n] = $2 ""; b[n] = $3 ""; r[n] = $6 "" }
       END { exit (NR == 2 && n == 2 && a[1] != a[2] && b[1] != b[2] && r[1] != r[2]) ? 0 : 1 }' "$2/key1.log" "$2/key2.log"
}
# samelist A B: the two lists hold the same rows (order ignored).
samelist() {
  sort "$1" > "$1.s" && sort "$2" > "$2.s" && cmp -s "$1.s" "$2.s"
}
# genrun ROWS DIR: each generated mutant row of tcp.om built with the corpus and run at fuzz
# 0, and with nokey.om. KILLED: a CORPUS_FAIL check line, or trnd did not refuse. SURVIVED:
# both passed. TRAPPED: the corpus ended without passing and without a failed check.
# NOT_BUILT: omc refuses the edited unit.
genrun() {
  while IFS=$tab read -r gname gfn gocc gold gnew; do
    D=$2/$gname; mkdir -p "$D"
    if ! mutapply "$HERE/tcp.om" "$gfn" "$gocc" "$gold" "$gnew" "$D/tcp.om" || cmp -s "$HERE/tcp.om" "$D/tcp.om"; then
      echo "$gname NOT_APPLIED"; continue
    fi
    if ! cat "$D/tcp.om" "$HERE/corpus.om" | "$OMC" > "$D/bin" 2> "$D/build.log"; then
      echo "$gname not_built"; rm -rf "$D"; continue
    fi
    chmod +x "$D/bin"; "$D/bin" 0 > "$D/corpus.log" 2>&1; gr=$?
    if grep -aq '^CORPUS_FAIL check=' "$D/corpus.log"; then
      echo "$gname killed corpus rc=$gr"; rm -rf "$D"; continue
    fi
    if ! { cat "$D/tcp.om" "$HERE/nokey.om" | "$OMC" > "$D/nk" 2>> "$D/build.log" && chmod +x "$D/nk" && nokey_ok "$D/nk" "$D/nokey.log"; }; then
      echo "$gname killed nokey"; rm -rf "$D"; continue
    fi
    if [ $gr -eq 0 ] && grep -aq '^CORPUS_PASS' "$D/corpus.log"; then echo "$gname survived"
    else echo "$gname trapped rc=$gr"; fi
    rm -rf "$D"
  done < "$1"
}
# expect NAME RC WANT CMD...: a control. CMD must exit RC with WANT in its last line.
expect() {
  en=$1 ew=$2 et=$3; shift 3
  "$@" > "$OUT/control-$en.log" 2>&1; er=$?
  if [ $er -eq "$ew" ] && tail -n 1 "$OUT/control-$en.log" | grep -q -- "$et"; then
    ctlok "$en"
  else
    ctlbad "$en" "rc=$er, wanted rc=$ew and '$et'"
  fi
}
# selfgate NAME WANT EDIT...: a copy of this directory (and the pin file) changed by EDIT,
# run inside the copy, must fail its own gate (exit 1, WANT in the last line) before that
# copy reaches its controls (TCP_GATE_DEPTH set: reaching them exits 4).
selfgate() {
  sn=$1 sw=$2; shift 2
  C=$OUT/self-$sn; rm -rf "$C"; mkdir -p "$C/kernel/native/net/tcp" "$C/seed/out"
  cp "$PINFILE" "$C/seed/out/omc.sha256"
  for f in "$HERE"/*; do [ -f "$f" ] && cp "$f" "$C/kernel/native/net/tcp/"; done
  if ! ( cd "$C/kernel/native/net/tcp" && "$@" ) > "$C/edit.log" 2>&1 || diff -r "$HERE" "$C/kernel/native/net/tcp" > /dev/null; then
    ctlbad "$sn" "the edit did not apply"; return
  fi
  expect "$sn" 1 "$sw" env TCP_GATE_DEPTH=1 sh "$C/kernel/native/net/tcp/gate.sh" corpus "$OMC" "$C/out"
}
# Edits for selfgate (run inside the copy).
ed_mut() { mutapply "$1" "$2" "$3" "$4" "$5" "$1.new" && mv "$1.new" "$1"; }
ed_awk() { awk "$2" "$1" > "$1.new" && mv "$1.new" "$1"; }
# ed_mut_repin: ed_mut on tcp.om, then GEN_PIN and GENSHA_PIN set to the edited rows, as an author
# who repins would, so that the check after the tables is the one that must fail.
ed_mut_repin() {
  ed_mut "$@" || return 1
  awk -v FNS="$(awk '$1 == "fn" { printf "%s ", $2 }' tcp.om)" -f mutgen.awk tcp.om > rows.new
  s=$(sha256sum < rows.new | cut -c1-64); n=$(wc -l < rows.new); rm -f rows.new
  ed_awk gate.sh "{ sub(/^  GENSHA_PIN=.*/, \"  GENSHA_PIN=$s\"); sub(/^  GEN_PIN=.*/, \"  GEN_PIN=$n\") } { print }"
}
corpus_gate() {
  T=TCP_CORPUS_GATE
  [ $# -eq 2 ] || { echo "usage: gate.sh corpus OMC OUTDIR" >&2; exit 2; }
  OMC=$1 OUT=$2
  tab=$(printf '\t')
  # Pins. Each changes with what it counts, in the same commit: FUZZ_PIN the seeded
  # frames of the run; GROUPS_PIN the case groups corpus.om runs (cgroup calls reached);
  # CHECKS0_PIN and IDS0_PIN the checks run at fuzz 0 and the sha256 of their sorted
  # distinct ids; MUTANTS_PIN the rows of mutants.tsv; GEN_PIN and GENSHA_PIN the rows
  # mutgen.awk makes of each tcp.om function and their sha256; SURVIVED_PIN, TRAPPED_PIN
  # and NOT_BUILT_PIN the rows of unasserted.tsv in each class; CONTROLS_PIN the controls.
  FUZZ_PIN=2000000
  GROUPS_PIN=37
  CHECKS0_PIN=1262
  IDS0_PIN=2523ffdc2e2a8f9dea96e1880b2bcbd81f8a65bd085ee8a166acbb49e9722550
  MUTANTS_PIN=202
  GEN_PIN=3151
  GENSHA_PIN=f8b9df2d9347450cee8e3e183c53a6ad995994f9cbd311f435ddd7647ddd731f
  SURVIVED_PIN=305
  TRAPPED_PIN=82
  NOT_BUILT_PIN=141
  CONTROLS_PIN=23
  pincheck $T "$OMC"
  OMC=$(cd "$(dirname "$OMC")" && pwd)/$(basename "$OMC")
  mkdir -p "$OUT" || notrun $T "cannot create $OUT"
  OUT=$(cd "$OUT" && pwd)
  FUZZ=${FUZZ:-$FUZZ_PIN}
  case $FUZZ in
    ''|*[!0-9]*|0*) echo "$T FAIL FUZZ=$FUZZ is not a positive count"; exit 1 ;;
  esac
  [ "$FUZZ" -ge $FUZZ_PIN ] || { echo "$T FAIL FUZZ=$FUZZ is below the pinned $FUZZ_PIN"; exit 1; }
  # 1. Tables, before anything runs.
  bad() { echo "$T FAIL $1"; exit 1; }
  grep -v '^#' "$HERE/mutants.tsv" | grep -v '^$' > "$OUT/mutants.rows"
  awk -F"$tab" 'NF != 7 || $1 == "" || ($2 != "tcp.om" && $2 != "tcpd.om") || $4 !~ /^[1-9][0-9]*$/ || $7 !~ /^([1-9][0-9]*|nokey|tcpdkey)$/ { print; bad = 1 }
    END { exit bad }' "$OUT/mutants.rows" > "$OUT/mutants.malformed" || bad "malformed mutants.tsv rows: $(head -1 "$OUT/mutants.malformed")"
  m=$(wc -l < "$OUT/mutants.rows")
  [ "$m" -eq $MUTANTS_PIN ] || bad "mutants=$m, pinned $MUTANTS_PIN"
  [ "$(cut -f1 "$OUT/mutants.rows" | sort -u | wc -l)" -eq "$m" ] || bad "duplicate mutant names"
  [ "$(cut -f2-6 "$OUT/mutants.rows" | sort -u | wc -l)" -eq "$m" ] || bad "duplicate mutant edits"
  fns=$(awk '$1 == "fn" { printf "%s ", $2 }' "$HERE/tcp.om")
  awk -v FNS="$fns" -f "$HERE/mutgen.awk" "$HERE/tcp.om" > "$OUT/generated.rows"
  g=$(wc -l < "$OUT/generated.rows")
  [ "$g" -eq $GEN_PIN ] || bad "generated=$g, pinned $GEN_PIN"
  gsha=$(sha256sum < "$OUT/generated.rows" | cut -c1-64)
  [ "$gsha" = "$GENSHA_PIN" ] || bad "generated rows sha256 $gsha, pinned $GENSHA_PIN"
  # unasserted.tsv: fn, occurrence, old line, new line, class, reason (- for none given).
  grep -v '^#' "$HERE/unasserted.tsv" | grep -v '^$' > "$OUT/unasserted.all"
  awk -F"$tab" 'NF != 6 || $2 !~ /^[1-9][0-9]*$/ || ($5 != "survived" && $5 != "trapped" && $5 != "not_built") || $6 == "" { print; bad = 1 }
    END { exit bad }' "$OUT/unasserted.all" > "$OUT/unasserted.malformed" || bad "malformed unasserted.tsv rows: $(head -1 "$OUT/unasserted.malformed")"
  cut -f1-5 "$OUT/unasserted.all" | LC_ALL=C sort > "$OUT/unasserted.rows"
  [ "$(cut -f1-4 "$OUT/unasserted.rows" | sort -u | wc -l)" -eq "$(wc -l < "$OUT/unasserted.rows")" ] || bad "duplicate unasserted edits"
  for cl in survived trapped not_built; do
    case $cl in survived) want=$SURVIVED_PIN ;; trapped) want=$TRAPPED_PIN ;; *) want=$NOT_BUILT_PIN ;; esac
    have=$(awk -F"$tab" -v c=$cl '$5 == c' "$OUT/unasserted.rows" | wc -l)
    [ "$have" -eq "$want" ] || bad "unasserted $cl=$have, pinned $want"
  done
  cut -f2-5 "$OUT/generated.rows" | sort -u > "$OUT/generated.edits"
  cut -f1-4 "$OUT/unasserted.rows" | sort -u | comm -23 - "$OUT/generated.edits" > "$OUT/unasserted.unknown"
  [ ! -s "$OUT/unasserted.unknown" ] || bad "unasserted row is no generated edit: $(head -1 "$OUT/unasserted.unknown")"
  # 2. trnd refuses without a key; tcpd's key path.
  cat "$HERE/tcp.om" "$HERE/nokey.om" | "$OMC" > "$OUT/nokey" || { echo "$T FAIL build nokey"; exit 2; }
  chmod +x "$OUT/nokey"
  nokey_ok "$OUT/nokey" "$OUT/nokey.log" || bad "nokey: trnd without a key did not trap 8"
  cat "$HERE/tcp.om" "$HERE/tcpd.om" | "$OMC" > "$OUT/tcpd" || { echo "$T FAIL build tcpd"; exit 2; }
  chmod +x "$OUT/tcpd"; mkdir -p "$OUT/tcpdkey"
  tcpdkey_ok "$OUT/tcpd" "$OUT/tcpdkey" || bad "tcpdkey: the key path check failed ($OUT/tcpdkey)"
  echo "KEYS nokey trap 8 PASS, tcpd key 2 distinct keys and short read exit 7 PASS"
  # 3. The corpus at fuzz 0: exact check count, case groups and check ids.
  cat "$HERE/tcp.om" "$HERE/corpus.om" | "$OMC" > "$OUT/corpus" || { echo "$T FAIL build corpus"; exit 2; }
  chmod +x "$OUT/corpus"
  sha256sum "$OMC" "$HERE"/*.om "$HERE/mutants.tsv" "$HERE/mutgen.awk" "$HERE/unasserted.tsv" "$OUT/corpus" > "$OUT/inputs.sha256"
  "$OUT/corpus" 0 ids > "$OUT/corpus0.log" 2>&1
  rc0=$?
  line0=$(grep -a '^CORPUS_PASS ' "$OUT/corpus0.log" | head -1)
  ids0=$(grep -a '^CK [0-9][0-9]*$' "$OUT/corpus0.log" | cut -c4- | sort -n -u | sha256sum | cut -c1-64)
  n0=$(grep -ac '^CK ' "$OUT/corpus0.log")
  echo "CORPUS0 rc=$rc0 checks_run=$n0 ids_sha256=$ids0 $line0"
  [ $rc0 -eq 0 ] || bad "fuzz 0 corpus rc=$rc0"
  case $line0 in
    "CORPUS_PASS checks=$CHECKS0_PIN fuzz=0 groups=$GROUPS_PIN "*) ;;
    *) bad "fuzz 0: wanted checks=$CHECKS0_PIN fuzz=0 groups=$GROUPS_PIN, got: $line0" ;;
  esac
  [ "$n0" -eq $CHECKS0_PIN ] || bad "fuzz 0 printed $n0 check ids, pinned $CHECKS0_PIN"
  [ "$ids0" = $IDS0_PIN ] || bad "fuzz 0 check id set sha256 $ids0, pinned $IDS0_PIN"
  # 4. The fuzzed run.
  fail=""
  "$OUT/corpus" "$FUZZ" > "$OUT/corpus.log" 2>&1
  rc=$?
  line=$(grep -a '^CORPUS_PASS ' "$OUT/corpus.log" | head -1)
  checks=$(printf '%s\n' "$line" | sed -n 's/^CORPUS_PASS checks=\([0-9][0-9]*\) fuzz=\([0-9][0-9]*\) groups=\([0-9][0-9]*\) .*/\1/p')
  fuzzed=$(printf '%s\n' "$line" | sed -n 's/^CORPUS_PASS checks=\([0-9][0-9]*\) fuzz=\([0-9][0-9]*\) groups=\([0-9][0-9]*\) .*/\2/p')
  groups=$(printf '%s\n' "$line" | sed -n 's/^CORPUS_PASS checks=\([0-9][0-9]*\) fuzz=\([0-9][0-9]*\) groups=\([0-9][0-9]*\) .*/\3/p')
  [ "$rc" -eq 0 ] || fail="$fail corpus_rc=$rc"
  [ -n "$checks" ] || { checks=0; fail="$fail no_CORPUS_PASS"; }
  [ "$checks" -ge $((CHECKS0_PIN + FUZZ)) ] || fail="$fail checks=$checks<$CHECKS0_PIN+fuzz"
  [ "${fuzzed:-x}" = "$FUZZ" ] || fail="$fail fuzz=${fuzzed:-none}!=$FUZZ"
  [ "${groups:-x}" = $GROUPS_PIN ] || fail="$fail groups=${groups:-none}!=$GROUPS_PIN"
  echo "CORPUS rc=$rc $line"
  # 5. Controls. Reached from a self-control copy, the gate stops here (exit 4, never a pass).
  if [ -n "${TCP_GATE_DEPTH:-}" ]; then echo "$T CONTROL_COPY reached its controls"; exit 4; fi
  ctl_ok=0 ctl_bad=0
  control no-compiler 3 sh "$HERE/gate.sh" corpus "$OUT/no-such-omc" "$OUT/ctl"
  cat "$OMC" > "$OUT/omc-wrong" && printf '\n' >> "$OUT/omc-wrong" && chmod +x "$OUT/omc-wrong"
  control wrong-compiler 3 sh "$HERE/gate.sh" corpus "$OUT/omc-wrong" "$OUT/ctl"
  control wrong-compiler-qemu 3 sh "$HERE/gate.sh" "$OUT/omc-wrong" "$OUT/no-image" "$OUT/no-busybox" "$OUT/ctl"
  expect fuzz-below-pin 1 "below the pinned" env FUZZ=$((FUZZ_PIN - 1)) TCP_GATE_DEPTH=1 sh "$HERE/gate.sh" corpus "$OMC" "$OUT/self-fuzz"
  expect fuzz-one 1 "below the pinned" env FUZZ=1 TCP_GATE_DEPTH=1 sh "$HERE/gate.sh" corpus "$OMC" "$OUT/self-fuzz"
  selfgate mutant-row-deleted "mutants=" ed_awk mutants.tsv '{ l[NR] = $0 } END { for (i = 1; i < NR; i++) print l[i] }'
  selfgate mutant-row-commented "mutants=" ed_awk mutants.tsv '!/^#/ && NF && !c { print "#" $0; c = 1; next } { print }'
  selfgate mutant-row-duplicated "duplicate mutant" ed_awk mutants.tsv '!/^#/ && NF { n++; if (n == 1) f = $0; if (n == 2) { print f; next } } { print }'
  selfgate group-skipped "groups=" ed_awk corpus.om '$0 != "ccases26"'
  selfgate check-deleted "fuzz 0" ed_awk corpus.om '$1 == "fn" { f = $2 } f == "ccases26" && $1 == "cck" && !d { d = 1; next } { print }'
  selfgate unasserted-row-deleted "unasserted survived=" ed_awk unasserted.tsv 'BEGIN { FS = "\t" } !/^#/ && $5 == "survived" && !d { d = 1; next } { print }'
  selfgate unasserted-class-changed "unasserted survived=" ed_awk unasserted.tsv 'BEGIN { FS = OFS = "\t" } !/^#/ && $5 == "survived" && !d { $5 = "trapped"; d = 1 } { print }'
  selfgate mutgen-neg "generated rows sha256" ed_awk mutgen.awk '{ sub(/"if not "/, "\"if nott \"") } { print }'
  selfgate frame-check-skipped "fuzz 0" ed_awk corpus.om '$0 != "cfrmchk n"'
  selfgate trnd-unrefused "nokey" ed_mut_repin tcp.om trnd 1 "trap 8" "note mutant"
  selfgate tcpd-constant-key "tcpdkey" ed_mut tcpd.om dseed 1 "tkey a b" "tkey 1 2"
  selfgate tcpd-short-read-kept "tcpdkey" ed_mut tcpd.om dseed 1 "exit 7" "note mutant"
  # The kill and list rules on fixed inputs: a trap, another check's failure and a CORPUS_PASS
  # are not check 7's kill, a CORPUS_FAIL check=7 at exit 1 is; a list missing a row, or
  # with a row the other lacks, is not the same list.
  K=$OUT/killrule; mkdir -p "$K"
  printf 'some output\n' > "$K/trap.log"
  printf 'CORPUS_FAIL check=5\nCORPUS_FAIL failures=1\n' > "$K/other.log"
  printf 'CORPUS_FAIL check=7\nCORPUS_PASS checks=1 fuzz=0 groups=1 x\n' > "$K/pass.log"
  printf 'CORPUS_FAIL check=70\nCORPUS_FAIL check=17\nCORPUS_FAIL failures=2\n' > "$K/near.log"
  printf 'CORPUS_FAIL check=7\nCORPUS_FAIL failures=1\n' > "$K/kill.log"
  printf 'a\t1\tx\ty\nb\t1\tx\tz\n' > "$K/two"; printf 'a\t1\tx\ty\n' > "$K/one"
  for kc in "trap 104" "other 1" "pass 1" "near 1"; do
    set -- $kc
    if corpus_kills "$K/$1.log" "$2" 7; then ctlbad "killrule-$1" "counted as a kill of check 7"
    else ctlok "killrule-$1"; fi
  done
  if corpus_kills "$K/kill.log" 1 7; then ctlok killrule-kill
  else ctlbad killrule-kill "a check 7 failure not counted"; fi
  if samelist "$K/two" "$K/one" || samelist "$K/one" "$K/two"; then ctlbad listrule "different lists taken as the same"
  else ctlok listrule; fi
  [ $ctl_bad -eq 0 ] && [ $ctl_ok -eq $CONTROLS_PIN ] || fail="$fail controls=$ctl_ok/$CONTROLS_PIN"
  # 6. Hand mutants: each row must fail its own check (kill column): a corpus check id at
  # fuzz 0, nokey (trnd without a key), or tcpdkey (tcpd's key path).
  M=0 K=0
  while IFS=$tab read -r name unit fn occ old new kill; do
    M=$((M + 1))
    D=$OUT/mutant-$name; rm -rf "$D"; mkdir -p "$D"
    cp "$HERE/tcp.om" "$HERE/tcpd.om" "$D/"
    if ! mutapply "$HERE/$unit" "$fn" "$occ" "$old" "$new" "$D/$unit" || cmp -s "$HERE/$unit" "$D/$unit"; then
      echo "MUTANT $name NOT_APPLIED (line not found in fn $fn of $unit)"; continue
    fi
    case $kill in
      nokey) cat "$D/tcp.om" "$HERE/nokey.om" ;;
      tcpdkey) cat "$D/tcp.om" "$D/tcpd.om" ;;
      *) cat "$D/tcp.om" "$HERE/corpus.om" ;;
    esac | "$OMC" > "$D/bin" 2> "$D/build.log" || { echo "MUTANT $name NOT_BUILT $(head -1 "$D/build.log")"; continue; }
    chmod +x "$D/bin"
    case $kill in
      nokey) if nokey_ok "$D/bin" "$D/run.log"; then mk=0; else mk=1; fi ;;
      tcpdkey) if tcpdkey_ok "$D/bin" "$D"; then mk=0; else mk=1; fi ;;
      *) "$D/bin" 0 > "$D/run.log" 2>&1; mrc=$?
         if corpus_kills "$D/run.log" $mrc "$kill"; then mk=1; else mk=0; fi ;;
    esac
    lname=$(printf '%s' "$name" | tr 'A-Z' 'a-z')
    if [ $mk -eq 1 ]; then K=$((K + 1)); echo "MUTANT $name KILLED by $kill"; echo "CONTROL OMEGA-KERNEL-TCP-CORPUS/mutant-$lname FAILED_AS_REQUIRED"
    else echo "MUTANT $name SURVIVED (not failed by $kill)"; echo "CONTROL OMEGA-KERNEL-TCP-CORPUS/mutant-$lname FAIL (not failed by $kill)"; fi
    rm -f "$D/bin"
  done < "$OUT/mutants.rows"
  [ $M -eq $MUTANTS_PIN ] || fail="$fail mutants_run=$M"
  [ $K -eq $M ] || fail="$fail survived_or_unapplied=$((M - K))"
  # 7. Generated mutants (mutgen.awk over each tcp.om function), eight at a time. The rows
  # not killed, each with its class, must be exactly unasserted.tsv.
  G=$OUT/generated; rm -rf "$G"; mkdir -p "$G"
  for s in 0 1 2 3 4 5 6 7; do
    awk -v s=$s 'NR % 8 == s' "$OUT/generated.rows" > "$G/rows$s"
    genrun "$G/rows$s" "$G" > "$G/out$s" 2>&1 &
  done
  wait
  cat "$G"/out[0-7] > "$OUT/generated.log"
  gn=$(wc -l < "$OUT/generated.log")
  gk=$(grep -c ' killed ' "$OUT/generated.log")
  gs=$(grep -c ' survived$' "$OUT/generated.log")
  gt=$(grep -c ' trapped ' "$OUT/generated.log")
  gb=$(grep -c ' not_built$' "$OUT/generated.log")
  [ "$gn" -eq "$g" ] && [ $((gk + gs + gt + gb)) -eq "$g" ] || fail="$fail generated_unrun=$((g - gk - gs - gt - gb))"
  awk '$2 == "survived" || $2 == "trapped" || $2 == "not_built" { print $1 "\t" $2 }' "$OUT/generated.log" > "$OUT/notkilled.names"
  awk -F"$tab" 'NR == FNR { c[$1] = $2; next } ($1 in c) { print $2 FS $3 FS $4 FS $5 FS c[$1] }' "$OUT/notkilled.names" "$OUT/generated.rows" | LC_ALL=C sort > "$OUT/notkilled.rows"
  if ! cmp -s "$OUT/notkilled.rows" "$OUT/unasserted.rows"; then
    diff "$OUT/notkilled.rows" "$OUT/unasserted.rows" | sed -n 's/^</NOT KILLED, not so in unasserted.tsv:/p; s/^>/unasserted.tsv row not so:/p'
    fail="$fail notkilled!=unasserted"
  fi
  gr=$((gk + gs + gt))
  echo "GENERATED rows=$g fns=$(echo $fns | wc -w) built=$gr killed=$gk survived=$gs trapped=$gt not_built=$gb kill_rate=$gk/$gr"
  tail="checks=$checks fuzz=$FUZZ groups=${groups:-0} mutants=$M killed=$K generated=$gr gen_killed=$gk survivors=$((gs + gt)) controls=$ctl_ok"
  if [ -z "$fail" ]; then echo "$T PASS $tail"; exit 0; fi
  echo "$T FAIL $tail$fail"; exit 1
}
if [ "${1:-}" = corpus ]; then shift; corpus_gate "$@"; fi
[ $# -ge 4 ] || { echo "usage: gate.sh corpus OMC OUTDIR | gate.sh OMC IMAGE BUSYBOX OUTDIR [PROFILES] [SCENARIOS]" >&2; exit 2; }
OMC=$1 IMAGE=$2 BUSYBOX=$3 OUT=$4
PROFILES=${5:-clean loss reorder hostile}
SCEN=${6:-echo h2g g2h}
pincheck GATE "$OMC"
[ -r "$IMAGE" ] || notrun GATE "no guest image at $IMAGE"
[ -r "$BUSYBOX" ] || notrun GATE "no busybox at $BUSYBOX"
command -v qemu-system-aarch64 > /dev/null || notrun GATE "no qemu-system-aarch64"
[ -r /dev/kvm ] && [ -w /dev/kvm ] || notrun GATE "no access to /dev/kvm"
mkdir -p "$OUT" || exit 2
OUT=$(cd "$OUT" && pwd)
B=$OUT/bin; mkdir -p "$B"
cat "$HERE/tcp.om" "$HERE/tcpd.om" | "$OMC" > "$B/tcpd" || { echo "GATE_FAIL build tcpd"; exit 2; }
"$OMC" < "$HERE/link.om" > "$B/link" || { echo "GATE_FAIL build link"; exit 2; }
"$OMC" < "$HERE/peer.om" > "$B/peer" || { echo "GATE_FAIL build peer"; exit 2; }
chmod +x "$B/tcpd" "$B/link" "$B/peer"
sha256sum "$OMC" "$IMAGE" "$BUSYBOX" "$B/tcpd" "$B/link" "$B/peer" > "$OUT/inputs.sha256"
# Hosted hostile corpus first, with its mutants and controls (the corpus mode above).
sh "$HERE/gate.sh" corpus "$OMC" "$OUT/corpus" > "$OUT/corpus.log" 2>&1
CS=$?
if [ $CS -ne 0 ] || ! grep -q '^TCP_CORPUS_GATE PASS' "$OUT/corpus.log"; then
  echo "CORPUS_FAIL rc=$CS $(tail -1 "$OUT/corpus.log")"; corpus_ok=0
else
  echo "CORPUS_OK $(grep '^TCP_CORPUS_GATE PASS' "$OUT/corpus.log")"; corpus_ok=1
fi
qemu-system-aarch64 --version | head -1 >> "$OUT/inputs.sha256"
# Payloads: a fixed pseudo-random file (derived from the busybox bytes, so it is
# reproducible) for echo and host-to-guest, the busybox binary for guest-to-host.
P1=$OUT/payload1
{ cat "$BUSYBOX"; cat "$BUSYBOX"; } | gzip -9 -n | head -c 1048576 > "$P1"
cat "$P1" "$P1" | head -c 2000000 > "$OUT/payload2"
P2=$OUT/payload2
# Initramfs
R=$OUT/rd; rm -rf "$R"; mkdir -p "$R/bin" "$R/proc" "$R/sys" "$R/dev" "$R/tmp"
cp "$BUSYBOX" "$R/bin/busybox"; cp "$B/tcpd" "$R/tcpd"
cat > "$R/init" <<'EOF'
#!/bin/busybox sh
B=/bin/busybox
$B mount -t proc p /proc
$B mount -t sysfs s /sys
$B mount -t devtmpfs d /dev
A=$($B sed -n 's/.*tcpdargs=\([^ ]*\).*/\1/p' /proc/cmdline | $B tr , ' ')
/tcpd $A
echo "TCPD_EXIT=$?"
[ -f /tmp/rx ] && $B sha256sum /tmp/rx
# Give the serial console time to drain; poweroff -f can cut the last lines.
$B sleep 1
$B poweroff -f
EOF
chmod +x "$R/init"
(cd "$R" && find . | cpio -o -H newc 2>/dev/null | gzip -1 > "$OUT/rd.cpio.gz")
fails=0; runs=0; n=0
num() { v=$(grep -a "^$1 " "$2" | head -1 | cut -d' ' -f"$3"); echo "${v:-0}"; }
# Host ports sit below the Linux ephemeral range (32768-60999) so an unrelated
# outgoing connection cannot already hold one when slirp binds its forward.
PORTBASE=${PORTBASE:-21100}
for prof in $PROFILES; do
  case $prof in
    clean)   RATES="0 0 0 0" ;;
    loss)    RATES="30 0 0 0" ;;
    reorder) RATES="0 150 0 0" ;;
    hostile) RATES="20 100 20 200" ;;
    *) echo "GATE_FAIL unknown profile $prof"; exit 2 ;;
  esac
  for sc in $SCEN; do
    n=$((n + 1)); runs=$((runs + 1))
    HP=$((PORTBASE + n)); SEED=$((7919 * n + 17))
    D=$OUT/run-$prof-$sc; rm -rf "$D"; mkdir -p "$D"; : > "$D/console.log"
    T=$(mktemp -d /tmp/l232g.XXXXXX)
    case $sc in
      echo) ARGS="e,7,-,-,150"; FWD=",hostfwd=tcp:127.0.0.1:$HP-10.0.2.15:7"; WANT=$P1 ;;
      h2g)  ARGS="r,9,-,/tmp/rx,150"; FWD=",hostfwd=tcp:127.0.0.1:$HP-10.0.2.15:9"; WANT=$P2 ;;
      g2h)  ARGS="s,$HP,10.0.2.2,/bin/busybox,150"; FWD=""; WANT=$BUSYBOX ;;
    esac
    # link.om stops on its own when the guest goes quiet; timeout bounds it if traffic never stops.
    timeout 230 "$B/link" "$T/l1" "$T/g" "$T/l2" "$T/s" $SEED $RATES 8 > "$D/link.log" 2>&1 &
    LP=$!
    if [ "$sc" = g2h ]; then
      "$B/peer" r $HP "$WANT" 170 "$D/received" > "$D/peer.log" 2>&1 &
      PP=$!
    fi
    sleep 0.2
    timeout 200 qemu-system-aarch64 -M virt -accel kvm -cpu host -m 512 -smp 1 -nographic -no-reboot \
      -kernel "$IMAGE" -initrd "$OUT/rd.cpio.gz" \
      -append "console=ttyAMA0 quiet panic=-1 ipv6.disable=1 tcpdargs=$ARGS" \
      -netdev dgram,id=n0,local.type=unix,local.path=$T/g,remote.type=unix,remote.path=$T/l1 \
      -device virtio-net-pci,netdev=n0,romfile= \
      -netdev dgram,id=d1,local.type=unix,local.path=$T/s,remote.type=unix,remote.path=$T/l2 \
      -netdev user,id=u0$FWD \
      -netdev hubport,id=hp0,hubid=1,netdev=u0 -netdev hubport,id=hp1,hubid=1,netdev=d1 \
      > "$D/console.log" 2>&1 &
    QP=$!
    if [ "$sc" != g2h ]; then
      i=0; while [ $i -lt 300 ] && ! grep -aq TCPD_READY "$D/console.log"; do sleep 0.1; i=$((i + 1)); done
      MODE=e; [ "$sc" = h2g ] && MODE=s
      "$B/peer" $MODE $HP "$WANT" 170 > "$D/peer.log" 2>&1
      PS=$?
    else
      wait $PP; PS=$?
    fi
    wait $QP; QS=$?
    wait $LP; LS=$?
    rm -rf "$T"
    ok=1; why=""
    [ $PS -eq 0 ] && grep -aq '^PEER_PASS' "$D/peer.log" || { ok=0; why="$why peer"; }
    grep -aq '^TCPD_PASS' "$D/console.log" && grep -aq 'TCPD_EXIT=0' "$D/console.log" || { ok=0; why="$why tcpd"; }
    [ $LS -eq 0 ] || { ok=0; why="$why link"; }
    [ $QS -eq 0 ] || { ok=0; why="$why qemu"; }
    want=$(sha256sum "$WANT" | cut -d' ' -f1)
    # Echo bytes are compared one by one by peer.om; the two transfers are compared by digest.
    case $sc in
      h2g) got=$(grep -a ' /tmp/rx' "$D/console.log" | cut -d' ' -f1) ;;
      g2h) got=$(sha256sum "$D/received" | cut -d' ' -f1) ;;
      echo) got=peer-compared ;;
    esac
    [ "$sc" = echo ] || [ "$got" = "$want" ] || { ok=0; why="$why digest"; }
    # The profile must really have impaired this run (LINK fields: 2 in 3 out 4 drop 5 held 6 dup, +8 for B to A; 18 hostile).
    drop=$(( $(num LINK "$D/link.log" 4) + $(num LINK "$D/link.log" 12) ))
    held=$(( $(num LINK "$D/link.log" 5) + $(num LINK "$D/link.log" 13) ))
    dup=$(( $(num LINK "$D/link.log" 6) + $(num LINK "$D/link.log" 14) ))
    host=$(num LINK "$D/link.log" 18)
    set -- $RATES
    [ "$1" -eq 0 ] || [ $drop -gt 0 ] || { ok=0; why="$why nodrop"; }
    [ "$2" -eq 0 ] || [ $held -gt 0 ] || { ok=0; why="$why noreorder"; }
    [ "$3" -eq 0 ] || [ $dup -gt 0 ] || { ok=0; why="$why nodup"; }
    [ "$4" -eq 0 ] || [ $host -gt 0 ] || { ok=0; why="$why nohostile"; }
    # Every one of the 15 hostile kinds (LINKH fields 2..16) must have been injected.
    kinds=0; k=2; while [ $k -le 16 ]; do [ $(num LINKH "$D/link.log" $k) -gt 0 ] && kinds=$((kinds + 1)); k=$((k + 1)); done
    [ "$4" -eq 0 ] || [ $kinds -eq 15 ] || { ok=0; why="$why kinds=$kinds"; }
    [ "$1$2$3$4" != 0000 ] || [ $((drop + held + dup + host)) -eq 0 ] || { ok=0; why="$why notclean"; }
    line="$prof $sc sha=$got drop=$drop held=$held dup=$dup hostile=$host qemu=$QS $(grep -a '^TCPD_PASS\|^TCPD_FAIL' "$D/console.log" | head -1)"
    if [ $ok -eq 1 ]; then echo "RUN_PASS $line"; else echo "RUN_FAIL$why $line"; fails=$((fails + 1)); fi
  done
done
if [ $fails -eq 0 ] && [ $corpus_ok -eq 1 ]; then echo "GATE_PASS runs=$runs corpus=pass"; exit 0; fi
echo "GATE_FAIL failed=$fails runs=$runs corpus_ok=$corpus_ok"; exit 1
