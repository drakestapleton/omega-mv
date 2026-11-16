#!/bin/sh
# External driver regression: failure of the test runner is never a mutation kill.
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/codebook-driver-check.XXXXXX")
OMC=${OMC:-$R/seed/out/omc}; export OMC
case $OMC in /*) ;; *) OMC=$(pwd)/$OMC; export OMC ;; esac
for mode in baseline crash no-assertion survivor; do
  d="$W/$mode"; mkdir -p "$d/tools" "$d/seed/trace"
  cp -r "$R/tools/codebook" "$d/tools/"
  cp "$R/seed/trace/sha256.om" "$d/seed/trace/"
  cat > "$d/tools/codebook/test.sh" <<'STUB'
#!/bin/sh
if [ "$MODE" = baseline ]; then echo 'runner unavailable' >&2; exit 2; fi
case $BIN in */base/codebook) echo 'TOTAL pass=1 fail=0 skip=0'; exit 0 ;; esac
case $MODE in
  crash) echo 'runner unavailable' >&2; exit 2 ;;
  no-assertion) echo 'TOTAL pass=0 fail=1 skip=0'; exit 1 ;;
  survivor) echo 'TOTAL pass=1 fail=0 skip=0'; exit 0 ;;
esac
exit 2
STUB
  rc=0
  (cd "$d" && MODE=$mode M="$d/results" sh tools/codebook/mutate.sh) > "$d/output.log" 2>&1 || rc=$?
  case $mode in baseline) want=5 ;; crash|no-assertion) want=4 ;; survivor) want=1 ;; esac
  if [ "$rc" != "$want" ]; then echo "FAIL $mode: exit $rc expected $want logs=$W"; exit 1; fi
  if grep -q ': caught' "$d/output.log"; then echo "FAIL $mode: false kill logs=$W"; exit 1; fi
  echo "PASS $mode exit=$rc"
done
# A supplied work directory and symlink must preserve existing evidence.
mkdir "$W/keep"; printf 'evidence\n' > "$W/keep/sentinel"; ln -s "$W/keep" "$W/link"
for target in "$W/keep" "$W/link"; do
  rc=0
  M="$target" sh "$R/tools/codebook/mutate.sh" > "$W/directory.log" 2>&1 || rc=$?
  [ "$rc" = 2 ] && [ "$(cat "$W/keep/sentinel")" = evidence ] && [ -L "$W/link" ] || { echo 'FAIL preserve work directory'; exit 1; }
done
echo "CODEBOOK-DRIVER PASS logs=$W"
