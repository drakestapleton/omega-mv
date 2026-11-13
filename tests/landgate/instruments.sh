#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# tests/landgate/instruments.sh: TEST INSTRUMENT. Controls for the three record judges of a landing:
# tests/landgate/readiness.py, tests/landgate/receipts.py and tests/landgate/bundle.py. Everything runs on a private
# fixture built here (a two-commit repository with a base and a head, a one-commit omega-bridge stand-in, a gate log
# directory with its summary, contract, RCCA, action record, rounds, author and limits files, and an external root
# holding cited records); the checkout is not written. Each judge gets a positive twin, the refusals it must make (each
# made by changing one input of the real instrument run, or by making one operation of it fail), and a
# predicate-removal case: a scratch copy of the instrument with its deciding line removed accepts the same bad input,
# which shows that line is what refuses. Every row states its expected exit and required text.
# usage: tests/landgate/instruments.sh OUT     (OUT must not exist)
# Exit 0 ("LANDGATE-INSTRUMENTS PASS rows=N"), 1 any row wrong, 2 usage/setup.
set -u
OUT=${1:?usage: instruments.sh OUT}
F=$(git rev-parse --show-toplevel) || exit 2; I=$F/tests/landgate
[ ! -e "$OUT" ] || { echo "instruments: refusing to reuse $OUT"; exit 2; }
mkdir -p "$OUT" && O=$(cd "$OUT" && pwd) || exit 2
rows=0; bad=0; RG=$(command -v git) || exit 2
row() { # NAME WANT_EXIT WANT_TEXT CMD...
  n=$1; want=$2; text=$3; shift 3; rows=$((rows + 1))
  printf '%q ' "$@" > "$O/$n.command"; rc=0; "$@" > "$O/$n.log" 2>&1 || rc=$?
  if [ "$rc" = "$want" ] && grep -qF -- "$text" "$O/$n.log"; then echo "PASS $n: exit $rc, [$text]"
  else echo "FAIL $n: exit $rc (want $want with [$text])"; tail -n 4 "$O/$n.log" | sed 's/^/  | /'; bad=$((bad + 1)); fi
}
setup_fail() { echo "instruments: setup: $*"; exit 2; }
echo "instruments head $(git rev-parse HEAD) utc $(date -u +%FT%TZ)"
for f in readiness.py receipts.py bundle.py; do echo "instrument tests/landgate/$f sha256 $(sha256sum < "$I/$f" | cut -c1-64)"; done

