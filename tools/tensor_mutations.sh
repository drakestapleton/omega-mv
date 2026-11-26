#!/bin/sh
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

# M20 OMEGA_TENSOR mutation sweep, a thin adapter over tools/mutation_runner.sh.
# For each rule marked MUT:<name> in src/tensor/*.c the runner copies the tree
# to a scratch directory, breaks that one rule, rebuilds the CPU test there and
# requires the test to FAIL. A mutation that does not apply, does not build or
# is not caught fails the sweep. The adapter maps the runner verdicts back to
# the legacy stdout lines. CPU only, no device. Shell only (no Python).
set -u
cd "$(dirname "$0")/.." || exit 2
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/tensor-mut.XXXXXX") || exit 2
trap 'rm -rf "$SCRATCH"' EXIT INT TERM

# --gb10 PHYSICS_DIR: the GB10 realization table (src/tensor/omega_tensor_gb10.c,
# M20 cut gb10). Builds tests/test_omega_tensor_gb10.c against the physics
# checkout and runs it WITHOUT --chip (host self checks, no device). Also
# requires, via nm, that the GB10 table references no CPU or reference tier
# (no silent CPU fallback). Each GB10_MUTATIONS rule must then make the host
# run or the nm check fail. Never opens the device.
if [ "${1:-}" = "--gb10" ]; then
    PHYS=${2:-}
    [ -n "$PHYS" ] && [ -d "$PHYS" ] || { echo "tensor gb10 mutation sweep: --gb10 needs the physics checkout"; exit 2; }
    NV=$PHYS/third_party/nvidia-open-580.173.02
    GFLAGS="-std=gnu11 -O2 -Wall -Wextra -Werror -D_GNU_SOURCE -ffp-contract=off -Isrc -I$PHYS/forge -I$PHYS/nvrm -I$PHYS/m16 \
-I$NV/src/common/sdk/nvidia/inc -I$NV/kernel-open/common/inc -I$NV/kernel-open/nvidia-uvm -I$NV/src/nvidia/arch/nvalloc/unix/include"
    GDEPS="src/omega_numeric_reduce.c src/omega_numeric_transc.c src/omega_numeric_reduce_gb10.c src/omega_numeric.c src/omega_numeric_gb10.c \
src/omega_numeric_divsqrt_gb10.c src/omega_numeric_provenance.c src/omega_blackwell_codegen.c src/omega_blackwell_encoder.c \
src/omega_blackwell_matmul.c src/omega_blackwell_qmd.c src/forge_realization.c src/aegis_verification.c src/omega_om_units.c \
$PHYS/forge/forge_descriptor.c $PHYS/forge/forge_realize.c $PHYS/sha256_clean.c $PHYS/nvrm/nvrm.c $PHYS/m16/m16_native.c"
    CPU_TIER='\b(omega_numeric_cpu_realize|omega_numeric_reference|omega_numeric_reference_ftz|omega_reduce_cpu|omega_reduce_rows_cpu|omega_reduce_reference|omega_reduce_rows_reference|omega_tensor_seam_reduce_cpu|omega_tensor_cpu_realization|omega_ds_cpu_semantic|omega_ds_host_exec)\b'
    GB10_MUTATIONS='GB10_NO_CPU_FALLBACK|s/return OMEGA_NUMERIC_ERR_NOT_ENCODED;/return omega_numeric_cpu_realize(op, a, b, c, out, n);/
