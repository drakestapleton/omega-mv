/* SPDX-License-Identifier: Apache-2.0
 * verify_dump.c -- REFERENCE-ONLY C dumper for tests/visor/verify_parity.sh. It links the C
 * Visor verify lane at main commit 3f2c70dc5 (src/visor/visor_verify.c and the C library it
 * calls) and prints, for every command of a corpus on stdin, what the OM-2 dumper
 * tests/visor/verify_dump.om prints from the shipped src/visor/visor_verify.om. Committed once
 * with the goldens it generated (tests/visor/verify_golden), then removed from the tree.
 * Commands (one per line, numbers decimal unless 0x):
 *   S            the hand scenario (every report shape of the C test, the V0/V1 lies, programs,
 *                effects, the native execution matrix)
 *   G op         graph u64 a=7 b=11 op(op, WRAP) ap=op(a,b); prints G rc
 *   O f v        field f of the graph: 1 op opcode, 2 op overflow, 3 type width, 4 value
 *                byte_len, 5 type tag, 6 value payload_len, 7 type payload_len, 8 apply
 *                payload_len, 9 op payload_len (ids unchanged)
 *   Q i          query object i (0 type, 1 a, 2 b, 3 op, 4 apply; 9 an id no object has)
 *   P            realize the op pure-binary into slot 0; prints P rc
 *   K            the DGX Spark machine model into machine slot 0
 *   W n w...     slot 4 := the n code words, bound to the op, realization id computed
 *   V s m        verify the query with slot s (-1, 0 or 4) and machine m (-1 or 0); a slot 0
 *                whose realization failed prints "V skip"
 *   X a b c      V0 structure of slot 4 (no graph); when it passes, run slot 4 on (a, b, c) */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "omega_verify.h"
#include "omega_core.h"
#include "omega_canonical.h"
#include "omega_machine.h"
#include "omega_program.h"
#include "omega_realize.h"
#include "omega_exec.h"
#include "visor_verify.h"

static char tb[8192], jb[8192];
static VisorVerifyReport R;

static void show(const char *name, int rc) {
    int t = visor_verify_format_text(&R, tb, sizeof tb);
    int j = visor_verify_format_json(&R, jb, sizeof jb);
    printf("== %s rc=%d t=%d j=%d\n", name, rc, t, j);
    if (t > 0) fputs(tb, stdout);
    printf("--json\n");
    if (j > 0) fputs(jb, stdout);
    printf("\n");
    /* C buffer semantics around the exact length */
    if (t > 0) {
        char small[8192];
        printf("tn: %d %d %d %d\n", visor_verify_format_text(&R, small, (size_t)t),
               visor_verify_format_text(&R, small, (size_t)t + 1), visor_verify_format_text(&R, small, 1),
               visor_verify_format_text(&R, small, 0));
    }
    if (j > 0) {
        char small[8192];
        printf("jn: %d %d %d %d\n", visor_verify_format_json(&R, small, (size_t)j),
               visor_verify_format_json(&R, small, (size_t)j + 1), visor_verify_format_json(&R, small, 1),
               visor_verify_format_json(&R, small, 0));
    }
}

static OmegaGraph *G;
static SemanticId T, A, B, OP, AP;
static void build_add(OpCode opc) {
    if (G) omega_graph_destroy(G);
    G = omega_graph_create();
    T = omega_build_type_uint(G, 64)->id;
    A = omega_build_val_uint(G, &T, 64, 7)->id;
    B = omega_build_val_uint(G, &T, 64, 11)->id;
    OP = omega_build_op_binary(G, opc, OVERFLOW_WRAP, &T)->id;
    AP = omega_build_apply(G, &OP, &A, &B)->id;
}

static void code_words(RealizationObject *r, const SemanticId *sem, const uint32_t *w, size_t n) {
    memset(r, 0, sizeof *r);
    r->semantic_id = *sem;
    r->target_profile = AARCH64_PROFILE_V8A_BAREMETAL;
    for (size_t i = 0; i < n; i++) {
        r->code_bytes[4 * i] = (uint8_t)w[i];
        r->code_bytes[4 * i + 1] = (uint8_t)(w[i] >> 8);
        r->code_bytes[4 * i + 2] = (uint8_t)(w[i] >> 16);
        r->code_bytes[4 * i + 3] = (uint8_t)(w[i] >> 24);
    }
    r->code_len = 4 * n;
    omega_compute_realization_id(r);
}