# ---- fixture
X=$O/fx.scratch; LANE=$X/lane; EXT=$X/ext; mkdir -p "$LANE/logs" "$EXT" "$X/outside" "$X/mut" || exit 2
G() { "$RG" -c user.name=fixture -c user.email=fixture@localhost "$@"; }
G init -q -b main "$X/bridge" && echo bridge > "$X/bridge/f" && G -C "$X/bridge" add f && G -C "$X/bridge" commit -q -m bridge || setup_fail bridge
LOCK=$("$RG" -C "$X/bridge" rev-parse HEAD)
R=$X/repo; G init -q -b main "$R" || setup_fail repo
mkdir -p "$R/seed/out" "$R/om"; printf 'base-omc\n' > "$R/seed/out/omc"
(cd "$R" && sha256sum seed/out/omc > seed/out/omc.sha256); printf '# omega-bridge commit\n%s\n' "$LOCK" > "$R/om/omega-bridge.lock"
G -C "$R" add -A && G -C "$R" commit -q -m base || setup_fail base; BASE=$("$RG" -C "$R" rev-parse HEAD)
G -C "$R" checkout -q -b land/fx; printf 'head-omc\n' > "$R/seed/out/omc"; (cd "$R" && sha256sum seed/out/omc > seed/out/omc.sha256); echo note > "$R/notes.txt"
G -C "$R" add -A && G -C "$R" commit -q -m head || setup_fail head; HEAD=$("$RG" -C "$R" rev-parse HEAD)
G -C "$R" checkout -q -b land/rx; printf 'a\n<<<<<<< ours\nb\n' > "$R/residue.txt"
G -C "$R" add -A && G -C "$R" commit -q -m residue || setup_fail residue; RX=$("$RG" -C "$R" rev-parse HEAD)
G -C "$R" checkout -q land/fx
"$RG" clone -q --bare --single-branch -b main "$R" "$X/base.git" || setup_fail base.git
"$RG" init -q --bare "$X/empty.git" || setup_fail empty.git
printf 'model records of the fixture authors\n' > "$EXT/model-records.txt"
printf '# verdict fx\nmodel records %s sha256 %s\n' "$EXT/model-records.txt" "$(sha256sum < "$EXT/model-records.txt" | cut -c1-64)" > "$EXT/verdict.md"
printf '# verdict citing a missing record\nsee %s\n' "$EXT/gone.txt" > "$EXT/verdict-missing-cite.md"
printf '# RCCA fx\n\n**H1 — receipts.**\n\n**R1 — accepted debt.**\n' > "$EXT/rcca.md"
printf '# RCCA other\n\n**H1 — x.**\n' > "$EXT/rcca-other.md"
printf 'Required gate rows (fx): step-a ctl-b! big opt?\n' > "$LANE/contract.md"
printf '| Action | Owner | Path | Evidence | State | Disposition |\n|---|---|---|---|---|---|\n| H1 receipts | o | p | e | EXERCISED | OPEN |\n| R1 debt | o | p | e | OPEN-ACCEPTED decision-1 | OPEN |\n' > "$LANE/actions.md"
sed 's/| EXERCISED |/| OPEN (not installed) |/' "$LANE/actions.md" > "$LANE/actions-open.md"
printf '# ledger fx\n' > "$LANE/ledger.md"; printf 'fx: one round\n' > "$LANE/rounds.md"
printf 'fx: one round\nNo RCCA file exists for fx.\n' > "$LANE/rounds-stale.md"
printf 'fx: one round\nNo RCCA file exists for fx.\nSUPERSEDED: an RCCA exists now (%s).\n' "$EXT/rcca.md" > "$LANE/rounds-superseded.md"
printf 'author records %s sha256 %s\n' "$EXT/model-records.txt" "$(sha256sum < "$EXT/model-records.txt" | cut -c1-64)" > "$LANE/authors.md"
printf -- '- fixture limit\n' > "$LANE/limits.md"; printf 'outside\n' > "$X/outside/x.log"
logdir() { # NAME [HEAD]: a gate log directory under the lane root with its summary
  d=$LANE/logs/$1; h=${2:-$HEAD}; mkdir -p "$d" || exit 2
  printf 'step a ok\n' > "$d/step-a.log"; printf 'expected refusal\nTEXT-B\n' > "$d/ctl-b.log"
  head -c 8192 /dev/zero | tr '\0' 'b' > "$d/big.log"; head -c 8192 /dev/zero | tr '\0' 's' > "$d/scratch-big.bin"
  s() { sha256sum < "$d/$1" | cut -c1-64; }
  { echo "head $h parent $BASE base $BASE utc 2026-01-01T00:00:00Z instrument fixture"
    echo "step-a rc=0 log=$d/step-a.log sha256=$(s step-a.log) start=2026-01-01T00:00:00Z"
    echo "ctl-b control_exit=1 expected_exit=1 log=$d/ctl-b.log sha256=$(s ctl-b.log) start=2026-01-01T00:00:00Z text=found"
    echo "big rc=0 log=$d/big.log sha256=$(s big.log) start=2026-01-01T00:00:00Z"
    echo "opt NOT_APPLICABLE: not in this fixture"
    echo "failed records: none"; echo "LANDGATE PASS rc=0"; } > "$d/SUMMARY.log"
}
RD() { # OUT LOGDIR [override args...]
  o=$1 l=$2; shift 2
  python3 "${READINESS_PY:-$I/readiness.py}" --name fx --head "$HEAD" --base "$BASE" --repo "$R" --logdir "$l" --contract "$LANE/contract.md" \
    --rcca "$EXT/rcca.md" --actions "$LANE/actions.md" --ledger "$LANE/ledger.md" --ledger-check true --rounds "$LANE/rounds.md" \
    --authors "$LANE/authors.md" --limits "$LANE/limits.md" --out "$o" --evidence "verdict=$EXT/verdict.md" "$@"
}
RC() { python3 "${RECEIPTS_PY:-$I/receipts.py}" --head "$HEAD" --base "$BASE" --logdir "$1" --core 1 --contract "$LANE/contract.md" --readiness "$2" --out "$3"; }
BN() { # LOGDIR READINESS RECEIPT OUT [override args...]
  l=$1 r=$2 c=$3 o=$4; shift 4
  BUNDLE_MAXB=4096 python3 "${BUNDLE_PY:-$I/bundle.py}" --name fx --head "$HEAD" --base "$BASE" --repo "$R" --logdir "$l" --readiness "$r" \
    --receipt "$c" --out "$o" --base-repo "$X/base.git" --bridge-repo "$X/bridge" --root "lane=$LANE" --root "ext=$EXT" --cite-scope "$X" "$@"
}
mk() { # NAME: log directory, READY readiness record and PASS receipt for it (setup; a refusal here is a setup failure)
  logdir "$1"; RD "$LANE/$1.readiness.md" "$LANE/logs/$1" > "$X/$1.setup" 2>&1 || setup_fail "readiness for $1: $(tail -1 "$X/$1.setup")"
  RC "$LANE/logs/$1" "$LANE/$1.readiness.md" "$LANE/$1.receipt" >> "$X/$1.setup" 2>&1 || setup_fail "receipt for $1: $(tail -1 "$X/$1.setup")"
}
mutate() { # SRC DST SED-EXPR: a scratch copy with one line changed; the change must apply exactly once
  sed "$3" "$1" > "$2"; [ "$(diff "$1" "$2" | grep -c '^>')" = 1 ] || setup_fail "mutation of $1 did not change exactly one line: $3"
}
mkdir -p "$X/gitstub"; printf '#!/bin/sh\nfor a; do [ "$a" = grep ] && { echo "git stand-in: grep fails" >&2; exit 128; }; done\nexec %s "$@"\n' "$RG" > "$X/gitstub/git"; chmod 755 "$X/gitstub/git"

