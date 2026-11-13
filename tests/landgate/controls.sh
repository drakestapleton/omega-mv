#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# tests/landgate/controls.sh: TEST INSTRUMENT. Judge controls for the landing campaign (BRIEF items 24-25): for each
# acceptance predicate below, a positive twin with the same setup, an incomplete-input or setup-failure case, and a
# predicate-removal case that shows the predicate is what decides. Every row states its expected exit and required
# text; any other outcome is a FAIL row. Scratch trees are private clones of HEAD; the checkout itself is not written.
# usage: tests/landgate/controls.sh BASE OUT     (OUT must not exist)
# Judge inventory (every acceptance predicate of the landing campaign; each has a twin, refusals and a predicate-removal
# row; the readiness, receipt and bundle judges are in tests/landgate/instruments.sh, same rules):
# (A) tests/landgate/samebytes.sh: identical / byte / status / stderr differences, abnormal exit, missing commit, empty
#     selection, missing executable; failure injected into its own listing (git ls-tree) and source read (git show).
# (C), run before (B), the historical-control correction program in gate-pools.sh keeps refusing a wrong pin under
#     python3 -O; with its refusal removed a wrong pin passes.
# (E) the record judge tests/landgate/rec.sh (rec, verdict) that run.sh aggregates every row with.
# (F) tests/landgate/merge-residue.sh: residue fails; a failing listing, a failing git grep and a git grep that reads
#     nothing are SCAN FAILED, never "no residue". (G) tests/landgate/pin-grep.sh: a typed live pin fails; a failing
#     scan is SCAN FAILED. (H) seed/host/matrix-check.py (where present): a missing cell fails.
# (B) seed/omc/gate-pools.sh section 11: skip, zero, partial, malformed limit and empty corpus are NOT_RUN or FAIL,
#     never PASS; a custom CTRL is NOT_RUN 11 while S and M still run, and a later S or M failure makes the whole gate
#     FAIL; the partial, NOT_RUN-aggregation and M predicates removed in scratch copies.
# (D) seed/host/check.sh (where the host modules exist): a module that is NOT_RUN makes the host gate NOT_RUN 3, and a
#     module that fails makes it fail, never PASS; with the NOT_RUN branch removed, or the failure exit removed, the
#     same stand-ins give PASS or NOT_RUN (scratch copies), which shows those lines decide.
# Exit 0 ("LANDGATE-CONTROLS PASS rows=N"), 1 any row wrong, 2 usage/setup.
set -u
BASE=${1:?usage: controls.sh BASE OUT}; OUT=${2:?usage: controls.sh BASE OUT}
F=$(git rev-parse --show-toplevel) || exit 2; cd "$F" || exit 2
[ ! -e "$OUT" ] || { echo "controls: refusing to reuse $OUT"; exit 2; }
mkdir -p "$OUT" && O=$(cd "$OUT" && pwd) || exit 2
H=$(git rev-parse HEAD); rows=0; bad=0
row() { # NAME WANT_EXIT WANT_TEXT CMD...   (runs CMD, judges exit and text)
  n=$1; want=$2; text=$3; shift 3; rows=$((rows + 1))
  printf '%q ' "$@" > "$O/$n.command"; rc=0; "$@" > "$O/$n.log" 2>&1 || rc=$?
  if [ "$rc" = "$want" ] && grep -qF -- "$text" "$O/$n.log"; then echo "PASS $n: exit $rc, [$text]"
  else echo "FAIL $n: exit $rc (want $want with [$text])"; tail -n 4 "$O/$n.log" | sed 's/^/  | /'; bad=$((bad + 1)); fi
}
scratch() { # DIR: a private clone of HEAD with the build oracles of this checkout
  git clone -q --no-local "$F" "$1" && git -C "$1" checkout -q --detach "$H" &&
  git -C "$1" fetch -q "$F" "$BASE" 2> /dev/null; git -C "$1" update-ref refs/remotes/origin/main "$BASE"
}
mutate() { # SRC DST SED-EXPR LINES: a scratch copy in which exactly LINES lines are removed or changed
  sed "$3" "$1" > "$2"; [ "$(diff "$1" "$2" | grep -c '^<')" = "$4" ] || { echo "controls: mutation of $1 did not change exactly $4 line(s): $3"; exit 2; }
}
RG=$(command -v git) || exit 2
standin() { # DIR SUBCOMMAND FLAG EXIT: a git that exits EXIT, printing nothing on stdout, when its arguments hold
  # SUBCOMMAND and FLAG ("-" matches any); every other git call goes to the real git
  mkdir -p "$1"; printf '#!/bin/sh
sub=; flag=; for a; do [ "$a" = %s ] && sub=1; [ "%s" = - ] || [ "$a" = %s ] && flag=1; done
if [ -n "$sub" ] && [ -n "$flag" ]; then echo "git stand-in: %s %s exits %s" >&2; exit %s; fi
exec %s "$@"
' \
    "$2" "$3" "$3" "$2" "$3" "$4" "$4" "$RG" > "$1/git"; chmod 755 "$1/git"
}
echo "controls head $H base $BASE utc $(date -u +%FT%TZ)"