#define RET 0xD65F03C0u
static const uint32_t LIES[][3] = {
    {0x8B010C00u, RET, 0}, {0x0B010000u, RET, 0}, {0xCB800820u, RET, 0}, {0x9B017C00u, RET, 0},
    {0x9B01FC00u, RET, 0}, {0xAAC11400u, RET, 0}, {0xCA010000u, RET, 0}, {0x0A411000u, RET, 0},
    {0xD2A000A0u, 0xF28000E0u, RET}, {0x8B020000u, RET, 0}, {0xCB410400u, RET, 0}, {0x8B81FC00u, RET, 0},
    {0xD29FFFE0u, 0xF2800020u, RET},
};
static const size_t LIEN[] = {2, 2, 2, 2, 2, 2, 2, 2, 3, 2, 2, 2, 3};
#define NLIES (sizeof LIEN / sizeof LIEN[0])
static const uint64_t XIN[][3] = {
    {0, 0, 0}, {1, 2, 3}, {7, 11, 3}, {UINT64_MAX, 1, 0}, {0x8000000000000000ull, 5, 9},
    {0x123456789abcdef0ull, 0xfedcba9876543210ull, 1}, {0xffffffffull, 0x100000001ull, 2},
    {5, UINT64_MAX, 7}, {0x7fffffffffffffffull, 0x8000000000000001ull, 3}, {42, 42, 42},
};

