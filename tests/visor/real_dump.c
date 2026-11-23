/* SPDX-License-Identifier: Apache-2.0
 * real_dump.c -- REFERENCE-ONLY C side of tests/visor/real_parity.sh. It is committed once,
 * used to generate tests/visor/real_golden/ from the C at main commit 3f2c70dc5, and removed
 * from the tree in the next commit (the MANIFEST records its blob and sha256). Not built by any
 * make target.
 *
 * Reads a corpus of one-letter commands on stdin (see tests/visor/real_parity.sh) and prints what
 * the C realization lab (src/visor/visor_realization.c) returns: visor_realize_apply,
 * visor_realize_program, visor_realization_view, _cost, _run_pure, _alternatives(_ex),
 * _compare, _why, _format_text, _format_json, visor_cost_format_text/_json (and through the
 * view, visor_disasm). tests/visor/real_dump.om prints the same bytes from the OM-2 lane.
 */
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "omega_canonical.h"
#include "omega_core.h"
#include "omega_program.h"
#include "visor.h"
#include "visor_machine.h"
#include "visor_realization.h"

static char b[65536];
static OmegaMachineGraph spark, qemu, custom;   /* custom: dgx-spark with another machine id */
static const OmegaMachineGraph *mgs[4];
static const uint64_t xs[10] = { 0, 1, 2, 5, 10, 50, 100, 0xFFFFFFFFull, 0xFFFFFFFFFFFFFFFFull, 0x8000000000000000ull };
static const uint64_t px[12] = { 0, 1, 2, 5, 10, 50, 100, 255, 256, 65535, 0xFFFFFFFFull, 0xFFFFFFFFFFFFFFFFull };
static VisorRealizationEntry ents[4];
static VisorRealizationView views[4];
static OmegaProgram gp;                 /* the current program (P and H build it) */
static OmegaGraph gg;                   /* the raw graph (R O L B E W F X T Y I o) */
static int gcur = -1;
static VisorRealizationEntry cur;       /* the current entry (G and H realize into it) */
static VisorRealizationView curv;
static const char *tnames[8] = { "aarch64-v8a", "dgx-spark", "qemu-virt", "blackwell-gb10-sm121", "x86-64",
                                 "aarch64-v8", "abcdefghijklmnopqrstuvwxyz01234", "" };

static void outv(const VisorRealizationView *v) {
    int t = visor_realization_format_text(v, b, sizeof b); printf("T%d\n", t); if (t > 0) fputs(b, stdout);
    int j = visor_realization_format_json(v, b, sizeof b); printf("J%d\n", j); if (j > 0) fputs(b, stdout);
    int w = visor_realization_why(v, b, sizeof b); printf("\nW%d\n", w); if (w > 0) fputs(b, stdout);
    int c = visor_cost_format_json(&v->cost, b, sizeof b); printf("C%d\n", c); if (c > 0) fputs(b, stdout);
    int k = visor_cost_format_text(&v->cost, b, sizeof b); printf("\nK%d\n", k); if (k > 0) fputs(b, stdout);
}

static void trunc_sizes(const VisorRealizationView *v) {
    int L[4];
    L[0] = visor_realization_format_text(v, b, sizeof b);
    L[1] = visor_realization_format_json(v, b, sizeof b);
    L[2] = visor_realization_why(v, b, sizeof b);
    L[3] = visor_cost_format_text(&v->cost, b, sizeof b);
    for (int f = 0; f < 4; ++f) {
        int ns[8] = { 1, 2, 63, 64, L[f] - 1, L[f], L[f] + 1, L[f] + 2 };
        printf("tr%d", f);
        for (int i = 0; i < 8; ++i) {
            int n = ns[i] < 1 ? 1 : ns[i], r;
            if (f == 0) r = visor_realization_format_text(v, b, (size_t)n);
            else if (f == 1) r = visor_realization_format_json(v, b, (size_t)n);
            else if (f == 2) r = visor_realization_why(v, b, (size_t)n);
            else r = visor_cost_format_text(&v->cost, b, (size_t)n);
            printf(" %d", r);
        }
        printf("\n");
    }
}

static const int ops[8] = { OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_AND, OP_OR, OP_EQUAL, OP_NOT };
static const int ws[4] = { 8, 16, 32, 64 };

