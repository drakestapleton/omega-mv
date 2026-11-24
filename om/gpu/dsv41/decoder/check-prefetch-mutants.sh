#!/bin/bash
# Self-judging qualification of the dsv41-decode prefetch switch and prefetch pipeline, with negative
# controls. Builds the decoder (README composition and om/gpu/dsv41/build.sh, which must agree byte for
# byte), the three controls, and the mutants, then requires every control to pass and every mutant to be
# rejected by the exact check or case named for it. Host only: no GPU is opened. What needs the GPU (the
# look-ahead launches, folded FP32 tables, and off-vs-on timing) requires an authorized GB10 window.
# Switch cases with a mutant of their own: unset (J), zero (O), two (N), double-zero (B), longer-name (M),
# big-entry-unset (I), many-entries-unset (L), repeated-name (C). The other switch cases (one, empty,
# leading-zero, trailing-space, word, shorter-name, lower-case, big-entry-zero, zero-among-others,
# many-entries-zero) are siblings of those and have no mutant of their own.
# Pipeline checks of check-arboris-prefetch.om: every exit has a mutant below that only it rejects, except
# 31, 70 and 77 (set-up failures), 34, 45, 50 and 51 (a step returned an error; the mutants of the checks
# after them cover the behaviour), 37 (no line of the pipeline publishes a guess the gate did not ask
# for, so no one-line change produces that fault), and 49 and 54 (they exercise the on-demand path, which
# this change does not alter: 49 shows the digest check itself accepts a good slot, 54 that a bad
# payload stops the decoder).
# usage (repository root, clean tree, AArch64 Linux):
#   bash om/gpu/dsv41/decoder/check-prefetch-mutants.sh OUT_DIR TENSORS SIDECAR_DIR CKPT_DIR
# Prints PREFETCH-MUTANTS PASS and exits 0 only if every expectation holds.
set -u -o pipefail
out=$1 tensors=$2 sidecars=$3 ckpt=$4
d=om/gpu/dsv41/decoder
map=$d/engram-token-map.u32
test -z "$(git status --porcelain)" || { echo "PREFETCH-MUTANTS FAIL: tree not clean"; exit 1; }
mkdir -p "$out/mutants"
m=$out/mutants
echo "head $(git rev-parse HEAD)"
echo "omc $(sha256sum seed/out/omc | cut -d' ' -f1)"
sha256sum -c seed/out/omc.sha256 > /dev/null || { echo "PREFETCH-MUTANTS FAIL: omc digest"; exit 1; }
fail=0
note_fail() { echo "FAIL $*"; fail=1; }

compose_decoder() { # forward switch cli
  echo om2
  sed -n '/^layout /,/^end$/p' om/sha256/sha256-om2.om om/runtime/slab_arena.om
  sed '/^layout /,/^end$/d;/^om2$/d;s/^export fn /fn /' om/sha256/sha256-om2.om om/runtime/slab_arena.om
  cat seed/ng/sha256.om gpu/nvidia/native/arboris/compute-lock.om gpu/nvidia/native/nvrm/context.om \
      gpu/nvidia/native/blackwell/vector.om gpu/nvidia/native/blackwell/launch.om gpu/nvidia/native/blackwell/batch.om \
      om/encoder/bw_enc_sm121.om om/gpu/dsv41/emit.om om/gpu/dsv41/head/launch.om \
      $d/checkpoint.om $d/io.om $d/core.om $d/kv.om $d/lease.om $d/resolve.om \
      $d/engram-layout.om $d/engram.om $d/trace.om $d/native.om \
      $d/layer-map.om $d/rope.om $d/workspace.om "$1" "$2" "$3"
}
mutate() { # name source sed-expression...; requires every expression to change the source
  local name=$1 src=$2 e before
  shift 2
  cp "$src" "$m/$name"
  for e in "$@"; do
    before=$(sha256sum "$m/$name" | cut -d' ' -f1)
    sed -i "$e" "$m/$name"
    [ "$(sha256sum "$m/$name" | cut -d' ' -f1)" != "$before" ] || { echo "PREFETCH-MUTANTS FAIL: $name: '$e' did not apply"; exit 1; }
  done
}
build() { # target; stdin is the source
  local rc
  seed/out/omc > "$1"
  rc=$?
  [ "$rc" = 0 ] && [ -s "$1" ] || { echo "PREFETCH-MUTANTS FAIL: build $1 rc=$rc"; exit 1; }
  chmod +x "$1"
}

