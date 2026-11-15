#!/bin/sh
# build.sh -- compile tools/codebook/codebook.om with the seeded omc, after the seeded SHA-256 core.
# Run from the repo root:  sh tools/codebook/build.sh   (OMC defaults to seed/out/omc)
# codebook.om is the shared core (also compiled into tools/trit); main.om is the command line.
# Same composition as tools/trit/build.sh and seed/omega-from-seed.sh step 5: om2 line, the
# `abstract` line (omc refuses it after any fn, error 9), sha256.om up to "fn sha256", the program.
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$R"
OMC=${OMC:-seed/out/omc}
B=${B:-build/codebook}
mkdir -p "$B"
{ printf 'om2\n'; grep '^abstract ' tools/codebook/codebook.om; sed '/^fn sha256 /,$d' seed/trace/sha256.om; grep -v '^abstract ' tools/codebook/codebook.om; cat tools/codebook/main.om; } > "$B/codebook.full.om"
"$OMC" < "$B/codebook.full.om" > "$B/codebook"
chmod +x "$B/codebook"
sha256sum "$OMC" tools/codebook/codebook.om tools/codebook/main.om tools/codebook/codebook.tsv "$B/codebook.full.om" "$B/codebook"
