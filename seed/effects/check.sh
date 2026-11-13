#!/bin/sh
# Qualification for seed/effects (effect-derived capability manifest).
# The tool is seeded Omega; this coordinator only compiles, runs and compares.
# strace, bwrap, od and dd are read-only oracles / launchers, not implementation.
# Exit 0 PASS, 1 FAIL, 3 NOT_RUN (wrong compiler or missing oracle).
set -u
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
OMC=${OMC:-$ROOT/seed/out/omc}
PIN=$(sed -n 's/^OMC_PIN=//p' om/units.sh)
[ -x "$OMC" ] || { echo "NOT_RUN effects: no omc at $OMC"; exit 3; }
[ "$(sha256sum < "$OMC" | cut -c1-64)" = "$PIN" ] || { echo "NOT_RUN effects: omc is not the pinned compiler $PIN"; exit 3; }
for t in strace bwrap od dd awk; do
    command -v $t > /dev/null || { echo "NOT_RUN effects: oracle $t missing"; exit 3; }
done
B=$ROOT/build/seed/effects
rm -rf "$B"; mkdir -p "$B/probe" "$B/corpus" "$B/run"
C=seed/effects/cases
E=$B/effects
fails=0; checks=0
ok() { checks=$((checks + 1)); printf 'ok   %s\n' "$*"; }
bad() { checks=$((checks + 1)); fails=$((fails + 1)); printf 'FAIL %s\n' "$*"; }
want() { # want NAME EXPECTED_EXIT ACTUAL_EXIT
    if [ "$2" = "$3" ]; then ok "$1 exit=$3"; else bad "$1 exit=$3 expected=$2"; fi
}
build() { # build SRC OUT
    "$OMC" < "$1" > "$2" 2> "$2.err" && chmod +x "$2"
}
sys_of() { # syscalls line of an elf report
    sed -n 's/^ELF 1 .* syscalls=//p'
}

build seed/effects/effects.om "$E" || { cat "$E.err"; echo "SEMANTIC EFFECTS FAIL build"; exit 1; }
echo "omc $PIN"
echo "effects sha256 $(sha256sum < "$E" | cut -c1-64)"

# 1. Closure: every keyword with a host code (>= 100, except the non-host type/declaration
#    keywords const and qty, the CPU ordering words cpufence and cpurelax, which lower to
#    DSB SY / YIELD with no SVC, and the fused float arithmetic word fma (FMADD); checked
#    below) is in the table,
#    and the table holds nothing else besides read/write. The keyword lists are found by
#    content (every split("...") line of genkw.awk), not by line number.
grep 'split("[a-z]' seed/omc/genkw.awk | grep -oE '[a-z0-9]+:[0-9]+' \
    | awk -F: '$2 >= 100 && $1 != "const" && $1 != "qty" && $1 != "cpufence" && $1 != "cpurelax" && $1 != "fma" { print $1 }' \
    | sort > "$B/kw.txt"
for w in cpufence cpurelax fma; do
    grep 'split("[a-z]' seed/omc/genkw.awk | grep -qE "[\" ]$w:[0-9]+" || bad "closure: $w no longer in genkw.awk; review exclusion"
done
printf 'fn main to int\ncpufence\ncpurelax\nx = fma 1.5f64 2.0f64 3.0f64\nret int x\nend\n' > "$B/probe/cpuord.om"
if build "$B/probe/cpuord.om" "$B/probe/cpuord"; then
    c=$("$E" elf < "$B/probe/cpuord" | sys_of)
    [ "$c" = 93 ] && ok "cpufence/cpurelax/fma issue no syscall (ELF syscalls = 93)" || bad "cpufence/cpurelax/fma syscalls = $c"
