#!/bin/sh
# Build and run the pure seeded-Omega MTPVarlen + N-gram speculative decoding gate.
set -eu
out=${1:?usage: sh om/gpu/spec/build.sh OUTPUT_DIR}
mkdir -p "$out"
tmp=$(mktemp -d "$out/build.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

( echo om2
  cat om/gpu/spec/mtp_varlen.om \
    om/gpu/spec/ngram_draft.om \
    om/gpu/spec/check_mtp_varlen.om
) > "$tmp/check_mtp_varlen.om"
seed/out/omc < "$tmp/check_mtp_varlen.om" > "$out/check_mtp_varlen"
chmod +x "$out/check_mtp_varlen"