/* A mi oi ov wi: the binary-apply case of the realization matrix */
static void apply_case(int mi, int oi, int ov, int wi) {
    OmegaGraph *g = omega_graph_create();
    OmegaObject *t = omega_build_type_uint(g, (uint16_t)ws[wi]);
    OmegaObject *a = omega_build_val_uint(g, &t->id, (uint16_t)ws[wi], 7);
    OmegaObject *bb = omega_build_val_uint(g, &t->id, (uint16_t)ws[wi], 11);
    OmegaObject *o = omega_build_op_binary(g, (OpCode)ops[oi], (OverflowPolicy)ov, &t->id);
    OmegaObject *ap = omega_build_apply(g, &o->id, &a->id, &bb->id);
    VisorRealizationEntry e; VisorRealizationView v;
    int rc = visor_realize_apply(g, &ap->id, mgs[mi], &e, &v);
    printf("A %d %d %d %d rc %d\n", mi, ops[oi], ov, ws[wi], rc);
    outv(&v);
    if (rc == 0) {
        for (int i = 0; i < 10; ++i)
            for (int k = 0; k < 10; ++k) {
                uint64_t args[3] = { xs[i], xs[k], 0 }, r = 0;
                int q = visor_realization_run_pure(&e, args, 2, &r);
                printf("r %d %llu\n", q, q == 0 ? (unsigned long long)r : 0ull);
            }
        uint64_t args[3] = { 9, 4, 1 }, r = 0;
        for (int argc = 0; argc <= 4; ++argc) {
            int q = visor_realization_run_pure(&e, args, (size_t)argc, &r);
            printf("ra %d %d %llu\n", argc, q, q == 0 ? (unsigned long long)r : 0ull);
        }
    }
    if (wi == 3 && ov == 1) {
        rc = visor_realize_apply(g, &o->id, mgs[mi], &e, &v);
        printf("O rc %d\n", rc);
        outv(&v);
    }
    if (mi == 0 && oi == 0 && ov == 1 && wi == 3) {
        trunc_sizes(&v);
        rc = visor_realize_apply(g, &t->id, mgs[mi], &e, &v);
        printf("TY rc %d\n", rc);
        outv(&v);
        trunc_sizes(&v);
        SemanticId junk; memset(&junk, 0x5A, sizeof junk);
        rc = visor_realize_apply(g, &junk, mgs[mi], &e, &v);
        printf("JU rc %d\n", rc);
        outv(&v);
        rc = visor_realize_apply(g, &a->id, mgs[mi], &e, &v);
        printf("VA rc %d\n", rc);
        outv(&v);
    }
    omega_graph_destroy(g);
}

static void hexid(const SemanticId *id) { for (int i = 0; i < 32; ++i) printf("%02x", id->bytes[i]); printf("\n"); }

static void manual(OmegaProgram *p, TypeTag it, uint16_t iw, TypeTag ot, uint16_t ow, const uint8_t *op, const uint64_t *imm, int n) {
    omega_program_init(p, "man");
    p->contract.input_type = it; p->contract.input_width = iw;
    p->contract.output_type = ot; p->contract.output_width = ow;
    snprintf(p->contract.precondition, sizeof p->contract.precondition, "x >= 0");
    omega_build_constraint_id(CONST_PRECONDITION, p->contract.precondition, &p->contract.precondition_id);
    snprintf(p->contract.postcondition, sizeof p->contract.postcondition, "manual");
    omega_build_constraint_id(CONST_POSTCONDITION, p->contract.postcondition, &p->contract.postcondition_id);
    p->body.has_body = true;
    p->body.step_count = (uint16_t)n;
    for (int i = 0; i < n; ++i) { p->body.steps[i].op = op[i]; p->body.steps[i].imm = imm[i]; }
    omega_program_compute_id(p);
}

