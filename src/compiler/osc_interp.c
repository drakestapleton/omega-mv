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

/*
 * osc_interp.c -- reference interpreter for the OSC-1 IR (DESIGN section 5).
 * OSC-1 slice; not a general Omega compiler; no self-hosting.
 *
 * Scalar operations use the seeded OSC scalar unit. It reports OSC trap
 * codes to this runtime and executes independently of the native back end.
 */
#include "osc_interp.h"
#include "omega_api_decl.h"

#include <string.h>

typedef struct {
    const OscUnit *u;
    OscRt *rt;
    uint64_t steps;
} Ctx;

static void trap(Ctx *c, unsigned code) { osc_rt_trap(c->rt, code); }

/* element pointer with the bounds rule of section 5 */
static uint64_t *elem(Ctx *c, const OscType *rt_, uint64_t base, OscScalar ti, uint64_t idx) {
    if (osc_scalar_signed(ti) && (int64_t)idx < 0) trap(c, OSC_TRAP_BOUNDS);
    if (idx >= rt_->len) trap(c, OSC_TRAP_BOUNDS);
    /* defensive: a REF must point into the pool (validated IR guarantees it) */
    uintptr_t lo = (uintptr_t)&c->rt->cells[0][0], hi = lo + sizeof c->rt->cells;
    if ((uintptr_t)base < lo || (uintptr_t)base + 8 * (idx + 1) > hi) trap(c, OSC_TRAP_RUNTIME);
    return (uint64_t *)(uintptr_t)base + idx;
}

/* OSC-2 structs: pointer to cell (field off + element idx) of struct ref base;
 * an array field index obeys the same bounds rule as elem() against alen */
static uint64_t *fcell(Ctx *c, const OscType *rt_, uint64_t base, unsigned field, bool has_ix, OscScalar ti,
                       uint64_t idx) {
    const OscField *fd = &c->u->structs[rt_->sid - 1].fields[field];
    uint64_t cell = fd->off;
    if (has_ix) {
        if (osc_scalar_signed(ti) && (int64_t)idx < 0) trap(c, OSC_TRAP_BOUNDS);
        if (idx >= fd->alen) trap(c, OSC_TRAP_BOUNDS);
        cell += idx;
    }
    uintptr_t lo = (uintptr_t)&c->rt->cells[0][0], hi = lo + sizeof c->rt->cells;
    if ((uintptr_t)base < lo || (uintptr_t)base + 8 * (cell + 1) > hi) trap(c, OSC_TRAP_RUNTIME);
    return (uint64_t *)(uintptr_t)base + cell;
}

/* External byte slice access (docs/osc/OSC-EXT-BYTES-DESIGN.md): its own checked path,
 * independent of the pool-range check of elem(). The index is unsigned: a negative signed
 * index is >= 2^63 and fails with every length, len 0 fails for every index (the caller
 * pointer, possibly NULL, is not touched). The buffer belongs to the caller. */
static uint64_t sload(Ctx *c, OscScalar kind, uint64_t ptr, uint64_t len, uint64_t idx) {
    if (idx >= len) trap(c, OSC_TRAP_BOUNDS);
    if (kind == OSC_T_BYTES) return ((const uint8_t *)(uintptr_t)ptr)[idx];
    return ((const uint64_t *)(uintptr_t)ptr)[idx];
}
static void sstore(Ctx *c, uint64_t ptr, uint64_t len, uint64_t idx, uint64_t val) {
    if (idx >= len) trap(c, OSC_TRAP_BOUNDS);
    ((uint64_t *)(uintptr_t)ptr)[idx] = val;
}