# (A) samebytes
A=$O/A; mkdir -p "$A/repo"; git -C "$A/repo" init -q; printf 'fn main to int\nret 1\nend\n' > "$A/repo/a.om"; printf 'fn main to int\nret 2\nend\n' > "$A/repo/b.om"
git -C "$A/repo" add a.om b.om; git -C "$A/repo" -c user.name=t -c user.email=t@t commit -q -m corpus
fake() { # FILE BODY: a stand-in compiler (reads stdin, writes stdout/stderr, exits)
  printf '#!/bin/sh\ncat > /dev/null\n%s\n' "$2" > "$1"; chmod 755 "$1"; }
fake "$A/same" 'printf ELF; exit 0'; fake "$A/same2" 'printf ELF; exit 0'
fake "$A/bytes" 'printf ELX; exit 0'; fake "$A/status" 'printf ELF; exit 7'; fake "$A/stderr" 'printf ELF; echo note >&2; exit 0'
fake "$A/abnormal" 'exit 137'
row samebytes-twin 0 "SAMEBYTES same=2 differ=0 checker_errors=0" bash tests/landgate/samebytes.sh "$A/same" "$A/same2" "$A/o1" "$A/repo@HEAD"
row samebytes-bytes 1 "differ=2" bash tests/landgate/samebytes.sh "$A/same" "$A/bytes" "$A/o2" "$A/repo@HEAD"
row samebytes-status 1 "differ=2" bash tests/landgate/samebytes.sh "$A/same" "$A/status" "$A/o3" "$A/repo@HEAD"
row samebytes-stderr 1 "differ=2" bash tests/landgate/samebytes.sh "$A/same" "$A/stderr" "$A/o4" "$A/repo@HEAD"
row samebytes-abnormal 1 "abnormal compiler exit" bash tests/landgate/samebytes.sh "$A/same" "$A/abnormal" "$A/o5" "$A/repo@HEAD"
row samebytes-missing-commit 1 "missing commit" bash tests/landgate/samebytes.sh "$A/same" "$A/same2" "$A/o6" "$A/repo@0000000000000000000000000000000000000000"
row samebytes-empty-selection 1 "SAMEBYTES same=0 differ=0" env SAMEBYTES_ONLY='^nomatch$' bash tests/landgate/samebytes.sh "$A/same" "$A/same2" "$A/o7" "$A/repo@HEAD"
row samebytes-missing-executable 1 "SAMEBYTES FAIL missing executable" bash tests/landgate/samebytes.sh "$A/same" "$A/nonexistent" "$A/o8" "$A/repo@HEAD"
# predicate removal: the final verdict line removed, a byte difference passes (shows that line decides)
sed '$d' tests/landgate/samebytes.sh > "$A/samebytes-nopredicate.sh"
row samebytes-predicate-removed 0 "differ=2" bash "$A/samebytes-nopredicate.sh" "$A/same" "$A/bytes" "$A/o9" "$A/repo@HEAD"
# failure injected into the comparator's own operations: its listing (git ls-tree) and its source read (git show)
standin "$A/git-ls-tree" ls-tree - 128; standin "$A/git-show" show - 128
row samebytes-listing-fails 1 "SAMEBYTES CHECKER ERROR ls-tree" env PATH="$A/git-ls-tree:$PATH" bash tests/landgate/samebytes.sh "$A/same" "$A/same2" "$A/o10" "$A/repo@HEAD"
row samebytes-source-read-fails 1 "SAMEBYTES CHECKER ERROR source unavailable" env PATH="$A/git-show:$PATH" bash tests/landgate/samebytes.sh "$A/same" "$A/same2" "$A/o11" "$A/repo@HEAD"

