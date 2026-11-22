#!/bin/sh
# seed/helix/ollm_factory/architect-builder-gate.sh
# Dual-Strand AArch64 Host Verification Gate for the 4-Strand Architect-Builder RLVR Pipeline.
# Zero GPU required; runs completely on AArch64 CPU.
#
# Verifies:
#   1. Regrow Strand A (`seed/out/omc`) & Strand B (`build/helix/A_fast`) from 804B seeds
#   2. Dual-strand identical compilation of `architect_client`, `strand4_attr`, `rlvr_factory`,
#      `bench`, and `ollm` (zero dynamic libraries)
#   3. Exhaustive positive & negative self-checks (`architect_client selfcheck`, `strand4_attr selfcheck`)
#   4. Real 4-strand `OLLMSP01` DNA specialist ensemble (`S1_arith.sp`, `S2_fold.sp`, `S3_rewrite.sp`,
#      `S4_repair.sp`) trained on a frozen base checkpoint with bit-exact `speval`, live 4-strand
#      `ollm spclip MODE=1 (S=4)` multi-helix inference, and all 3 tamper controls (`rc=60/61/62`)
#   5. Complete end-to-end offline cycle via `architect-builder-cycle.sh --offline`
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
cd "$R"

bad() { printf 'ARCH_BUILD_GATE FAIL: %s\n' "$*" >&2; exit 1; }
sha() { sha256sum "$1" | cut -d' ' -f1; }

B=build/ab4-gate
rm -rf "$B"
mkdir -p "$B/bin" "$B/spec" "$B/cycle"

printf '=== [1/5] REGROW STRAND A & STRAND B FROM 804B SEEDS ===\n'
sh seed/helix/helix-from-seeds.sh
OMC_A=seed/out/omc
OMC_B=build/helix/A_fast
cp "$OMC_A" "$B/bin/omc"
chmod +x "$B/bin/omc"

printf '\n=== [2/5] DUAL-STRAND BUILD OF ARCHITECT-BUILDER TOOLS & OLLM ===\n'
for item in "architect_client:seed/helix/ollm_factory/architect_client.om" \
            "strand4_attr:seed/helix/ollm_factory/strand4_attr.om" \
            "rlvr_factory:seed/helix/ollm_factory/rlvr_factory.om" \
            "bench:train/omega-llm/tools/bench/bench.om"; do
  name="${item%%:*}"
  src="${item#*:}"
  "$OMC_A" < "$src" > "$B/bin/${name}.A"
  "$OMC_B" < "$src" > "$B/bin/${name}.B"
  cmp -s "$B/bin/${name}.A" "$B/bin/${name}.B" || bad "$name diverged across strands"
  mv "$B/bin/${name}.A" "$B/bin/${name}"
  rm -f "$B/bin/${name}.B"
  chmod +x "$B/bin/${name}"
  printf 'PASS %s dual-strand identical (%s)\n' "$name" "$(sha "$B/bin/${name}")"
done

COMMON="si/directives/om2.om \
  train/omega-llm/native/net/http.om \
  train/omega-llm/native/net/json.om \
  train/omega-llm/native/net/jsonw.om \
  train/omega-llm/native/math.om \
  train/omega-llm/native/data.om \
  train/omega-llm/native/lpool.om \
  train/omega-llm/native/model.om \
  train/omega-llm/native/adam.om \
  train/omega-llm/native/ckpt.om \
  train/omega-llm/native/bpe.om \
  train/omega-llm/native/spec.om \
  train/omega-llm/native/cli.om \
  train/omega-llm/native/lio.om \
  train/omega-llm/native/serve.om \
  train/omega-llm/native/nogpu.om"
cat $COMMON > "$B/bin/ollm_cpu.om"
"$OMC_A" < "$B/bin/ollm_cpu.om" > "$B/bin/ollm.A"
"$OMC_B" < "$B/bin/ollm_cpu.om" > "$B/bin/ollm.B"
cmp -s "$B/bin/ollm.A" "$B/bin/ollm.B" || bad "ollm diverged across strands"
mv "$B/bin/ollm.A" "$B/bin/ollm"
rm -f "$B/bin/ollm.B"
chmod +x "$B/bin/ollm"
printf 'PASS ollm dual-strand identical (%s)\n' "$(sha "$B/bin/ollm")"

printf '\n=== [3/5] POSITIVE & NEGATIVE SELF-CHECKS ===\n'
"$B/bin/architect_client" selfcheck
"$B/bin/strand4_attr" selfcheck

printf '\n=== [4/5] 4-STRAND OLLMSP01 ENSEMBLE + LIVE 4-STRAND SPCLIP (MODE=1, S=4) + TAMPER ===\n'
OLLM="$B/bin/ollm"
SD="$B/spec"
"$B/bin/rlvr_factory" corpus > "$SD/rlvr.bin"
"$B/bin/rlvr_factory" repair > "$SD/repair.bin"
head -c 256 "$SD/rlvr.bin" > "$SD/held.bin"

"$OLLM" init "$SD/base.ck" 256 16 32 2 64 2 2 42 20 5000 1 >/dev/null
BASE_EVAL=$("$OLLM" eval "$SD/base.ck" "$SD/held.bin" 4)