# ---- (R) readiness.py
logdir twin
row readiness-twin 0 " READY" RD "$LANE/twin.readiness.md" "$LANE/logs/twin"
logdir del; rm "$LANE/logs/del/step-a.log"
row readiness-row-log-deleted 1 "row step-a: log missing or sha256 differs" RD "$X/del.readiness.md" "$LANE/logs/del"
logdir alt; printf 'x' >> "$LANE/logs/alt/big.log"
row readiness-row-log-altered 1 "row big: log missing or sha256 differs" RD "$X/alt.readiness.md" "$LANE/logs/alt"
logdir drop; sed -i '/^step-a rc=0 /d' "$LANE/logs/drop/SUMMARY.log"
row readiness-required-row-removed 1 "required row step-a absent" RD "$X/drop.readiness.md" "$LANE/logs/drop"
logdir ctl; sed -i 's/^ctl-b control_exit=1 /ctl-b control_exit=0 /' "$LANE/logs/ctl/SUMMARY.log"
row readiness-control-row-wrong-exit 1 "control row ctl-b did not show its expected exit and text" RD "$X/ctl.readiness.md" "$LANE/logs/ctl"
logdir fail; sed -i 's/^LANDGATE PASS rc=0$/LANDGATE FAIL/' "$LANE/logs/fail/SUMMARY.log"
row readiness-summary-not-pass 1 "gate summary is not LANDGATE PASS" RD "$X/fail.readiness.md" "$LANE/logs/fail"
row readiness-no-rcca 1 "required rcca missing" RD "$X/x.readiness.md" "$LANE/logs/twin" --rcca none
row readiness-unrelated-rcca 1 "does not name line fx" RD "$X/x.readiness.md" "$LANE/logs/twin" --rcca "$EXT/rcca-other.md"
row readiness-action-not-installed 1 "action H1 is OPEN (not installed)" RD "$X/x.readiness.md" "$LANE/logs/twin" --actions "$LANE/actions-open.md"
row readiness-ledger-refuses 1 "ledger check exit 1" RD "$X/x.readiness.md" "$LANE/logs/twin" --ledger-check false
row readiness-rounds-stale 1 'rounds file still says "No RCCA file exists"' RD "$X/x.readiness.md" "$LANE/logs/twin" --rounds "$LANE/rounds-stale.md"
row readiness-rounds-superseded-twin 0 " READY" RD "$X/x.readiness.md" "$LANE/logs/twin" --rounds "$LANE/rounds-superseded.md"
logdir rx "$RX"
row readiness-merge-residue 1 "merge residue: $RX:residue.txt" RD "$X/x.readiness.md" "$LANE/logs/rx" --head "$RX"
row readiness-residue-scan-fails 1 "merge-residue scan failed (git grep exit 128)" env PATH="$X/gitstub:$PATH" bash -c "$(declare -f RD); $(declare -p I HEAD BASE R LANE EXT); RD \"\$@\"" sh "$X/x.readiness.md" "$LANE/logs/twin"
row readiness-required-evidence-none 1 "required evidence extra is none" RD "$X/x.readiness.md" "$LANE/logs/twin" --evidence extra=none
mutate "$I/readiness.py" "$X/mut/readiness-nopredicate.py" 's/^    if not ok: why.append(msg)  # readiness predicate$/    pass/'
row readiness-predicate-removed 0 " READY" env READINESS_PY="$X/mut/readiness-nopredicate.py" bash -c "$(declare -f RD); $(declare -p I HEAD BASE R LANE EXT); RD \"\$@\"" sh "$X/x.readiness.md" "$LANE/logs/del"
mutate "$I/readiness.py" "$X/mut/readiness-noscan.py" 's/^if need(mr.returncode in (0, 1), \(.*\)):  # scan predicate$/if True:/'
sed -i 's/^    need(mr.returncode == 1 and not mr.stdout.strip(), /    need(not mr.stdout.strip(), /' "$X/mut/readiness-noscan.py"
row readiness-scan-predicate-removed 0 " READY" env PATH="$X/gitstub:$PATH" READINESS_PY="$X/mut/readiness-noscan.py" bash -c "$(declare -f RD); $(declare -p I HEAD BASE R LANE EXT); RD \"\$@\"" sh "$X/x.readiness.md" "$LANE/logs/twin"