else bad "cpufence/cpurelax/fma probe does not compile: $(cat "$B/probe/cpuord.err")"; fi
"$E" table | cut -d' ' -f1 | grep -v -x -e read -e write | sort > "$B/tab.txt"
if cmp -s "$B/kw.txt" "$B/tab.txt"; then ok "closure: $(wc -l < "$B/kw.txt") host keywords == table"
else bad "closure: host keywords differ from table"; diff "$B/kw.txt" "$B/tab.txt"; fi
# omc emits SVC at exactly these sites; a new site means the table must be re-reviewed. The 7: fn vs_call,
# hsys, stubs, eof_prog, stmt, and fn en_help's two (the omc_enlarge helper's mremap 216 and mmap 222).
n=$(grep -c '^emit 3556769793$' seed/omc/omc.om)
if [ "$n" = 7 ]; then ok "omc.om SVC emit sites = 7"; else bad "omc.om SVC emit sites = $n (expected 7): review table"; fi

# 2. Probe parity: compile one program per table word with the pinned omc and read the
#    syscalls back out of the ELF; they must equal the table row (93 = exit is always present).
probe() { # probe EXPR OUT; EXPR @FILE is a whole probe program in $C (a word that cannot be an expression)
    case $1 in @*) cp "$C/${1#@}" "$2.om"; build "$2.om" "$2"; return ;; esac
    printf 'fn main to int\na = new uchar 8 65\nb = new uchar 64 0\nc = new uchar 128 0\nr = long %s\nret 0\nend\n' "$1" > "$2.om"
    build "$2.om" "$2"
}
probe_parity() { # probe_parity TOOL -> prints mismatches, returns count
    m=0
    "$1" table > "$B/probe/table.txt"
    while read -r w cl rest; do
        expr=$(grep "^$w|" $C/probes.txt | head -1 | cut -d'|' -f2-)
        [ -n "$expr" ] || { echo "  no probe for $w"; m=$((m + 1)); continue; }
        probe "$expr" "$B/probe/$w" || { echo "  probe $w does not compile: $(cat "$B/probe/$w.err")"; m=$((m + 1)); continue; }
        got=$("$E" elf < "$B/probe/$w" | sys_of | tr ',' '\n' | grep -v -x 93 | sort -n | tr '\n' ' ')
        exp=$(printf '%s\n' $rest | grep -v -x -- - | sort -n -u | tr '\n' ' ')
        [ "$got" = "$exp" ] || { echo "  $w table=[$exp] elf=[$got]"; m=$((m + 1)); }
    done < "$B/probe/table.txt"
    return $m
}
if probe_parity "$E"; then ok "probe parity: $(wc -l < "$B/probe/table.txt") words, table == pinned omc"
else bad "probe parity"; fi
printf 'fn main to int\nret 0\nend\n' > "$B/probe/base.om"; build "$B/probe/base.om" "$B/probe/base"
b=$("$E" elf < "$B/probe/base" | sys_of)
[ "$b" = 93 ] && ok "base program syscalls = 93" || bad "base program syscalls = $b"

# 3. Self manifest: the tool reads stdin/files and writes stdout, nothing else.
"$E" src allow=io,fd,path,env < seed/effects/effects.om > "$B/self.txt"; want "self manifest allow=io,fd,path,env" 0 $?
grep -qx 'EFFECTS 1 words=6 classes=io,fd,path,env syscalls=56,57,63,64,93' "$B/self.txt" && ok "self manifest exact" || bad "self manifest: $(tail -1 "$B/self.txt")"
"$E" verify seed/effects/effects.om "$E" > "$B/selfv.txt"; want "self verify source vs binary" 0 $?