# Mutants. Each names the check that must reject it.
# Pipeline mutants: pmut NAME EXIT SED..., rejected only by exit EXIT of check-arboris-prefetch.
pm_names=() pm_exits=()
pmut() {
  local name=$1 want=$2
  shift 2
  mutate "$name.om" $d/forward.om "$@"
  pm_names+=("$name"); pm_exits+=("$want")
}
noop='put dfPfStat 4 get dfPfStat 4'
pmut A-off-dispatches 38 's/^  if eq pfOn 1$/  if true/' 's/^  if or eq get dfArbPfMeta 4 0 eq get dfPfActive 0 0$/  if eq get dfPfActive 0 0/'
pmut P-off-startsworkers 41 's/^  if eq pfOn 1$/  if true/'
pmut E-start-ignores-setting 40 's/^  put dfArbPfMeta 4 pfOn$/  put dfArbPfMeta 4 1/'
pmut H-any-setting 43 's/^  if gt pfOn 1$/  if false/'
pmut Q-on-noworkers 44 's/^  if eq pfOn 1$/  if false/'
pmut R-no-dispatch 32 's/^        if lt e 384$/        if lt e 0/'
pmut S-dispatch-not-recorded 33 's/^  put dfPfOfKey key uchar add ulong slot 1$/  put dfPfOfKey key 0/'
pmut T-waits-for-unneeded 46 's/^  dfGateAwait layer src not par$/  dfPfFinish 0/'
pmut U-misses-not-counted 47 's/^  put dfStats 1 add get dfStats 1 1$/  put dfStats 1 get dfStats 1/'
pmut V-used-not-counted 35 's/^  put dfArbPfMeta 2 add get dfArbPfMeta 2 1$/  put dfArbPfMeta 2 get dfArbPfMeta 2/'
pmut W-staging-not-freed 36 "s/^  dfPfFree stage\$/  $noop/"
pmut X-wrong-staging-bytes 48 's/^  sOff = mul stage deBytes$/  sOff = add mul stage deBytes 4096/'
pmut Y-worker-skips-digest 52 's/^      if deVerifyAt get dfShardFD layer desc get dfPfStage 0 mul slot deBytes$/      if deWriteVerifiedAt get dfShardFD layer desc get dfPfStage 0 mul slot deBytes/'
pmut Z-failed-kept-staged 53 "s/^    dfPfFree ulong slot\$/    $noop/"
pmut a-stop-leaves-workers 55 "s/^  dfPfStop\$/  $noop/"
pmut b-slot-newest 61 's/^      if or lt best 0 lt get dfPfSlotSeq s bestSeq$/      if or lt best 0 gt get dfPfSlotSeq s bestSeq/'
pmut c-free-keeps-key 62 "s/^    put dfPfOfKey ulong key 0\$/    $noop/"
pmut e-drop-not-counted 63 's/^    put dfPfStat 0 add get dfPfStat 0 1$/    put dfPfStat 0 get dfPfStat 0/'
pmut f-free-slot-ignored 65 's/^    if eq st 0$/    if eq st 9/'
pmut g-takes-inflight-slot 67 's/^    if eq st 2$/    if ge st 1/'
pmut h-lookahead-ignores-switch 71 's/^  if eq get dfArbPfMeta 4 0$/  if false/'
pmut i-launch-count 72 's/^  ret add 2 mul 2 n$/  ret mul 2 n/'
pmut k-last-layer 73 's/^    if le add layer dfSpecDepthAt i 39$/    if lt add layer dfSpecDepthAt i 39/'
pmut n-score-inverted 75 's/^          if eq g get dfCurIds k$/          if ne g get dfCurIds k/'
pmut o-score-no-guess 76 's/^    if ge layer dfSpecDepthAt i$/    if true/'
pmut q-bad-id-kept 78 's/^        if ge e 384$/        if ge e 999/'
pmut r-guess-wrong-layer 79 's/^      base = mul add mul i 40 add layer dfSpecDepthAt i 6$/      base = mul add mul i 40 layer 6/'
mutate B-switch-nolen.om $d/prefetch-switch.om 's/^    ok = eq ulong n add kl 1$/    ok = true/'
mutate C-switch-nodup.om $d/prefetch-switch.om 's/^    if seen$/    if false/'
mutate I-switch-smallbuf.om $d/prefetch-switch.om 's/^global dpsBuf uchar 2097152$/global dpsBuf uchar 65536/'
mutate J-switch-defaultoff.om $d/prefetch-switch.om 's/^  found = long 1$/  found = long 0/'
mutate L-switch-bound.om $d/prefetch-switch.om 's/^  for i ulong ec$/  for i ulong ec bound 65536/'
mutate M-switch-keynoeq.om $d/prefetch-switch.om 's/^text dpsKey "DSV41_ARBORIS_PREFETCH="$/text dpsKey "DSV41_ARBORIS_PREFETCH"/'
mutate N-switch-anyvalue.om $d/prefetch-switch.om 's/^    ok = and ok or eq c 48 eq c 49$/    ok = and ok true/'
mutate O-switch-nooff.om $d/prefetch-switch.om 's/^    if eq c 48$/    if false/'
mutate K-cli-startoff.om $d/decode-cli.om 's/^  if not dfStartWorkers pfOn$/  if not dfStartWorkers 0/'
mutate F-cli-starton.om $d/decode-cli.om 's/^  if not dfStartWorkers pfOn$/  if not dfStartWorkers 1/'
mutate G-cli-norefuse.om $d/decode-cli.om 's/^  if lt pfSetting 0$/  if false/'