# ---- (P) receipts.py
row receipt-twin 0 "PASS" bash -c 'RECEIPT=$3; python3 "$1"/receipts.py --head "$2" --base "$4" --logdir "$5" --core 1 --contract "$6" --readiness "$7" --out "$RECEIPT" && head -1 "$RECEIPT" | grep -x "RECEIPT PASS head=$2"' sh "$I" "$HEAD" "$LANE/twin.receipt" "$BASE" "$LANE/logs/twin" "$LANE/contract.md" "$LANE/twin.readiness.md"
mk rdel; rm "$LANE/logs/rdel/big.log"
row receipt-row-log-deleted 1 "row big: log missing" RC "$LANE/logs/rdel" "$LANE/rdel.readiness.md" "$X/rdel.receipt"
mk ralt; printf 'x' >> "$LANE/logs/ralt/ctl-b.log"
row receipt-row-log-altered 1 "row ctl-b: log changed" RC "$LANE/logs/ralt" "$LANE/ralt.readiness.md" "$X/ralt.receipt"
logdir rnr; RD "$LANE/rnr.readiness.md" "$LANE/logs/rnr" --actions "$LANE/actions-open.md" > /dev/null 2>&1 && setup_fail "rnr readiness was READY"
row receipt-not-ready 1 "readiness verdict is not READY" RC "$LANE/logs/rnr" "$LANE/rnr.readiness.md" "$X/rnr.receipt"
head -1 "$X/rnr.receipt" | grep -q '^RECEIPT NOT_READY' || { echo "FAIL receipt-not-ready: first line is not RECEIPT NOT_READY"; bad=$((bad + 1)); }
mutate "$I/receipts.py" "$X/mut/receipts-nopredicate.py" 's/^\( *\)if now != m\[6\]: .*  # receipt log predicate$/\1pass/'
row receipt-predicate-removed 0 "PASS" env RECEIPTS_PY="$X/mut/receipts-nopredicate.py" bash -c "$(declare -f RC); $(declare -p I HEAD BASE LANE); RC \"\$@\"" sh "$LANE/logs/rdel" "$LANE/rdel.readiness.md" "$X/rdel-nop.receipt"

# ---- (B) bundle.py
row bundle-twin 0 "BUNDLE-TWIN-CHECKS PASS" bash -c "$(declare -f BN); $(declare -p I HEAD BASE R LANE EXT X)"'
  BN "$LANE/logs/twin" "$LANE/twin.readiness.md" "$LANE/twin.receipt" "$X/bundle-twin" || exit 1
  m=$X/bundle-twin/MANIFEST.sha256; o=$X/bundle-twin/logs-omitted.txt
  grep -q "  lane/logs/twin/big.log$" "$m" || { echo "cited large log not bundled"; exit 1; }
  grep -q "  ext/rcca.md$" "$m" && grep -q "  ext/verdict.md$" "$m" && grep -q "  ext/model-records.txt$" "$m" || { echo "external citations not followed"; exit 1; }
  grep -q "lane/logs/twin/scratch-big.bin" "$o" && ! grep -q "big.log" "$o" || { echo "omission list wrong"; cat "$o"; exit 1; }
  (cd "$X/bundle-twin" && sha256sum -c --quiet MANIFEST.sha256) || exit 1
  echo "BUNDLE-TWIN-CHECKS PASS"'
