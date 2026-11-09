#!/bin/sh
# L775 run 298 replay. Development orchestration only: composes .om sources, feeds them to the
# given compiler on stdin, checks the ELF header and runs each program under timeout. All judged
# behaviour is in the .om programs (core.om, run.om, admit.om and their tests).
# Usage: sh replay.sh OMC OUTDIR   (from the repository root). Exit 0 only if every row matches.
set -u
OMC=$1
OUT=$2
mkdir -p "$OUT/bin"
T=$OUT/results.tsv
R=evidence/LEARNING-652/benchmark/resume-20261023
A=evidence/LEARNING-652/curriculum/L776-admission-review/source
printf 'case\twant_compile\tcompile\telf\twant_run\trun\tstdout_sha256\tbinary_sha256\n' > "$T"
fail=0

build() { # name, then source files
	n=$1; shift
	cat "$@" > "$OUT/bin/$n.om"
	"$OMC" < "$OUT/bin/$n.om" > "$OUT/bin/$n" 2> "$OUT/$n.compile.stderr"
	echo $? > "$OUT/$n.compile.exit"
}
elfok() {
	readelf -h "$1" 2>/dev/null | grep -q 'Type:.*EXEC' &&
	readelf -h "$1" | grep -q 'Machine:.*AArch64' &&
	! readelf -l "$1" 2>/dev/null | grep -q INTERP
}
row() { # name, want_compile, want_run, [stdin file]
	n=$1; wc=$2; wr=$3; c=$(cat "$OUT/$n.compile.exit"); e=-; r=-; so=-; bs=-
	if [ "$c" = 0 ]; then
		if elfok "$OUT/bin/$n"; then e=ok; else e=bad; fi
		chmod +x "$OUT/bin/$n"
		bs=$(sha256sum < "$OUT/bin/$n" | cut -c1-64)
		if [ "$wr" != - ]; then
			timeout 10 "$OUT/bin/$n" < "${4:-/dev/null}" > "$OUT/$n.stdout" 2> "$OUT/$n.stderr"
			r=$?
			so=$(sha256sum < "$OUT/$n.stdout" | cut -c1-64)
		fi
	fi
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$wc" "$c" "$e" "$wr" "$r" "$so" "$bs" >> "$T"
	if [ "$c" != "$wc" ] || [ "$r" != "$wr" ] || [ "$e" = bad ]; then echo "FAIL $n" >&2; fail=1; fi
}
case_() { n=$1; wc=$2; wr=$3; shift 3; build "$n" "$@"; row "$n" "$wc" "$wr"; }

