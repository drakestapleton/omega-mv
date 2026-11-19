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

# r15_receipt.sh -- write the R15 receipt (spec/r15-performance-proof.md §12,
# §13, §14) from one qualification run directory.
#
#   tools/r15_receipt.sh <raw-dir> <out-dir> [candidate-commit] [reruns.json] [notes.tsv]
#
# Inputs, all read, none changed:
#   <raw-dir>/summary.json   the reducer output (every metric, comparison, CI,
#                            gate threshold and gate outcome)
#   <raw-dir>/machine.json   hardware identity and commits (§13), written by
#                            tools/r15_qualify.sh at run time
#   <raw-dir>/SHA256SUMS     the raw file digests
#   <raw-dir>/build-provenance.json, final-state.json and
#                            PROVENANCE_SHA256SUMS bind the archived sources,
#                            toolchain, sealed executables and final tree state
#   candidate-commit         the commit proposed for R15 (default: env
#                            OMEGA_CANDIDATE_COMMIT; empty = not candidate-bound)
#   reruns.json              the §14 correctness reruns (+ §16 item 9 SEQ parity)
#                            as one JSON object, e.g. {"R3":"PASS",...}; absent =
#                            not done
#   notes.tsv                human-written, tab-separated lines (# = comment):
#                              regression<TAB>metric<TAB>resident<TAB>SEQ<TAB>justification
#                              limit<TAB>text
#                            every metric where the resident path is worse
#                            than SEQ (spec §11) and the receipt's stated
#                            limits; values are copied from summary.json by
#                            hand and cited, never used to decide the outcome
#
# Output: <out-dir>/<sha256>.json, schema AIEN_RX_R15_REACTION_PERFORMANCE_V1,
# named by the SHA-256 of its own bytes. The path is printed on stdout.
#
# No number is computed or edited here: summary.json and machine.json are
# embedded byte for byte. The writer only decides the outcome:
#   PASS only if every gate G1-G16 is PASS (all_gates_pass true), the raw
#   directory verifies against SHA256SUMS and the reducer's raw digest, the
#   run is candidate-bound (run commit == candidate, clean initial/final tree,
#   archive-built binaries unchanged through execution), silicon was observed,
#   aienos and physics commits equal the pins at the run commit, and every
#   required correctness rerun is PASS. Anything else is FAIL, with reasons.
# Shell, coreutils, git and the seeded Omega compiler. No jq, Python or C is
# introduced on this path; reruns.json is parsed by seed/json/json.om.
set -u
export GIT_NO_REPLACE_OBJECTS=1 GIT_GRAFT_FILE=/nonexistent/r15-receipt-grafts

RAW=${1:?raw run directory}
OUTDIR=${2:?output directory}
CANDIDATE=${3:-${OMEGA_CANDIDATE_COMMIT:-}}
RERUNS=${4:-}
NOTES=${5:-}
HERE=$(cd "$(dirname "$0")/.." && pwd)

# A run stopped by the instrument preflight is BLOCKED_INSTRUMENT: the run never
# measured anything, so there is nothing to receipt. Refuse, write nothing.
if [ -s "$RAW/instrument-unavailable.txt" ]; then
    echo "r15_receipt: BLOCKED_INSTRUMENT: this run stopped before any trial (instrument unavailable); no receipt written. $(sed -n 2p "$RAW/instrument-unavailable.txt")" >&2
    exit 4
fi
SUM=$RAW/summary.json
MACH=$RAW/machine.json
PROV=$RAW/build-provenance.json
FINAL=$RAW/final-state.json
PROV_SUMS=$RAW/PROVENANCE_SHA256SUMS
for f in "$SUM" "$MACH" "$RAW/SHA256SUMS"; do
    [ -s "$f" ] || { echo "r15_receipt: missing $f" >&2; exit 2; }
done
mkdir -p "$OUTDIR" || exit 2

REQUIRED_RERUNS="R3 R7 R8 R9 R10 R11 R12_host R12_silicon R13_host R13_silicon R14_host R14_silicon R15_SEQ_parity"

