/* SPDX-License-Identifier: Apache-2.0
 * Copyright 2026 Drake Stapleton (AIEN / aien-dev)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/* omega_blackwell_codegen_pf.c: device-resident prefill helper kernels (OWN-30B T3b).
 * IR emission runs in pure seeded OM-2 (om/gpu/cg_pf.om). */
#include "omega_blackwell_codegen_pf.h"
#include "omega_bw_om_ir.h"
#include "omega_native.h"

int omega_blackwell_codegen_pf_copy_prog(BlackwellIRProgram *prog) {
    if (!prog) return -1;
    uint64_t ins[8192], meta[512], rc = 1;
    if (omega2_cg_pf_copy(&rc, ins, 8192u, meta, 512u) != 0 || rc != 0) return -1;
    return omega_bw_ir_from_om(ins, meta, prog);
}
