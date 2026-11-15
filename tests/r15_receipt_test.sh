#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Drake Stapleton (AIEN / aien-dev)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# r15_receipt_test.sh -- host test for tools/r15_receipt.sh. Runs the writer on
# the recorded attempt-1 raw data (evidence/R15/raw/20260929T020536Z-...) into
# build/, then checks: every §12/§13 required field is present, outcome is
# FAIL (G10 failed, aienos_commit blank, no correctness reruns), the failed
# gate is listed under regressions, historical runs without build provenance
# are not candidate-bound, and the file is named by its own SHA-256.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
RAW=$HERE/evidence/R15/raw/20260929T020536Z-ad8e1f2ea4e4-silicon
OUT=$HERE/build/r15-receipt-test
rm -rf "$OUT"; mkdir -p "$OUT"
FAILS=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; FAILS=$((FAILS + 1)); fi; }

R=$("$HERE/tools/r15_receipt.sh" "$RAW" "$OUT" ad8e1f2ea4e4906ed810c6bd696cc905b801d69a)
rc=$?
check "writer exits 1 (FAIL outcome)" '[ $rc = 1 ]'
check "receipt file written" '[ -s "$R" ]'
check "named by its own SHA-256" '[ "$(basename "$R" .json)" = "$(sha256sum "$R" | cut -d" " -f1)" ]'

for k in schema run_id outcome outcome_reasons candidate_commit run_commit candidate_bound \
    tree_dirty silicon_observed aienos_commit physics_commit benchmark_binaries_sha256 \
    provenance_digest_sha256 provenance_files_verified build_provenance final_state \
    raw_digest_sha256 reducer_source_sha256 legacy_status seq_selector_symbol nodigest_macro \
    gates correctness_reruns regressions limits not_claimed hardware_identity summary \
    hostname machine_id_sha256 kernel midr governor_freq mem_kb gpu secure_boot lockdown \
    perf_event_paranoid thermal_mc compiler binaries metrics comparisons all_gates_pass; do
    check "field $k present" 'grep -q "\"$k\":" "$R"'
done
for m in m1_ m2_ m3_ m4_ m5_ m6_ m7_ m8_ m9_ m10_ m11_ m12_13_14_15_ m16_ m17_; do   # the reducer reports 12-15 together
    check "metric ${m%_} present" 'grep -q "\"$m[a-z0-9_]*\":" "$R"'
done
check "schema AIEN_RX_R15_REACTION_PERFORMANCE_V1" 'grep -q "\"schema\": \"AIEN_RX_R15_REACTION_PERFORMANCE_V1\"" "$R"'
check "outcome == FAIL" 'grep -q "\"outcome\": \"FAIL\"" "$R"'
check "reason names G10" 'grep -q "gate G10 FAIL" "$R"'
check "reason names blank aienos_commit" 'grep -q "aienos_commit not recorded" "$R"'
check "reason names missing reruns" 'grep -q "correctness reruns (§14) not recorded" "$R"'
check "G10 listed under regressions" 'grep -o "\"regressions\": \[.*\"id\":\"G10\"" "$R" >/dev/null'
check "historical run is not provenance-bound" 'grep -q "\"run_commit\": \"ad8e1f2ea4e4906ed810c6bd696cc905b801d69a\"" "$R" && grep -q "\"candidate_bound\": false" "$R" && grep -q "PROVENANCE_SHA256SUMS missing" "$R"'
check "raw digest matches reducer" 'grep -q "\"raw_digest_matches_reducer\": true" "$R" && grep -q "\"raw_files_verified\": true" "$R"'
check "16 gates present" 'grep -q "\"gates_present\": 16" "$R"'
if command -v jq >/dev/null; then
    check "valid JSON (jq)" 'jq -e .outcome "$R" >/dev/null'
else
    echo "note jq not installed: JSON validity not checked"
fi