# ---- small readers (flat keys only; the inputs are written by our own tools)
mstr() { grep -o "\"$1\":\"[^\"]*\"" "$MACH" | head -1 | sed 's/^"[^"]*":"//; s/"$//'; }
mraw() { grep -o "\"$1\":[^,}]*" "$MACH" | head -1 | sed 's/^"[^"]*"://'; }
sraw() { grep -o "\"$1\":[^,}]*" "$SUM" | tail -1 | sed 's/^"[^"]*"://'; }
fstr() { grep -o "\"$2\":\"[^\"]*\"" "$1" 2>/dev/null | head -1 | sed 's/^"[^"]*":"//; s/"$//'; }
fraw() { grep -o "\"$2\":[^,}]*" "$1" 2>/dev/null | head -1 | sed 's/^"[^"]*"://'; }
fobj() { grep -o "\"$2\":{[^}]*}" "$1" 2>/dev/null | head -1 | sed 's/^"[^"]*"://'; }
jstr() { printf '"%s"' "$(printf '%s' "$1" | tr -d '"\\' | tr '\n' ' ')"; }
is_sha256() { [[ "$1" =~ ^[0-9a-f]{64}$ ]]; }
is_commit() { [[ "$1" =~ ^[0-9a-f]{40}$ ]]; }

REASONS=()
fail() { REASONS+=("$1"); }

RUN_ID=$(mstr run_id)
MODE=$(mstr mode)
RUN_COMMIT=$(mstr candidate_commit)          # qualify.sh records HEAD at run time here
TREE_DIRTY=$(mraw tree_dirty)
AIENOS=$(mstr aienos_commit)
PHYSICS=$(mstr physics_commit)
REDUCER_SRC=$(mstr reducer_source_sha256)
BINARIES=$(grep -o '"binaries":{[^}]*}' "$MACH" | sed 's/^"binaries"://')
PROV_SCHEMA=$(fstr "$PROV" schema)
PROV_COMMIT=$(fstr "$PROV" candidate_commit)
PROV_CANDIDATE_ARCHIVE=$(fstr "$PROV" candidate_archive_sha256)
PROV_PHYSICS=$(fstr "$PROV" physics_commit)
PROV_PHYSICS_ARCHIVE=$(fstr "$PROV" physics_archive_sha256)
PROV_AIENOS=$(fstr "$PROV" aienos_commit)
PROV_AIENOS_ARCHIVE=$(fstr "$PROV" aienos_archive_sha256)
PROV_BUILD_COMMAND=$(fstr "$PROV" build_command)
PROV_COMPILER=$(fstr "$PROV" compiler_sha256)
PROV_MAKE=$(fstr "$PROV" make_sha256)
PROV_BUILD_LOG=$(fstr "$PROV" build_log_sha256)
PROV_BINARIES=$(fobj "$PROV" binaries)
PROV_TRIAL=$(fstr "$PROV" trial)
PROV_NODIGEST=$(fstr "$PROV" nodigest)
PROV_REDUCER=$(fstr "$PROV" reducer)
FINAL_SCHEMA=$(fstr "$FINAL" schema)
FINAL_COMMIT=$(fstr "$FINAL" candidate_commit)
FINAL_HEAD=$(fstr "$FINAL" final_head)
FINAL_DIRTY=$(fraw "$FINAL" tracked_tree_dirty)
FINAL_HEAD_UNCHANGED=$(fraw "$FINAL" head_unchanged)
FINAL_BINARIES_UNCHANGED=$(fraw "$FINAL" binaries_unchanged)
FINAL_BINARIES=$(fobj "$FINAL" binaries)
SCHEMA_IN=$(grep -o '"schema":"[^"]*"' "$SUM" | head -1 | sed 's/.*:"//; s/"$//')
ALL_PASS=$(sraw all_gates_pass)
DIGEST_CLAIMED=$(grep -o '"raw_digest_sha256_of_SHA256SUMS":"[0-9a-f]*"' "$SUM" | sed 's/.*:"//; s/"$//')
DIGEST_ACTUAL=$(sha256sum "$RAW/SHA256SUMS" | cut -d' ' -f1)
GATES=$(grep -o '"gates":\[[^]]*\]' "$SUM" | sed 's/^"gates"://')

[ "$SCHEMA_IN" = AIEN_RX_R15_SUMMARY_V1 ] || fail "summary.json schema is '$SCHEMA_IN', not AIEN_RX_R15_SUMMARY_V1"
[ -n "$GATES" ] || fail "summary.json has no gate table"
RUN_COMMIT_OK=true
is_commit "$RUN_COMMIT" || { RUN_COMMIT_OK=false; fail "run commit is missing or malformed"; }
MODE_OK=true
case "$MODE" in host|silicon) ;; *) MODE_OK=false; fail "run mode '$MODE' is invalid";; esac