static int prog_case(int k, OmegaProgram *p) {
    static const int uops[6] = { OP_ADD, OP_SUB, OP_MUL, OP_AND, OP_OR, OP_DIV };
    static const uint64_t uimm[7] = { 0, 1, 5, 0xFFFF, 0x12345, 0xFFFFFFFFull, 0x100000000ull };
    static const uint8_t mop[5] = { OP_MUL, OP_ADD, OP_AND, OP_OR, OP_SUB };
    static const uint64_t mimm[5] = { 3, 0x7F, 0x55, 1, 2 };
    char err[128];
    if (k < 42) return omega_program_build_unary_op(p, "u", (OpCode)uops[k / 7], uimm[k % 7]);
    k -= 42;
    if (k < 4) { manual(p, TYPE_UNSIGNED_INT, (uint16_t)ws[k], TYPE_UNSIGNED_INT, (uint16_t)ws[k], mop, mimm, 5); return 0; }
    k -= 4;
    if (k == 0) { uint8_t o[1] = { OP_ADD }; uint64_t m[1] = { 0x100 }; manual(p, TYPE_UNSIGNED_INT, 8, TYPE_UNSIGNED_INT, 8, o, m, 1); return 0; }
    if (k == 1) { manual(p, TYPE_UNSIGNED_INT, 32, TYPE_UNSIGNED_INT, 64, mop, mimm, 5); return 0; }
    if (k == 2) { manual(p, TYPE_SIGNED_INT, 32, TYPE_SIGNED_INT, 32, mop, mimm, 5); return 0; }
    if (k == 3) { manual(p, TYPE_UNSIGNED_INT, 12, TYPE_UNSIGNED_INT, 12, mop, mimm, 5); return 0; }
    if (k == 4) {
        uint8_t o[20]; uint64_t m[20];
        for (int i = 0; i < 20; ++i) { o[i] = (i % 2) ? OP_MUL : OP_ADD; m[i] = (uint64_t)(i + 1); }
        manual(p, TYPE_UNSIGNED_INT, 8, TYPE_UNSIGNED_INT, 8, o, m, 20); return 0;
    }
    if (k == 5) { uint8_t o[2] = { OP_ADD, OP_DIV }; uint64_t m[2] = { 1, 2 }; manual(p, TYPE_UNSIGNED_INT, 64, TYPE_UNSIGNED_INT, 64, o, m, 2); return 0; }
    if (k == 6) { manual(p, TYPE_UNSIGNED_INT, 16, TYPE_UNSIGNED_INT, 16, mop, mimm, 5); p->body.steps[0].imm = 9; return 0; }
    if (k == 7) { omega_program_init(p, "nobody"); return 0; }
    if (k == 8) {
        OmegaProgram a, c;
        omega_program_build_unary_op(&a, "mul2", OP_MUL, 2);
        omega_program_build_unary_op(&c, "add1", OP_ADD, 1);
        return omega_program_compose(&a, &c, p, err, sizeof err);
    }
    if (k == 9) {
        OmegaProgram a, c;
        omega_program_build_unary_op(&a, "mul3", OP_MUL, 3);
        omega_program_build_unary_op(&c, "sub2", OP_SUB, 2);
        return omega_program_compose(&a, &c, p, err, sizeof err);
    }
    if (k == 10) {
        static OmegaProgram acc, st, tmp;
        omega_program_build_unary_op(&acc, "c", OP_ADD, 1);
        for (int i = 2; i <= 17; ++i) {
            omega_program_build_unary_op(&st, "s", (i % 3 == 0) ? OP_MUL : OP_ADD, (uint64_t)i);
            if (omega_program_compose(&acc, &st, &tmp, err, sizeof err) != 0) return -1;
            acc = tmp;
        }
        *p = acc;
        return 0;
    }
    return -9;
}

static void prun(const VisorRealizationEntry *e) {
    for (int i = 0; i < 12; ++i) {
        uint64_t args[1] = { px[i] }, r = 0;
        int z = visor_realization_run_pure(e, args, 1, &r);
        printf("r %d %llu\n", z, z == 0 ? (unsigned long long)r : 0ull);
    }
}

