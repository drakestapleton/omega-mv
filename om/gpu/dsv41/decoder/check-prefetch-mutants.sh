#!/bin/bash
# Self-judging qualification of the dsv41-decode Arboris prefetch switch, with its negative controls.
# Builds the decoder (README composition and om/gpu/dsv41/build.sh, which must agree byte for byte), the
# three controls, and eight mutants, then requires every control to pass and every mutant to be rejected
# by the exact check named for it. Host only: no GPU is opened.
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
  name=$1 src=$2; shift 2
  cp "$src" "$m/$name"
  for e in "$@"; do
    before=$(sha256sum "$m/$name" | cut -d' ' -f1)
    sed -i "$e" "$m/$name"
    [ "$(sha256sum "$m/$name" | cut -d' ' -f1)" != "$before" ] || { echo "PREFETCH-MUTANTS FAIL: $name: '$e' did not apply"; exit 1; }
  done
}
build() { # target; stdin is the source
  seed/out/omc > "$1"
  rc=$?
  [ "$rc" = 0 ] && [ -s "$1" ] || { echo "PREFETCH-MUTANTS FAIL: build $1 rc=$rc"; exit 1; }
  chmod +x "$1"
}

# Mutants. Each names the check that must reject it.
mutate A-forward-nogate.om $d/forward.om 's/^  if or eq get dfArbPfMeta 4 0 ne get dfWrActive 0 6$/  if ne get dfWrActive 0 6/'
mutate D-forward-silent.om $d/forward.om 's/^  if or eq get dfArbPfMeta 4 0 ne get dfWrActive 0 6$/  if ne get dfWrActive 0 6/' \
  's/^  put dfArbPfMeta 0 pfCount$/  put dfArbPfMeta 0 0/' 's/^  put dfArbPfMeta 3 add get dfArbPfMeta 3 pfCount$/  put dfArbPfMeta 3 get dfArbPfMeta 3/'
mutate E-forward-starton.om $d/forward.om 's/^  put dfArbPfMeta 4 pfOn$/  put dfArbPfMeta 4 1/'
mutate H-forward-anyarg.om $d/forward.om 's/^  if gt pfOn 1$/  if false/'
mutate B-switch-nolen.om $d/prefetch-switch.om 's/^    ok = eq ulong n add kl 1$/    ok = true/'
mutate C-switch-nodup.om $d/prefetch-switch.om 's/^    if seen$/    if false/'
mutate F-cli-starton.om $d/decode-cli.om 's/^  if not dfStartWorkers pfOn$/  if not dfStartWorkers 1/'
mutate G-cli-norefuse.om $d/decode-cli.om 's/^  if lt pfSetting 0$/  if false/'

compose_decoder $d/forward.om $d/prefetch-switch.om $d/decode-cli.om | build "$out/dsv41-decode" || exit 1
compose_decoder $d/forward.om $d/prefetch-switch.om $d/check-arboris-prefetch.om | build "$out/check-arboris-prefetch" || exit 1
(echo om2; cat $d/prefetch-switch.om $d/check-prefetch-switch.om) | build "$out/check-prefetch-switch" || exit 1
for x in A-forward-nogate D-forward-silent E-forward-starton H-forward-anyarg; do
  compose_decoder "$m/$x.om" $d/prefetch-switch.om $d/check-arboris-prefetch.om | build "$m/$x" || exit 1
done
for x in B-switch-nolen C-switch-nodup; do
  (echo om2; cat "$m/$x.om" $d/check-prefetch-switch.om) | build "$m/$x" || exit 1
done
for x in F-cli-starton G-cli-norefuse; do
  compose_decoder $d/forward.om $d/prefetch-switch.om "$m/$x.om" | build "$m/$x" || exit 1
done

ob=$(mktemp -d)
sh om/gpu/dsv41/build.sh "$ob" > "$out/official-build.log" 2>&1 || { echo "PREFETCH-MUTANTS FAIL: om/gpu/dsv41/build.sh"; exit 1; }
cmp -s "$ob/dsv41-decode" "$out/dsv41-decode" && echo "PASS official build identical" || note_fail "official build differs"
rm -rf "$ob"

L1=$sidecars/layer1.bin S4=$ckpt/model-00004-of-00048.safetensors
expect_rc() { # label want cmd...
  label=$1 want=$2; shift 2
  "$@" > /dev/null 2>&1
  got=$?
  [ "$got" = "$want" ] && echo "PASS $label (exit $got)" || note_fail "$label want exit $want got $got"
}
expect_rc "switch control" 0 sh $d/check-prefetch-switch.sh "$out/check-prefetch-switch"
expect_rc "decoder control" 0 sh $d/check-decoder-prefetch.sh "$out/dsv41-decode" "$tensors" "$map" "$sidecars" "$ckpt"
expect_rc "off-arm and on-arm control" 0 "$out/check-arboris-prefetch" "$L1" "$S4"
expect_rc "mutant A rejected by off-arm dispatch check" 38 "$m/A-forward-nogate" "$L1" "$S4"
expect_rc "mutant D rejected by worker-reply check" 39 "$m/D-forward-silent" "$L1" "$S4"
expect_rc "mutant E rejected by start-setting check" 40 "$m/E-forward-starton" "$L1" "$S4"
expect_rc "mutant H rejected by setting-range check" 43 "$m/H-forward-anyarg" "$L1" "$S4"
expect_rc "mutant B rejected by switch control" 1 sh $d/check-prefetch-switch.sh "$m/B-switch-nolen"
expect_rc "mutant C rejected by switch control" 1 sh $d/check-prefetch-switch.sh "$m/C-switch-nodup"
expect_rc "mutant F rejected by decoder control" 1 sh $d/check-decoder-prefetch.sh "$m/F-cli-starton" "$tensors" "$map" "$sidecars" "$ckpt"
expect_rc "mutant G rejected by decoder control" 1 sh $d/check-decoder-prefetch.sh "$m/G-cli-norefuse" "$tensors" "$map" "$sidecars" "$ckpt"

(cd "$out" && sha256sum dsv41-decode check-arboris-prefetch check-prefetch-switch mutants/*)
if [ "$fail" = 0 ]; then echo "PREFETCH-MUTANTS PASS"; else echo "PREFETCH-MUTANTS FAIL"; fi
exit "$fail"