C=src/learning/benchmark/core.om
B=tests/learning/benchmark
P=tests/learning/public
# L775 component and its compiled bypass controls
case_ core-test 0 0 $C $B/core-test.om
case_ mutant-pins 0 120 $R/mutant-pins.om $B/core-test.om
case_ mutant-scope 0 48 $R/mutant-scope.om $B/core-test.om
case_ profile-positive 0 0 $B/profile-positive.om
case_ profile-trap-overflow 0 101 $B/profile-trap-overflow.om
case_ profile-trap-div 0 102 $B/profile-trap-div.om
case_ profile-trap-bounds 0 103 $B/profile-trap-bounds.om
case_ profile-trap-loop 0 104 $B/profile-trap-loop.om
case_ profile-trap-conversion 0 105 $B/profile-trap-conversion.om
case_ profile-trap-shift 0 107 $B/profile-trap-shift.om
case_ profile-refuse-type 7 - $B/profile-refuse-type.om
case_ profile-refuse-float 3 - $B/profile-refuse-float.om
# L776 public oracle fixtures
for f in arithmetic boundary-u64 composition family-duplicates oracle observable; do case_ $f 0 0 $P/$f.om; done
case_ neg-saturating-add 0 105 $P/negative/saturating-add.om
case_ neg-observable-saturating 0 0 $P/negative/observable-saturating.om
case_ neg-u64-literal-overflow 8 - $P/negative/u64-literal-overflow.om
# L775 observation consumer over actual oracle/observable bytes
build observe-pair $C $B/observe-pair.om
cat "$OUT/oracle.stdout" "$OUT/observable.stdout" > "$OUT/good.bin"
cat "$OUT/oracle.stdout" "$OUT/neg-observable-saturating.stdout" > "$OUT/bad.bin"
: > "$OUT/empty.bin"
head -c 200 "$OUT/good.bin" > "$OUT/short.bin"
{ cat "$OUT/good.bin"; printf x; } > "$OUT/long.bin"
for k in good:0 bad:7 empty:40 short:41 long:42; do
	cp "$OUT/observe-pair.compile.exit" "$OUT/observe-${k%%:*}.compile.exit"
	cp "$OUT/bin/observe-pair" "$OUT/bin/observe-${k%%:*}"
	row observe-${k%%:*} 0 ${k#*:} "$OUT/${k%%:*}.bin"
done
# L776 admission consumer of core.om, its bypass controls and the L782 reviewer probe
case_ admit-test 0 0 $C src/learning/curriculum/admit.om tests/learning/curriculum/admit-test.om
case_ admit-provenance-bypass 0 83 $C tests/learning/curriculum/negative/provenance-bypass.om tests/learning/curriculum/admit-test.om
case_ admit-source-identity-bypass 0 93 $C tests/learning/curriculum/negative/source-identity-bypass.om tests/learning/curriculum/admit-test.om
case_ admit-reviewer-probe 0 0 $A/independent-combined.om
# Run 298: native executor over real child processes under execpure. The process words
# (argcnt, fork, execpure, waitpid, pipefds, waitio, killpid) postdate the 191b776e pin:
# with EXEC=0 that compiler must refuse them (error 3, unknown name) and nothing runs.
for f in empty spin flood c256 split stdin forge; do case_ cand-$f 0 - $B/cand/$f.om; done
if [ "${EXEC:-1}" = 0 ]; then
	case_ cand-escape 3 - $B/cand/escape.om
	case_ run-test 3 - $C src/learning/benchmark/run.om $B/run-test.om
	echo "rows $(($(wc -l < "$T") - 1)) fail $fail"
	exit $fail
fi
case_ cand-escape 0 - $B/cand/escape.om
M=evidence/LEARNING-652/benchmark/L775-run298/mutants
for src in src/learning/benchmark/run.om $M/*.om; do
	n=run-test; want=0
	case $src in $M/*) n=mut-$(basename "$src" .om)
		# exit 40+k: check k is the one observation the mutant falsifies (run-test.om order:
		# checks 1-3 oracle, 4+c candidate c = argv c+2 (c 0..13), 18/19 timeout charge bounds,
		# 20 timed-out child reaped, 21 CPU-limit spin)
		case $n in
		mut-missing-launched) want=0;;                   # equivalent: nonce still reports 6
		mut-timeout-completed|mut-no-deadline) want=47;;  # spin must be timeout 4
		mut-status-byte0) want=48;;                      # trap-div must keep code 102
		mut-no-output-cap|mut-cap-257) want=49;;         # flood must be resource 5
		mut-no-isolation) want=51;;                      # escape must be empty 9, not code 9
		mut-cap-255) want=52;;                           # exactly 256 bytes is allowed (7)
		mut-first-read-eof) want=53;;                    # two writes must assemble (0)
		mut-stdin-inherited) want=54;;                   # stdin must be the empty pipe (9)
		mut-nonce-ignored) want=55;;                     # non-executable must be operational 6
		mut-nonce-constant|mut-nonce-uncompared) want=57;; # forgery must stay completed (8)
		mut-no-kill) want=59;;                           # timeout must end before the CPU limit
		mut-kill-abandoned) want=60;;                    # timed-out child must be reaped
		mut-signal-completed) want=61;;                  # SIGXCPU must be resource 5
		*) want=unlisted;;
		esac;;
	esac
	build $n $C "$src" $B/run-test.om
	c=$(cat "$OUT/$n.compile.exit"); e=-; r=-
	if [ "$c" = 0 ]; then
		elfok "$OUT/bin/$n" && e=ok || e=bad
		chmod +x "$OUT/bin/$n"
		( cd "$OUT/bin" && timeout 30 ./$n ./oracle ./observable ./neg-observable-saturating \
			./cand-empty ./cand-spin ./profile-trap-div ./cand-flood ./no-such-candidate ./cand-escape \
			./cand-c256 ./cand-split ./cand-stdin ./cand-empty.om . ./cand-forge < ../good.bin \
			> ../$n.stdout 2> ../$n.stderr; echo $? > ../$n.run.exit )
		r=$(cat "$OUT/$n.run.exit")
	fi
	printf '%s\t0\t%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$c" "$e" "$want" "$r" \
		"$(sha256sum < "$OUT/$n.stdout" 2>/dev/null | cut -c1-64)" \
		"$(sha256sum < "$OUT/bin/$n" 2>/dev/null | cut -c1-64)" >> "$T"
	ok=1
	[ "$c" = 0 ] && [ "$e" = ok ] || ok=0
	[ "$r" = "$want" ] || ok=0
	[ $ok = 1 ] || { echo "FAIL $n" >&2; fail=1; }
done
echo "rows $(($(wc -l < "$T") - 1)) fail $fail"
exit $fail