# 4. Fixtures: manifest, policy, verify.
for f in plain clock files net; do build $C/$f.om "$B/$f" || bad "fixture $f does not compile"; done
"$E" src < $C/plain.om | grep -qx 'EFFECTS 1 words=1 classes=io syscalls=64,93' && ok "plain manifest" || bad "plain manifest"
"$E" src < $C/clock.om | grep -qx 'EFFECTS 1 words=4 classes=io,ident,time,random syscalls=64,93,113,172,278' && ok "clock manifest" || bad "clock manifest"
"$E" src allow=io,ident,time,random < $C/clock.om > /dev/null; want "clock allow=io,ident,time,random" 0 $?
"$E" src allow=io,fd,path < $C/net.om > "$B/net.txt"; want "NEGATIVE net under allow=io,fd,path" 1 $?
grep -qx 'EFFECTS REFUSED word=socknew class=net line=3' "$B/net.txt" && ok "net refusal names word, class and line" || bad "net refusal text"
"$E" src allow=io,nosuch < $C/plain.om > /dev/null; want "NEGATIVE unknown class" 2 $?
for f in plain clock files net; do "$E" verify $C/$f.om "$B/$f" > /dev/null; want "verify $f" 0 $?; done
"$E" verify $C/plain.om "$B/net" > "$B/undecl.txt"; want "NEGATIVE verify plain source vs net binary" 1 $?
grep -q '^VERIFY FAIL undeclared=57,198' "$B/undecl.txt" && ok "undeclared syscalls named (57,198)" || bad "undeclared text: $(tail -1 "$B/undecl.txt")"

# 5. Corpus: every program-mode unit in seed/host/tests and the fixtures; binary within source.
cn=0; cf=0
for s in seed/host/tests/*.om seed/rung4/tests/*.om; do
    grep -q '^fn main' "$s" || continue
    o=$B/corpus/$(echo "$s" | tr '/' '_')
    build "$s" "$o" || continue
    cn=$((cn + 1))
    "$E" verify "$s" "$o" > "$o.v" || { cf=$((cf + 1)); echo "  corpus FAIL $s: $(tail -1 "$o.v")"; }
done
[ $cn -gt 0 ] && [ $cf = 0 ] && ok "corpus verify: $cn compiled programs, binary syscalls within source manifest" || bad "corpus verify: $cf of $cn"
"$E" verify seed/omc/omc.om "$OMC" > "$B/omc.v"; want "verify omc.om vs pinned omc" 0 $?

# 6. Dynamic oracle: syscalls observed by strace (after the initial execve) within the ELF set.
dyn() { # dyn NAME BINARY [ARGS] < stdin
    n=$1; shift
    (cd "$B/run" && strace -f -n -qq -o "$B/run/$n.st" "$@" > /dev/null 2>&1)
    obs=$(sed 1d "$B/run/$n.st" | sed -n 's/^[0-9]* \[ *\([0-9]*\)\].*/\1/p' | sort -n -u | tr '\n' ' ')
    allow=$("$E" elf < "$1" | sys_of | tr ',' ' ')
    extra=""
    for x in $obs; do case " $allow " in *" $x "*) ;; *) extra="$extra $x";; esac; done
    [ -z "$extra" ] && ok "strace $n observed [$obs] within ELF" || bad "strace $n undeclared:$extra"
}
dyn plain "$B/plain"
dyn clock "$B/clock"
dyn files "$B/files"
dyn net "$B/net"
dyn self "$E" src < seed/effects/effects.om
dyn selfv "$E" verify "$ROOT/seed/effects/effects.om" "$E"

# 7. Enforcement: the manifest compiled to seccomp cBPF, loaded by bwrap before execve.
#    'launch' adds execve (221), which bwrap needs to start the program.
sec() { # sec NAME FILTER_SOURCE BINARY EXPECTED_EXIT
    "$E" bpf launch < "$2" > "$B/run/$1.bpf"
    (cd "$B/run" && bwrap --dev-bind / / --seccomp 9 "$3" > /dev/null 2>&1 9< "$B/run/$1.bpf")
    want "seccomp $1" "$4" $?
}
sec plain $C/plain.om "$B/plain" 0
sec clock $C/clock.om "$B/clock" 0
sec files $C/files.om "$B/files" 0
sec net $C/net.om "$B/net" 0
sec plain-runs-net $C/plain.om "$B/net" 159
sec plain-runs-clock $C/plain.om "$B/clock" 159
sec clock-runs-files $C/clock.om "$B/files" 159
"$E" bpf launch < seed/effects/effects.om > "$B/run/self.bpf"
bwrap --dev-bind / / --seccomp 9 "$E" src < seed/effects/effects.om 9< "$B/run/self.bpf" | tail -1 | grep -q '^EFFECTS 1 words=6 ' \
    && ok "effects runs under its own filter" || bad "effects under its own filter"