static void hand(void) {
    RealizationObject real, bad, sreal, sbad, lie, freal, tmp;
    OmegaMachineGraph mg, mg2;
    int rc;

    build_add(OP_ADD);
    rc = visor_verify_object(G, &AP, NULL, NULL, &R); show("apply-none", rc);
    rc = visor_verify_object(G, &T, NULL, NULL, &R); show("type-none", rc);
    rc = visor_verify_object(G, &A, NULL, NULL, &R); show("value-none", rc);
    rc = visor_verify_object(G, &OP, NULL, NULL, &R); show("op-none", rc);
    omega_realize_pure_binary(G, &OP, &real);
    omega_machine_build_dgx_spark(&mg);
    rc = visor_verify_object(G, &AP, &real, &mg, &R); show("apply-real-mg", rc);
    rc = visor_verify_object(G, &OP, &real, &mg, &R); show("op-real-mg", rc);
    rc = visor_verify_object(G, &AP, &real, NULL, &R); show("apply-real", rc);
    bad = real; bad.code_bytes[0] ^= 0x01;
    rc = visor_verify_object(G, &AP, &bad, &mg, &R); show("apply-bad-mg", rc);
    mg2 = mg; mg2.target_profile = 0x02;
    rc = visor_verify_object(G, &AP, &real, &mg2, &R); show("apply-real-mg2", rc);
    rc = visor_verify_object(G, &A, &real, NULL, &R); show("value-real", rc);
    /* machine-bound realizations (triple id) */
    tmp = real; tmp.machine_id = mg.machine_id; tmp.has_machine_id = true;
    omega_realize_compute_triple_id(&tmp.semantic_id, &tmp.machine_id, &tmp, &tmp.realization_id);
    rc = visor_verify_object(G, &AP, &tmp, &mg, &R); show("apply-bound-mg", rc);
    tmp.machine_id.bytes[3] ^= 0x40;
    omega_realize_compute_triple_id(&tmp.semantic_id, &tmp.machine_id, &tmp, &tmp.realization_id);
    rc = visor_verify_object(G, &AP, &tmp, &mg, &R); show("apply-bound-other", rc);
    rc = visor_verify_object(G, &AP, &tmp, NULL, &R); show("apply-bound-nomg", rc);
    /* V0 realization failures */
    tmp = real; tmp.target_profile = 2; omega_compute_realization_id(&tmp);
    rc = visor_verify_object(G, &AP, &tmp, &mg, &R); show("v0-profile", rc);
    tmp = real; tmp.code_len = 6; omega_compute_realization_id(&tmp);
    rc = visor_verify_object(G, &AP, &tmp, NULL, &R); show("v0-bounds", rc);
    tmp = real; tmp.code_len = 4100;
    rc = visor_verify_object(G, &AP, &tmp, NULL, &R); show("v0-bounds-big", rc);
    { uint32_t w[] = {0x00000000u, RET}; code_words(&tmp, &OP, w, 2); }
    rc = visor_verify_object(G, &AP, &tmp, NULL, &R); show("v0-decode", rc);
    { uint32_t w[] = {0x8B010000u}; code_words(&tmp, &OP, w, 1); }
    rc = visor_verify_object(G, &AP, &tmp, NULL, &R); show("v0-noret", rc);
    tmp = real; tmp.has_id = false;
    rc = visor_verify_object(G, &AP, &tmp, NULL, &R); show("v0-noid", rc);
    tmp = real; tmp.code_len = 0; omega_compute_realization_id(&tmp);
    rc = visor_verify_object(G, &AP, &tmp, NULL, &R); show("v0-empty", rc);
    /* missing / invalid */
    SemanticId missing; memset(&missing, 0xAB, sizeof missing);
    rc = visor_verify_object(G, &missing, NULL, NULL, &R); show("missing", rc);
    rc = visor_verify_object(NULL, &AP, NULL, NULL, &R); show("null-graph", rc);
    /* lies: other code bound to the ADD op; V1 reports native results */
    for (size_t i = 0; i < NLIES; i++) {
        code_words(&lie, &OP, LIES[i], LIEN[i]);
        char nm[32]; snprintf(nm, sizeof nm, "lie-%zu", i);
        rc = visor_verify_object(G, &AP, &lie, &mg, &R); show(nm, rc);
    }
    /* SUB graph */
    build_add(OP_SUB);
    omega_realize_pure_binary(G, &OP, &sreal);
    rc = visor_verify_object(G, &AP, &sreal, NULL, &R); show("sub-real", rc);
    sbad = sreal; sbad.code_bytes[0] ^= 0x01;
    rc = visor_verify_object(G, &AP, &sbad, NULL, &R); show("sub-bad", rc);
    build_add(OP_ADD);
    lie = sreal; lie.semantic_id = OP; omega_compute_realization_id(&lie);
    rc = visor_verify_object(G, &AP, &lie, NULL, &R); show("sub-lie", rc);
    /* MUL graph: op realization not ADD */
    build_add(OP_MUL);
    omega_realize_pure_binary(G, &OP, &tmp);
    rc = visor_verify_object(G, &AP, &tmp, &mg, &R); show("mul-real", rc);
    /* graph faults */
    build_add(OP_ADD);
    {
        OmegaObject *ap = omega_graph_find_object(G, &AP);
        ap->relations[0].kind = REL_DEPENDS_ON;
        memset(&ap->relations[0].target_id, 0xCD, sizeof(SemanticId));
        ap->rel_count = 1;
        rc = visor_verify_object(G, &AP, NULL, NULL, &R); show("dangling", rc);
        ap->relations[0].kind = 0;
        rc = visor_verify_object(G, &AP, NULL, NULL, &R); show("relkind", rc);
        ap->relations[0].kind = REL_DEPENDS_ON;
        ap->relations[0].target_id = AP;
        rc = visor_verify_object(G, &AP, NULL, NULL, &R); show("selfcycle", rc);
        ap->rel_count = 0;
        OmegaObject *a = omega_graph_find_object(G, &A);
        a->relations[0].kind = REL_DERIVED_FROM; a->relations[0].target_id = AP; a->rel_count = 1;
        rc = visor_verify_object(G, &AP, NULL, NULL, &R); show("cycle", rc);
        a->rel_count = 0;
        ((ValuePayload *)a->payload)->byte_len = 3;
        rc = visor_verify_object(G, &A, NULL, NULL, &R); show("vbytes", rc);
        ((ValuePayload *)a->payload)->byte_len = 8;
        OmegaObject *t = omega_graph_find_object(G, &T);
        ((TypePayload *)t->payload)->width = 0;
        rc = visor_verify_object(G, &T, NULL, NULL, &R); show("uwidth", rc);
        ((TypePayload *)t->payload)->width = 64;
        OmegaObject *op = omega_graph_find_object(G, &OP);
        ((OperationPayload *)op->payload)->overflow = 0;
        rc = visor_verify_object(G, &AP, NULL, NULL, &R); show("ovf", rc);
        ((OperationPayload *)op->payload)->overflow = OVERFLOW_WRAP;
        ((OperationPayload *)op->payload)->opcode = 0x33;
        rc = visor_verify_object(G, &OP, NULL, NULL, &R); show("opcode", rc);
        ((OperationPayload *)op->payload)->opcode = OP_ADD;
        memset(&a->attributes[a->attr_count], 0, sizeof a->attributes[0]);
        a->attr_count++;
        rc = visor_verify_object(G, &A, NULL, NULL, &R); show("attrkey", rc);
    }
    /* f_add_sub */
    if (G) omega_graph_destroy(G);
    G = omega_graph_create();
    SemanticId root;
    omega_build_f_add_sub_graph(G, &root);
    omega_realize_f_add_sub(G, &root, &freal);
    rc = visor_verify_object(G, &root, &freal, NULL, &R); show("fadd", rc);
    rc = visor_verify_object(G, &root, &freal, &mg, &R); show("fadd-mg", rc);
    { uint32_t w[] = {0x8B010000u, RET}; code_words(&tmp, &root, w, 2); }
    rc = visor_verify_object(G, &root, &tmp, NULL, &R); show("fadd-lie", rc);
    /* effects and capability refs */
    OmegaObject *eff = omega_build_effect(G, 1, 1, 3, 1);
    SemanticId eid = eff->id;
    rc = visor_verify_object(G, &eid, NULL, NULL, &R); show("effect", rc);
    SemanticId cap = omega_build_type_cap_ref(G)->id;
    OmegaObject *e2 = omega_build_effect(G, 2, 5, 7, 9);
    memcpy(e2->payload + 16, cap.bytes, 32);
    omega_compute_semantic_id(e2);
    SemanticId e2id = e2->id;
    rc = visor_verify_object(G, &e2id, NULL, NULL, &R); show("effect-cap", rc);
    OmegaObject *e3 = omega_build_effect(G, 1, 1, 3, 1);
    e3->payload[0] = 0; e3->payload[1] = 0; omega_compute_semantic_id(e3);
    SemanticId e3id = e3->id;
    rc = visor_verify_object(G, &e3id, NULL, NULL, &R); show("effect-bad", rc);
    rc = visor_verify_object(G, &root, &freal, NULL, &R); show("fadd-after-badeff", rc);
    /* programs */
    OmegaProgram p;
    omega_program_build_unary_op(&p, "add5", OP_ADD, 5);
    rc = visor_verify_program(&p, &R); show("prog", rc);
    OmegaProgram q = p; q.is_realized = false;
    rc = visor_verify_program(&q, &R); show("prog-unreal", rc);
    q = p; q.realization.code_bytes[0] ^= 0x01;
    rc = visor_verify_program(&q, &R); show("prog-corrupt", rc);
    q = p; memset(&q.contract.postcondition_id, 0, sizeof(SemanticId));
    rc = visor_verify_program(&q, &R); show("prog-nopost", rc);
    q = p; q.contract.input_width = 0;
    rc = visor_verify_program(&q, &R); show("prog-0w", rc);
    rc = visor_verify_program(NULL, &R); show("prog-null", rc);
    omega_program_build_unary_op(&q, "big", OP_MUL, 0x12345678);
    rc = visor_verify_program(&q, &R); show("prog-mul", rc);
    /* empty graph */
    omega_graph_destroy(G);
    G = omega_graph_create();
    rc = visor_verify_object(G, &AP, NULL, NULL, &R); show("empty", rc);
    /* execution matrix: native vs the OM interpreter */
    build_add(OP_ADD);
    for (size_t i = 0; i < NLIES; i++) {
        code_words(&lie, &OP, LIES[i], LIEN[i]);
        printf("x%zu:", i);
        for (size_t k = 0; k < sizeof XIN / sizeof XIN[0]; k++) {
            uint64_t o = 0;
            int er = omega_exec_native_f3(&lie, XIN[k][0], XIN[k][1], XIN[k][2], &o);
            printf(" %d/%llu", er, (unsigned long long)o);
        }
        printf("\n");
    }
    /* a realization bound to a value: neither an operation nor an apply */
    build_add(OP_ADD);
    omega_realize_pure_binary(G, &OP, &tmp);
    tmp.semantic_id = A; omega_compute_realization_id(&tmp);
    rc = visor_verify_object(G, &A, &tmp, NULL, &R); show("value-bound", rc);
    fflush(stdout);
}