cp "$LANE/twin.readiness.md" "$LANE/cites-missing.readiness.md"; echo "- extra $EXT/does-not-exist.log" >> "$LANE/cites-missing.readiness.md"
row bundle-cited-missing 1 "cited path missing: $EXT/does-not-exist.log" BN "$LANE/logs/twin" "$LANE/cites-missing.readiness.md" "$LANE/twin.receipt" "$X/bundle-missing"
cp "$LANE/twin.readiness.md" "$LANE/ext-missing.readiness.md"; echo "- extra $EXT/verdict-missing-cite.md" >> "$LANE/ext-missing.readiness.md"
row bundle-external-cited-missing 1 "cited path missing: $EXT/gone.txt (in ext/verdict-missing-cite.md)" BN "$LANE/logs/twin" "$LANE/ext-missing.readiness.md" "$LANE/twin.receipt" "$X/bundle-extmissing"
cp "$LANE/twin.readiness.md" "$LANE/outside.readiness.md"; echo "- extra $X/outside/x.log" >> "$LANE/outside.readiness.md"
row bundle-cited-outside-roots 1 "outside bundle roots: $X/outside/x.log" BN "$LANE/logs/twin" "$LANE/outside.readiness.md" "$LANE/twin.receipt" "$X/bundle-outside"
mk dig; printf 'x' >> "$LANE/logs/dig/step-a.log"
row bundle-recorded-digest-differs 1 "$LANE/logs/dig/step-a.log differs from its recorded sha256" BN "$LANE/logs/dig" "$LANE/dig.readiness.md" "$LANE/dig.receipt" "$X/bundle-dig"
mutate "$I/bundle.py" "$X/mut/bundle-nodigest.py" 's/^\( *\)if sha(D \/ k) != d: .*  # recorded-digest predicate$/\1pass/'
row bundle-digest-predicate-removed 0 "errors=0" env BUNDLE_PY="$X/mut/bundle-nodigest.py" bash -c "$(declare -f BN); $(declare -p I HEAD BASE R LANE EXT X); BN \"\$@\"" sh "$LANE/logs/dig" "$LANE/dig.readiness.md" "$LANE/dig.receipt" "$X/bundle-dig-nop"
mutate "$I/bundle.py" "$X/mut/bundle-omits.py" 's/ and not is_cited: omitted\[k\] = src; return  # omission rule$/: omitted[k] = src; return  # omission rule, fault injected: cited files omitted too/'
row bundle-large-cited-omitted 1 "required artifact omitted: $LANE/logs/twin/big.log" env BUNDLE_PY="$X/mut/bundle-omits.py" bash -c "$(declare -f BN); $(declare -p I HEAD BASE R LANE EXT X); BN \"\$@\"" sh "$LANE/logs/twin" "$LANE/twin.readiness.md" "$LANE/twin.receipt" "$X/bundle-omits"
mutate "$X/mut/bundle-omits.py" "$X/mut/bundle-omits-nopredicate.py" 's/^\( *\)if k not in copied: .*  # required-artifact predicate$/\1pass/'
row bundle-required-predicate-removed 0 "errors=0" env BUNDLE_PY="$X/mut/bundle-omits-nopredicate.py" bash -c "$(declare -f BN); $(declare -p I HEAD BASE R LANE EXT X); BN \"\$@\"" sh "$LANE/logs/twin" "$LANE/twin.readiness.md" "$LANE/twin.receipt" "$X/bundle-omits-nop"
grep -q "lane/logs/twin/big.log" "$X/bundle-omits-nop/logs-omitted.txt" || { echo "FAIL bundle-required-predicate-removed: big.log was not omitted, so the row shows nothing"; bad=$((bad + 1)); }
row bundle-base-objects-absent 1 "does not verify" BN "$LANE/logs/twin" "$LANE/twin.readiness.md" "$LANE/twin.receipt" "$X/bundle-nobase" --base-repo "$X/empty.git"
row bundle-bridge-lock-absent 1 "omega-bridge lock $LOCK not bundled" BN "$LANE/logs/twin" "$LANE/twin.readiness.md" "$LANE/twin.receipt" "$X/bundle-nobridge" --bridge-repo "$X/empty.git"

if [ "$bad" = 0 ]; then echo "LANDGATE-INSTRUMENTS PASS rows=$rows"; exit 0; fi
echo "LANDGATE-INSTRUMENTS FAIL failed=$bad rows=$rows"; exit 1