"$E" bpf < $C/plain.om > "$B/run/exact.bpf"
[ "$(wc -c < "$B/run/exact.bpf")" = 64 ] && ok "exact filter for plain = 8 instructions (64 bytes)" || bad "exact filter size $(wc -c < "$B/run/exact.bpf")"

# 8. Fail-closed ELF controls (patched copies of plain).
le32() { # LE_BYTES (octal escapes) of the 32-bit value $1
    printf '\\%03o\\%03o\\%03o\\%03o' $(($1 & 255)) $((($1 >> 8) & 255)) $((($1 >> 16) & 255)) $((($1 >> 24) & 255))
}
word_at_svc() { # index of the first SVC word in the text segment
    od -An -v -tx4 -w4 "$1" | awk '$1 == "d4000001" { print NR - 1; exit }'
}
patch() { # patch IN OUT WORDINDEX LE_BYTES(octal escapes)
    cp "$1" "$2"
    printf "$4" | dd of="$2" bs=1 seek=$(($3 * 4)) conv=notrunc 2> /dev/null
}
i=$(word_at_svc "$B/plain")
patch "$B/plain" "$B/run/nomovz" $((i - 1)) '\037\040\003\325'          # NOP replaces MOVZ X8
"$E" elf < "$B/run/nomovz" > "$B/run/nomovz.txt"; want "NEGATIVE svc without MOVZ X8" 3 $?
grep -q 'reason=prev-not-movz-x8' "$B/run/nomovz.txt" && ok "  reason prev-not-movz-x8" || bad "  reason text"
patch "$B/plain" "$B/run/movzx9" $((i - 1)) '\011\010\200\322'        # MOVZ X9,#64: right number, wrong register
"$E" elf < "$B/run/movzx9" > "$B/run/movzx9.txt"; want "NEGATIVE svc after MOVZ X9" 3 $?
grep -q 'reason=prev-not-movz-x8' "$B/run/movzx9.txt" && ok "  reason prev-not-movz-x8" || bad "  reason text"
patch "$B/plain" "$B/run/btgt" $((i - 2)) '\002\000\000\024'            # B +2 lands on the SVC
"$E" elf < "$B/run/btgt" > "$B/run/btgt.txt"; want "NEGATIVE branch into SVC" 3 $?
grep -q 'reason=branch-target' "$B/run/btgt.txt" && ok "  reason branch-target" || bad "  reason text"
patch "$B/plain" "$B/run/br" $((i - 2)) '\000\000\037\326'              # BR X0
"$E" elf < "$B/run/br" > "$B/run/br.txt"; want "NEGATIVE indirect branch" 3 $?
grep -q 'reason=indirect-branch' "$B/run/br.txt" && ok "  reason indirect-branch" || bad "  reason text"
patch "$B/plain" "$B/run/wx" 17 '\007'                                  # p_flags of phdr 0 = RWX
"$E" elf < "$B/run/wx" > "$B/run/wx.txt"; want "NEGATIVE W+X segment" 3 $?
grep -qx 'ELF REFUSED wx-segment' "$B/run/wx.txt" && ok "  reason wx-segment" || bad "  reason text"
patch "$B/plain" "$B/run/nr600" $((i - 1)) "$(le32 $((0xd2800008 | (600 << 5))))"   # MOVZ X8,#600: number out of range
"$E" elf < "$B/run/nr600" > "$B/run/nr600.txt"; want "NEGATIVE syscall number out of range" 3 $?
grep -q 'reason=nr-range' "$B/run/nr600.txt" && ok "  reason nr-range" || bad "  reason text: $(cat "$B/run/nr600.txt")"
patch "$B/plain" "$B/run/noexec" 17 '\004'                              # p_flags of phdr 0 = R
"$E" elf < "$B/run/noexec" > "$B/run/noexec.txt"; want "NEGATIVE no executable segment" 3 $?
grep -qx 'ELF REFUSED no-exec-segment' "$B/run/noexec.txt" && ok "  reason no-exec-segment" || bad "  reason text: $(cat "$B/run/noexec.txt")"
printf 'not an elf' > "$B/run/junk"
"$E" elf < "$B/run/junk" > /dev/null; want "NEGATIVE not an ELF" 3 $?