# ---- gates (§11): every one of G1-G16 present and PASS
NGATES=0
for g in $(seq 1 16); do
    ent=$(printf '%s' "$GATES" | grep -o "{\"id\":\"G$g\"[^}]*}")
    if [ -z "$ent" ]; then fail "gate G$g missing from summary.json"; continue; fi
    NGATES=$((NGATES + 1))
    out=$(printf '%s' "$ent" | grep -o '"outcome":"[A-Z]*"' | sed 's/.*:"//; s/"$//')
    [ "$out" = PASS ] || fail "gate G$g $out: $(printf '%s' "$ent" | grep -o '"note":"[^"]*"' | sed 's/^"note":"//; s/"$//')"
done
[ "$ALL_PASS" = true ] || fail "reducer reports all_gates_pass=$ALL_PASS"

# ---- raw evidence integrity (§12)
RAW_FILES_OK=false
if (cd "$RAW" && sha256sum --quiet -c SHA256SUMS >/dev/null 2>&1); then RAW_FILES_OK=true
else fail "raw files do not verify against SHA256SUMS"; fi
DIGEST_OK=false
if [ -n "$DIGEST_CLAIMED" ] && [ "$DIGEST_CLAIMED" = "$DIGEST_ACTUAL" ]; then DIGEST_OK=true
else fail "raw digest in summary.json ($DIGEST_CLAIMED) != SHA-256 of SHA256SUMS ($DIGEST_ACTUAL)"; fi

# ---- build and execution provenance
PROV_FILES_OK=false
PROV_DIGEST=""
if [ ! -s "$PROV_SUMS" ]; then
    fail "PROVENANCE_SHA256SUMS missing"
elif [ "$MODE_OK" != true ]; then
    fail "cannot validate executable provenance for invalid run mode"
elif ! awk -v b1="bin/rx_r15_perf_$MODE" -v b2="bin/rx_r15_perf_${MODE}_nodigest" '
        NF != 2 { bad = 1; next }
        $2 != "build.log" && $2 != "build-provenance.json" && $2 != "final-state.json" &&
            $2 != b1 && $2 != b2 && $2 != "bin/r15_reduce" { bad = 1 }
        { if (++seen[$2] != 1) bad = 1 }
        END { if (NR != 6 || bad) exit 1 }
    ' "$PROV_SUMS"; then
    fail "PROVENANCE_SHA256SUMS has an unexpected, duplicate or malformed path"
elif ! (cd "$RAW" && sha256sum --quiet -c PROVENANCE_SHA256SUMS >/dev/null 2>&1); then
    fail "build provenance files do not verify against PROVENANCE_SHA256SUMS"
else
    MANIFEST_COMPLETE=true
    for rel in build.log build-provenance.json final-state.json \
        "bin/rx_r15_perf_$MODE" "bin/rx_r15_perf_${MODE}_nodigest" bin/r15_reduce; do
        awk -v want="$rel" 'NF == 2 && $2 == want { found = 1 } END { exit !found }' "$PROV_SUMS" \
            || { MANIFEST_COMPLETE=false; fail "$rel missing from PROVENANCE_SHA256SUMS"; }
    done
    if [ "$MANIFEST_COMPLETE" = true ]; then PROV_FILES_OK=true; fi
    PROV_DIGEST=$(sha256sum "$PROV_SUMS" | cut -d' ' -f1)
fi

PROVENANCE_OK=true
[ "$PROV_SCHEMA" = AIEN_RX_R15_BUILD_PROVENANCE_V1 ] || { PROVENANCE_OK=false; fail "build provenance schema is '$PROV_SCHEMA'"; }
[ "$PROV_COMMIT" = "$RUN_COMMIT" ] || { PROVENANCE_OK=false; fail "build provenance commit $PROV_COMMIT != run commit $RUN_COMMIT"; }
[ "$PROV_PHYSICS" = "$PHYSICS" ] || { PROVENANCE_OK=false; fail "build provenance physics commit $PROV_PHYSICS != recorded $PHYSICS"; }
[ "$PROV_AIENOS" = "$AIENOS" ] || { PROVENANCE_OK=false; fail "build provenance aienos commit $PROV_AIENOS != recorded $AIENOS"; }
[ "$PROV_BINARIES" = "$BINARIES" ] || { PROVENANCE_OK=false; fail "build provenance binary hashes differ from machine.json"; }
[ -n "$PROV_BUILD_COMMAND" ] || { PROVENANCE_OK=false; fail "build provenance has no build command"; }
for ent in "candidate archive:$PROV_CANDIDATE_ARCHIVE" "physics archive:$PROV_PHYSICS_ARCHIVE" \
    "aienos archive:$PROV_AIENOS_ARCHIVE" "compiler:$PROV_COMPILER" "make:$PROV_MAKE" \
    "build log:$PROV_BUILD_LOG"; do
    label=${ent%%:*}; value=${ent#*:}
    is_sha256 "$value" || { PROVENANCE_OK=false; fail "$label digest is missing or malformed"; }
done
if [ -s "$RAW/build.log" ]; then
    [ "$PROV_BUILD_LOG" = "$(sha256sum "$RAW/build.log" | cut -d' ' -f1)" ] \
        || { PROVENANCE_OK=false; fail "build log digest differs from build provenance"; }
else
    PROVENANCE_OK=false; fail "build.log missing"
fi
if [ "$MODE_OK" = true ]; then
    for ent in "bin/rx_r15_perf_$MODE:$PROV_TRIAL" \
        "bin/rx_r15_perf_${MODE}_nodigest:$PROV_NODIGEST" "bin/r15_reduce:$PROV_REDUCER"; do
        rel=${ent%%:*}; expected=${ent#*:}
        if ! is_sha256 "$expected"; then
            PROVENANCE_OK=false; fail "$rel digest is missing or malformed"
        elif [ ! -f "$RAW/$rel" ] || [ "$(sha256sum "$RAW/$rel" | cut -d' ' -f1)" != "$expected" ]; then
            PROVENANCE_OK=false; fail "$rel does not match the source-to-binary manifest"
        fi
    done
else
    PROVENANCE_OK=false
fi

FINAL_OK=true
[ "$FINAL_SCHEMA" = AIEN_RX_R15_FINAL_STATE_V1 ] || { FINAL_OK=false; fail "final state schema is '$FINAL_SCHEMA'"; }
[ "$FINAL_COMMIT" = "$RUN_COMMIT" ] || { FINAL_OK=false; fail "final state commit $FINAL_COMMIT != run commit $RUN_COMMIT"; }
[ "$FINAL_HEAD" = "$RUN_COMMIT" ] || { FINAL_OK=false; fail "final HEAD $FINAL_HEAD != run commit $RUN_COMMIT"; }
[ "$FINAL_DIRTY" = false ] || { FINAL_OK=false; fail "run tree was dirty at final seal"; }
[ "$FINAL_HEAD_UNCHANGED" = true ] || { FINAL_OK=false; fail "HEAD did not remain unchanged through the run"; }
[ "$FINAL_BINARIES_UNCHANGED" = true ] || { FINAL_OK=false; fail "an executed binary changed during the run"; }
[ "$FINAL_BINARIES" = "$BINARIES" ] || { FINAL_OK=false; fail "final binary hashes differ from machine.json"; }

SILICON=false
if [ "$MODE" = silicon ]; then SILICON=true
elif [ "$MODE_OK" = true ]; then fail "run mode is '$MODE', not silicon"
fi

# ---- pinned dependencies (aienos.lock / physics.lock at the run commit)
AIENOS_LOCK=""; PHYSICS_LOCK=""
if [ "$RUN_COMMIT_OK" = true ]; then
    AIENOS_LOCK=$(git -C "$HERE" show "$RUN_COMMIT:aienos.lock" 2>/dev/null | tr -d '[:space:]')
    PHYSICS_LOCK=$(git -C "$HERE" show "$RUN_COMMIT:physics.lock" 2>/dev/null | tr -d '[:space:]')
fi
DEPENDENCIES_OK=true
[ "$RUN_COMMIT_OK" = true ] || DEPENDENCIES_OK=false
if [ -z "$AIENOS" ]; then DEPENDENCIES_OK=false; fail "aienos_commit not recorded in machine.json"
elif [ "$AIENOS" != "$AIENOS_LOCK" ]; then DEPENDENCIES_OK=false; fail "aienos_commit $AIENOS != aienos.lock $AIENOS_LOCK"; fi
if [ -z "$PHYSICS" ]; then DEPENDENCIES_OK=false; fail "physics_commit not recorded in machine.json"
elif [ "$PHYSICS" != "$PHYSICS_LOCK" ]; then DEPENDENCIES_OK=false; fail "physics_commit $PHYSICS != physics.lock $PHYSICS_LOCK"; fi

# ---- candidate binding: every source, executable and final-state control
BOUND=false
if [ -z "$CANDIDATE" ]; then fail "no candidate commit given"
elif [ "$CANDIDATE" != "$RUN_COMMIT" ]; then fail "run commit $RUN_COMMIT is not the candidate $CANDIDATE"
elif [ "$TREE_DIRTY" != false ]; then fail "run tree was dirty at start"
elif [ "$PROV_FILES_OK" != true ] || [ "$PROVENANCE_OK" != true ] || \
     [ "$FINAL_OK" != true ] || [ "$DEPENDENCIES_OK" != true ]; then :
else BOUND=true; fi

# ---- correctness reruns (§14, §16 item 9)
# Parse before embedding. The schema-specific Omega validator composes the
# repository's strict RFC 8259 reader and rejects non-root, missing, extra,
# duplicate or non-PASS members (including escaped spellings of a duplicate).
if [ -n "$RERUNS" ] && [ -s "$RERUNS" ]; then
    OMC=$HERE/seed/out/omc
    JSON_UNIT=$HERE/seed/json/json.om
    RERUN_UNIT=$HERE/tools/r15_reruns_validate.om
    for f in "$OMC" "$HERE/seed/out/omc.sha256" "$JSON_UNIT" "$RERUN_UNIT"; do
        [ -s "$f" ] || { echo "r15_receipt: missing $f" >&2; exit 2; }
    done
    [ -x "$OMC" ] || { echo "r15_receipt: seeded compiler $OMC is not executable" >&2; exit 2; }
    (cd "$HERE" && sha256sum --quiet -c seed/out/omc.sha256) || {
        echo "r15_receipt: seeded compiler does not match seed/out/omc.sha256" >&2
        exit 2
    }
    # omc and the programs it emits are AArch64. The digest above binds the
    # compiler bytes. On any other machine, qemu-user runs those same bytes.
    OM_PFX=()
    if [ "$(uname -m)" != aarch64 ]; then
        command -v qemu-aarch64 >/dev/null 2>&1 || {
            echo "r15_receipt: seeded compiler is AArch64 and qemu-aarch64 is not installed" >&2
            exit 2
        }
        OM_PFX=(qemu-aarch64 -L /usr/aarch64-linux-gnu)
    fi
    RERUN_CHECK=$(mktemp "$OUTDIR/.r15-reruns-check.XXXXXX") || exit 2
    if ! { printf 'om2\n'; cat "$JSON_UNIT" "$RERUN_UNIT"; } | "${OM_PFX[@]}" "$OMC" > "$RERUN_CHECK"; then
        rm -f "$RERUN_CHECK"
        echo "r15_receipt: cannot build strict rerun validator" >&2
        exit 2
    fi
    chmod 700 "$RERUN_CHECK" || { rm -f "$RERUN_CHECK"; exit 2; }
    "${OM_PFX[@]}" "$RERUN_CHECK" < "$RERUNS"
    RERUN_RC=$?
    rm -f "$RERUN_CHECK"
    if [ "$RERUN_RC" = 0 ]; then
        RERUN_JSON=$(tr -d '\r\n' < "$RERUNS")
    elif [ "$RERUN_RC" = 1 ]; then
        RERUN_JSON='{"status":"invalid"}'
        fail "correctness reruns must be one exact root object with every required key once and string value PASS"
    else
        echo "r15_receipt: rerun validator failed with exit $RERUN_RC" >&2
        exit 2
    fi
else
    RERUN_JSON='{"status":"not done"}'
    fail "correctness reruns (§14) not recorded"
fi

# ---- RES-1-NODIGEST flag, checked from raw (every process records
# causal_digest): the NODIGEST measurement build must have digests off
# (0) and every other process (RES-4, RES-1, SEQ trials, L2) must have them on.
ND_OK=true; ND_FILES=0; PROD_FILES=0
for f in "$RAW"/trial-*.jsonl "$RAW"/l2-*.jsonl; do
    [ -e "$f" ] || continue
    vals=$(grep -o '"causal_digest":[0-9]*' "$f" | sort -u | sed 's/.*://' | paste -sd, -)
    case $(basename "$f") in
        trial-RES1ND-*) ND_FILES=$((ND_FILES + 1)); want=0 ;;
        *)              PROD_FILES=$((PROD_FILES + 1)); want=1 ;;
    esac
    if [ "$vals" != "$want" ]; then
        ND_OK=false
        fail "$(basename "$f"): causal_digest values '$vals', expected $want"
    fi
done
[ "$ND_FILES" -gt 0 ] || { ND_OK=false; fail "no RES-1-NODIGEST trial files found"; }

OUTCOME=FAIL
[ ${#REASONS[@]} -eq 0 ] && OUTCOME=PASS

# ---- regressions: every failed gate, with its value and threshold
REGR=$(printf '%s' "$GATES" | grep -o '{"id":"G[0-9]*"[^}]*"outcome":"FAIL"[^}]*}' \
    | sed 's/}$/,"justification":"none: a failed gate means no PASS (spec §11)"}/' | paste -sd, -)

# ---- human-written regressions (spec §11) and stated limits
NOTE_REGR=""; LIMITS=""
if [ -n "$NOTES" ]; then
    [ -s "$NOTES" ] || { echo "r15_receipt: notes file $NOTES missing or empty" >&2; exit 2; }
    while IFS=$'\t' read -r kind a b c d; do
        case $kind in
            regression)
                e="{\"metric\":$(jstr "$a"),\"resident\":$(jstr "$b"),\"seq\":$(jstr "$c"),\"justification\":$(jstr "$d")}"
                NOTE_REGR=${NOTE_REGR:+$NOTE_REGR,}$e ;;
            limit)
                LIMITS=${LIMITS:+$LIMITS,}$(jstr "$a") ;;
            ''|'#'*) ;;
            *) echo "r15_receipt: bad notes line kind '$kind'" >&2; exit 2 ;;
        esac
    done < "$NOTES"
