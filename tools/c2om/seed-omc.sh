#!/bin/sh
# tools/c2om/seed-omc.sh [outdir]: the seed-born Omega compiler omc for the C-to-Omega program (ledger L418).
#
# Runs the repository's one birth script, seed/omega-from-seed.sh (seed0.hex -> hex1 -> asm2 -> om4 ->
# omc, fixpoint stage2 = stage3, names-pass probes), requires its RC=0 line, requires the result to equal
# the committed seed/out/omc, and copies it to <outdir>/omc. gcc, the C-built Omega and oscc never run.
# Prints the sha256 of omc on the last line; writes <outdir>/omc and <outdir>/omc.sha256.
set -eu
D=$(cd "$(dirname "$0")/../.." && pwd)
O=${1:-$D/build/c2om/seed}
mkdir -p "$O"
bad() { echo "seed-omc: $*" >&2; exit 1; }
cd "$D"
sh seed/omega-from-seed.sh > "$O/birth.out" 2>&1 || bad "seed/omega-from-seed.sh failed: $(tail -1 "$O/birth.out")"
[ "$(tail -1 "$O/birth.out")" = "RC=0" ] || bad "seed/omega-from-seed.sh did not print RC=0"
git diff --quiet -- seed/out/omc seed/out/omc.sha256 || bad "birth produced an omc different from the committed seed/out/omc"
cp seed/out/omc "$O/omc"
chmod +x "$O/omc"
sha256sum "$O/omc" | cut -d' ' -f1 > "$O/omc.sha256"
echo "omc $(wc -c < "$O/omc") bytes, born by seed/omega-from-seed.sh (RC=0), equal to committed seed/out/omc"
cat "$O/omc.sha256"