GB10_TRANSC_NO_CPU_FALLBACK|s/if (k < 0) return OMEGA_NUMERIC_ERR_NOT_ENCODED;/if (k < 0) return omega_tensor_cpu_realization()->transc(op, a, out, n);/
GB10_TRANSC_EXP_LOG_SWAP|s/\[OMEGA_TU_EXP\] = 1 + OMEGA_DS_EXP, \[OMEGA_TU_LOG\] = 1 + OMEGA_DS_LOG,/[OMEGA_TU_EXP] = 1 + OMEGA_DS_LOG, [OMEGA_TU_LOG] = 1 + OMEGA_DS_EXP,/
GB10_REDUCE_MAX_N|s/if (n > OMEGA_REDUCE_GB10_MAX_N) return OMEGA_NUMERIC_ERR_OPERANDS;/(void)0;/
GB10_ROWS_MAX_N|s/if (n > OMEGA_REDUCE_GB10_MAX_N) return OMEGA_NUMERIC_ERR_OPERANDS;/(void)0;/'
    # gb10_try DIR: 0 if build + host run + nm check all pass, 1 otherwise
    gb10_try() {
        gcc $GFLAGS -I"$1" -o "$SCRATCH/g" tests/test_omega_tensor_gb10.c "$1/omega_tensor.c" "$1/omega_tensor_cpu.c" \
            "$1/omega_tensor_reduce_seam.c" "$1/omega_tensor_gb10.c" $GDEPS > "$SCRATCH/gbuild.log" 2>&1 || return 2
        gcc $GFLAGS -I"$1" -c -o "$SCRATCH/g.o" "$1/omega_tensor_gb10.c" >> "$SCRATCH/gbuild.log" 2>&1 || return 2
        if nm -u "$SCRATCH/g.o" | grep -Eq "$CPU_TIER"; then echo "  nm: GB10 table references a CPU/reference tier"; return 1; fi
        "$SCRATCH/g" > "$SCRATCH/grun.log" 2>&1 || return 1
        return 0
    }
    gb10_try src/tensor; rc=$?
    if [ "$rc" -ne 0 ]; then
        head -20 "$SCRATCH/gbuild.log" "$SCRATCH/grun.log" 2>/dev/null
        echo "tensor gb10 mutation sweep: FAIL (unmutated GB10 baseline does not pass, rc $rc)"; exit 1
    fi
    grep -E '^(TENSOR_GB10_HOST|HOST_HARNESS_MUTANTS|HOST_MUTANT_)' "$SCRATCH/grun.log"
    echo "GB10 nm check: PASS (no CPU or reference tier referenced by omega_tensor_gb10.c)"
    gfail=0; gtotal=0
    old_ifs=$IFS
    IFS='
'
    for m in $GB10_MUTATIONS; do
        IFS=$old_ifs
        gname=${m%%|*}; gexpr=${m#*|}
        gtotal=$((gtotal + 1))
        rm -rf "$SCRATCH/tensor" && cp -r src/tensor "$SCRATCH/tensor"
        sed -i "/MUT:$gname/ $gexpr" "$SCRATCH/tensor/omega_tensor_gb10.c"
        if cmp -s src/tensor/omega_tensor_gb10.c "$SCRATCH/tensor/omega_tensor_gb10.c"; then
            echo "MUTATION $gname: NOT APPLIED (marker or pattern missing)"; gfail=1; continue
        fi
        gb10_try "$SCRATCH/tensor"; rc=$?
        case $rc in
            0) echo "MUTATION $gname: NOT CAUGHT (host checks and nm still pass)"; gfail=1 ;;
            2) head -5 "$SCRATCH/gbuild.log"; echo "MUTATION $gname: does not build (fix the sed expression)"; gfail=1 ;;
            *) echo "MUTATION $gname: caught ($(grep -c '^FAIL' "$SCRATCH/grun.log" 2>/dev/null) failing checks)" ;;
        esac
    done
    IFS=$old_ifs
    if [ "$gfail" -ne 0 ]; then echo "tensor gb10 mutation sweep: FAIL"; exit 1; fi
    echo "tensor gb10 mutation sweep: PASS ($gtotal of $gtotal mutations caught)"
    exit 0
fi
OMC=${TENSOR_OMC:-seed/out/omc}
OM_CORE="src/tensor/tensor_shape.om src/tensor/tensor_ops.om src/train/tg_sha256.om src/tensor/omega_tensor_cpu.om src/tensor/omega_tensor_gb10.om src/tensor/omega_tensor.om"
OM_STORE="src/tensor/tensor_shape.om src/tensor/tensor_ops.om src/train/tg_sha256.om src/tensor/omega_tensor_cpu.om src/tensor/omega_tensor.om src/tensor/omega_tensor_store.om"