# (C) historical-control correction program under python3 -O
awk '/<<.PYBOOL.$/{on=1;next} /^PYBOOL$/{on=0} on' seed/omc/gate-pools.sh > "$O/pybool.py"
git cat-file blob f615b139:seed/out/omc > "$O/ctrl-raw"; chmod 755 "$O/ctrl-raw"; git cat-file blob f615b139:seed/omc/omc.om > "$O/ctrl-src.om"
PB=1e628c80d5bd2ad0b08eb46d8abff66eff284a74e5a302e589c2d61cfe9f7347; PF=a0db6165a56811f1315cb445b037568a13bd40d82a155636a53550d123db8748
row pybool-twin 0 "PASS historical control bool correction" python3 "$O/pybool.py" "$O/ctrl-raw" "$O/ctrl-src.om" "$O/ctrl-ok" "$PB" "$PF"
row pybool-twin-O 0 "PASS historical control bool correction" python3 -O "$O/pybool.py" "$O/ctrl-raw" "$O/ctrl-src.om" "$O/ctrl-ok-O" "$PB" "$PF"
row pybool-wrong-base-pin-O 1 "historical control: raw compiler sha256" python3 -O "$O/pybool.py" "$O/ctrl-raw" "$O/ctrl-src.om" "$O/ctrl-bad1" "$(printf '%064d' 0)" "$PF"
row pybool-wrong-fixed-pin-O 1 "historical control: corrected image sha256" python3 -O "$O/pybool.py" "$O/ctrl-raw" "$O/ctrl-src.om" "$O/ctrl-bad2" "$PB" "$(printf '%064d' 0)"
printf 'x' >> "$O/ctrl-src.om"
row pybool-wrong-source-O 1 "historical control: source sha256" python3 -O "$O/pybool.py" "$O/ctrl-raw" "$O/ctrl-src.om" "$O/ctrl-bad3" "$PB" "$PF"
# predicate removal: with its refusal line removed, the program accepts a wrong raw-compiler pin
mutate "$O/pybool.py" "$O/pybool-nopredicate.py" "s/^        sys.exit('historical control: ' + what)$/        pass/" 1
git cat-file blob f615b139:seed/omc/omc.om > "$O/ctrl-src2.om"
row pybool-predicate-removed 0 "PASS historical control bool correction" python3 "$O/pybool-nopredicate.py" "$O/ctrl-raw" "$O/ctrl-src2.om" "$O/ctrl-np" "$(printf '%064d' 0)" "$PF"

# (E) the record judge: rec and verdict of tests/landgate/rec.sh, as run.sh sources them, in private log directories
E=$O/E; mkdir -p "$E"
recjudge() { # LIB DIR WANT_TEXT EXPECTED CMD...: one record of CMD, then the verdict
  local lib=$1 d=$E/$2 wt=$3 want=$4; shift 4; mkdir -p "$d"
  (L=$d; S=$d/SUMMARY.log; failed=0; echo "head fixture" > "$S"; . "$lib" || exit 2; WANT_TEXT=$wt rec step "$want" "$@"; verdict; cat "$S"; [ "$failed" = 0 ])
}
row record-twin 0 "LANDGATE PASS rc=0" recjudge "$F/tests/landgate/rec.sh" twin "" 0 true
row record-control-twin 0 "control_exit=3 expected_exit=3" recjudge "$F/tests/landgate/rec.sh" ctl "" 3 sh -c 'exit 3'
row record-exit-differs 1 "LANDGATE FAIL" recjudge "$F/tests/landgate/rec.sh" exit "" 0 false
row record-text-missing 1 "text=MISSING" recjudge "$F/tests/landgate/rec.sh" text never-printed 0 true
mutate "$F/tests/landgate/rec.sh" "$E/rec-nopredicate.sh" '/# record predicate$/d' 1
row record-predicate-removed 0 "LANDGATE PASS rc=0" recjudge "$E/rec-nopredicate.sh" nop "" 0 false