static void alts(int mi, size_t max) {
    size_t n = 0;
    int q = visor_realization_alternatives_ex(&gp, mgs[mi], ents, views, max, &n);
    printf("AL %d rc %d n %zu\n", mi, q, n);
    for (size_t i = 0; i < n; ++i) {
        printf("e %d %d %d %d %s|\n", ents[i].verdict_known, ents[i].compatible, ents[i].has_machine_id,
               ents[i].has_estimate, ents[i].incompatible_reason);
        outv(&views[i]);
    }
    if (n == 4) {
        int c = visor_realization_compare(&views[0], &views[2], b, sizeof b); printf("Q%d\n", c); if (c > 0) fputs(b, stdout);
        c = visor_realization_compare(&views[1], &views[3], b, sizeof b); printf("Q%d\n", c); if (c > 0) fputs(b, stdout);
    }
}

/* P k: the program case of the realization matrix (k 0..56) */
static void prog_cases(int k) {
    int rc = prog_case(k, &gp);
    printf("P %d rc %d\n", k, rc);
    hexid(&gp.program_id);
    for (int mi = 0; mi < 3; ++mi) {
        VisorRealizationEntry e; VisorRealizationView v;
        int q = visor_realize_program(&gp, mgs[mi], &e, &v);
        printf("RP %d rc %d\n", mi, q);
        outv(&v);
        if (q == 0) prun(&e);
    }
    for (int mi = 0; mi < 3; ++mi) alts(mi, 4);
}

static OmegaObject *gobj(void) { return gcur >= 0 ? &gg.objects[gcur] : NULL; }

