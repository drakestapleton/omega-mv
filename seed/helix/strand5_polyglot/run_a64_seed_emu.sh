#!/bin/sh
# seed/helix/strand5_polyglot/run_a64_seed_emu.sh -- Strand E ("The Polyglot"):
# Builds pure-Omega a64_seed_emu.om and verifies ALL FOUR independent AArch64 seeds
# (seed0, seedB0, seedC0, seedD0) via Arm DDI 0487 allowlist decoding + full software emulation:
#   - Every 32-bit instruction word audited against Arm DDI 0487 allowlist (fail-closed)
#   - Full software emulation of each ELF-64 binary on its own source -> byte-for-byte identity
#   - Negative controls on ALL 4 seeds:
#       * bad character exit codes (seed0: 4, seedB0: 5, seedC0: 11, seedD0: 21)
#       * odd/short nibble exit codes (seed0: 1, seedB0: 6, seedC0: 12, seedD0: 22)
#       * poisoned instruction word rejected fail-closed (exit 10)
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
cd "$R"

OMC=${OMC:-seed/out/omc}
B=${BUILD_DIR:-build/strand5_polyglot/a64_seed_emu}

bad() { printf 'A64_SEED_EMU FAIL: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Linux ] && [ "$(uname -m)" = aarch64 ] || {
  printf 'A64_SEED_EMU NOT_RUN: requires Linux AArch64 host (got %s %s)\n' "$(uname -s)" "$(uname -m)"
  exit 3
}
[ -x "$OMC" ] || bad "compiler OMC=$OMC not executable"

rm -rf "$B"
mkdir -p "$B"

printf '=== [1/4] BUILD PURE-OMEGA a64_seed_emu.om ===\n'
"$OMC" < seed/helix/strand5_polyglot/a64_seed_emu.om > "$B/a64_seed_emu" 2> "$B/build.err" || \
  bad "omc refused a64_seed_emu.om: $(cat "$B/build.err")"
chmod +x "$B/a64_seed_emu"
printf '  PASS built a64_seed_emu (%s bytes)\n' "$(wc -c < "$B/a64_seed_emu" | tr -d ' ')"

printf '=== [2/4] GROW ALL 4 RAW SEEDS & VERIFY BY SOFTWARE EMULATION ===\n'
sh seed/rung0/load0.sh seed/rung0/seed0.hex "$B/seed0.bin"
sh seed/helix/rung0/loadB0.sh seed/helix/rung0/seedB0.b0 "$B/seedB0.bin"
sh seed/helix/strand3_trickster/loadC0.sh seed/helix/strand3_trickster/seedC0.c0 "$B/seedC0.bin"
sh seed/helix/strand4_ascetic/loadD0.sh seed/helix/strand4_ascetic/seedD0.d0 "$B/seedD0.bin"

printf '  [seed0 ] '; "$B/a64_seed_emu" verify "$B/seed0.bin"  seed/rung0/seed0.hex
printf '  [seedB0] '; "$B/a64_seed_emu" verify "$B/seedB0.bin" seed/helix/rung0/seedB0.b0
printf '  [seedC0] '; "$B/a64_seed_emu" verify "$B/seedC0.bin" seed/helix/strand3_trickster/seedC0.c0
printf '  [seedD0] '; "$B/a64_seed_emu" verify "$B/seedD0.bin" seed/helix/strand4_ascetic/seedD0.d0

printf '=== [3/4] NEGATIVE CONTROLS: BAD CHAR & ODD/SHORT NIBBLE IN SOFTWARE EMULATION ===\n'
printf 'ZZ\n' > "$B/bad_char.in"
printf 'a\n'  > "$B/odd_nib.in"

printf '  [seed0  bad=4  ] '; "$B/a64_seed_emu" run "$B/seed0.bin"  "$B/bad_char.in" 4
printf '  [seed0  odd=1  ] '; "$B/a64_seed_emu" run "$B/seed0.bin"  "$B/odd_nib.in"  1
printf '  [seedB0 bad=5  ] '; "$B/a64_seed_emu" run "$B/seedB0.bin" "$B/bad_char.in" 5
printf '  [seedB0 odd=6  ] '; "$B/a64_seed_emu" run "$B/seedB0.bin" "$B/odd_nib.in"  6
printf '  [seedC0 bad=11 ] '; "$B/a64_seed_emu" run "$B/seedC0.bin" "$B/bad_char.in" 11
printf '  [seedC0 odd=12 ] '; "$B/a64_seed_emu" run "$B/seedC0.bin" "$B/odd_nib.in"  12
printf '  [seedD0 bad=21 ] '; "$B/a64_seed_emu" run "$B/seedD0.bin" "$B/bad_char.in" 21
printf '  [seedD0 odd=22 ] '; "$B/a64_seed_emu" run "$B/seedD0.bin" "$B/odd_nib.in"  22

printf '=== [4/4] NEGATIVE CONTROL: POISONED INSTRUCTION WORD REJECTED FAIL-CLOSED ===\n'
cp "$B/seed0.bin" "$B/seed0_poison.bin"
# Overwrite first instruction word at offset 120 (0x78) with 0x00000000 (UDF #0, disallowed!)
printf '\000\000\000\000' | dd of="$B/seed0_poison.bin" bs=1 seek=120 conv=notrunc 2>/dev/null
set +e
"$B/a64_seed_emu" verify "$B/seed0_poison.bin" seed/rung0/seed0.hex > "$B/poison.out" 2> "$B/poison.err"
prc=$?
set -e
[ "$prc" -eq 10 ] || bad "poisoned instruction expected exit 10, got $prc (stderr: $(cat "$B/poison.err"))"
printf '  PASS poisoned instruction (UDF 0x00000000 at +120) rejected fail-closed (exit 10): %s\n' "$(cat "$B/poison.err")"

printf '\nA64_SEED_EMU PASS seeds=4/4 self_emu=EXACT bad_char=4/4 odd_nib=4/4 poison_reject=PASS\n'