# (F) merge residue and (G) the pin grep, in a private clone (residue and a typed pin are committed there only)
Z=$O/mr.scratch; scratch "$Z" || { echo "controls: scratch clone failed"; exit 2; }
inz() { (cd "$Z" && exec "$@"); }
standin "$O/git-grep-E" grep -E 128; standin "$O/git-ls-files" ls-files - 128; standin "$O/git-grep-nothing" grep - 1; standin "$O/git-grep-e" grep -e 128
row merge-residue-twin 0 "MERGE-RESIDUE PASS" inz bash tests/landgate/merge-residue.sh
row merge-residue-scan-fails 1 "MERGE-RESIDUE SCAN FAILED: git grep exit 128" inz env PATH="$O/git-grep-E:$PATH" bash tests/landgate/merge-residue.sh
row merge-residue-listing-fails 1 "MERGE-RESIDUE SCAN FAILED: tracked-file listing exit 128" inz env PATH="$O/git-ls-files:$PATH" bash tests/landgate/merge-residue.sh
row merge-residue-grep-reads-nothing 1 "MERGE-RESIDUE SCAN FAILED: probe" inz env PATH="$O/git-grep-nothing:$PATH" bash tests/landgate/merge-residue.sh
mutate tests/landgate/merge-residue.sh "$O/merge-residue-nopredicate.sh" '/# scan-exit predicate$/d' 2
row merge-residue-predicate-removed 0 "MERGE-RESIDUE PASS" inz env PATH="$O/git-grep-E:$PATH" bash "$O/merge-residue-nopredicate.sh"
row pin-grep-twin 0 "PINGREP PASS" inz bash tests/landgate/pin-grep.sh "$BASE"
row pin-grep-scan-fails 1 "PINGREP SCAN FAILED: git grep exit 128" inz env PATH="$O/git-grep-e:$PATH" bash tests/landgate/pin-grep.sh "$BASE"
mutate tests/landgate/pin-grep.sh "$O/pin-grep-noscan.sh" '/# scan predicate$/d' 2
row pin-grep-scan-predicate-removed 0 "PINGREP PASS hits=0" inz env PATH="$O/git-grep-e:$PATH" bash "$O/pin-grep-noscan.sh" "$BASE"
printf '#!/bin/sh
# a typed live pin
PIN=%s
' "$(cut -d' ' -f1 seed/out/omc.sha256)" > "$Z/tests/landgate/planted-pin.sh"
git -C "$Z" add tests/landgate/planted-pin.sh && git -C "$Z" -c user.name=controls -c user.email=controls@localhost commit -q -m "controls: typed pin"
row pin-grep-typed-live-pin 1 "class=TYPED LIVE PIN" inz bash tests/landgate/pin-grep.sh "$BASE"
mutate tests/landgate/pin-grep.sh "$O/pin-grep-noclass.sh" 's/^\[ "\$fails" = 0 \] && { echo "PINGREP PASS hits=\$n"; exit 0; }  # class predicate$/{ echo "PINGREP PASS hits=$n"; exit 0; }/' 1
row pin-grep-class-predicate-removed 0 "PINGREP PASS" inz bash "$O/pin-grep-noclass.sh" "$BASE"
printf 'kept\n<<<<<<< ours\nmine\n' > "$Z/residue.txt"
git -C "$Z" add residue.txt && git -C "$Z" -c user.name=controls -c user.email=controls@localhost commit -q -m "controls: residue"
row merge-residue-planted 1 "MERGE-RESIDUE FAIL lines=1" inz bash tests/landgate/merge-residue.sh