# Train all 4 frozen-core specialist strands (L=2 -> 3) off the identical frozen base
for pair in "S1_arith:rlvr.bin:8:4" \
            "S2_fold:rlvr.bin:10:4" \
            "S3_rewrite:rlvr.bin:12:4" \
            "S4_repair:repair.bin:8:4"; do
  sname="${pair%%:*}"
  rest="${pair#*:}"
  dfile="${rest%%:*}"
  rest2="${rest#*:}"
  steps="${rest2%%:*}"
  bsz="${rest2#*:}"
  "$OLLM" growpro "$SD/base.ck" "$SD/${sname}.ck" 3 40 5000
  S0_EVAL=$("$OLLM" eval "$SD/${sname}.ck" "$SD/held.bin" 4)
  [ "$BASE_EVAL" = "$S0_EVAL" ] || bad "$sname growpro step-0 not bit-identical to base"
  "$OLLM" fcache "$SD/base.ck" "$SD/$dfile" 8 "$SD/${sname}.hc"
  "$OLLM" trainfc "$SD/${sname}.ck" "$SD/${sname}.hc" "$steps" "$bsz" 2 2
  "$OLLM" spext "$SD/base.ck" "$SD/${sname}.ck" "$SD/${sname}.sp"
  PE=$("$OLLM" speval "$SD/base.ck" "$SD/${sname}.sp" "$SD/held.bin" 4)
  CE=$("$OLLM" eval "$SD/${sname}.ck" "$SD/held.bin" 4)
  [ "$(printf '%s' "$PE" | awk '{print $3,$4,$5}')" = "$(printf '%s' "$CE" | awk '{print $3,$4,$5}')" ] || bad "$sname speval mismatch"
  printf '  PASS %s (%s B, bit-exact speval)\n' "$sname" "$(wc -c < "$SD/${sname}.sp" | tr -d ' ')"
done

# Live 4-strand DNA multi-helix spclip (MODE=1 entropy-gated, S=4 strands)
"$OLLM" spclip "$SD/base.ck" 1 "fn solve " 16 0 42 - 4 \
  250 1 "$SD/S1_arith.sp" \
  250 1 "$SD/S2_fold.sp" \
  250 1 "$SD/S3_rewrite.sp" \
  250 1 "$SD/S4_repair.sp" > "$SD/spclip4.out"
printf '  PASS Live 4-strand spclip MODE=1 (S=4, %s bytes emitted)\n' "$(wc -c < "$SD/spclip4.out" | tr -d ' ')"

# Tamper controls (rc=60 truncated, rc=61 1-bit flipped, rc=62 wrong base / swapped link)
head -c 32 "$SD/S1_arith.sp" > "$SD/trunc.sp"
rc=0; "$OLLM" speval "$SD/base.ck" "$SD/trunc.sp" "$SD/held.bin" 4 >/dev/null 2>&1 || rc=$?
[ "$rc" = "60" ] || bad "truncated pack expected rc=60 got $rc"

cp "$SD/S4_repair.sp" "$SD/flip.sp"
printf '\377' | dd of="$SD/flip.sp" bs=1 seek=64 count=1 conv=notrunc 2>/dev/null
rc=0; "$OLLM" speval "$SD/base.ck" "$SD/flip.sp" "$SD/held.bin" 4 >/dev/null 2>&1 || rc=$?
[ "$rc" = "61" ] || bad "flipped pack expected rc=61 got $rc"

"$OLLM" init "$SD/other_base.ck" 256 16 32 2 64 2 2 99 20 5000 1 >/dev/null
rc=0; "$OLLM" speval "$SD/other_base.ck" "$SD/S1_arith.sp" "$SD/held.bin" 4 >/dev/null 2>&1 || rc=$?
[ "$rc" = "62" ] || bad "wrong base expected rc=62 got $rc"
printf '  PASS 4-strand tamper controls: truncated=rc60 flipped=rc61 wrong_base=rc62\n'

printf '\n=== [5/5] END-TO-END OFFLINE 4-STRAND ARCHITECT-BUILDER CYCLE ===\n'
cat > "$B/cycle/tasks.tsv" <<'EOF'
# Synthetic zero-leakage tasks spanning all 4 strands
syn-001	arith	compute 3 times a plus 1 for unsigned input a
syn-002	fold	accumulate weighted sum of array prefix elements
syn-003	rewrite	replace negative-sentinel elements in place with bound
syn-004	branch	clamp unsigned value into closed interval 5 to 99
syn-005	repair	fix missing loop bound and type mismatch in accumulator
EOF

sh seed/helix/ollm_factory/architect-builder-cycle.sh \
  --offline \
  --bin-dir "$B/bin" \
  --work-dir "$B/cycle/run1" \
  --base-ck "$SD/base.ck" \
  --merges - \
  --s1 "$SD/S1_arith.sp" \
  --s2 "$SD/S2_fold.sp" \
  --s3 "$SD/S3_rewrite.sp" \
  --s4 "$SD/S4_repair.sp" \
  --tasks "$B/cycle/tasks.tsv" \
  --min-floor 64

printf '\nARCH_BUILD_4STRAND_GATE PASS dual_strand=5/5 selfchecks=2/2 spclip_4strand=PASS tamper=3/3 offline_cycle=PASS\n'