# 8b. Data is not code. Texts share the executable segment with the instructions, so a text can
# hold the bit pattern of a direct branch onto an SVC. The fixtures carry the text "QZQZ" (one
# word, 5a515a51) in three places: behind the entry branch, behind a RET and behind an exit SVC.
# That word is patched into a B onto an SVC. Control cannot reach it, so the binary must pass
# with the syscalls of the unpatched one; the mutants in section 9 prove each stop rule is needed.
word_of() { # index of the first word equal to HEX
    od -An -v -tx4 -w4 "$1" | awk -v h="$2" '$1 == h { print NR - 1; exit }'
}
bword() { # LE_BYTES of B with the signed word displacement $1
    le32 $(( 0x14000000 | ($1 & 0x3ffffff) ))
}
for f in tb-entry tb-ret tb-exit; do
    build $C/$f.om "$B/$f" || { bad "fixture $f does not compile"; continue; }
    d=$(word_of "$B/$f" 5a515a51); v=$(word_at_svc "$B/$f")
    if [ -z "$d" ] || [ -z "$v" ]; then bad "fixture $f: text word or SVC not found"; continue; fi
    patch "$B/$f" "$B/run/$f" "$d" "$(bword $((v - d)))"
    u=$("$E" elf < "$B/$f" | sys_of)
    g=$("$E" elf < "$B/run/$f" | sys_of); r=$?
    [ "$r" = 0 ] && [ -n "$u" ] && [ "$g" = "$u" ] && ok "text word that reads as B onto an SVC is data ($f: syscalls $g)" \
        || bad "$f: text word held to the branch rule (exit $r, syscalls [$g], unpatched [$u])"
