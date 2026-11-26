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

# M21 OMEGA_AUTODIFF mutation sweep. For each rule marked MUT:<name> in
# src/autodiff, copy the sources to a scratch directory, break that one
# rule, rebuild the CPU test against the copy and require the test to FAIL.
# A mutation that does not apply, does not build, or that the tests do not
# catch, fails the sweep. The source tree is never edited. CPU only, no
# device. Shell only (no Python).
set -u
cd "$(dirname "$0")/.." || exit 2
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/autodiff-mut.XXXXXX") || exit 2
trap 'rm -rf "$SCRATCH"' EXIT INT TERM

# name|file|sed expression (applied only to the line carrying MUT:<name>)
# DIV_FORMULA computes gb as -((g * y) / b) instead of -(g * (y / b)): the same
# real number with the same rounding count, so it stays inside the per-op
# contract and the 1e-3 FD bound; it is aimed at the bit-exact layer.
MUTATIONS='TAPE_WALK|omega_autodiff.om|{n;s/ad_bwd_visit sub root k/ad_bwd_visit k/;}
ACCUMULATE|omega_autodiff.om|{n;s/ot_binary OT_TB_ADD get ad_nodes add nb 10 get ad_nodes add nb 11 cs cg sum_h/ot_contiguous cs cg sum_h/;}
UNBROADCAST|gradient_shape.om|{n;s/if and eq get target axis 1 ne get source add leading axis 1/if false/;}
SUB_NEGATE|omega_autodiff.om|{n;s/-1\.0f32/1.0f32/;}
MUL_OPERAND|omega_autodiff.om|{n;s/ad_bwd_mul_side in0 in1/ad_bwd_mul_side in0 in0/;}
MATMUL_TRANSPOSE|omega_autodiff.om|{n;s/ot_matmul gs gg get tmp 0 get tmp 1 c/ot_matmul gs gg get ad_nodes add nbb 8 get ad_nodes add nbb 9 c/;}
SQRT_TWICE|omega_autodiff.om|{n;s/ot_binary OT_TB_ADD vs vg vs vg tmp/ot_contiguous vs vg tmp/;}
MEAN_DIVISOR|omega_autodiff.om|{n;s/f32 axlen/f32 add axlen 1/;}
MAX_ROUTE|omega_autodiff.om|{n;s/ret gt a b/ret lt a b/;}
MAX_TIE|omega_autodiff.om|{n;s/ret gt a b/ret ge a b/;}
DIV_B_SIGN|omega_autodiff.om|{n;s/-1\.0f32/1.0f32/;}
DIV_FORMULA|omega_autodiff.om|{n;s/ot_binary OT_TB_DIV ys yg bs bg tmp/ot_binary OT_TB_MUL gs gg ys yg tmp/;s/ot_binary OT_TB_MUL gs gg get tmp 0 get tmp 1 c2/ot_binary OT_TB_DIV get tmp 0 get tmp 1 bs bg c2/;}'

# Runs on the shared runner tools/mutation_runner.sh (marker reader) using pure
# seeded OM-2 (seed/out/omc), zero C compiler and zero external bridge checkout.
OMC=${AUTODIFF_OMC:-seed/out/omc}
OM_SRCS="src/tensor/tensor_shape.om src/tensor/tensor_ops.om src/train/tg_sha256.om src/tensor/omega_tensor_cpu.om src/tensor/omega_tensor.om src/autodiff/gradient_shape.om src/autodiff/omega_autodiff.om src/autodiff/test_autodiff.om"
BUILD="(printf 'om2\n'; sed -e '/^om2$/d' -e 's/^export fn /fn /' $OM_SRCS) | $OMC > t && chmod +x t"
printf '%s\n' "$MUTATIONS" | sed 's#^\([A-Z_]*\)|#\1|src/autodiff/#' > "$SCRATCH/rows"
tools/mutation_runner.sh -k marker -m "$SCRATCH/rows" -d . -c "src/tensor src/train/tg_sha256.om src/autodiff $OMC" \
    -b "$BUILD" -t ./t -f FAIL -B > "$SCRATCH/runner.out" 2> "$SCRATCH/runner.err"
if grep -q 'unmutated baseline' "$SCRATCH/runner.out"; then
    cat "$SCRATCH/runner.err"
    echo "autodiff mutation sweep: FAIL (unmutated baseline does not pass)"; exit 1
fi
fail=0
total=0
while IFS= read -r line; do
    case $line in
        *' KILLED '*|*' SURVIVED '*|*' ERROR '*) ;;
        *) continue;;
    esac
    name=${line%% *}
    rest=${line#* }; status=${rest%% *}
    note=${line#* (}; note=${note%)}
    total=$((total + 1))
    case $status in
        KILLED)
            n=0
            case $note in *' failing case(s)'*) n=${note%% failing case(s)*};; esac
            echo "MUTATION $name: caught ($n failing checks)";;
        SURVIVED) echo "MUTATION $name: NOT CAUGHT (tests still pass)"; fail=1;;
        *)
            case $note in
                'edit did not apply'*) echo "MUTATION $name: NOT APPLIED (marker or pattern missing)";;
                *) echo "$note"; echo "MUTATION $name: does not build (fix the sed expression)";;
            esac
            fail=1;;
    esac
done < "$SCRATCH/runner.err"
if [ "$total" -lt 5 ]; then echo "autodiff mutation sweep: FAIL (fewer than 5 mutations)"; exit 1; fi
if [ "$fail" -ne 0 ]; then echo "autodiff mutation sweep: FAIL"; exit 1; fi
echo "autodiff mutation sweep: PASS ($total of $total mutations caught)"