compose_decoder $d/forward.om $d/prefetch-switch.om $d/decode-cli.om | build "$out/dsv41-decode" || exit 1
compose_decoder $d/forward.om $d/prefetch-switch.om $d/check-arboris-prefetch.om | build "$out/check-arboris-prefetch" || exit 1
(echo om2; cat $d/prefetch-switch.om $d/check-prefetch-switch.om) | build "$out/check-prefetch-switch" || exit 1
for x in "${pm_names[@]}"; do
  compose_decoder "$m/$x.om" $d/prefetch-switch.om $d/check-arboris-prefetch.om | build "$m/$x" || exit 1
done
for x in B-switch-nolen C-switch-nodup I-switch-smallbuf J-switch-defaultoff L-switch-bound M-switch-keynoeq N-switch-anyvalue O-switch-nooff; do
  (echo om2; cat "$m/$x.om" $d/check-prefetch-switch.om) | build "$m/$x" || exit 1
done
for x in F-cli-starton G-cli-norefuse K-cli-startoff; do
  compose_decoder $d/forward.om $d/prefetch-switch.om "$m/$x.om" | build "$m/$x" || exit 1
done

ob=$(mktemp -d)
sh om/gpu/dsv41/build.sh "$ob" > "$out/official-build.log" 2>&1 || { echo "PREFETCH-MUTANTS FAIL: om/gpu/dsv41/build.sh"; exit 1; }
cmp -s "$ob/dsv41-decode" "$out/dsv41-decode" && echo "PASS official build identical" || note_fail "official build differs"
rm -rf "$ob"

# Layer 3 lives in checkpoint shard 6 (layer + 3). The bad sidecar is a copy with one byte of expert 9's
# digest (offset 9 * 64 + 8) inverted.
L3=$sidecars/layer3.bin S6=$ckpt/model-00006-of-00048.safetensors bad=$out/layer3-bad.bin
cp "$L3" "$bad"
b=$(dd if="$L3" bs=1 skip=584 count=1 2>/dev/null | od -An -tu1 | tr -d ' ')
printf "$(printf '\\%03o' $((b ^ 255)))" | dd of="$bad" bs=1 seek=584 conv=notrunc 2>/dev/null
{ cmp -l "$L3" "$bad" || [ "$?" = 1 ]; } | awk 'END { exit !(NR == 1 && $1 == 585) }' || { echo "PREFETCH-MUTANTS FAIL: bad sidecar not made"; exit 1; }
# expect LABEL WANT_RC PATTERN CMD...: CMD must exit WANT_RC and print a line matching the extended regex PATTERN
# (empty PATTERN: no output check). A mutant counts as rejected only through the exact case it targets.
expect() {
  local label=$1 want=$2 pat=$3 res got
  shift 3
  res=$("$@" 2>&1)
  got=$?
  if [ "$got" = "$want" ] && { [ -z "$pat" ] || printf '%s\n' "$res" | grep -q -E "$pat"; }; then
    echo "PASS $label (exit $got)"
  else
    note_fail "$label want exit $want${pat:+ and /$pat/} got $got"
    printf '%s\n' "$res" | sed 's/^/    /'
  fi
}
# The decoder and the Arboris controls claim the shared host lock /tmp/omega-arboris-compute-v1.lock;
# a running dsv41-decode holds it, and the controls would then fail for that reason alone.
if ps -eo comm= | grep -q -x -F dsv41-decode; then
  echo "PREFETCH-MUTANTS FAIL: another dsv41-decode is running and holds the Arboris compute lock; rerun when it exits"
  exit 1