done
# the same word is refused as soon as control can reach it
d=$(word_of "$B/tb-entry" 5a515a51)
e=$(( (0x$(od -An -v -tx4 -w4 -j 24 -N 4 "$B/tb-entry" | tr -d ' ') - 0x400000) / 4 ))       # entry word index
patch "$B/run/tb-entry" "$B/run/reach" "$e" "$(bword $((d - e)))"       # entry: B onto the patched text word
"$E" elf < "$B/run/reach" > "$B/run/reach.txt"; want "NEGATIVE reached text word branches into SVC" 3 $?
grep -q 'reason=branch-target' "$B/run/reach.txt" && ok "  reason branch-target" || bad "  reason text"
patch "$B/plain" "$B/run/svcnext" $((i + 1)) "$(bword -1)"              # word after the write SVC: B onto it
"$E" elf < "$B/run/svcnext" > "$B/run/svcnext.txt"; want "NEGATIVE word after a returning SVC branches into it" 3 $?
grep -q 'reason=branch-target' "$B/run/svcnext.txt" && ok "  reason branch-target" || bad "  reason text"
patch "$B/run/tb-entry" "$B/run/noentry" 6 '\000\000\000\000'             # e_entry outside the segment: every word is held
"$E" elf < "$B/run/noentry" > "$B/run/noentry.txt"; want "NEGATIVE entry outside the segment holds every word" 3 $?
grep -q 'reason=branch-target' "$B/run/noentry.txt" && ok "  reason branch-target" || bad "  reason text"
sx=$(od -An -v -tx4 -w4 "$B/plain" | awk '$1 == "d4000001" { n = NR - 1 } END { print n }')   # last SVC of plain: exit
[ "$(od -An -v -tx4 -w4 -j $(((sx - 1) * 4)) -N 4 "$B/plain" | tr -d ' ')" = d2800ba8 ] && ok "plain: last SVC is exit (MOVZ X8,#93 before it)" || bad "plain: last SVC is not exit"
patch "$B/plain" "$B/run/entrysvc" 6 "$(le32 $((0x400000 + sx * 4)))"       # e_entry = the exit SVC
[ "$(od -An -v -tx4 -w4 -j 24 -N 4 "$B/run/entrysvc" | tr -d ' ')" = "$(printf '%08x' $((0x400000 + sx * 4)))" ] && ok "entrysvc: e_entry is the exit SVC" || bad "entrysvc: e_entry not patched as meant"
"$E" elf < "$B/run/entrysvc" > "$B/run/entrysvc.txt"; want "NEGATIVE entry point on an SVC" 3 $?
grep -q 'reason=entry-svc' "$B/run/entrysvc.txt" && ok "  reason entry-svc" || bad "  reason text"
patch "$B/tb-entry" "$B/run/outbr" "$e" "$(bword 1048576)"              # entry: B far past the segment
"$E" elf < "$B/run/outbr" > "$B/run/outbr.txt"; want "NEGATIVE reached branch leaves the segment" 3 $?
grep -q 'reason=leaves-segment' "$B/run/outbr.txt" && ok "  reason leaves-segment" || bad "  reason text"
patch "$B/tb-entry" "$B/run/backbr" "$e" "$(bword $((-e - 1)))"         # entry: B to before the segment start
"$E" elf < "$B/run/backbr" > "$B/run/backbr.txt"; want "NEGATIVE reached branch to before the segment" 3 $?
grep -q 'reason=leaves-segment' "$B/run/backbr.txt" && ok "  reason leaves-segment" || bad "  reason text"
[ "$sx" = "$(( $(wc -c < "$B/plain") / 4 - 1 ))" ] && ok "plain: the exit SVC is the last word" || bad "plain: exit SVC is not the last word"
patch "$B/plain" "$B/run/falloff" "$sx" '\037\040\003\325'                 # NOP replaces the final exit SVC
"$E" elf < "$B/run/falloff" > "$B/run/falloff.txt"; want "NEGATIVE reached word falls off the end of the segment" 3 $?
grep -q 'reason=leaves-segment' "$B/run/falloff.txt" && ok "  reason leaves-segment" || bad "  reason text"
patch "$B/tb-entry" "$B/run/braaz" "$e" "$(le32 0xd61f0a1f)"             # entry: BRAAZ X16
"$E" elf < "$B/run/braaz" > "$B/run/braaz.txt"; want "NEGATIVE reached pointer-auth branch" 3 $?
grep -q 'reason=unknown-branch' "$B/run/braaz.txt" && ok "  reason unknown-branch" || bad "  reason text"
patch "$B/tb-entry" "$B/run/bccond" "$e" "$(le32 0x54000030)"            # entry: BC.EQ +1
"$E" elf < "$B/run/bccond" > "$B/run/bccond.txt"; want "NEGATIVE reached BC.cond" 3 $?
grep -q 'reason=unknown-branch' "$B/run/bccond.txt" && ok "  reason unknown-branch" || bad "  reason text"
patch "$B/tb-entry" "$B/run/databraaz" "$d" "$(le32 0xd61f0a1f)"         # the text word: same pattern, never reached
g=$("$E" elf < "$B/run/databraaz" | sys_of); r=$?
[ "$r" = 0 ] && [ "$g" = "$("$E" elf < "$B/tb-entry" | sys_of)" ] && ok "text word that reads as BRAAZ is data (syscalls $g)" || bad "text word with a BRAAZ pattern refused (exit $r)"
patch "$B/tb-entry" "$B/run/oddentry" 6 '\262\000\100\000'                # e_entry not on a word boundary
"$E" elf < "$B/run/oddentry" > "$B/run/oddentry.txt"; want "NEGATIVE entry off a word boundary" 3 $?
grep -qx 'ELF INVALID' "$B/run/oddentry.txt" && ok "  reason invalid" || bad "  reason text"

