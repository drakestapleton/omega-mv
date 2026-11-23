#!/bin/sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
kit=$(CDPATH= cd -- "$1" && pwd)
{ sed '/^fn main to int$/,$d' "$here/../../bench/bench.om"
  sed '/^fn main to int$/,$d' "$here/../combined.om"
  cat "$here/predict.om"
} | "$kit/omc" > "$kit/predict"
chmod 700 "$kit/predict"