static uint64_t run_func(Ctx *c, int fi, const uint64_t *args) {
    const OscFunc *f = &c->u->funcs[fi];
    const OscType *T = f->vtype;
    uint64_t v[OSC_MAX_VREGS];
    memset(v, 0, sizeof(uint64_t) * f->nvregs);
    for (int p = 0; p < f->nparams; p++) v[p] = args[p];
    int b = 0;
    for (;;) {
        const OscBlock *bl = &f->blocks[b];
        int next = -1;
        for (uint32_t i = bl->first; i < bl->first + bl->count; i++) {
            const OscInsn *in = &f->insns[i];
            if (++c->steps > OSC_INTERP_MAX_STEPS) trap(c, OSC_TRAP_RUNTIME);
            switch (in->op) {
            case OSC_I_CONST: v[in->dst] = in->imm; break;
            case OSC_I_MOV: v[in->dst] = v[in->a]; break;
            case OSC_I_BIN: {
                uint64_t code = osc_alu_bin(in->sub, T[in->a].s, v[in->a], v[in->b], &v[in->dst]);
                if (code) trap(c, (unsigned)code);
                break;
            }
            case OSC_I_UN: {
                uint64_t code = osc_alu_un(in->sub, T[in->a].s, v[in->a], &v[in->dst]);
                if (code) trap(c, (unsigned)code);
                break;
            }
            case OSC_I_CMP:
                v[in->dst] = osc_alu_cmp(in->sub, T[in->a].s, v[in->a], v[in->b]);
                break;
            case OSC_I_CAST: {
                uint64_t code = osc_alu_cast(T[in->dst].s, T[in->a].s, v[in->a], &v[in->dst]);
                if (code) trap(c, (unsigned)code);
                break;
            }
            case OSC_I_ALLOC: v[in->dst] = osc_rt_alloc(c->rt, T[in->dst].len, v[in->a]); break;
            case OSC_I_RELEASE: osc_rt_release(c->rt, v[in->a], T[in->a].len); break;
            case OSC_I_AOPEN: v[in->dst] = osc_rt_arena_open(c->rt, in->imm); break;
            case OSC_I_AALLOC: v[in->dst] = osc_rt_arena_alloc(c->rt, v[in->b], T[in->dst].len, v[in->a]); break;
            case OSC_I_ADESTROY: osc_rt_arena_destroy(c->rt, v[in->a]); break;
            case OSC_I_POPEN: v[in->dst] = osc_rt_pool_open(c->rt, in->nargs, in->imm); break;
            case OSC_I_PCLOSE: osc_rt_pool_close(c->rt, v[in->a]); break;
            case OSC_I_HALLOC: v[in->dst] = osc_rt_h_alloc(c->rt, v[in->b], v[in->a]); break;
            case OSC_I_HGEN: v[in->dst] = osc_rt_h_gen(c->rt, v[in->a], v[in->b]); break;
            case OSC_I_HFREE: osc_rt_h_free(c->rt, v[in->a], v[in->b], v[in->c]); break;
            case OSC_I_HLOAD: v[in->dst] = osc_rt_h_load(c->rt, v[in->a], v[in->b], v[in->c]); break;
            case OSC_I_HSTORE: osc_rt_h_store(c->rt, v[in->a], v[in->b], v[in->c], v[in->args[0]]); break;
            case OSC_I_LOAD: v[in->dst] = *elem(c, &T[in->a], v[in->a], T[in->b].s, v[in->b]); break;
            case OSC_I_STORE: *elem(c, &T[in->a], v[in->a], T[in->b].s, v[in->b]) = v[in->c]; break;
            case OSC_I_SLOAD: v[in->dst] = sload(c, T[in->a].s, v[in->a], v[in->a + 1], v[in->b]); break;
            case OSC_I_SSTORE: sstore(c, v[in->a], v[in->a + 1], v[in->b], v[in->c]); break;
            case OSC_I_FLOAD:
                v[in->dst] = *fcell(c, &T[in->a], v[in->a], (unsigned)in->imm, in->b >= 0,
                                    in->b >= 0 ? T[in->b].s : OSC_T_VOID, in->b >= 0 ? v[in->b] : 0);
                break;
            case OSC_I_FSTORE:
                *fcell(c, &T[in->a], v[in->a], (unsigned)in->imm, in->b >= 0, in->b >= 0 ? T[in->b].s : OSC_T_VOID,
                       in->b >= 0 ? v[in->b] : 0) = v[in->c];
                break;
            case OSC_I_CALL: {
                uint64_t ca[OSC_MAX_PARAMS] = {0};
                for (int k = 0; k < in->nargs; k++) ca[k] = v[in->args[k]];
                uint64_t r = run_func(c, in->callee, ca);
                if (in->dst >= 0) v[in->dst] = r;
                break;
            }
            case OSC_I_TRAP: trap(c, (unsigned)in->imm); break;
            case OSC_I_BR: next = in->blk_t; break;
            case OSC_I_CBR: next = v[in->a] ? in->blk_t : in->blk_f; break;
            case OSC_I_RET: return in->a >= 0 ? v[in->a] : 0;
            default: trap(c, OSC_TRAP_RUNTIME);
            }
        }
        if (next < 0) trap(c, OSC_TRAP_RUNTIME); /* unreachable for validated IR */
        b = next;
    }
}

static int check_args(const OscUnit *u, int func, const uint64_t *args, unsigned nargs, const OscRt *rt) {
    if (!rt || func < 0 || func >= u->nfuncs) return -1;
    const OscFunc *f = &u->funcs[func];
    if (nargs != f->nparams || (nargs && !args)) return -1;
    for (unsigned p = 0; p < nargs; p++) {
        const OscType *t = &f->vtype[p];
        if (t->s == OSC_T_BYTES || t->s == OSC_T_CELLS) continue; /* external pointer: checked as a pair below */
        if (t->s == OSC_T_REF) {
            if (!osc_rt_is_live_ref(rt, args[p], t->len)) return -1;
        } else if (osc_alu_canon(t->s, args[p]) != args[p]) {
            return -1;
        }
    }
    return osc_ir_slice_args_ok(f, args, nargs); /* NULL with len > 0, wrapping range, overlapping cells */
}

int osc_interp_run_prevalidated(const OscUnit *u, int func, const uint64_t *args, unsigned nargs, OscRt *rt,
                                uint64_t *ret) {
    if (!u || !ret || check_args(u, func, args, nargs, rt)) return -1;
    Ctx c = {u, rt, 0};
    uint64_t a[OSC_MAX_PARAMS] = {0};
    for (unsigned i = 0; i < nargs; i++) a[i] = args[i];
    rt->trap_code = 0;
    if (setjmp(rt->jb) != 0) return (int)rt->trap_code;
    *ret = run_func(&c, func, a);
    return 0;
}

int osc_interp_run(const OscUnit *u, int func, const uint64_t *args, unsigned nargs, OscRt *rt, uint64_t *ret) {
    if (!u || osc_ir_validate(u, NULL, 0)) return -1;
    return osc_interp_run_prevalidated(u, func, args, nargs, rt, ret);
}