# (H) the effect matrix reference checker
if [ -f seed/host/matrix-check.py ]; then
  row matrix-twin 0 "MATRIX-CHECK PASS" python3 seed/host/matrix-check.py seed/host/EFFECT-MATRIX.md "$BASE"
  awk '/^- P: / && !d { d = 1; next } { print }' seed/host/EFFECT-MATRIX.md > "$O/matrix-missing-cell.md"
  row matrix-missing-cell 1 "missing cells ['P']" python3 seed/host/matrix-check.py "$O/matrix-missing-cell.md" "$BASE"
  mutate seed/host/matrix-check.py "$O/matrix-check-nopredicate.py" 's/^            if cells\[row\] != CELLS:$/            if False:/' 1
  row matrix-predicate-removed 0 "MATRIX-CHECK PASS" python3 "$O/matrix-check-nopredicate.py" "$O/matrix-missing-cell.md" "$BASE"
else
  echo "NOT_APPLICABLE matrix-check: seed/host/matrix-check.py is not in this head"
fi

# (B) gate-pools section 11 and S
P=$O/pools; scratch "$P/tree" || { echo "controls: scratch clone failed"; exit 2; }
# a custom CTRL: the corrected historical control image (made by pybool-twin above) plus one trailing byte, so it is
# still a no-pools compiler but not the pinned BASEFIX image
[ -f "$O/ctrl-ok" ] || { echo "controls: corrected control image missing (pybool-twin)"; exit 2; }
cp "$O/ctrl-ok" "$P/custom-ctrl"; printf '\n' >> "$P/custom-ctrl"; chmod 755 "$P/custom-ctrl"
pools() { (cd "$P/tree" && exec env "$@" sh seed/omc/gate-pools.sh seed/out/omc); }
row pools-skip 3 "NOT_RUN 11: comparison skipped (POOLS_SKIP_EQUIV=1" pools POOLS_ONLY=11 POOLS_SKIP_EQUIV=1
row pools-zero 3 "NOT_RUN 11: comparison skipped (POOLS_SKIP_EQUIV=0, POOLS_EQUIV_MAX=0)" pools POOLS_ONLY=11 POOLS_EQUIV_MAX=0
row pools-partial 3 "NOT_RUN 11: partial compiler-outcome comparison: 3 of" pools POOLS_ONLY=11 POOLS_EQUIV_MAX=3
row pools-limit-malformed 1 "POOLS_EQUIV_MAX must be a nonnegative integer" pools POOLS_ONLY=11 POOLS_EQUIV_MAX=x
row pools-custom-ctrl-S-continues 3 "PASS S server" pools POOLS_ONLY="11 S" CTRL="$P/custom-ctrl"
grep -qF "NOT_RUN 11: custom CTRL has no pinned source mapping" "$O/pools-custom-ctrl-S-continues.log" || { echo "FAIL pools-custom-ctrl-S-continues: no NOT_RUN 11 custom CTRL line"; bad=$((bad + 1)); }
# predicate removal for the partial rule: without the notrun11 assignment a partial run would pass
sed 's/^        notrun11="partial compiler-outcome comparison: \$n11 of \$total11 units"$/        :/' "$P/tree/seed/omc/gate-pools.sh" > "$P/gate-pools-nopartial.sh"
if cmp -s "$P/gate-pools-nopartial.sh" "$P/tree/seed/omc/gate-pools.sh"; then echo "FAIL pools-partial-predicate-removed: removal did not apply"; bad=$((bad + 1)); rows=$((rows + 1))
else cp "$P/gate-pools-nopartial.sh" "$P/tree/seed/omc/gate-pools-nopartial.sh"; row pools-partial-predicate-removed 0 "PASS gate-pools (sections 0 11 only)" bash -c 'cd "$1" && POOLS_ONLY=11 POOLS_EQUIV_MAX=3 exec sh seed/omc/gate-pools-nopartial.sh seed/out/omc' sh "$P/tree"; rm -f "$P/tree/seed/omc/gate-pools-nopartial.sh"; fi
# a later failure dominates NOT_RUN: S fails because its tracer (strace, run only by section S here) is a stand-in
# that exits 1 (srv.want itself is regenerated and checked by section 0, so it cannot be the failing input)
mkdir -p "$P/stub"; printf '#!/bin/sh\necho "strace stand-in: fails"\nexit 1\n' > "$P/stub/strace"; chmod 755 "$P/stub/strace"
row pools-custom-ctrl-S-fails 1 "FAIL: S: srv exit" pools PATH="$P/stub:$PATH" POOLS_ONLY="11 S" CTRL="$P/custom-ctrl"
# M continues too: under the custom CTRL section 11 is NOT_RUN while section M builds and catches every mutant (exit 3)
MT=$P/tree/seed/omc/tests/pools/mutants.tsv
row pools-custom-ctrl-M-continues 3 "PASS mutant" pools POOLS_ONLY="11 M" CTRL="$P/custom-ctrl"
k=$(grep -c '^PASS mutant ' "$O/pools-custom-ctrl-M-continues.log"); nm=$(awk -F'\t' '$1 != ""' "$MT" | wc -l)
grep -qF "NOT_RUN 11: custom CTRL has no pinned source mapping" "$O/pools-custom-ctrl-M-continues.log" && [ "$k" = "$nm" ] ||
  { echo "FAIL pools-custom-ctrl-M-continues: NOT_RUN 11 line missing or $k of $nm mutants caught"; bad=$((bad + 1)); }