fi
expect "switch control" 0 "^PREFETCH-SWITCH PASS$" sh $d/check-prefetch-switch.sh "$out/check-prefetch-switch"
expect "decoder control" 0 "^DECODER-PREFETCH PASS$" sh $d/check-decoder-prefetch.sh "$out/dsv41-decode" "$tensors" "$map" "$sidecars" "$ckpt"
expect "pipeline control" 0 "" "$out/check-arboris-prefetch" "$L3" "$S6" "$bad"
if [ "$fail" != 0 ]; then
  echo "PREFETCH-MUTANTS FAIL: a control failed on the real code, so no mutant result is meaningful"
  exit 1
fi
for i in "${!pm_names[@]}"; do
  expect "mutant ${pm_names[$i]} rejected by pipeline check ${pm_exits[$i]}" "${pm_exits[$i]}" "" "$m/${pm_names[$i]}" "$L3" "$S6" "$bad"
done
expect "mutant B rejected by exact-length cases" 1 "^FAIL double-zero want 12 got 11" sh $d/check-prefetch-switch.sh "$m/B-switch-nolen"
expect "mutant C rejected by repeated-name case" 1 "^FAIL repeated-name want 50" sh $d/check-prefetch-switch.sh "$m/C-switch-nodup"
expect "mutant I rejected by maximum-size entry case" 1 "^FAIL big-entry-unset want 10 got 12" sh $d/check-prefetch-switch.sh "$m/I-switch-smallbuf"
expect "mutant J rejected by default case" 1 "^FAIL unset want 10 got 11" sh $d/check-prefetch-switch.sh "$m/J-switch-defaultoff"
expect "mutant L rejected by many-entries case" 1 "^FAIL many-entries-unset want 10 got 104" sh $d/check-prefetch-switch.sh "$m/L-switch-bound"
expect "mutant M rejected by longer-name case" 1 "^FAIL longer-name want 10 got 12" sh $d/check-prefetch-switch.sh "$m/M-switch-keynoeq"
expect "mutant N rejected by bad-value case" 1 "^FAIL two want 12 got 10" sh $d/check-prefetch-switch.sh "$m/N-switch-anyvalue"
expect "mutant O rejected by off case" 1 "^FAIL zero want 11 got 10" sh $d/check-prefetch-switch.sh "$m/O-switch-nooff"
expect "mutant K rejected by decoder default case" 1 "^FAIL unset want 0 \[ARBORIS pf_enabled=1\] got 0 \[ARBORIS pf_enabled=0\]" \
  sh $d/check-decoder-prefetch.sh "$m/K-cli-startoff" "$tensors" "$map" "$sidecars" "$ckpt"
expect "mutant F rejected by off case" 1 "^FAIL zero want 0 \[ARBORIS pf_enabled=0\] got 0 \[ARBORIS pf_enabled=1\]" \
  sh $d/check-decoder-prefetch.sh "$m/F-cli-starton" "$tensors" "$map" "$sidecars" "$ckpt"
expect "mutant G rejected by refusal case" 1 "^FAIL two want 64 " \
  sh $d/check-decoder-prefetch.sh "$m/G-cli-norefuse" "$tensors" "$map" "$sidecars" "$ckpt"

(cd "$out" && sha256sum dsv41-decode check-arboris-prefetch check-prefetch-switch mutants/*)
if [ "$fail" = 0 ]; then echo "PREFETCH-MUTANTS PASS"; else echo "PREFETCH-MUTANTS FAIL"; fi
exit "$fail"