# 9. Tool mutants must be killed by the checks above.
mut() { # mut NAME SED_EXPR [CONTROL that must be among the killers]
    sed "$2" seed/effects/effects.om > "$B/mut-$1.om"
    if cmp -s seed/effects/effects.om "$B/mut-$1.om"; then bad "mutant $1 did not apply"; return; fi
    build "$B/mut-$1.om" "$B/mut-$1" || { bad "mutant $1 does not compile"; return; }
    k=""
    probe_parity "$B/mut-$1" > /dev/null || k="$k probe-parity"
    "$B/mut-$1" table | cut -d' ' -f1 | grep -v -x -e read -e write | sort | cmp -s - "$B/kw.txt" || k="$k closure"
    "$B/mut-$1" verify $C/clock.om "$B/clock" > /dev/null || k="$k verify"
    "$B/mut-$1" elf < "$B/run/movzx9" > /dev/null; [ $? = 3 ] || k="$k movzx9"
    "$B/mut-$1" elf < "$B/run/btgt" > /dev/null; [ $? = 3 ] || k="$k btgt"
    "$B/mut-$1" elf < "$B/run/noentry" > /dev/null; [ $? = 3 ] || k="$k noentry"
    "$B/mut-$1" elf < "$B/run/nr600" | grep -q 'reason=nr-range' || k="$k nr600"
    "$B/mut-$1" elf < "$B/run/noexec" | grep -qx 'ELF REFUSED no-exec-segment' || k="$k noexec"
    for f in entrysvc outbr backbr falloff braaz bccond; do
        "$B/mut-$1" elf < "$B/run/$f" > /dev/null; [ $? = 3 ] || k="$k $f"
    done
    for f in tb-entry tb-ret tb-exit; do
        "$B/mut-$1" elf < "$B/run/$f" > /dev/null; [ $? = 0 ] || k="$k $f"
    done
    if [ -z "$k" ]; then bad "mutant $1 survived"; return; fi
    case " $k " in
    *" ${3:-} "*) ok "mutant $1 killed by:$k" ;;
    *) [ -z "${3:-}" ] && ok "mutant $1 killed by:$k" || bad "mutant $1 killed by:$k but not by $3" ;;
    esac
}
mut drop-getpid 's/getpid ident 172 -\\n//'
mut wrong-random 's/random random 278 -/random random 277 -/'
mut svc-any-prev 's/^if ne and p 4292870175 3531603976$/if eq p 1/'
mut nr-msg-wrong 's/^ret unres j 27$/ret unres j 29/' nr600
mut noexec-msg-wrong 's/^say 28$/say 30/' noexec
# reach rules: every word held again (the defect), nothing held, and each stop rule removed
mut reach-all 's/^if ge ent nwd$/if ge ent 0/' tb-entry
mut reach-none 's/^sp = ulong 1$/sp = ulong 0/' btgt
mut fallback-off 's/^if eq get mk u 1$/if eq get mk u 2/' noentry
mut b-falls 's/^if eq and w 4227858432 335544320$/if eq and w 4227858432 335544321/' tb-entry
mut ret-falls 's/^if eq and w 4294966303 3596550144$/if eq and w 4294966303 3596550145/' tb-ret
mut exit-falls 's/^if or eq nr 93 eq nr 94$/if or eq nr 293 eq nr 294/' tb-exit
mut entry-svc-ok 's/^if eq get mk ent 1$/if eq get mk ent 2/' entrysvc
mut out-branch-ok 's/^if and ne t 4294967295 ge t nwd$/if and ne t 4294967295 ge t 4294967295/' outbr
mut fall-off-ok 's/^if and eq fal 1 ge nx1 nwd$/if and eq fal 2 ge nx1 nwd/' falloff
mut regbranch-ok 's/^if eq and w 4261412864 3590324224$/if eq and w 4261412864 3590324225/' braaz
mut bccond-ok 's/^if eq and w 4278190096 1409286160$/if eq and w 4278190096 1409286161/' bccond

if [ $fails = 0 ]; then echo "SEMANTIC EFFECTS PASS checks=$checks"; exit 0; fi
echo "SEMANTIC EFFECTS FAIL failed=$fails checks=$checks"; exit 1
