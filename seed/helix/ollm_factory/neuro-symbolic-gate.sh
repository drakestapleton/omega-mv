#!/bin/sh
# seed/helix/ollm_factory/neuro-symbolic-gate.sh
# Pure Seeded OM-2 AArch64 Host Verification Gate for the Neuro-Symbolic
# Observational-Equivalence Synthesizer, SM121 Kernel Contract, Wake-Sleep
# Combinator Miner, Zero-Weight Idiom Retriever, and Dual-Pass Formalizer.
# Zero GPU required; zero expect.txt leakage; zero C/Python in the engines.
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
cd "$R"

bad() { printf 'NEURO_SYM_GATE FAIL: %s\n' "$*" >&2; exit 1; }
sha() { sha256sum "$1" | cut -d' ' -f1; }

B=build/neuro-sym-gate
rm -rf "$B"
mkdir -p "$B/bin" "$B/work"

OMC=seed/out/omc
[ -x "$OMC" ] || bad "seed/out/omc missing (run sh seed/omega-from-seed.sh)"

printf '=== [1/5] COMPILE PURE SEEDED OM-2 MODULES WITH seed/out/omc ===\n'
for name in om_synth om_synth_sm121 om_sketch om_retriever om_formalize; do
  src="seed/helix/ollm_factory/${name}.om"
  "$OMC" < "$src" > "$B/bin/$name" || bad "omc failed on $src"
  chmod +x "$B/bin/$name"
  printf 'PASS %s (%s)\n' "$name" "$(sha "$B/bin/$name")"
done
"$OMC" < train/omega-llm/tools/bench/bench.om > "$B/bin/bench" || bad "omc failed on bench.om"
chmod +x "$B/bin/bench"

printf '\n=== [2/5] MODULE SELF-CHECKS ===\n'
"$B/bin/om_synth" selfcheck || bad "om_synth selfcheck failed"
"$B/bin/om_synth_sm121" layout || bad "om_synth_sm121 layout failed"
"$B/bin/om_synth_sm121" selfcheck || bad "om_synth_sm121 selfcheck failed"
"$B/bin/om_sketch" selfcheck || bad "om_sketch selfcheck failed"
"$B/bin/om_retriever" selfcheck || bad "om_retriever selfcheck failed"
"$B/bin/om_formalize" selfcheck || bad "om_formalize selfcheck failed"

printf '\n=== [3/5] WAKE-SLEEP COMBINATOR MINING + OMC COMPILE + ZERO LEAKAGE ===\n'
"$B/bin/om_synth" mine "$B/work/mined_lib.om" || bad "om_synth mine failed"
{ echo "om2"; tr '\0' '\n' < "$B/work/mined_lib.om"; echo "fn main to int"; echo "ret 0"; echo "end"; } | "$OMC" > "$B/work/mined_test" || bad "mined_lib failed omc compile"
SEEN_OUT=$("$B/bin/bench" seen train/omega-llm/tools/bench/tasks.om "$B/work/mined_lib.om")
printf '%s\n' "$SEEN_OUT"
printf '%s\n' "$SEEN_OUT" | grep -q 'SEENSUM tasks 165 seen 0 ' || bad "mined_lib leaked benchmark task"

printf '\n=== [4/5] RETRIEVER ON WAKE-SLEEP MINED COMBINATORS ===\n'
printf 'note round down to multiple of 14\nfn solve a ulong to ulong\n' > "$B/work/q1.om"
"$B/bin/om_retriever" retrieve "$B/work/mined_lib.om" "$B/work/q1.om" 2 500 "$B/work/q1_out.om" || bad "retriever failed"
grep -q 'fn lib_comb_0' "$B/work/q1_out.om" || bad "retriever missed mined combinator"

printf '\n=== [5/5] ZERO-LEAKAGE DUAL-PASS FORMALIZE -> OM_SYNTH -> OMC ===\n'
printf 'note return the argument rounded down to a multiple of 14\nfn solve a ulong to ulong\n' > "$B/work/p_syn.om"
"$B/bin/om_formalize" formalize "$B/work/p_syn.om" "$B/work/p_syn.spec" || bad "formalize failed on synthetic spec"
"$B/bin/om_synth" solve "$B/work/p_syn.spec" "$B/work/p_syn_out.om" || bad "om_synth solve failed on formalized spec"
{ echo "om2"; cat "$B/work/p_syn_out.om"; echo "fn main to int"; echo "if ne solve 41 28"; echo "ret 1"; echo "end"; echo "ret 0"; echo "end"; } | "$OMC" > "$B/work/p_syn_bin" || bad "synthesized code failed omc compile"
chmod +x "$B/work/p_syn_bin"
"$B/work/p_syn_bin" || bad "synthesized binary failed execution check"

printf '\nNEURO_SYM_GATE PASS modules=5/5 sm121_invariants=3/3 mined_seen=0 e2e_exec=1\n'
