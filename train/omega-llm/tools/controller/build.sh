#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
root=$(cd ../../../.. && pwd)
out=${OUT:-$root/build/omega-controller}
omc=${OMC:-$root/seed/out/omc}
mkdir -p "$out"
driver=$out/driver.om
grader=$out/grader.om
sed 's/^fn main to int$/fn wbmain to int/' ../wdrive/wbuild.om >"$driver"
sed 's/^fn main to int$/fn priorgrade to int/' ../contrast/grade.om >"$grader"
compile() {
  local name=$1
  shift
  cat "$@" | "$omc" >"$out/$name.tmp"
  chmod +x "$out/$name.tmp"
  mv "$out/$name.tmp" "$out/$name"
}
compile normalize "$driver" normalize.om
compile train "$driver" policy.om policy-train.om
compile train-second "$driver" policy.om second.om train-second.om
compile controller "$driver" "$root/seed/json/json.om" "$grader" ../contrast/read.om policy.om second.om controller.om
compile resident "$driver" "$root/seed/net/http.om" "$root/seed/net/notls.om" "$root/seed/json/json.om" resident.om
compile grade "$driver" "$root/seed/json/json.om" ../contrast/grade.om
for data in training second-training second-augmented-training; do
  xxd -r -p "calibration/$data.hex" >"$out/$data.bin"
done
"$out/train" "$out/training.bin" >"$out/controller.ck"
"$out/train-second" "$out/second-training.bin" >"$out/second.ck"
"$out/train-second" "$out/second-augmented-training.bin" >"$out/second-augmented.ck"
(cd "$out" && sha256sum -c "$root/train/omega-llm/tools/controller/calibration/checkpoints.sha256")
