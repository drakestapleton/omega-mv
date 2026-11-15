#!/bin/sh
# build.sh -- compile tools/trit/trit.om with the seeded omc, after the seeded SHA-256 core.
# Run from the repo root:  sh tools/trit/build.sh   (OMC defaults to seed/out/omc)
# The composition mirrors seed/omega-from-seed.sh step 5 (diaggen): om2 line, the sha256.om core
# up to "fn sha256", then the program. Prints the sha256 of the composed source and the binary.
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$R"
OMC=${OMC:-seed/out/omc}
B=${B:-build/trit}
mkdir -p "$B"
# omc refuses an `abstract` line after any `fn` (error 9), and the core ends in functions, so the
# trit type line is lifted ahead of the core.
{ printf 'om2\n'; grep '^abstract ' tools/codebook/codebook.om; sed '/^fn sha256 /,$d' seed/trace/sha256.om; grep -v '^abstract ' tools/codebook/codebook.om; cat tools/trit/trit.om; } > "$B/trit.full.om"
"$OMC" < "$B/trit.full.om" > "$B/trit"
chmod +x "$B/trit"
sha256sum "$OMC" tools/codebook/codebook.om tools/trit/trit.om "$B/trit.full.om" "$B/trit"
