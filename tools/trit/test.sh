#!/bin/sh
# test.sh -- fixture tests for tools/trit.
# Usage: ./test.sh from tools/trit, or sh tools/trit/test.sh from the repo root.
# BIN defaults to <repo>/build/trit/trit if present, else trit.bin beside this script.
# CBIN defaults to <repo>/build/codebook/codebook, else codebook.bin beside tools/codebook.
# Every case builds its own DIR/inbox under $FIX/<case> (kept as the fixture), runs the binary, and
# compares stdout, stderr and exit status exactly. Expected tokens and cursor hashes come from
# coreutils (head, wc, sha256sum), not from the program.
set -u
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
if [ -z "${BIN:-}" ]; then
  if [ -x "$ROOT/build/trit/trit" ]; then BIN=$ROOT/build/trit/trit
  elif [ -x "$HERE/trit.bin" ]; then BIN=$HERE/trit.bin
  else echo "test.sh: no trit binary ($ROOT/build/trit/trit or $HERE/trit.bin)" >&2; exit 2
  fi
fi
case $BIN in /*) ;; *) BIN=$(pwd)/$BIN ;; esac
if [ -z "${CBIN:-}" ]; then
  if [ -x "$ROOT/build/codebook/codebook" ]; then CBIN=$ROOT/build/codebook/codebook
  elif [ -x "$HERE/../codebook/codebook.bin" ]; then CBIN=$HERE/../codebook/codebook.bin
  else echo "test.sh: no codebook binary" >&2; exit 2
  fi
fi
CBT=${CBT:-$HERE/../codebook/codebook.tsv}
FIX=${FIX:-${TMPDIR:-/tmp}/trit-fixtures.$$}
rm -rf "$FIX"; mkdir -p "$FIX"; chmod 700 "$FIX"
KEY=$FIX/.key; KEY2=$FIX/.key2; (umask 077; head -c 32 /dev/urandom > "$KEY"; head -c 32 /dev/urandom > "$KEY2")
chmod 600 "$KEY" "$KEY2"
printf 'BIN %s\nFIX %s\n' "$BIN" "$FIX"
pass=0; fail=0; skip=0
ok() { pass=$((pass+1)); printf 'PASS %s\n' "$1"; }
no() { fail=$((fail+1)); printf 'FAIL %s: %s\n' "$1" "$2"; }
skip() { skip=$((skip+1)); printf 'SKIP %s\n' "$1"; }
# ELF e_machine: 183=AArch64, 62=x86-64. Prefer native strace -f when the binary runs natively;
# otherwise qemu-user -strace if qemu is on PATH; else SKIP (never PASS).
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
# Every fixture gets DIR/codebook/{codebook.tsv,key} (a fresh random test key, never printed).
new() { D="$FIX/$1"; mkdir -p "$D/inbox" "$D/codebook"; cp "$CBT" "$D/codebook/codebook.tsv"; cp "$KEY" "$D/codebook/key"; chmod 600 "$D/codebook/key"; C=$1; LANE=n; TO=a; }
L() { printf '%s|%s|%s|%s|-\n' "$1" "$2" "$3" "$4"; }
# S TS SENDER TAG TEXT COUNTER DIGITS [KEYFILE]: a 6-field line signed as ocb2 (lane=$LANE, to=$TO).
sg() { printf '%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "${LANE:-n}" "$1" "$2" "${TO:-a}" "$3" "$4" "-" "$5" "$6" | "$CBIN" sign "$CBT" "${7:-$KEY}"; }
S() { printf '%s|%s|%s|%s|%s|%s|%s\n' "$1" "$2" "${TO:-a}" "$3" "$4" "-" "$(sg "$1" "$2" "$3" "$4" "$5" "$6" "${7:-}")"; }
Se() { LANE=e S "$@"; LANE=n; }
HDR='# Inbox: a
One line per note: `YYYY-MM-DDTHH:MM|from|tag|text|ref`.'
# tokf LANE FILE: L<offset of the end of the last complete line>:<sha256 of that line>
tokf() {
  nl=$(tr -dc '\n' < "$2" | wc -c | tr -d ' ')
  off=$(head -n "$nl" "$2" | wc -c | tr -d ' ')
  h=$(head -c "$off" "$2" | sha256sum | cut -c1-64)
  printf '%s%s:%s' "$1" "$off" "$h"
}
# ex LANE BOT TRIT: the expected output line (nothing for 0: silence)
ex() {
  if [ "$3" = 0 ]; then return; fi
  if [ "$1" = e ]; then f="$D/inbox/$2.emergency.md"; else f="$D/inbox/$2.md"; fi
  printf '%s %s %s' "$2" "$3" "$(tokf "$1" "$f")"
}
# run NAME EXPECT_STDOUT EXPECT_STDERR ARGS...   (exit 0 when a line is printed, 1 when silent)
run() {
  n=$1; eo=$2; ee=$3; shift 3
  wrc=0; [ -z "$eo" ] && wrc=1
  o=$("$BIN" "$D" "$@" 2>"$D/.err"); rc=$?; e=$(cat "$D/.err"); rm -f "$D/.err"
  if [ "$rc" = "$wrc" ] && [ "$o" = "$eo" ] && [ "$e" = "$ee" ]; then ok "$C/$n"; else no "$C/$n" "rc=$rc out=[$o] err=[$e] want=$wrc [$eo] [$ee]"; fi
}
# refuse NAME RC ARGS...: expects that exit status, no stdout, and cursor files unchanged
refuse() {
  n=$1; want=$2; shift 2
  before=$(cat "$D"/inbox/*.cur 2>/dev/null | sha256sum)
  o=$("$BIN" "$D" "$@" 2>/dev/null); rc=$?
  after=$(cat "$D"/inbox/*.cur 2>/dev/null | sha256sum)
  if [ "$rc" = "$want" ] && [ -z "$o" ] && [ "$before" = "$after" ]; then ok "$C/$n"; else no "$C/$n" "rc=$rc out=[$o] cursor-changed=$([ "$before" = "$after" ] && echo no || echo yes)"; fi
}
tok() { "$BIN" "$D" a 2>/dev/null | cut -d' ' -f3; }
T1=2026-11-15T12:00; T2=2026-11-15T12:05; T3=2026-11-15T12:10

new zero-header-only;  printf '%s\n' "$HDR" > "$D/inbox/a.md";                         run t "" "" a
new one-unread;        { printf '%s\n' "$HDR"; L $T1 drake-bot turn "do it"; } > "$D/inbox/a.md"; run t "$(ex n a 1)" "" a
new stop-tag-unsigned; L $T1 drake-bot stop halt > "$D/inbox/a.md";                     run is-1 "$(ex n a 1)" "" a
new stop-text-unsigned; L $T1 drake-bot fyi "STOP now" > "$D/inbox/a.md";               run is-1 "$(ex n a 1)" "" a
new stop-to-field;     printf '%s|drake-bot|a|stop|halt|-\n' $T1 > "$D/inbox/a.md";    run is-1 "$(ex n a 1)" "" a
new empty-inbox;       : > "$D/inbox/a.md";                                             run t "" "" a
new missing-inbox;                                                                      run t "" "" a
new partial-line;      { printf '%s\n' "$HDR"; printf '%s|x|turn|half|-' $T1; } > "$D/inbox/a.md"; run before-newline "" "" a
                       printf '\n' >> "$D/inbox/a.md";                                  run after-newline "$(ex n a 1)" "" a
new multi-bot;         L $T1 x turn t > "$D/inbox/a.md"; : > "$D/inbox/b.md"; TO=c S $T1 drake stop s 1 300 > "$D/inbox/c.md"; TO=a
                       run t "$(ex n a 1)
$(ex n c 2)" "" a b c

# Signed lines (tools/codebook format, last '|' field ocb1:<cbsha>:<counter>:<digits>:<mac>).
new signed;            S $T1 drake stop halt 1 300 > "$D/inbox/a.md";                   run verified-300-is-2 "$(ex n a 2)" "" a
                       S $T1 drake turn work 1 100 > "$D/inbox/a.md";                   run verified-100-is-1 "$(ex n a 1)" "" a
                       S $T1 drake fyi note 1 100 > "$D/inbox/a.md";                    run verified-fyi-100-silent "" "" a
                       S $T1 drake fyi note 1 301 > "$D/inbox/a.md";                    run verified-fyi-301-is-2 "$(ex n a 2)" "" a
                       S $T1 drake turn x 1 900300 > "$D/inbox/a.md";                   run escape-then-300-unknown-is-1 "$(ex n a 1)" "" a
                       S $T1 drake fyi n 1 100 > "$D/inbox/a.md";                    run to-format-sig-stripped-fyi-silent "" "" a
                       S $T1 drake turn "STOP" 1 001 > "$D/inbox/a.md";                 run verified-non-3xx-STOP-is-1 "$(ex n a 1)" "" a
                       if [ -e "$D/inbox/a.drake.ctr" ]; then no "$C/read-does-not-write-counter" "ctr exists"; else ok "$C/read-does-not-write-counter"; fi
new tampered;          S $T1 drake stop h 1 300 | sed 's/:300:/:301:/' > "$D/inbox/a.md"; run digits-changed-is-1 "$(ex n a 1)" "" a
                       S $T1 drake stop h 1 300 | sed 's/|drake|/|b|/' > "$D/inbox/a.md"; run sender-changed-is-1 "$(ex n a 1)" "" a
                       S $T1 drake stop h 1 300 "$KEY2" > "$D/inbox/a.md";              run other-key-is-1 "$(ex n a 1)" "" a
                       S $T1 drake stop h 1 300 | sed 's/:1:300:/:2:300:/' > "$D/inbox/a.md"; run counter-changed-is-1 "$(ex n a 1)" "" a
                       printf '%s|drake|stop|h|-|ocb1:%064d:1:300:%064d\n' $T1 0 0 > "$D/inbox/a.md"; run wrong-cbsha-is-1 "$(ex n a 1)" "" a
                       printf '%s|drake|stop|STOP|-\n' $T1 > "$D/inbox/a.md";          run unsigned-STOP-is-1 "$(ex n a 1)" "" a
new stale;             printf '5\n' > "$D/inbox/a.drake.ctr"; S $T1 drake stop h 5 300 > "$D/inbox/a.md"; run equal-counter-is-1 "$(ex n a 1)" "" a
                       S $T1 drake stop h 6 300 > "$D/inbox/a.md";                      run higher-counter-is-2 "$(ex n a 2)" "" a
                       printf 'junk\n' > "$D/inbox/a.drake.ctr";                        run malformed-counter-file-is-1 "$(ex n a 1)" "" a
                       rm -f "$D/inbox/a.drake.ctr"; { S $T1 drake turn a 5 100; S $T2 drake stop b 3 300; } > "$D/inbox/a.md"
                       run lower-counter-later-in-batch-is-1 "$(ex n a 1)" "" a
new replay;            S $T1 drake stop h 1 300 > "$D/inbox/a.md"; cp "$D/inbox/a.md" "$D/line"
                       run first-is-2 "$(ex n a 2)" "" a
                       t=$(tok); run ack "a 0" "" --ack a "$t"
                       if [ "$(cat "$D/inbox/a.drake.ctr")" = "1 $T1" ]; then ok "$C/ack-advanced-counter"; else no "$C/ack-advanced-counter" "$(cat "$D/inbox/a.drake.ctr" 2>&1)"; fi
                       if [ "$(stat -c %a "$D/inbox/a.drake.ctr")" = 600 ]; then ok "$C/counter-mode-600"; else no "$C/counter-mode-600" "$(stat -c %a "$D/inbox/a.drake.ctr")"; fi
                       if [ -e "$D/inbox/a.ctr.lock" ] && [ ! -e "$D/inbox/a.drake.ctr.tmp" ]; then ok "$C/lock-file-no-tmp"; else no "$C/lock-file-no-tmp" "$(ls "$D/inbox")"; fi
                       cat "$D/line" >> "$D/inbox/a.md";                               run replayed-copy-is-1 "$(ex n a 1)" "" a
                       cp "$D/line" "$D/inbox/b.md";                                    run other-bot-copy-is-1 "$(ex n b 1)" "" b
new no-codebook;       rm -rf "$D/codebook"; S $T1 drake stop h 1 300 > "$D/inbox/a.md"; run no-codebook-is-1 "$(ex n a 1)" "" a
                       mkdir -p "$D/codebook"; cp "$CBT" "$D/codebook/codebook.tsv";    run no-key-is-1 "$(ex n a 1)" "" a
                       cp "$KEY" "$D/codebook/key"; printf 'bad\n' >> "$D/codebook/codebook.tsv"
                       "$BIN" "$D" a >/dev/null 2>&1; rc=$?; if [ "$rc" = 4 ]; then ok "$C/invalid-codebook-exit-4"; else no "$C/invalid-codebook-exit-4" "rc=$rc"; fi
new syscalls;          S $T1 drake stop h 1 300 > "$D/inbox/a.md"; t=$(tok)
                       pick_tracer "$BIN"
                       if [ -z "$TRC" ]; then
                         echo "note: no strace/qemu tracer; syscall order not checked"
                         skip "$C/lock-ctr-rename-dirsync-unlock-cursor-rename-dirsync"
                       else
                         if [ "$TRC" = strace ]; then
                           strace -f -o "$D/trace" "$BIN" "$D" --ack a "$t" > /dev/null 2> "$D/err" || true
                         else
                           "$TRC" -strace "$BIN" "$D" --ack a "$t" > /dev/null 2> "$D/trace" || true
                         fi
                         got=$(awk -v inbox="$D/inbox" '
                           /flock\([0-9]+, *(2|LOCK_EX)/ { printf "L"; next }
                           /flock\([0-9]+, *(8|LOCK_UN)/ { printf "U"; next }
                           /renameat2/ { printf "R"; next }
                           /[^a-z]fsync\(/ || /^[0-9]+ fsync\(/ || / fsync\(/ { printf "F"; next }
                           index($0, "openat(AT_FDCWD, \"" inbox "\"") || index($0, "openat(AT_FDCWD,\"" inbox "\"") { printf "D"; next }
                         ' "$D/trace")
                         if [ "$got" = LFRDFUFRDF ]; then ok "$C/lock-ctr-rename-dirsync-unlock-cursor-rename-dirsync"; else no "$C/syscall-order" "$got"; fi
                       fi

new ack-advances;      { printf '%s\n' "$HDR"; L $T1 x turn one; S $T2 drake stop two 1 300; } > "$D/inbox/a.md"
                       run before "$(ex n a 2)" "" a
                       t=$(tok); run ack "a 0" "" --ack a "$t"
                       run after "" "" a
                       off=$(wc -c < "$D/inbox/a.md" | tr -d ' ')
                       want=$(sha256sum < "$D/inbox/a.md" | cut -c1-64)
                       if [ "$(cat "$D/inbox/a.md.cur")" = "$off $want" ]; then ok "$C/cursor-is-offset-and-sha256"; else no "$C/cursor" "$(cat "$D/inbox/a.md.cur") want $off $want"; fi
                       if [ -e "$D/inbox/a.md.cur.tmp" ]; then no "$C/no-temp-left" "tmp exists"; else ok "$C/no-temp-left"; fi
                       run reack-same-token-is-noop "a 0" "" --ack a "$t"
                       L $T3 x turn three >> "$D/inbox/a.md";                           run new-line "$(ex n a 1)" "" a
                       S $T3 drake stop p 2 300 | tr -d '\n' >> "$D/inbox/a.md";        run partial-not-counted "$(ex n a 1)" "" a
                       t=$(tok); run ack2 "a 0" "" --ack a "$t"
                       printf '\n' >> "$D/inbox/a.md";                                  run partial-completed "$(ex n a 2)" "" a
new ack-race;          L $T1 x turn read-me > "$D/inbox/a.md"
                       t=$(tok); S $T2 drake stop arrived-after-read 1 300 >> "$D/inbox/a.md"
                       run ack-keeps-late-line-unread "a 0
$(ex n a 2)" "" --ack a "$t"
                       o=${t%%:*}; if [ "$(cat "$D/inbox/a.md.cur")" = "${o#n} ${t#*:}" ]; then ok "$C/cursor-is-exactly-the-token"; else no "$C/cursor-is-exactly-the-token" "$(cat "$D/inbox/a.md.cur") vs $t"; fi
                       if [ -e "$D/inbox/a.drake.ctr" ]; then no "$C/late-line-counter-not-advanced" "advanced"; else ok "$C/late-line-counter-not-advanced"; fi
                       t=$(tok); run ack-late-line "a 0" "" --ack a "$t"
new ack-race-emerg;    L $T1 x turn n1 > "$D/inbox/a.md"
                       t=$(tok); Se $T2 drake alert fire 1 300 >> "$D/inbox/a.emergency.md"
                       run normal-ack-leaves-emergency "a 0
$(ex e a 2)" "" --ack a "$t"
                       t=$(tok); Se $T3 drake alert fire2 2 301 >> "$D/inbox/a.emergency.md"
                       run emerg-ack-keeps-late-emergency "a 0
$(ex e a 2)" "" --ack a "$t"
                       t=$(tok); run emerg-cleared "a 0" "" --ack a "$t"
new ack-refusals;      { L $T1 x turn one; L $T2 x turn two; } > "$D/inbox/a.md"
                       t1=$(tokf n "$D/inbox/a.md"); h1=${t1#*:}; o1=${t1%%:*}; o1=${o1#n}
                       first=$(head -n 1 "$D/inbox/a.md"); fo=$(printf '%s\n' "$first" | wc -c | tr -d ' ')
                       fh=$(printf '%s\n' "$first" | sha256sum | cut -c1-64)
                       refuse not-line-boundary 3 --ack a "n$((o1-1)):$h1"
                       refuse mid-line-with-matching-hash 3 --ack a "n$((o1-1)):$(head -c $((o1-1)) "$D/inbox/a.md" | sha256sum | cut -c1-64)"
                       refuse past-eof 3 --ack a "n$((o1+1)):$h1"
                       refuse zero-offset 3 --ack a "n0:$h1"
                       refuse wrong-hash 3 --ack a "n$o1:$fh"
                       refuse wrong-lane 3 --ack a "e$o1:$h1"
                       refuse bad-lane-letter 3 --ack a "x$o1:$h1"
                       refuse no-colon 3 --ack a "n$o1"
                       refuse short-hex 3 --ack a "n$o1:$(printf '%s' "$h1" | cut -c1-63)"
                       refuse upper-hex 3 --ack a "n$o1:$(printf '%s' "$h1" | tr a-f A-F)"
                       refuse no-digits 3 --ack a "n:$h1"
                       refuse plain-ack-removed 2 --ack a
                       run ack-first-line "a 0
$(ex n a 1)" "" --ack a "n$fo:$fh"
                       run ack-all "a 0" "" --ack a "$t1"
                       refuse stale-behind-cursor 3 --ack a "n$fo:$fh"
                       { L $T1 x turn one; L $T2 x turn TWO; } > "$D/inbox/a.md"
                       refuse rewritten-since-read 3 --ack a "$t1"
                       run rewritten-shows-unread "$(ex n a 1)" "" a
new oracle-cursor;     { L $T1 x turn one; L $T2 x turn two; } > "$D/inbox/a.md"
                       h=$(sha256sum < "$D/inbox/a.md" | cut -c1-64)
                       printf '%s %s\n' "$(wc -c < "$D/inbox/a.md" | tr -d ' ')" "$h" > "$D/inbox/a.md.cur"; run external-cursor-accepted "" "" a
new torn-write;        { L $T1 x turn one; L $T2 x turn two; } > "$D/inbox/a.md"; t=$(tok); run ack "a 0" "" --ack a "$t"
                       printf 'garbage-from-a-crash' > "$D/inbox/a.md.cur.tmp";        run stale-tmp-ignored "" "" a
                       head -c 40 "$D/inbox/a.md.cur" > "$D/x" && mv "$D/x" "$D/inbox/a.md.cur"; run torn-cursor-fails-safe-unread "$(ex n a 1)" "" a
                       : > "$D/inbox/a.md.cur";                                         run empty-cursor-unread "$(ex n a 1)" "" a
                       t=$(tok); run ack-replaces-torn "a 0" "" --ack a "$t"
                       if [ -e "$D/inbox/a.md.cur.tmp" ]; then no "$C/tmp-renamed-away" "tmp exists"; else ok "$C/tmp-renamed-away"; fi
new cursor-past-eof;   { L $T1 x turn one; L $T2 x turn two; } > "$D/inbox/a.md"; t=$(tok); run ack "a 0" "" --ack a "$t"
                       L $T1 x turn one > "$D/inbox/a.md";                              run truncated "$(ex n a 1)" "" a
                       printf '99999 %064d\n' 0 > "$D/inbox/a.md.cur";                  run huge-offset "$(ex n a 1)" "" a
new rewritten-file;    { L $T1 x turn one; L $T2 x turn two; } > "$D/inbox/a.md"; t=$(tok); run ack "a 0" "" --ack a "$t"
                       { L $T1 x turn one; L $T2 x turn TWO; } > "$D/inbox/a.md";       run same-size-new-hash "$(ex n a 1)" "" a
new mid-line-cursor;   { L $T1 x turn one; L $T2 x turn two; } > "$D/inbox/a.md"; o=$(($(wc -c < "$D/inbox/a.md")-1))
                       printf '%s %s\n' "$o" "$(head -c "$o" "$D/inbox/a.md" | sha256sum | cut -c1-64)" > "$D/inbox/a.md.cur"
                       run hash-matching-mid-line-cursor-ignored "$(ex n a 1)" "" a
new bad-cursor;        L $T1 x turn one > "$D/inbox/a.md"; printf 'garbage\n' > "$D/inbox/a.md.cur"; run t "$(ex n a 1)" "" a
new read-stop-ignored; L $T1 x stop old > "$D/inbox/a.md"; t=$(tok); run ack "a 0" "" --ack a "$t"
                       L $T2 x turn new >> "$D/inbox/a.md";                             run t "$(ex n a 1)" "" a

# Emergency lane: DIR/inbox/<bot>.emergency.md. Allowlist = drake + any slug with DIR/inbox/<slug>.md.
# Only a verified 3xx is a 2 and jumps the normal lane; other admitted lines are 1 and wait for it.
new emerg-jumps-line;  { L $T1 x turn n1; L $T2 x turn n2; } > "$D/inbox/a.md"; Se $T1 drake alert fire 1 300 > "$D/inbox/a.emergency.md"
                       run pending "$(ex e a 2)" "" a
                       t=$(tok); run ack-clears-emergency-only "a 0
$(ex n a 1)" "" --ack a "$t"
                       if [ -f "$D/inbox/a.md.cur" ]; then no "$C/normal-untouched" "normal cursor written"; else ok "$C/normal-untouched"; fi
                       t=$(tok); run ack-normal "a 0" "" --ack a "$t"
new emerg-unsigned-waits; L $T1 x turn n > "$D/inbox/a.md"; L $T1 drake alert fire > "$D/inbox/a.emergency.md"
                       run normal-first "$(ex n a 1)" "" a
                       t=$(tok); run then-emergency-1 "a 0
$(ex e a 1)" "" --ack a "$t"
new emerg-over-stop;   S $T1 drake stop halt 3 301 > "$D/inbox/a.md"; Se $T1 drake alert f 2 300 > "$D/inbox/a.emergency.md"
                       run t "$(ex e a 2)" "" a
                       t=$(tok); run ack-then-higher-counter-stop-visible "a 0
$(ex n a 2)" "" --ack a "$t"
                       Se $T1 drake alert g 1 300 > "$D/inbox/a.emergency.md"; rm -f "$D/inbox/a.emergency.md.cur"; run lower-counter-emergency-is-1-and-waits "$(ex n a 2)" "" a
new emerg-known-bot;   : > "$D/inbox/a.md"; : > "$D/inbox/six-sigma.md"; Se $T1 six-sigma alert x 1 310 > "$D/inbox/a.emergency.md"; run t "$(ex e a 2)" "" a
new emerg-unknown;     L $T1 x turn n > "$D/inbox/a.md"; Se $T1 mallory alert x 1 300 > "$D/inbox/a.emergency.md"; run t "$(ex n a 1)" "rejected a 1" a
new emerg-bad-slug;    : > "$D/inbox/a.md"; { L $T1 ../a fyi x; L $T1 Drake fyi x; L $T1 '' fyi x; } > "$D/inbox/a.emergency.md"; run t "" "rejected a 3" a
new emerg-bad-time;    : > "$D/inbox/a.md"; { L 2026-11-15T25:00 drake alert x; L 2026-13-15T12:00 drake alert x; L 2026-11-15T12 drake alert x; } > "$D/inbox/a.emergency.md"; run t "" "rejected a 3" a
new emerg-partial;     : > "$D/inbox/a.md"; printf '%s|drake|fyi|x|-' $T1 > "$D/inbox/a.emergency.md"; run t "" "" a
new emerg-header-only; : > "$D/inbox/a.md"; printf '# Emergency: a\n' > "$D/inbox/a.emergency.md"; run t "" "" a
new emerg-flood;       : > "$D/inbox/a.md"
                       i=0; for m in 00 10 20 30 40; do i=$((i+1)); Se 2026-11-15T12:$m drake alert "f$m" $i 300; done > "$D/inbox/a.emergency.md"
                       run five-in-window "$(ex e a 2)" "rejected a 2" a
                       t=$(tok); run ack "a 0" "" --ack a "$t"
                       Se 2026-11-15T12:50 drake alert f50 6 300 >> "$D/inbox/a.emergency.md"; run ack-does-not-refill "" "rejected a 1" a
                       Se 2026-11-15T13:21 drake alert f81 7 300 >> "$D/inbox/a.emergency.md"; run window-slides "$(ex e a 2)" "rejected a 1" a
new emerg-forged-flood; : > "$D/inbox/a.md"
                       { for m in 00 01 02 03 04 05; do Se 2026-11-15T12:$m drake alert forged 9$m 300 "$KEY2"; done; Se 2026-11-15T12:06 drake alert real 1 300; Se 2026-11-15T12:07 drake alert real2 2 300; Se 2026-11-15T12:08 drake alert real3 3 301; } > "$D/inbox/a.emergency.md"
                       run forged-lines-use-no-quota "$(ex e a 2)" "" a
new emerg-replay-flood; : > "$D/inbox/a.md"; Se 2026-11-15T12:00 drake alert r 1 300 > "$D/line"
                       { for j in 1 2 3 4 5; do cat "$D/line"; done; Se 2026-11-15T12:06 drake alert new 2 300; Se 2026-11-15T12:07 drake alert new3 3 300; } > "$D/inbox/a.emergency.md"
                       run replays-counted-once "$(ex e a 2)" "" a
                       Se 2026-11-15T12:08 drake alert new4 4 300 >> "$D/inbox/a.emergency.md"; run fourth-distinct-rejected "$(ex e a 2)" "rejected a 1" a
new emerg-per-sender;  : > "$D/inbox/a.md"; : > "$D/inbox/b.md"
                       { i=0; for m in 00 01 02 03; do i=$((i+1)); Se 2026-11-15T12:$m drake alert d $i 300; done; Se 2026-11-15T12:04 b alert b 1 300; } > "$D/inbox/a.emergency.md"
                       run t "$(ex e a 2)" "rejected a 1" a
new emerg-day-wrap;    : > "$D/inbox/a.md"
                       { Se 2026-12-31T23:30 drake alert x 1 300; Se 2026-12-31T23:40 drake alert x 2 300; Se 2026-12-31T23:50 drake alert x 3 300; Se 2027-01-01T00:20 drake alert x 4 300; Se 2027-01-01T00:41 drake alert x 5 300; } > "$D/inbox/a.emergency.md"
                       run year-boundary-window "$(ex e a 2)" "rejected a 1" a
new emerg-rewritten;   : > "$D/inbox/a.md"; Se $T1 drake alert x 1 300 > "$D/inbox/a.emergency.md"; t=$(tok); run ack "a 0" "" --ack a "$t"
                       Se $T1 drake alert y 2 300 > "$D/inbox/a.emergency.md"; run t "$(ex e a 2)" "" a

# Silence, exact STOP (now at most 1 unsigned), fyi, full-prefix cursor hash.
new silent;            : > "$D/inbox/a.md"; : > "$D/inbox/b.md"; L $T1 x turn t > "$D/inbox/c.md"
                       run all-silent-exit-1 "" "" a b
                       run one-wakes-exit-0 "$(ex n c 1)" "" a b c
new stop-exact;        for t in "STOPWATCH x" "STOPS" "stop" "STOP-now" "Stop"; do L $T1 x turn "$t"; done > "$D/inbox/a.md"
                       run near-misses-are-1 "$(ex n a 1)" "" a
                       printf '%s|x|a|turn|STOP|-\n' $T1 > "$D/inbox/a.md";              run to-format-text-STOP-unsigned-is-1 "$(ex n a 1)" "" a
                       printf '%s|x|turn|STOP: halt|-\n' $T1 > "$D/inbox/a.md";          run STOP-colon-unsigned-is-1 "$(ex n a 1)" "" a
new fyi;               L $T1 x fyi "note only" > "$D/inbox/a.md";                       run fyi-silent "" "" a
                       L $T2 x turn work >> "$D/inbox/a.md";                            run fyi-plus-turn "$(ex n a 1)" "" a
                       L $T1 x fyi "STOP now" > "$D/inbox/a.md";                        run fyi-STOP-wakes-1 "$(ex n a 1)" "" a
                       L $T1 drake fyi heads-up > "$D/inbox/a.emergency.md"; : > "$D/inbox/a.md"; run emergency-fyi-silent "" "" a
new prefix-hash;       { L $T1 x turn one; L $T2 x turn two; } > "$D/inbox/a.md"; t=$(tok); run ack "a 0" "" --ack a "$t"
                       { L $T1 x stop one; L $T2 x turn two; } > "$D/inbox/a.md";       run earlier-line-rewritten-in-place "$(ex n a 1)" "" a
                       refuse old-token-after-earlier-rewrite 3 --ack a "$t"
new receipt;           L $T1 x turn one > "$D/inbox/a.md"; t=$(tok)
                       run receipt-only "a 0" "" --ack a "$t"
                       run silent-after "" "" a


# Binding (ocb2): a keyless copy or edit of a signed 3xx line is 1, never 2.
new binding;           S $T1 drake stop h 1 300 > "$D/inbox/a.md"; cp "$D/inbox/a.md" "$D/line"
                       run first-is-2 "$(ex n a 2)" "" a
                       TO=b S $T1 drake stop h 1 300 > "$D/inbox/a.md";                   run to-mismatch-is-1 "$(ex n a 1)" "" a
                       cp "$D/line" "$D/inbox/a.emergency.md"; : > "$D/inbox/a.md";      run lane-copy-is-1 "$(ex e a 1)" "" a
                       cat "$D/line" | sed 's/|h|/|HACK|/' > "$D/inbox/a.md"; rm -f "$D/inbox/a.emergency.md"
                       run text-edit-is-1 "$(ex n a 1)" "" a
                       cat "$D/line" | sed 's/|stop|/|turn|/' > "$D/inbox/a.md";         run tag-edit-is-1 "$(ex n a 1)" "" a
                       cat "$D/line" | sed 's/|-|/|REF|/' > "$D/inbox/a.md";             run ref-edit-is-1 "$(ex n a 1)" "" a
                       cat "$D/line" | sed 's/2026-11-15T12:00/2027-11-15T12:00/' > "$D/inbox/a.md"
                       run ts-edit-is-1 "$(ex n a 1)" "" a
                       printf '1 %s\n' "$T2" > "$D/inbox/a.drake.ctr"; S $T1 drake stop h 2 300 > "$D/inbox/a.md"
                       run ts-regress-is-1 "$(ex n a 1)" "" a
                       printf '%s|drake|a|stop|h|-|ocb1:%064d:1:300:%064d\n' $T1 0 0 > "$D/inbox/a.md"
                       run ocb1-is-1 "$(ex n a 1)" "" a
new key-mode;          S $T1 drake stop h 1 300 > "$D/inbox/a.md"; chmod 644 "$D/codebook/key"
                       "$BIN" "$D" a >/dev/null 2>&1; rc=$?; if [ "$rc" = 5 ]; then ok "$C/world-readable-key-exit-5"; else no "$C/world-readable-key-exit-5" "rc=$rc"; fi
new boards-key;        D="$FIX/boards/kcase"; mkdir -p "$D/inbox" "$D/codebook"; C=boards-key
                       cp "$CBT" "$D/codebook/codebook.tsv"; cp "$KEY" "$D/codebook/key"; chmod 600 "$D/codebook/key"
                       S $T1 drake stop h 1 300 > "$D/inbox/a.md"
                       "$BIN" "$D" a >/dev/null 2>&1; rc=$?; if [ "$rc" = 5 ]; then ok "$C/key-inside-boards-exit-5"; else no "$C/key-inside-boards-exit-5" "rc=$rc"; fi

new usage;             : > "$D/inbox/a.md"
                       for args in "../x" "A" "--ack" "--ack a" "--ack a b c" "--trust-unsigned a"; do
                         "$BIN" "$D" $args >/dev/null 2>&1; rc=$?
                         if [ "$rc" = 2 ]; then ok "$C/refuse[$args]"; else no "$C/refuse[$args]" "rc=$rc"; fi
                       done
                       "$BIN" >/dev/null 2>&1; rc=$?; if [ "$rc" = 2 ]; then ok "$C/no-args"; else no "$C/no-args" "rc=$rc"; fi
                       S $T1 drake stop h 1 300 | sed 's/:300:/:301:/' > "$D/inbox/a.md"
                       "$BIN" --trust-unsigned "$D" a >/dev/null 2>&1; rc=$?; if [ "$rc" = 2 ]; then ok "$C/trust-flag-removed"; else no "$C/trust-flag-removed" "rc=$rc"; fi

printf 'TOTAL pass=%d fail=%d skip=%d\n' "$pass" "$fail" "$skip"
[ "$fail" = 0 ]