# a later M failure dominates NOT_RUN: one mutant row whose case cannot catch it (g4base, which every built mutant must
# compile correctly) survives, so section M and the whole gate FAIL
printf 'survivor\tg4base\tcmpdrop\n' > "$MT"
row pools-custom-ctrl-M-fails 1 "FAIL: 1 mutants not built or not caught" pools POOLS_ONLY="11 M" CTRL="$P/custom-ctrl"
grep -qF "FAIL mutant survivor (cmpdrop): g4base passed" "$O/pools-custom-ctrl-M-fails.log" || { echo "FAIL pools-custom-ctrl-M-fails: the survivor line is missing"; bad=$((bad + 1)); }
# predicate removal for M: without its failure line the surviving mutant passes the gate
mutate "$P/tree/seed/omc/gate-pools.sh" "$P/gate-pools-nomut.sh" 's/^  \[ \$fails = 0 \] || bad "\$fails mutants not built or not caught"$/  :/' 1
cp "$P/gate-pools-nomut.sh" "$P/tree/seed/omc/gate-pools-nomut.sh"
row pools-M-predicate-removed 0 "PASS gate-pools (sections 0 M only)" bash -c 'cd "$1" && POOLS_ONLY=M exec sh seed/omc/gate-pools-nomut.sh seed/out/omc' sh "$P/tree"
rm -f "$P/tree/seed/omc/gate-pools-nomut.sh"; git -C "$P/tree" checkout -q -- seed/omc/tests/pools/mutants.tsv
# predicate removal for the NOT_RUN aggregation: without the final notrun11 exit the custom CTRL run passes
mutate "$P/tree/seed/omc/gate-pools.sh" "$P/gate-pools-nonotrun.sh" '/^if \[ -n "\$notrun11" \]; then$/,/^fi$/d' 5
cp "$P/gate-pools-nonotrun.sh" "$P/tree/seed/omc/gate-pools-nonotrun.sh"
row pools-notrun-predicate-removed 0 "PASS gate-pools (sections 0 11 only)" bash -c 'cd "$1" && POOLS_ONLY=11 CTRL="$2" exec sh seed/omc/gate-pools-nonotrun.sh seed/out/omc' sh "$P/tree" "$P/custom-ctrl"
rm -f "$P/tree/seed/omc/gate-pools-nonotrun.sh"
[ -z "$(git -C "$P/tree" status --porcelain)" ] || { echo "controls: pools scratch tree not clean after the M rows"; exit 2; }
# empty corpus: every tracked unit outside the pool fixtures untracked in the scratch tree (files stay on disk)
git -C "$P/tree" ls-files '*.om' | grep -v '^seed/omc/tests/pools/' | (cd "$P/tree" && xargs git rm -q --cached --)
git -C "$P/tree" -c user.name=controls -c user.email=controls@localhost commit -q -m "controls: untrack the corpus"
row pools-empty-corpus 1 "11 comparison: empty corpus/exact set" pools POOLS_ONLY=11