static RealizationObject S0, S4;
static int s0ok;
static OmegaMachineGraph M0;
static SemanticId Q;

static uint64_t num(const char *t) { return strtoull(t, NULL, 0); }

int main(void) {
    char line[1024];
    while (fgets(line, sizeof line, stdin)) {
        char *tok[24]; int nt = 0;
        for (char *p = strtok(line, " \t\r\n"); p && nt < 24; p = strtok(NULL, " \t\r\n")) tok[nt++] = p;
        if (nt == 0 || tok[0][0] == '#') continue;
        char c = tok[0][0];
        int rc;
        if (c == 'S') { hand(); continue; }
        if (c == 'G') {
            build_add((OpCode)num(tok[1]));
            printf("G %d\n", 0);
        } else if (c == 'O') {
            int f = (int)num(tok[1]); uint64_t v = num(tok[2]);
            if (f == 1) ((OperationPayload *)omega_graph_find_object(G, &OP)->payload)->opcode = (OpCode)v;
            if (f == 2) ((OperationPayload *)omega_graph_find_object(G, &OP)->payload)->overflow = (OverflowPolicy)v;
            if (f == 3) ((TypePayload *)omega_graph_find_object(G, &T)->payload)->width = (uint16_t)v;
            if (f == 4) ((ValuePayload *)omega_graph_find_object(G, &A)->payload)->byte_len = (uint16_t)v;
            if (f == 5) ((TypePayload *)omega_graph_find_object(G, &T)->payload)->tag = (TypeTag)v;
            if (f == 6) omega_graph_find_object(G, &A)->payload_len = (uint16_t)v;
            if (f == 7) omega_graph_find_object(G, &T)->payload_len = (uint16_t)v;
            if (f == 8) omega_graph_find_object(G, &AP)->payload_len = (uint16_t)v;
            if (f == 9) omega_graph_find_object(G, &OP)->payload_len = (uint16_t)v;
        } else if (c == 'Q') {
            int i = (int)num(tok[1]);
            if (i == 0) Q = T; else if (i == 1) Q = A; else if (i == 2) Q = B; else if (i == 3) Q = OP;
            else if (i == 4) Q = AP; else memset(&Q, 0xAB, sizeof Q);
        } else if (c == 'P') {
            memset(&S0, 0, sizeof S0);
            rc = omega_realize_pure_binary(G, &OP, &S0);
            s0ok = rc == 0;
            printf("P %d\n", rc == 0 ? 0 : -1);
        } else if (c == 'K') {
            omega_machine_build_dgx_spark(&M0);
        } else if (c == 'W') {
            uint32_t w[16]; size_t n = (size_t)num(tok[1]);
            for (size_t i = 0; i < n && i < 16; i++) w[i] = (uint32_t)num(tok[2 + i]);
            code_words(&S4, &OP, w, n);
        } else if (c == 'V') {
            int s = (int)strtol(tok[1], NULL, 10), m = (int)strtol(tok[2], NULL, 10);
            if (s == 0 && !s0ok) { printf("V skip\n"); continue; }
            const RealizationObject *r = s == 0 ? &S0 : s == 4 ? &S4 : NULL;
            rc = visor_verify_object(G, &Q, r, m == 0 ? &M0 : NULL, &R);
            show("V", rc);
        } else if (c == 'X') {
            VerifyReport vr;
            if (omega_verify_v0_structural(NULL, &S4, &vr) != 0 || !vr.passed) { printf("X v0\n"); continue; }
            uint64_t o = 0;
            rc = omega_exec_native_f3(&S4, num(tok[1]), num(tok[2]), num(tok[3]), &o);
            printf("X %d %llu\n", rc, (unsigned long long)o);
        }
        fflush(stdout);
    }
    return 0;
}