# name|file|sed expression (applied only to the line carrying MUT:<name>)
# Reduction order and padding mutations live in the E1 WP-D suite
# (test-numeric-reduce-cpu, RED_DIFFERENT_ORDER_CAUGHT): the seam calls it.
MUTATIONS='RELEASE_BUMP|omega_tensor.om|{n;s/add cur 1/cur/;}
STORAGE_GEN_CHECK|omega_tensor.om|{n;s/ret eq get ot_st_gen s g/ret true/;}
BCAST_ZERO_STRIDE|omega_tensor.om|{n;s/put ot_tmp_st d 0/put ot_tmp_st d get ot_ts_strides idx/;}
PERMUTE_STRIDES|omega_tensor.om|{n;s/put ot_tmp_st d get ot_ts_strides idx/put ot_tmp_st d get ot_ts_strides add s8 d/;}
SLICE_OFFSET|omega_tensor.om|{n;s/mul a istr/a/;}
TRANSC_EXP2_LOG2_SWAP|omega_tensor_cpu.om|{n;s/ret ot_math_exp2 x/ret ot_math_log2 x/;}
UNARY_VIEW_STRIDE|omega_tensor.om|{n;s/ot_load_ts_desc s/ot_load_ts_desc s\n  put ot_tmp_st 0 16/;}
TRANSC_EXP_LOG_SWAP|omega_tensor_cpu.om|{n;s/ret ot_math_exp x/ret ot_math_log x/;}
RELU_NEG_ZERO|omega_tensor_cpu.om|{n;s/ret uint 0/if eq u OT_NEG0_BITS\n      ret u\n    end\n    ret uint 0/;}
RELU_NAN_PAYLOAD|omega_tensor_cpu.om|{n;s/ret OT_QNAN_BITS/ret u/;}
TRANSC_RSQRT_ERF_SWAP|omega_tensor_cpu.om|{n;s/ret ot_math_erf x/ret div 1.0f32 fsqrt x/;}
GELU_VIEW_STRIDE|omega_tensor.om|{n;s/ot_load_ts_desc s/ot_load_ts_desc s\n  if eq op OT_TU_GELU\n    put ot_tmp_st 0 16\n  end/;}
TRIG_SIN_COS_SWAP|omega_tensor_cpu.om|{n;s/ret ot_math_sin x/ret ot_math_cos x/;}
TRIG_DOMAIN_NUMBER|omega_tensor_cpu.om|{n;s/ret bitcast f32 OT_QNAN_BITS/ret 0.0f32/;}
ZEROS_NEG0|omega_tensor.om|{n;s/0\.0f32/-0.0f32/;}
NEG_SUB|omega_tensor_cpu.om|{n;s/ret xor u OT_NEG0_BITS/ret bitcast uint sub 0.0f32 bitcast f32 u/;}
NEG_NAN|omega_tensor_cpu.om|{n;s/ret OT_QNAN_BITS/ret xor u OT_NEG0_BITS/;}
FULL_CANON|omega_tensor.om|{n;s/ot_arena_put_f32 dbase i val/if ot_is_nan bitcast uint val\n      ot_arena_put_f32 dbase i bitcast f32 OT_QNAN_BITS\n    else\n      ot_arena_put_f32 dbase i val\n    end/;}
EMBED_START|omega_tensor.om|{n;s/ret long mul a ds_d/ret long mul add a 1 ds_d/;}
EMBED_STEP|omega_tensor.om|{n;s/put ot_tmp_st d mul ds_d st/put ot_tmp_st d ds_d/;}
CONCAT_AXIS_OFFSET|omega_tensor.om|{n;s/mul aoff get ds axis/aoff/;}
CMP_FALSE_NEG_ZERO|omega_tensor_cpu.om|{n;s/ret 0\.0f32/ret bitcast f32 OT_NEG0_BITS/;}
CMP_EQ_NAN_TRUE|omega_tensor_cpu.om|{n;s/ret false/ret true/;}
WHERE_ACCEPTS_HALF|omega_tensor.om|{n;s/if and ne u OT_ONE_BITS ne u uint 0/if eq u uint 0x3f000000\n      continue\n    end\n    if and ne u OT_ONE_BITS ne u uint 0/;}
REDUCE_AXES_DESCENDING|omega_tensor.om|{n;s/d = sub sub rank 1 di/d = di/;}
REDUCE_AXES_KEEPDIMS|omega_tensor.om|{n;s/keepdims = get keep_and_out 2/keepdims = ulong 0/;}
SUM_TO_SHAPE_SIZE1|omega_tensor.om|{n;s/n = add n 1/n = n/;}'