# A PASS needs everything: flip only the inputs the writer judges and check it
# still refuses without reruns and accepts with them (synthetic copy, build/ only).
SYN=$OUT/syn; mkdir -p "$SYN"; cp "$RAW"/* "$SYN"/
sed -i 's/"outcome":"FAIL"/"outcome":"PASS"/; s/"all_gates_pass":false/"all_gates_pass":true/' "$SYN/summary.json"
sed -i 's/"aienos_commit":""/"aienos_commit":"c8ab65e3ba2fddbe99245f747fdfdb99f6042fd3"/' "$SYN/machine.json"
mkdir "$SYN/bin"
printf 'synthetic trial executable\n' > "$SYN/bin/rx_r15_perf_silicon"
printf 'synthetic nodigest executable\n' > "$SYN/bin/rx_r15_perf_silicon_nodigest"
printf 'synthetic reducer executable\n' > "$SYN/bin/r15_reduce"
chmod 0555 "$SYN/bin/"*
TRIAL_SHA=$(sha256sum "$SYN/bin/rx_r15_perf_silicon" | cut -d' ' -f1)
ND_SHA=$(sha256sum "$SYN/bin/rx_r15_perf_silicon_nodigest" | cut -d' ' -f1)
RED_SHA=$(sha256sum "$SYN/bin/r15_reduce" | cut -d' ' -f1)
BINARIES="{\"trial\":\"$TRIAL_SHA\",\"nodigest\":\"$ND_SHA\",\"reducer\":\"$RED_SHA\"}"
sed -i "s/\"binaries\":{[^}]*}/\"binaries\":$BINARIES/" "$SYN/machine.json"
printf 'synthetic isolated build log\n' > "$SYN/build.log"
BUILD_LOG_SHA=$(sha256sum "$SYN/build.log" | cut -d' ' -f1)
PHYSICS=$(grep -o '"physics_commit":"[^"]*"' "$SYN/machine.json" | sed 's/.*:"//; s/"$//')
H1=$(printf '%064x' 1); H2=$(printf '%064x' 2); H3=$(printf '%064x' 3)
H4=$(printf '%064x' 4); H5=$(printf '%064x' 5)
cat > "$SYN/build-provenance.json" <<EOF
{"schema":"AIEN_RX_R15_BUILD_PROVENANCE_V1","candidate_commit":"ad8e1f2ea4e4906ed810c6bd696cc905b801d69a","candidate_archive_sha256":"$H1","physics_commit":"$PHYSICS","physics_archive_sha256":"$H2","aienos_commit":"c8ab65e3ba2fddbe99245f747fdfdb99f6042fd3","aienos_archive_sha256":"$H3","build_command":"synthetic isolated make","compiler_path":"/usr/bin/gcc","compiler_sha256":"$H4","compiler_version":"synthetic gcc","make_path":"/usr/bin/make","make_sha256":"$H5","make_version":"synthetic make","build_log_sha256":"$BUILD_LOG_SHA","binaries":$BINARIES}
EOF
cat > "$SYN/final-state.json" <<EOF
{"schema":"AIEN_RX_R15_FINAL_STATE_V1","candidate_commit":"ad8e1f2ea4e4906ed810c6bd696cc905b801d69a","final_head":"ad8e1f2ea4e4906ed810c6bd696cc905b801d69a","tracked_tree_dirty":false,"head_unchanged":true,"binaries_unchanged":true,"binaries":$BINARIES}
EOF
(cd "$SYN" && sha256sum build.log build-provenance.json final-state.json \
    bin/rx_r15_perf_silicon bin/rx_r15_perf_silicon_nodigest bin/r15_reduce > PROVENANCE_SHA256SUMS)
# machine.json is covered by SHA256SUMS, and the reducer's raw digest covers
# SHA256SUMS: re-seal both so only the judged inputs differ.
sed -i "s/^[0-9a-f]*  machine.json\$/$(sha256sum "$SYN/machine.json" | cut -d' ' -f1)  machine.json/" "$SYN/SHA256SUMS"
sed -i "s/\"raw_digest_sha256_of_SHA256SUMS\":\"[0-9a-f]*\"/\"raw_digest_sha256_of_SHA256SUMS\":\"$(sha256sum "$SYN/SHA256SUMS" | cut -d' ' -f1)\"/" "$SYN/summary.json"
printf '{' > "$OUT/reruns.json"
for k in R3 R7 R8 R9 R10 R11 R12_host R12_silicon R13_host R13_silicon R14_host R14_silicon R15_SEQ_parity; do
    printf '"%s":"PASS",' "$k" >> "$OUT/reruns.json"; done
sed -i 's/,$/}/' "$OUT/reruns.json"
"$HERE/tools/r15_receipt.sh" "$SYN" "$OUT/syn-out" ad8e1f2ea4e4906ed810c6bd696cc905b801d69a >/dev/null 2>&1
check "all gates PASS but no reruns -> still FAIL" '[ $? = 1 ]'
P=$("$HERE/tools/r15_receipt.sh" "$SYN" "$OUT/syn-out" ad8e1f2ea4e4906ed810c6bd696cc905b801d69a "$OUT/reruns.json")
check "all gates PASS + provenance + reruns PASS -> PASS" '[ $? = 0 ] && grep -q "\"outcome\": \"PASS\"" "$P" && grep -q "\"candidate_bound\": true" "$P" && grep -q "\"provenance_files_verified\": true" "$P"'

printf '{\n' > "$OUT/reruns-formatted.json"
first=1
for k in R15_SEQ_parity R14_silicon R14_host R13_silicon R13_host R12_silicon R12_host R11 R10 R9 R8 R7 R3; do
    [ $first = 1 ] || printf ',\n' >> "$OUT/reruns-formatted.json"
    first=0
    printf '  "%s" : "PASS"' "$k" >> "$OUT/reruns-formatted.json"
done
printf '\n}\n' >> "$OUT/reruns-formatted.json"
F=$("$HERE/tools/r15_receipt.sh" "$SYN" "$OUT/syn-out" ad8e1f2ea4e4906ed810c6bd696cc905b801d69a "$OUT/reruns-formatted.json")
check "reordered whitespace-formatted reruns -> PASS" '[ $? = 0 ] && grep -q "\"outcome\": \"PASS\"" "$F"'

# The rerun input is a security boundary: only the exact root object is
# accepted. The structural fixtures retain enough PASS substrings for the old
# grep loop to accept them; the value fixtures exercise the exact schema.
bad_reruns() { # label file
    label=$1; file=$2
    Q=$("$HERE/tools/r15_receipt.sh" "$SYN" "$OUT/syn-out" ad8e1f2ea4e4906ed810c6bd696cc905b801d69a "$file")
    qrc=$?
    check "$label -> FAIL" '[ $qrc = 1 ] && grep -q "correctness reruns must be one exact root object" "$Q"'
    check "$label -> untrusted JSON not embedded" 'grep -Fq "\"correctness_reruns\": {\"status\":\"invalid\"}" "$Q"'
}

printf '{"reported":' > "$OUT/reruns-nested.json"
cat "$OUT/reruns.json" >> "$OUT/reruns-nested.json"
printf '}' >> "$OUT/reruns-nested.json"
bad_reruns "nested decoy PASS keys" "$OUT/reruns-nested.json"

sed 's/}$/,"R3":"FAIL"}/' "$OUT/reruns.json" > "$OUT/reruns-duplicate.json"
bad_reruns "duplicate conflicting key" "$OUT/reruns-duplicate.json"

sed 's/}$/,"R\\u0033":"FAIL"}/' "$OUT/reruns.json" > "$OUT/reruns-escaped-duplicate.json"
bad_reruns "escaped duplicate key" "$OUT/reruns-escaped-duplicate.json"

sed 's/"R7":"PASS"/"R\\u0033":"FAIL"/' "$OUT/reruns.json" > "$OUT/reruns-escaped-duplicate-13.json"
bad_reruns "decoded duplicate among thirteen keys" "$OUT/reruns-escaped-duplicate-13.json"

sed 's/}$/,"extra":"PASS"}/' "$OUT/reruns.json" > "$OUT/reruns-extra.json"
bad_reruns "extra root key" "$OUT/reruns-extra.json"

sed 's/"R3":"PASS"/"R3":true/' "$OUT/reruns.json" > "$OUT/reruns-nonstring.json"
bad_reruns "non-string PASS value" "$OUT/reruns-nonstring.json"

sed 's/"R3":"PASS"/"R3":"FAIL"/' "$OUT/reruns.json" > "$OUT/reruns-fail.json"
bad_reruns "non-PASS string value" "$OUT/reruns-fail.json"

sed 's/"R3":"PASS",//' "$OUT/reruns.json" > "$OUT/reruns-missing.json"
bad_reruns "missing required key" "$OUT/reruns-missing.json"

sed 's/}$//' "$OUT/reruns.json" > "$OUT/reruns-malformed.json"
bad_reruns "malformed JSON" "$OUT/reruns-malformed.json"

printf '%s{"injected":true}\n' "$(cat "$OUT/reruns.json")" > "$OUT/reruns-trailing.json"
bad_reruns "trailing second value" "$OUT/reruns-trailing.json"

sed 's/"R3":"PASS"/"R3":"\\u0050ASS"/' "$OUT/reruns.json" > "$OUT/reruns-pass-escape.json"
E=$("$HERE/tools/r15_receipt.sh" "$SYN" "$OUT/syn-pass-escape" ad8e1f2ea4e4906ed810c6bd696cc905b801d69a "$OUT/reruns-pass-escape.json")
check "decoded PASS escape -> PASS" '[ $? = 0 ] && grep -q "\"outcome\": \"PASS\"" "$E"'

"$HERE/tools/r15_receipt.sh" "$SYN" "$OUT/syn-out" 0000000000000000000000000000000000000000 "$OUT/reruns.json" >/dev/null
check "wrong candidate -> FAIL" '[ $? = 1 ]'
check "nodigest flag checked from raw" 'grep -q "\"checked_from_raw\": true, \"nodigest_processes_digest_off\": 12, \"production_processes_digest_on\": 46" "$R"'

# Replacing a sealed executable after the run invalidates provenance and can
# never retain candidate_bound, even though machine.json still has the initial digest.
MUT=$OUT/replaced-bin; mkdir -p "$MUT"; cp -a "$SYN"/. "$MUT"/
chmod u+w "$MUT/bin/rx_r15_perf_silicon"; printf 'replacement\n' > "$MUT/bin/rx_r15_perf_silicon"
M=$($HERE/tools/r15_receipt.sh "$MUT" "$OUT/replaced-out" ad8e1f2ea4e4906ed810c6bd696cc905b801d69a "$OUT/reruns.json")
check "replaced executable -> FAIL, not candidate-bound" '[ $? = 1 ] && grep -q "build provenance files do not verify" "$M" && grep -q "\"candidate_bound\": false" "$M"'

# human-written notes: a regression and a limit are copied into the receipt
printf '# test notes\nregression\tL1-A p50 ns\t7376\t4688\ttest justification\nlimit\ttest limit text\n' > "$OUT/notes.tsv"
N=$("$HERE/tools/r15_receipt.sh" "$SYN" "$OUT/syn-notes" ad8e1f2ea4e4906ed810c6bd696cc905b801d69a "$OUT/reruns.json" "$OUT/notes.tsv")
check "notes: still PASS" '[ $? = 0 ]'
check "notes: regression listed" 'grep -q "\"metric\":\"L1-A p50 ns\",\"resident\":\"7376\",\"seq\":\"4688\",\"justification\":\"test justification\"" "$N"'
check "notes: limit listed" 'grep -q "\"limits\": \[\"test limit text\"\]" "$N"'

# a NODIGEST process that kept digests on must fail the receipt (re-sealed)
ND=$OUT/nd; mkdir -p "$ND"; cp -a "$SYN"/. "$ND"/
f=$(ls "$ND"/trial-RES1ND-*.jsonl | head -1); sed -i 's/"causal_digest":0/"causal_digest":1/' "$f"
sed -i "s/^[0-9a-f]*  $(basename "$f")\$/$(sha256sum "$f" | cut -d' ' -f1)  $(basename "$f")/" "$ND/SHA256SUMS"
sed -i "s/\"raw_digest_sha256_of_SHA256SUMS\":\"[0-9a-f]*\"/\"raw_digest_sha256_of_SHA256SUMS\":\"$(sha256sum "$ND/SHA256SUMS" | cut -d' ' -f1)\"/" "$ND/summary.json"
Q=$("$HERE/tools/r15_receipt.sh" "$ND" "$OUT/nd-out" ad8e1f2ea4e4906ed810c6bd696cc905b801d69a "$OUT/reruns.json")
check "NODIGEST process with digests on -> FAIL" '[ $? = 1 ] && grep -q "causal_digest values .1., expected 0" "$Q" && grep -q "\"raw_files_verified\": true" "$Q"'

echo "r15 receipt test: $FAILS failure(s)"
[ $FAILS = 0 ]