# (D) host-gate aggregation of module NOT_RUN and failure
if [ -f seed/host/container/check.sh ] && [ -f seed/host/execfds/check.sh ]; then
  for c in notrun fail notrun-nobranch fail-nopropagate; do
    D=$O/host-$c; scratch "$D" || { echo "controls: scratch clone failed"; exit 2; }
    mkdir -p "$D/build"; for o in omegese omega_emit checker2; do cp -r "$F/build/$o" "$D/build/"; done
    # The stand-in changes only the host gate's own call (argument seed/out/omc). Section 11 of the pool gate, which
    # the host gate runs first, executes the same file as a declared owner with its recording compiler as the
    # argument; that call goes to the real module, so the control reaches the aggregation it is about.
    case $c in notrun*) m=container; say='container module stand-in: NOT_RUN'; st=3 ;; *) m=execfds; say='execfds module stand-in: FAIL'; st=1 ;; esac
    case $c in
      notrun-nobranch) mutate "$D/seed/host/check.sh" "$D/check.tmp" '/^if \[ -n "\$host_notrun" \]; then$/,/^fi$/d' 4; mv "$D/check.tmp" "$D/seed/host/check.sh" ;;
      fail-nopropagate) mutate "$D/seed/host/check.sh" "$D/check.tmp" 's/^\(sh seed\/host\/execfds\/check.sh seed\/out\/omc || { r=\$?; \)\[ \$r = 3 \] || exit \$r; /\1/' 1; mv "$D/check.tmp" "$D/seed/host/check.sh" ;;
    esac
    mv "$D/seed/host/$m/check.sh" "$D/seed/host/$m/check-real.sh"
    printf '#!/bin/sh\nif [ "${1:-}" = seed/out/omc ]; then echo "%s"; exit %s; fi\nexec sh "$(dirname "$0")/check-real.sh" "$@"\n' "$say" "$st" > "$D/seed/host/$m/check.sh"
    git -C "$D" add -A && git -C "$D" -c user.name=controls -c user.email=controls@localhost commit -q -m "controls: module stand-in ($c)"
    [ -z "$(git -C "$D" status --porcelain)" ] || { echo "controls: stand-in tree not clean"; exit 2; }
  done
  # One host gate at a time: the host gate holds timed steps (the memory-ceiling sweep kills a compile after 30 s), and
  # running these trees side by side on the campaign's single core made one of them time out before the aggregation
  # under test (logs/final10-08d17b9a8c1b, kept). Sequential runs reach the aggregation in every tree.
  row host-module-notrun 3 "NOT_RUN native-host qualification: did not run: container" bash -c 'cd "$1" && exec sh seed/host/check.sh' sh "$O/host-notrun"
  row host-module-fail 1 "execfds module stand-in: FAIL" bash -c 'cd "$1" && exec sh seed/host/check.sh' sh "$O/host-fail"
  row host-notrun-predicate-removed 0 "PASS native-host qualification" bash -c 'cd "$1" && exec sh seed/host/check.sh' sh "$O/host-notrun-nobranch"
  row host-fail-predicate-removed 3 "NOT_RUN native-host qualification: did not run: execfds(strace missing)" bash -c 'cd "$1" && exec sh seed/host/check.sh' sh "$O/host-fail-nopropagate"
  ! grep -q 'PASS native-host qualification' "$O/host-module-notrun.log" "$O/host-module-fail.log" || { echo "FAIL host stand-ins: a host run printed the PASS line"; bad=$((bad + 1)); }
else
  echo "NOT_APPLICABLE host-module aggregation: seed/host/container or seed/host/execfds is not in this head"
fi

if [ "$bad" = 0 ]; then echo "LANDGATE-CONTROLS PASS rows=$rows"; exit 0; fi
echo "LANDGATE-CONTROLS FAIL failed=$bad rows=$rows"; exit 1