STORE_MUTATIONS='TSTORE_HASH_VERIFY|{n;s/if ne get dig i get ots_sl_psha add mul sl 32 i/if false/;}
TSTORE_SHORT_RECORD|{n;s/if ne jlen add OTS_HDR_BYTES mul cnt OTS_REC_BYTES/if false/;}
TSTORE_GEN_RESET|{n;s/put ots_sl_meta add sb 1 add gen 1/put ots_sl_meta add sb 1 1/;}
TSTORE_RENAME_BEFORE_WRITE|{n;s/fopen ots_pa 0 get ots_plen 0/fopen ots_pb 0 get ots_plen 1/;}
TSTORE_RECORD_SUM|{n;s/if ne get sum k get ots_jbuf add add off 168 k/if false/;}
TSTORE_HEADER_SUM|{n;s/if ne get sum i get ots_jbuf add 24 i/if false/;}'
# The runner reads its own env var ONLY; the legacy sweep never did.
unset ONLY
fail=0
total=0

# run_block ROWSFILE BUILDCMD TESTCMD: run the shared runner (marker reader,
# baseline check on) and print one legacy "MUTATION <name>: ..." line per
# mutant, in row order. Returns 3 if the unmutated baseline does not pass.
# Sets fail=1 if the runner reported fewer or more verdict lines than rows.
run_block() {
    rb_rows=$1
    "tools/mutation_runner.sh" -k marker -m "$rb_rows" -t "$3" -b "$2" -c "src/tensor src/train/tg_sha256.om $OMC" -f FAIL -B \
        > "$SCRATCH/rb.out" 2> "$SCRATCH/rb.err"
    if grep -q 'unmutated baseline does not pass' "$SCRATCH/rb.out"; then
        cat "$SCRATCH/rb.err"; return 3
    fi
    rb_seen=0
    while IFS= read -r rb_l; do
        rb_id=${rb_l%% *}; rb_r=${rb_l#* }; rb_st=${rb_r%% *}
        rb_note=${rb_l#*\(}; rb_note=${rb_note%)}
        total=$((total + 1)); rb_seen=$((rb_seen + 1))
        case $rb_st in
            KILLED)
                rb_n=$(printf '%s\n' "$rb_note" | sed -n 's/^\([0-9][0-9]*\) failing case.*/\1/p')
                echo "MUTATION $rb_id: caught (${rb_n:-0} failing checks)" ;;
            SURVIVED*) echo "MUTATION $rb_id: NOT CAUGHT (tests still pass)"; fail=1 ;;
            *)
                case $rb_note in
                    "build failed"*) echo "$rb_note"; echo "MUTATION $rb_id: does not build (fix the sed expression)" ;;
                    *) echo "MUTATION $rb_id: NOT APPLIED (marker or pattern missing)" ;;
                esac
                fail=1 ;;
        esac
    done < "$SCRATCH/rb.err"
    rb_want=$(grep -c '|' "$rb_rows")
    if [ "$rb_seen" -ne "$rb_want" ]; then
        echo "MUTATION $rb_rows: runner reported $rb_seen verdicts for $rb_want rows (runner died or reported nothing)"
        fail=1
    fi
}

# Main block (pure seeded OM-2).
printf '%s\n' "$MUTATIONS" | sed 's#^\([A-Z0-9_]*\)|#\1|src/tensor/#' > "$SCRATCH/main.rows"
if ! run_block "$SCRATCH/main.rows" \
    "(printf 'om2\n'; sed -e '/^om2$/d' -e 's/^export fn /fn /' $OM_CORE src/tensor/test_tensor.om) | $OMC > .tensor_t && chmod +x .tensor_t" \
    ./.tensor_t; then
    echo "tensor mutation sweep: FAIL (unmutated baseline does not pass)"; exit 1
fi
# M20 receipt writer mutants (MUT: markers in tools/m20_receipt.sh), own sweep.
tools/m20_receipt_mutations.sh || fail=1

# Crash-safe storage lifetime (src/tensor/omega_tensor_store.om): pure seeded OM-2.
printf '%s\n' "$STORE_MUTATIONS" | sed 's#^\([A-Z0-9_]*\)|#\1|src/tensor/omega_tensor_store.om|#' > "$SCRATCH/store.rows"
if ! run_block "$SCRATCH/store.rows" \
    "(printf 'om2\n'; sed -e '/^om2$/d' -e 's/^export fn /fn /' $OM_STORE src/tensor/test_tensor_store.om) | $OMC > .tstore_t && chmod +x .tstore_t" \
    "rm -rf .tstore_d && mkdir -p .tstore_d && ./.tstore_t .tstore_d"; then
    echo "MUTATION store baseline: unmutated store test does not pass"; fail=1
fi

if [ "$fail" -ne 0 ]; then echo "tensor mutation sweep: FAIL"; exit 1; fi
echo "tensor mutation sweep: PASS ($total of $total mutations caught)"