int main(void) {
    static char line[8192];
    unsigned long ln = 0;
    omega_machine_build_dgx_spark(&spark);
    omega_machine_build_qemu_virt(&qemu);
    custom = spark;
    custom.machine_id.bytes[0] ^= 1;
    mgs[0] = &spark; mgs[1] = &qemu; mgs[2] = NULL; mgs[3] = &custom;
    while (fgets(line, sizeof line, stdin)) {
        ln++;
        char c = line[0];
        if (c == '#' || c == '\n' || c == '\0') continue;
        uint64_t a[4] = {0, 0, 0, 0};
        char *p = line + 1;
        for (int i = 0; i < 4; i++) {
            while (*p == ' ') p++;
            if (*p < '0' || *p > '9') break;
            a[i] = strtoull(p, &p, 10);
        }
        OmegaObject *o = gobj();
        int mi = (int)(a[1] % 4);
        switch (c) {
        case 'A': apply_case((int)a[0] % 3, (int)a[1] % 8, (int)a[2] % 4, (int)a[3] % 4); break;
        case 'P': prog_cases((int)a[0]); break;
        /* raw graph */
        case 'R': memset(&gg, 0, sizeof gg); gcur = -1; break;
        case 'O': {
            OmegaObject *n = omega_graph_add_object(&gg, (SemanticKind)a[0]);
            if (!n) printf("L%lu O full\n", ln);
            else gcur = (int)(n - gg.objects);
            break;
        }
        case 'L': if (o) o->payload_len = (uint32_t)a[0]; break;
        case 'B': if (o) o->payload[a[0]] = (uint8_t)a[1]; break;
        case 'E':
            if (o) for (uint64_t i = 0; i < a[1]; i++) o->payload[a[0] + i] = (uint8_t)(a[2] >> (8 * (a[1] - 1 - i)));
            break;
        case 'W':
            if (o) for (uint64_t i = 0; i < a[1]; i++) o->payload[a[0] + i] = (uint8_t)(a[2] >> (8 * i));
            break;
        case 'F': if (o) memcpy(o->payload + a[0], gg.objects[a[1]].id.bytes, 32); break;
        case 'X': if (o) memset(o->payload + a[0], (int)a[1], 32); break;
        case 'T':
            if (o && omega_object_add_relation(o, (RelationKind)a[0], &gg.objects[a[1]].id) != 0) printf("L%lu T full\n", ln);
            break;
        case 'I': if (o && omega_compute_semantic_id(o) != 0) printf("L%lu I rc=-1\n", ln); break;
        case 'o': {   /* o sint w opcode ov: type, two values, a binary operation and its apply */
            OmegaObject *t = a[0] ? omega_build_type_signed_int(&gg, (uint16_t)a[1]) : omega_build_type_uint(&gg, (uint16_t)a[1]);
            OmegaObject *x = omega_build_val_uint(&gg, &t->id, (uint16_t)a[1], 7);
            OmegaObject *y = omega_build_val_uint(&gg, &t->id, (uint16_t)a[1], 11);
            OmegaObject *op = omega_build_op_binary(&gg, (OpCode)a[2], (OverflowPolicy)a[3], &t->id);
            OmegaObject *ap = omega_build_apply(&gg, &op->id, &x->id, &y->id);
            printf("L%lu o %d\n", ln, (int)(ap - gg.objects));
            break;
        }
        /* the current entry */
        case 'G': {   /* G j mi: realize the apply/operation object j */
            int rc = visor_realize_apply(&gg, &gg.objects[a[0]].id, mgs[mi], &cur, &curv);
            printf("L%lu G %" PRIu64 " %d rc %d\n", ln, a[0], mi, rc);
            outv(&curv);
            break;
        }
        case 'H': {   /* H k mi: build program k, realize it */
            int rc = prog_case((int)a[0], &gp);
            int q = visor_realize_program(&gp, mgs[mi], &cur, &curv);
            printf("L%lu H %" PRIu64 " %d rc %d %d\n", ln, a[0], mi, rc, q);
            outv(&curv);
            break;
        }
        case 'n': snprintf(cur.target_name, sizeof cur.target_name, "%s", tnames[a[0] % 8]); break;
        case 'q': cur.real.target_profile = (uint8_t)a[0]; break;
        case 'z': cur.real.code_len = (size_t)a[0]; break;
        case 'u': cur.real.entry_offset = (uint32_t)a[0]; break;
        case 'k':
            for (int i = 0; i < 4; i++) cur.real.code_bytes[a[0] + i] = (uint8_t)(a[1] >> (8 * i));
            break;
        case 'm': cur.has_machine_id = a[0] != 0; break;
        case 'b': visor_machine_blackwell_id(&cur.machine_id); break;
        case 'h': cur.real.has_machine_id = a[0] != 0; break;
        case 'j':
            cur.verdict_known = a[0] != 0; cur.compatible = a[1] != 0;
            snprintf(cur.incompatible_reason, sizeof cur.incompatible_reason, "%s", a[2] ? "corpus verdict" : "");
            break;
        case 's': cur.has_estimate = a[0] != 0; cur.estimated_cycles = (uint32_t)a[1]; break;
        case 'v': {   /* v _ mi: view the current entry */
            int rc = visor_realization_view(&cur, mgs[mi], &curv);
            printf("L%lu v %d rc %d\n", ln, mi, rc);
            outv(&curv);
            break;
        }
        case 'c': {   /* c _ mi: cost only */
            int rc = visor_realization_cost(&cur, mgs[mi], &curv.cost);
            printf("L%lu c %d rc %d\n", ln, mi, rc);
            int j = visor_cost_format_json(&curv.cost, b, sizeof b); printf("C%d\n", j); if (j > 0) fputs(b, stdout);
            int k = visor_cost_format_text(&curv.cost, b, sizeof b); printf("\nK%d\n", k); if (k > 0) fputs(b, stdout);
            break;
        }
        case 'x': {   /* x argc a b c: run_pure */
            uint64_t args[3] = { a[1], a[2], a[3] }, r = 0;
            int q = visor_realization_run_pure(&cur, args, (size_t)a[0], &r);
            printf("L%lu x %d %llu\n", ln, q, q == 0 ? (unsigned long long)r : 0ull);
            break;
        }
        case 'y': trunc_sizes(&curv); break;
        case 'w': {   /* w max mi: alternatives without entries */
            size_t n = 0;
            int q = visor_realization_alternatives(&gp, mgs[mi], views, (size_t)a[0], &n);
            printf("L%lu w %d rc %d n %zu\n", ln, mi, q, n);
            for (size_t i = 0; i < n; ++i) outv(&views[i]);
            break;
        }
        case 'e': alts(mi, (size_t)a[0]); break;   /* e max mi */
        case 'Q': {   /* Q i: compare the current view with alternative view i */
            int q = visor_realization_compare(&curv, &views[a[0] % 4], b, sizeof b);
            printf("Q%d\n", q); if (q > 0) fputs(b, stdout);
            break;
        }
        default: printf("L%lu ? %c\n", ln, c); break;
        }
        fflush(stdout);
    }
    return 0;
}