fi
[ -n "$NOTE_REGR" ] && REGR=${REGR:+$REGR,}$NOTE_REGR

reasons_json() {
    local first=1 r
    printf '['
    for r in "${REASONS[@]}"; do
        [ $first = 1 ] || printf ','
        first=0
        jstr "$r"
    done
    printf ']'
}

TMP=$(mktemp "$OUTDIR/.r15-receipt.XXXXXX") || exit 2
{
    printf '{\n'
    printf '  "schema": "AIEN_RX_R15_REACTION_PERFORMANCE_V1",\n'
    printf '  "run_id": %s,\n' "$(jstr "$RUN_ID")"
    printf '  "outcome": "%s",\n' "$OUTCOME"
    printf '  "outcome_reasons": %s,\n' "$(reasons_json)"
    printf '  "candidate_commit": %s,\n' "$(jstr "$CANDIDATE")"
    printf '  "run_commit": %s,\n' "$(jstr "$RUN_COMMIT")"
    printf '  "candidate_bound": %s,\n' "$BOUND"
    printf '  "tree_dirty": %s,\n' "${TREE_DIRTY:-null}"
    printf '  "silicon_observed": %s,\n' "$SILICON"
    printf '  "aienos_commit": %s,\n' "$(jstr "$AIENOS")"
    printf '  "aienos_lock": %s,\n' "$(jstr "$AIENOS_LOCK")"
    printf '  "physics_commit": %s,\n' "$(jstr "$PHYSICS")"
    printf '  "physics_lock": %s,\n' "$(jstr "$PHYSICS_LOCK")"
    printf '  "benchmark_binaries_sha256": %s,\n' "${BINARIES:-null}"
    printf '  "provenance_digest_sha256": %s,\n' "$(jstr "$PROV_DIGEST")"
    printf '  "provenance_files_verified": %s,\n' "$PROV_FILES_OK"
    printf '  "build_provenance": '
    if [ -s "$PROV" ]; then tr -d '\n' < "$PROV"; else printf 'null'; fi
    printf ',\n  "final_state": '
    if [ -s "$FINAL" ]; then tr -d '\n' < "$FINAL"; else printf 'null'; fi
    printf ',\n'
    printf '  "raw_digest_sha256": %s,\n' "$(jstr "$DIGEST_ACTUAL")"
    printf '  "raw_digest_matches_reducer": %s,\n' "$DIGEST_OK"
    printf '  "raw_files_verified": %s,\n' "$RAW_FILES_OK"
    printf '  "reducer_source_sha256": %s,\n' "$(jstr "$REDUCER_SRC")"
    printf '  "legacy_status": "NOT DIRECTLY COMPARABLE (spec §2): sovereign-core run_until_complete/step is LLM batched decode; aegis-runtime execute_task is an LLM tool-calling loop; the baseline is the sequential control SEQ",\n'
    printf '  "seq_selector_symbol": "rx_world_init_native_sequential_reference",\n'
    printf '  "nodigest_macro": {"name": "RX_MEASURE_NO_CAUSAL_DIGEST", "used_by": "RES-1-NODIGEST measurement build only", "checked_from_raw": %s, "nodigest_processes_digest_off": %s, "production_processes_digest_on": %s},\n' \
        "$ND_OK" "$ND_FILES" "$PROD_FILES"
    printf '  "gates_present": %s,\n' "$NGATES"
    printf '  "all_gates_pass": %s,\n' "${ALL_PASS:-null}"
    printf '  "gates": %s,\n' "${GATES:-[]}"
    printf '  "correctness_reruns_required": %s,\n' \
        "[$(for k in $REQUIRED_RERUNS; do jstr "$k"; printf ','; done | sed 's/,$//')]"
    printf '  "correctness_reruns": %s,\n' "$RERUN_JSON"
    printf '  "regressions": [%s],\n' "$REGR"
    printf '  "limits": [%s],\n' "$LIMITS"
    printf '  "not_claimed": ["R16", "whole-project performance beyond the measured workloads", "LLM decode or agent-loop performance (the legacy loops, spec §2)", "general cognition", "open-ended synthesis", "energy of anything outside the measured windows"],\n'
    printf '  "hardware_identity": '
    tr -d '\n' < "$MACH"
    printf ',\n  "summary": '
    tr -d '\n' < "$SUM"
    printf '\n}\n'
} > "$TMP"
SHA=$(sha256sum "$TMP" | cut -d' ' -f1)
mv "$TMP" "$OUTDIR/$SHA.json" || exit 2
echo "$OUTDIR/$SHA.json"
[ "$OUTCOME" = PASS ] && exit 0 || exit 1
