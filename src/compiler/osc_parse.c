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
 * osc_parse.c -- OSC-1 recursive-descent parser. See osc_parse.h and
 * docs/osc/OSC-1-DESIGN.md section 2 (grammar).
 * OSC-1 slice; not a general Omega compiler; no self-hosting.
 */
#include "osc_parse.h"
#include "omega_api_decl.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define LOOP_BOUND_MAX 1000000

typedef struct {
    OscAst *ast;
    OscDiag *d;
    uint32_t pos;
    int depth;
} P;

static const OscToken *cur(P *p) { return &p->ast->toks[p->pos]; }
static int peek_kind(P *p, uint32_t k) { uint32_t i = p->pos + k; return i < p->ast->ntok ? p->ast->toks[i].kind : OT_EOF; }
static int at(P *p, int k) { return cur(p)->kind == k; }
static void adv(P *p) { if (cur(p)->kind != OT_EOF) p->pos++; }

void osc_node_name(const OscAst *ast, const OscNode *n, char *buf, size_t cap)
{
    osc_tok_text(ast->src, &ast->toks[n->tok], buf, cap);
}

static int syntax(P *p, const char *what)
{
    const OscToken *t = cur(p);
    char buf[64];
    if (t->kind == OT_EOF) snprintf(buf, sizeof buf, "end of input");
    else osc_tok_text(p->ast->src, t, buf, sizeof buf);
    if (t->kind == OT_RESERVED)
        osc_diag_set(p->d, OSC_DIAG_SYNTAX, t->line, t->col, buf, 0, NULL, "reserved word",
                     "'%s' is reserved (destruction and effects have no surface syntax)", buf);
    else
        osc_diag_set(p->d, OSC_DIAG_SYNTAX, t->line, t->col, buf, 0, NULL, what, "expected %s, found '%s'", what, buf);
    return -1;
}

static int expect(P *p, int k)
{
    if (!at(p, k)) return syntax(p, osc_tok_kind_name(k));
    adv(p);
    return 0;
}

_Static_assert(sizeof(OscNode) == 104 && offsetof(OscNode, kind) == 0 && offsetof(OscNode, line) == 4 &&
               offsetof(OscNode, col) == 8 && offsetof(OscNode, a) == 12 && offsetof(OscNode, b) == 16 &&
               offsetof(OscNode, c) == 20 && offsetof(OscNode, next) == 24 && offsetof(OscNode, tok) == 28 &&
               offsetof(OscNode, sym) == 88 && offsetof(OscNode, sym2) == 92, "OSC initial AST layout");
static int new_node(P *p, int kind, const OscToken *t)
{
    OscAst *a = p->ast;
    if (a->nnodes >= OSC_AST_MAX_NODES) {
        osc_diag_set(p->d, OSC_DIAG_CAPACITY, t->line, t->col, "unit", 0, NULL, "AST node capacity",
                     "more than %d AST nodes", OSC_AST_MAX_NODES);
        return -1;
    }
    int i = (int)a->nnodes++;
    osc_new_node((uint8_t *)&a->nodes[i], (uint16_t)kind, (uint32_t)(t - a->toks), t->line, t->col);
    return i;
}
#define N(i) (&p->ast->nodes[(i)])

static int enter(P *p)
{
    if (++p->depth > OSC_AST_MAX_DEPTH) {
        const OscToken *t = cur(p);
        osc_diag_set(p->d, OSC_DIAG_CAPACITY, t->line, t->col, "unit", 0, NULL, "nesting depth",
                     "nesting deeper than %d", OSC_AST_MAX_DEPTH);
        return -1;
    }
    return 0;
}
static void leave(P *p) { p->depth--; }

static int parse_expr(P *p);

/* ---- OSC-2 structs (docs/osc/OSC-2-DESIGN.md section 2) ---------------- */
static int tok_eq(P *p, const OscToken *t, const char *s)
{
    size_t n = strlen(s);
    return t->kind == OT_NAME && t->len == n && memcmp(p->ast->src + t->off, s, n) == 0;
}

/* index of the struct named by token t, -1 if none is declared (yet) */
_Static_assert(offsetof(OscStruct, name) == 0 && offsetof(OscField, name) == 0 &&
               OSC_NAME_MAX == 64, "OSC record name layout");

static int find_struct(P *p, const OscToken *t)
{
    if (t->kind != OT_NAME) return -1;
    return (int)osc_record_name((const uint8_t *)p->ast->structs,
                                (size_t)p->ast->nstructs * sizeof(OscStruct),
                                (const uint8_t *)p->ast->src + t->off, t->len, sizeof(OscStruct), 0);
}

static int find_field(P *p, int k, const OscToken *t)
{
    if (t->kind != OT_NAME) return -1;
    const OscStruct *s = &p->ast->structs[k];
    return (int)osc_record_name((const uint8_t *)s->fields, s->nfields * sizeof(OscField),
                                (const uint8_t *)p->ast->src + t->off, t->len, sizeof(OscField), 0);
}

static int undefined_type(P *p, const OscToken *t)
{
    char nm[64];
    osc_tok_text(p->ast->src, t, nm, sizeof nm);
    osc_diag_set(p->d, OSC_DIAG_UNDEFINED_TYPE, t->line, t->col, nm, 0, NULL, "undefined struct type",
                 "struct type '%s' is not declared (structs are declared before use)", nm);
    return -1;
}

/* a struct named where a value type is expected (let x: S, p: S, -> S) */
static int struct_by_value(P *p, const OscToken *t, const char *transition)
{
    char nm[64];
    osc_tok_text(p->ast->src, t, nm, sizeof nm);
    osc_diag_set(p->d, OSC_DIAG_UNSUPPORTED, t->line, t->col, nm, p->ast->struct_line[find_struct(p, t)], NULL,
                 transition, "struct '%s' is used through 'own', '&' or '&mut' only; it is never a value "
                 "or a return type", nm);
    return -1;
}

/* NAME with the ref kind already consumed: a reference to a declared struct */
static int parse_struct_ref(P *p, OscType *ty, OscRefKind rk)
{
    const OscToken *t = cur(p);
    int k = find_struct(p, t);
    if (k < 0) return undefined_type(p, t);
    adv(p);
    memset(ty, 0, sizeof *ty);
    ty->s = OSC_T_REF;
    ty->ref = rk;
    ty->elem = OSC_T_VOID;
    ty->len = p->ast->structs[k].ncells;
    ty->sid = (uint8_t)(k + 1);
    return 0;
}

/* OSC-3 item 2: pools and handles are function-local (never parameters or
 * results) */
static int local_only(P *p)
{
    const OscToken *t = cur(p);
    osc_diag_set(p->d, OSC_DIAG_UNSUPPORTED, t->line, t->col, at(p, OT_HANDLE) ? "handle" : "pool", 0, NULL,
                 "handle crosses a function boundary",
                 "pools and handles are function-local: no handle or pool parameters or return types");
    return -1;
}

/* The longest type spelling has OSC_TYPE_WINDOW tokens. A zero kind pads
 * the end of the stream with EOF, as peek_kind does. The grammar consumes
 * only its prefix and returns the offset of the exact failure token. */
static int parse_type(P *p, OscType *ty, unsigned form, OscRefKind ref)
{
    uint16_t kinds[OSC_TYPE_WINDOW] = {0};
    uint64_t values[OSC_TYPE_WINDOW] = {0};
    uint32_t remaining = p->ast->ntok - p->pos;
    for (unsigned i = 0; i < remaining && i < OSC_TYPE_WINDOW; ++i) {
        kinds[i] = p->ast->toks[p->pos + i].kind;
        values[i] = p->ast->toks[p->pos + i].ival;
    }
    OscParsedType parsed;
    uint64_t status = osc_read_type(kinds, values, form, ref, OSC_MAX_ARRAY_LEN, &parsed);
    p->pos += parsed.used;
    if (status == 0) {
        *ty = (OscType){.s = (OscScalar)parsed.scalar, .ref = (OscRefKind)parsed.refkind,
                        .elem = (OscScalar)parsed.elem, .len = (uint16_t)parsed.count};
        return 0;
    }
    const OscToken *t = cur(p);
    switch (status) {
    case OSC_TYPE_NAMED_REF:
        return parse_struct_ref(p, ty, (OscRefKind)parsed.refkind);
    case OSC_TYPE_BARE_NAME:
        if (find_struct(p, t) >= 0) return struct_by_value(p, t, "struct by value");
        /* fall through */
    case OSC_TYPE_EXPECT_SCALAR:
        return syntax(p, "a type (u8 u16 u32 u64 i8 i16 i32 i64 bool)");
    case OSC_TYPE_LOCAL_ONLY:
        return local_only(p);
    case OSC_TYPE_SLICE_ESCAPE: {
        const char *name = osc_tok_kind_name(t->kind);
        osc_diag_set(p->d, OSC_DIAG_SLICE_ESCAPE, t->line, t->col, name, 0, NULL,
                     "slice type outside a parameter", "'%s' is a parameter type only: a slice is never a local, field, element or result", name);
        return -1;
    }
    case OSC_TYPE_EXPECT_OPEN: return syntax(p, osc_tok_kind_name(OT_LBRACK));
    case OSC_TYPE_EXPECT_SEMI: return syntax(p, osc_tok_kind_name(OT_SEMI));
    case OSC_TYPE_EXPECT_LENGTH: return syntax(p, "array length INT");
    case OSC_TYPE_EXPECT_CLOSE: return syntax(p, osc_tok_kind_name(OT_RBRACK));
    case OSC_TYPE_ZERO_LENGTH:
        osc_diag_set(p->d, OSC_DIAG_UNSUPPORTED, t->line, t->col, "array", 0, NULL, "array length 0",
                     "array length must be 1..%d", OSC_MAX_ARRAY_LEN);
        return -1;
    case OSC_TYPE_LONG_ARRAY:
        osc_diag_set(p->d, OSC_DIAG_CAPACITY, t->line, t->col, "array", 0, NULL, "array length",
                     "array length %llu > %d", (unsigned long long)t->ival, OSC_MAX_ARRAY_LEN);
        return -1;
    default: abort();
    }
}

/* struct_decl = "struct" NAME "{" field { "," field } [","] "}" ;
 * field = NAME ":" ( scalar | "[" scalar ";" INT "]" ) */
static int parse_struct(P *p)
{
    OscAst *a = p->ast;
    const OscToken *st = cur(p);
    adv(p);
    if (!at(p, OT_NAME)) return syntax(p, "a struct name");
    const OscToken *nt = cur(p);
    char sname[64];
    osc_tok_text(a->src, nt, sname, sizeof sname);
    int prev = find_struct(p, nt);
    if (prev >= 0) {
        osc_diag_set(p->d, OSC_DIAG_REDEFINED_NAME, nt->line, nt->col, sname, a->struct_line[prev], NULL,
                     "struct declared twice", "struct '%s' is already declared", sname);
        return -1;
    }
    if (a->nstructs >= OSC_MAX_STRUCTS) {
        osc_diag_set(p->d, OSC_DIAG_CAPACITY, nt->line, nt->col, sname, 0, NULL, "struct capacity",
                     "more than %d structs", OSC_MAX_STRUCTS);
        return -1;
    }
    adv(p);
    OscStruct *s = &a->structs[a->nstructs];
    memset(s, 0, sizeof *s);
    snprintf(s->name, sizeof s->name, "%s", sname);
    if (expect(p, OT_LBRACE)) return -1;
    if (at(p, OT_RBRACE)) {
        osc_diag_set(p->d, OSC_DIAG_UNSUPPORTED, nt->line, nt->col, sname, 0, NULL, "empty struct",
                     "struct '%s' declares no fields (1..%d required)", sname, OSC_MAX_FIELDS);
        return -1;
    }
    unsigned cells = 0;
    while (!at(p, OT_RBRACE)) {
        const OscToken *ft = cur(p);
        if (!at(p, OT_NAME)) return syntax(p, "a field name");
        char fname[64];
        osc_tok_text(a->src, ft, fname, sizeof fname);
        for (int g = 0; g < s->nfields; g++)
            if (!strcmp(s->fields[g].name, fname)) {
                osc_diag_set(p->d, OSC_DIAG_DUPLICATE_FIELD, ft->line, ft->col, fname, nt->line, sname,
                             "field declared twice", "struct '%s' declares field '%s' twice", sname, fname);
                return -1;
            }
        if (s->nfields >= OSC_MAX_FIELDS) {
            osc_diag_set(p->d, OSC_DIAG_CAPACITY, ft->line, ft->col, sname, nt->line, fname, "field capacity",
                         "struct '%s' has more than %d fields", sname, OSC_MAX_FIELDS);
            return -1;
        }
        adv(p);
        if (expect(p, OT_COLON)) return -1;
        OscField *fd = &s->fields[s->nfields];
        snprintf(fd->name, sizeof fd->name, "%s", fname);
        const OscToken *tt = cur(p);
        if (at(p, OT_OWN) || at(p, OT_AMP) || at(p, OT_NAME)) {
            uint32_t q = p->pos;
            while (q < a->ntok && (a->toks[q].kind == OT_OWN || a->toks[q].kind == OT_AMP || a->toks[q].kind == OT_MUT)) q++;
            const OscToken *rt = &a->toks[q];
            if (tok_eq(p, rt, sname)) {
                osc_diag_set(p->d, OSC_DIAG_RECURSIVE_STRUCT, rt->line, rt->col, sname, nt->line, fname,
                             "struct field of its own type", "field '%s' of struct '%s' names '%s' itself "
                             "(no recursive or self-referential structs)", fname, sname, sname);
                return -1;
            }
            if (rt->kind == OT_NAME && find_struct(p, rt) < 0 && tt->kind == OT_NAME) return undefined_type(p, rt);
            osc_diag_set(p->d, OSC_DIAG_UNSUPPORTED, tt->line, tt->col, fname, nt->line, sname,
                         tt->kind == OT_NAME ? "struct-typed field" : "owner or borrow field",
                         "field '%s': a field is an integer, bool or fixed array [T; N]", fname);
            return -1;
        }
        if (at(p, OT_LBRACK)) {
            OscType at_;
            if (parse_type(p, &at_, OSC_TYPE_ARRAY, OSC_REF_OWN)) return -1;
            fd->s = at_.elem;
            fd->alen = at_.len;
        } else {
            OscType sc;
            if (parse_type(p, &sc, OSC_TYPE_SCALAR, OSC_REF_NONE)) return -1;
            fd->s = sc.s;
        }
        fd->off = (uint16_t)cells;
        cells += fd->alen ? fd->alen : 1;
        if (cells > OSC_MAX_ARRAY_LEN) {
            osc_diag_set(p->d, OSC_DIAG_CAPACITY, tt->line, tt->col, sname, nt->line, fname, "struct size",
                         "struct '%s' needs more than %d cells", sname, OSC_MAX_ARRAY_LEN);
            return -1;
        }
        s->nfields++;
        if (at(p, OT_COMMA)) { adv(p); continue; }
        if (!at(p, OT_RBRACE)) return syntax(p, "',' or '}' after a field");
    }
    adv(p);
    s->ncells = (uint16_t)cells;
    a->struct_line[a->nstructs++] = st->line;
    return 0;
}

/* struct literal  S "{" NAME ":" ( expr | "[" expr ";" INT "]" ) { "," ... } [","] "}"
 * as the initialiser of `let x: own S`; cur is S. Fills n->a with ON_FINIT
 * nodes. Every field exactly once: UNKNOWN_FIELD / DUPLICATE_FIELD / MISSING_FIELD. */
static int parse_struct_lit(P *p, int n)
{
    OscAst *a = p->ast;
    const OscToken *lt = cur(p);
    int k = find_struct(p, lt);
    char bname[64];
    osc_node_name(a, N(n), bname, sizeof bname);
    if (k < 0) return undefined_type(p, lt);
    const OscStruct *s = &a->structs[k];
    if (k + 1 != N(n)->ty.sid) {
        osc_diag_set(p->d, OSC_DIAG_TYPE_MISMATCH, lt->line, lt->col, bname, N(n)->line,
                     s->name, "struct literal of another type", "'%s' is declared own %s, initialised with a %s literal",
                     bname, a->structs[N(n)->ty.sid - 1].name, s->name);
        return -1;
    }
    adv(p);
    if (expect(p, OT_LBRACE)) return -1;
    uint32_t seen = 0;
    int last = -1;
    while (!at(p, OT_RBRACE)) {
        const OscToken *ft = cur(p);
        if (!at(p, OT_NAME)) return syntax(p, "a field name");
        char fname[64];
        osc_tok_text(a->src, ft, fname, sizeof fname);
        int f = find_field(p, k, ft);
        if (f < 0) {
            osc_diag_set(p->d, OSC_DIAG_UNKNOWN_FIELD, ft->line, ft->col, fname, a->struct_line[k], s->name,
                         "initialise unknown field", "struct '%s' has no field '%s'", s->name, fname);
            return -1;
        }
        if (seen >> f & 1) {
            osc_diag_set(p->d, OSC_DIAG_DUPLICATE_FIELD, ft->line, ft->col, fname, lt->line, s->name,
                         "field initialised twice", "field '%s' of '%s' is initialised twice", fname, s->name);
            return -1;
        }
        seen |= 1u << f;
        int fi = new_node(p, ON_FINIT, ft);
        if (fi < 0) return -1;
        N(fi)->hi = f;
        adv(p);
        if (expect(p, OT_COLON)) return -1;
        const OscField *fd = &s->fields[f];
        if (fd->alen) {
            if (!at(p, OT_LBRACK)) {
                const OscToken *t = cur(p);
                osc_diag_set(p->d, OSC_DIAG_TYPE_MISMATCH, t->line, t->col, fname, a->struct_line[k], s->name,
                             "array field without [e; N]", "array field '%s' is initialised with '[value; %u]'",
                             fname, fd->alen);
                return -1;
            }
            adv(p);
            int e = parse_expr(p);
            if (e < 0) return -1;
            N(fi)->a = e;
            if (expect(p, OT_SEMI)) return -1;
            if (!at(p, OT_INT)) return syntax(p, "array length INT");
            const OscToken *nt = cur(p);
            if (nt->ival != fd->alen) {
                osc_diag_set(p->d, OSC_DIAG_TYPE_MISMATCH, nt->line, nt->col, fname, a->struct_line[k], s->name,
                             "array field length mismatch", "array field '%s' has length %u, initialiser gives %llu",
                             fname, fd->alen, (unsigned long long)nt->ival);
                return -1;
            }
            N(fi)->flag = 1;
            N(fi)->ival = nt->ival;
            adv(p);
            if (expect(p, OT_RBRACK)) return -1;
        } else {
            int e = parse_expr(p);
            if (e < 0) return -1;
            N(fi)->a = e;
        }
        if (last < 0) N(n)->a = fi; else N(last)->next = fi;
        last = fi;
        if (at(p, OT_COMMA)) { adv(p); continue; }
        if (!at(p, OT_RBRACE)) return syntax(p, "',' or '}' in a struct literal");
    }
    for (int f = 0; f < s->nfields; f++)
        if (!(seen >> f & 1)) {
            const OscToken *t = cur(p);
            osc_diag_set(p->d, OSC_DIAG_MISSING_FIELD, t->line, t->col, s->fields[f].name, lt->line, s->name,
                         "field not initialised", "struct literal of '%s' does not initialise field '%s'",
                         s->name, s->fields[f].name);
            return -1;
        }
    adv(p);
    return 0;
}

/* NAME "." NAME [ "[" expr "]" ] ; cur is the first NAME. kind = ON_FIELD / ON_FSTORE */
static int parse_field_ref(P *p, int kind)
{
    int n = new_node(p, kind, cur(p));
    if (n < 0) return -1;
    adv(p);
    adv(p);  /* '.' */
    if (!at(p, OT_NAME)) return syntax(p, "a field name after '.'");
    N(n)->lo = p->pos;
    adv(p);
    if (at(p, OT_LBRACK)) {
        adv(p);
        int ix = parse_expr(p);
        if (ix < 0) return -1;
        N(n)->a = ix;
        if (expect(p, OT_RBRACK)) return -1;
    }
    return n;
}

static int parse_expr(P *p);
static int parse_block(P *p);

static int parse_borrow(P *p)
{
    int n = new_node(p, ON_BORROW, cur(p));
    if (n < 0) return -1;
    if (expect(p, OT_AMP)) return -1;
    if (at(p, OT_MUT)) { N(n)->mut = 1; adv(p); }
    if (!at(p, OT_NAME)) return syntax(p, "a name after '&'");
    N(n)->tok = p->pos;
    N(n)->line = cur(p)->line;
    N(n)->col = cur(p)->col;
    adv(p);
    return n;
}

/* call: NAME "(" [arg {"," arg}] ")" ; cur is NAME */
static int parse_call(P *p)
{
    int n = new_node(p, ON_CALL, cur(p));
    if (n < 0) return -1;
    if (enter(p)) return -1;
    adv(p);
    if (expect(p, OT_LPAREN)) return -1;
    int last = -1;
    if (!at(p, OT_RPAREN)) {
        for (;;) {
            int a = at(p, OT_AMP) ? parse_borrow(p) : parse_expr(p);
            if (a < 0) return -1;
            if (last < 0) N(n)->a = a; else N(last)->next = a;
            last = a;
            if (at(p, OT_COMMA)) { adv(p); continue; }
            break;
        }
    }
    if (expect(p, OT_RPAREN)) return -1;
    leave(p);
    return n;
}

static int parse_operand(P *p)
{
    OscOperandState state = {0};
    const uint32_t first_prefix = p->ast->nnodes;
    int value = -1;
    for (;;) {
        const OscToken *t = cur(p);
        uint64_t action = osc_operand_step(&state, t->kind, peek_kind(p, 1), peek_kind(p, 2));
        int n;
        switch (action) {
        case OSC_OPERAND_PREFIX:
            if (enter(p) || new_node(p, ON_UN, t) < 0) return -1;
            adv(p);
            break;
        case OSC_OPERAND_UNWIND:
            n = (int)(first_prefix + state.pending);
            N(n)->op = p->ast->toks[N(n)->tok].kind;
            N(n)->a = value;
            leave(p);
            value = n;
            break;
        case OSC_OPERAND_INTEGER:
        case OSC_OPERAND_TRUE:
        case OSC_OPERAND_FALSE:
        case OSC_OPERAND_NAME: {
            int kind = action == OSC_OPERAND_INTEGER ? ON_INT : action == OSC_OPERAND_NAME ? ON_NAME : ON_BOOL;
            value = new_node(p, kind, t);
            if (value < 0) return -1;
            N(value)->ival = action == OSC_OPERAND_INTEGER ? t->ival : action == OSC_OPERAND_TRUE;
            adv(p);
            break;
        }
        case OSC_OPERAND_CALL:
            value = parse_call(p);
            if (value < 0) return -1;
            break;
        case OSC_OPERAND_FIELD:
            value = parse_field_ref(p, ON_FIELD);
            if (value < 0) return -1;
            break;
        case OSC_OPERAND_INDEX:
            n = new_node(p, ON_INDEX, t);
            if (n < 0) return -1;
            adv(p); adv(p);
            value = parse_expr(p);
            if (value < 0) return -1;
            N(n)->a = value;
            if (expect(p, OT_RBRACK)) return -1;
            value = n;
            break;
        case OSC_OPERAND_POOL:
            n = new_node(p, ON_PALLOC, t);
            if (n < 0) return -1;
            adv(p); adv(p); adv(p);
            if (expect(p, OT_LPAREN) || enter(p)) return -1;
            value = parse_expr(p);
            leave(p);
            if (value < 0) return -1;
            N(n)->a = value;
            if (expect(p, OT_RPAREN)) return -1;
            value = n;
            break;
        case OSC_OPERAND_GROUP:
            if (enter(p)) return -1;
            adv(p);
            value = parse_expr(p);
            if (value < 0 || expect(p, OT_RPAREN)) return -1;
            leave(p);
            break;
        case OSC_OPERAND_CAST:
            n = new_node(p, ON_CAST, t);
            if (n < 0) return -1;
            adv(p);
            if (parse_type(p, &N(n)->ty, OSC_TYPE_SCALAR, OSC_REF_NONE)) return -1;
            N(n)->a = value;
            N(n)->line = N(value)->line;
            N(n)->col = N(value)->col;
            value = n;
            break;
        case OSC_OPERAND_DONE:
            return value;
        case OSC_OPERAND_CAST_ERROR:
            return syntax(p, "';' (chained 'as' needs parentheses)");
        case OSC_OPERAND_BORROW_ERROR:
            osc_diag_set(p->d, OSC_DIAG_UNSUPPORTED, t->line, t->col, "&", 0, NULL, "borrow in expression",
                         "a borrow may only be a call argument or a borrow binding's value");
            return -1;
        case OSC_OPERAND_SYNTAX:
            return syntax(p, "an expression");
        default:
            abort();
        }
    }
}

/* Omega decides when to consume the next operator and when to finish an
 * existing node. Allocate at the operator token and attach edges only after
 * the right operand parses, preserving the AST prefix on syntax errors. */
static int parse_expr(P *p)
{
    OscExprStack stack = {0};
    int operand = parse_operand(p);
    while (operand >= 0) {
        uint64_t action = osc_expr_step(&stack, cur(p)->kind, (uint64_t)operand);
        switch (action) {
        case OSC_EXPR_DONE:
            return operand;
        case OSC_EXPR_SHIFT: {
            int n = new_node(p, ON_BIN, cur(p));
            if (n < 0) return -1;
            stack.node[stack.depth - 1] = n;
            N(n)->op = cur(p)->kind;
            adv(p);
            operand = parse_operand(p);
            break;
        }
        case OSC_EXPR_REDUCE:
        case OSC_EXPR_CHAINED:
            N(stack.parent)->a = stack.left;
            N(stack.parent)->b = operand;
            if (action == OSC_EXPR_CHAINED)
                return syntax(p, "no second comparison (comparisons do not chain)");
            operand = stack.parent;
            break;
        default:
            abort();
        }
    }
    return -1;
}

static int parse_name_tok(P *p, int n)
{
    if (!at(p, OT_NAME)) return syntax(p, "a name");
    N(n)->tok = p->pos;
    adv(p);
    return 0;
}

static int parse_for_range(P *p, int n, const OscToken *kw)
{
    uint16_t kinds[OSC_FOR_WINDOW] = {0};
    uint64_t values[OSC_FOR_WINDOW] = {0};
    uint32_t start = p->pos;
    for (unsigned i = 0; i < OSC_FOR_WINDOW && i < p->ast->ntok - start; ++i) {
        kinds[i] = p->ast->toks[start + i].kind;
        values[i] = p->ast->toks[start + i].ival;
    }
    OscForRange range;
    uint64_t status = osc_for_range(kinds, values, LOOP_BOUND_MAX, &range);
    if (range.used) N(n)->tok = start;
    p->pos += range.used;
    N(n)->lo = (int64_t)range.low;
    N(n)->hi = (int64_t)range.high;
    switch (status) {
    case 0: return 0;
    case OSC_FOR_NAME: return syntax(p, "a name");
    case OSC_FOR_IN: return syntax(p, osc_tok_kind_name(OT_IN));
    case OSC_FOR_INT: return syntax(p, "an integer literal");
    case OSC_FOR_DOTS: return syntax(p, osc_tok_kind_name(OT_DOTDOT));
    case OSC_FOR_OVERFLOW:
        osc_diag_set(p->d, OSC_DIAG_OVERFLOW_UNSAFE, cur(p)->line, cur(p)->col, "for", 0, NULL,
                     "literal does not fit i64", "for-loop end does not fit i64");
        return -1;
    case OSC_FOR_TRIPS: {
        char nm[64];
        osc_node_name(p->ast, N(n), nm, sizeof nm);
        const OscToken *lt = &p->ast->toks[start + range.lower_at];
        osc_diag_set(p->d, OSC_DIAG_UNBOUNDED_LOOP, lt->line, lt->col, nm, kw->line, NULL,
                     "for range outside 0..1000000 trips", "for range must satisfy A <= B and B - A <= %d",
                     LOOP_BOUND_MAX);
        return -1;
    }
    default: abort();
    }
}

static int parse_bound(P *p, int n, const OscToken *kw)
{
    int arena = kw->kind == OT_ARENA;
    int limit = arena ? OSC_ARENA_MAX_CELLS : LOOP_BOUND_MAX;
    const OscToken *value = p->pos + 1 < p->ast->ntok ? cur(p) + 1 : cur(p);
    uint64_t status = osc_read_bound(cur(p)->kind, value->kind, value->ival, limit);
    if (status == OSC_BOUND_KEYWORD) {
        if (arena) return syntax(p, "'bound K' after the arena name");
        osc_diag_set(p->d, OSC_DIAG_UNBOUNDED_LOOP, kw->line, kw->col, "while", 0, NULL, "while without bound",
                     "'while' needs 'bound N' (static trip-count bound)");
        return -1;
    }
    adv(p);
    if (status == OSC_BOUND_INT) return syntax(p, "bound INT");
    if (status == OSC_BOUND_RANGE) {
        if (arena) {
            char nm[64];
            osc_node_name(p->ast, N(n), nm, sizeof nm);
            osc_diag_set(p->d, OSC_DIAG_ARENA_CAPACITY, value->line, value->col, nm, kw->line, NULL,
                         "arena bound outside 1..64", "arena bound %llu outside 1..%d cells",
                         (unsigned long long)value->ival, limit);
        } else {
            osc_diag_set(p->d, OSC_DIAG_UNBOUNDED_LOOP, value->line, value->col, "while", kw->line, NULL,
                         "bound outside 1..1000000", "loop bound %llu outside 1..%d",
                         (unsigned long long)value->ival, limit);
        }
        return -1;
    }
    if (status != 0) abort();
    N(n)->ival = value->ival;
    adv(p);
    return 0;
}

static int parse_if(P *p);

_Static_assert(ON_ASSIGN == 8 && ON_STORE == 9 && ON_RETURN == 13 && ON_CALLSTMT == 14 &&
               ON_FSTORE == 26 && ON_PFREE == 31, "statement plan AST kinds");

static int parse_simple_stmt(P *p)
{
    const OscToken *t = cur(p);
    const OscToken *third = p->ast->ntok - p->pos > 2 ? t + 2 : &p->ast->toks[p->ast->ntok - 1];
    OscStmtPlan plan;
    if (osc_statement_plan(&plan, t->kind, peek_kind(p, 1), third->kind,
                           (const uint8_t *)p->ast->src + third->off, third->len)) {
        adv(p);
        return syntax(p, "'=', '[' or '(' after a name at statement start");
    }
    int n = plan.nodekind == ON_FSTORE ? parse_field_ref(p, ON_FSTORE) : new_node(p, plan.nodekind, t);
    if (n < 0) return -1;
    p->pos += plan.skip;
    int index = -1;
    for (unsigned i = 0; i < plan.steps; ++i) {
        unsigned action = plan.actions[i];
        int child;
        switch (action) {
        case OSC_ST_CALL: child = parse_call(p); break;
        case OSC_ST_BORROW_A: child = parse_borrow(p); break;
        case OSC_ST_INDEX:
        case OSC_ST_EXPR_A:
        case OSC_ST_EXPR_B: child = parse_expr(p); break;
        case OSC_ST_STORE:
            if (at(p, OT_AMP)) {
                const OscToken *bt = cur(p);
                char nm[64];
                osc_node_name(p->ast, N(n), nm, sizeof nm);
                osc_diag_set(p->d, OSC_DIAG_BORROW_OUTLIVES_OWNER, bt->line, bt->col, nm, 0, NULL,
                             "store borrow into array", "a borrow cannot be stored anywhere but a borrow binding");
                return -1;
            }
            child = parse_expr(p);
            break;
        default:
            if (expect(p, (int)action)) return -1;
            continue;
        }
        if (child < 0) return -1;
        if (action == OSC_ST_INDEX) index = child;
        else if (action == OSC_ST_STORE) { N(n)->a = index; N(n)->b = child; }
        else if (action == OSC_ST_EXPR_B) N(n)->b = child;
        else N(n)->a = child;
    }
    return n;
}

static int parse_stmt(P *p)
{
    const OscToken *t = cur(p);
    int n;
    switch (t->kind) {
    case OT_LET: {
        adv(p);
        int mut = 0;
        if (at(p, OT_MUT)) { mut = 1; adv(p); }
        n = new_node(p, ON_LET, t);
        if (n < 0) return -1;
        if (parse_name_tok(p, n)) return -1;
        if (expect(p, OT_COLON)) return -1;
        if (at(p, OT_HANDLE)) { /* OSC-3 item 2: let [mut] h: handle P = P.alloc(e) | h2; */
            N(n)->kind = ON_LET_HANDLE;
            N(n)->mut = (uint8_t)mut;
            adv(p);
            if (!at(p, OT_NAME)) return syntax(p, "a pool name after 'handle'");
            int pn = new_node(p, ON_NAME, cur(p));
            if (pn < 0) return -1;
            adv(p);
            N(n)->c = pn;
            if (expect(p, OT_ASSIGN)) return -1;
            int e = parse_expr(p);
            if (e < 0) return -1;
            N(n)->a = e;
            if (expect(p, OT_SEMI)) return -1;
            return n;
        }
        if (at(p, OT_OWN)) {
            if (mut) {
                const OscToken *mt = &p->ast->toks[N(n)->tok - 1];
                osc_diag_set(p->d, OSC_DIAG_SYNTAX, mt->line, mt->col, "mut", 0, NULL, "let mut owner",
                             "an owner binding cannot be 'mut' (owners are never reassigned)");
                return -1;
            }
            adv(p);
            if (parse_type(p, &N(n)->ty, OSC_TYPE_REF_BODY, OSC_REF_OWN)) return -1;
            int in_arena = -1; /* OSC-2 arenas: "in NAME" */
            if (at(p, OT_IN)) {
                adv(p);
                if (!at(p, OT_NAME)) return syntax(p, "an arena name after 'in'");
                in_arena = new_node(p, ON_NAME, cur(p));
                if (in_arena < 0) return -1;
                adv(p);
            }
            if (expect(p, OT_ASSIGN)) return -1;
            if (N(n)->ty.sid && at(p, OT_NAME) && peek_kind(p, 1) == OT_LBRACE) {
                N(n)->kind = ON_LET_ALLOC;
                if (parse_struct_lit(p, n)) return -1;
            } else if (N(n)->ty.sid && at(p, OT_ALLOC)) {
                const OscToken *at_ = cur(p);
                char nm[64];
                osc_node_name(p->ast, N(n), nm, sizeof nm);
                osc_diag_set(p->d, OSC_DIAG_UNSUPPORTED, at_->line, at_->col, nm, 0,
                             p->ast->structs[N(n)->ty.sid - 1].name, "alloc of a struct",
                             "a struct owner is created by a struct literal, not alloc");
                return -1;
            } else if (at(p, OT_ALLOC)) {
                adv(p);
                N(n)->kind = ON_LET_ALLOC;
                if (expect(p, OT_LPAREN)) return -1;
                int e = parse_expr(p);
                if (e < 0) return -1;
                N(n)->a = e;
                if (expect(p, OT_RPAREN)) return -1;
            } else if (at(p, OT_NAME)) {
                N(n)->kind = ON_LET_MOVE;
                int s = new_node(p, ON_NAME, cur(p));
                if (s < 0) return -1;
                adv(p);
                N(n)->a = s;
            } else {
                return syntax(p, "'alloc' or an owner name");
            }
            N(n)->c = in_arena;
        } else if (at(p, OT_AMP)) {
            N(n)->kind = ON_LET_BORROW;
            N(n)->mut = (uint8_t)mut;
            adv(p);
            OscRefKind rk = OSC_REF_SHARED;
            if (at(p, OT_MUT)) { rk = OSC_REF_MUT; adv(p); }
            if (parse_type(p, &N(n)->ty, OSC_TYPE_REF_BODY, rk)) return -1;
            if (expect(p, OT_ASSIGN)) return -1;
            if (!at(p, OT_AMP)) return syntax(p, "a borrow '&name' or '&mut name'");
            int b = parse_borrow(p);
            if (b < 0) return -1;
            N(n)->a = b;
        } else {
            N(n)->mut = (uint8_t)mut;
            if (at(p, OT_NAME) && find_struct(p, cur(p)) >= 0) return struct_by_value(p, cur(p), "struct by value");
            if (parse_type(p, &N(n)->ty, OSC_TYPE_SCALAR, OSC_REF_NONE)) return -1;
            if (expect(p, OT_ASSIGN)) return -1;
            int e = parse_expr(p);
            if (e < 0) return -1;
            N(n)->a = e;
        }
        if (expect(p, OT_SEMI)) return -1;
        return n;
    }
    case OT_NAME:
    case OT_RETURN:
        return parse_simple_stmt(p);
    case OT_POOL: { /* OSC-3 item 2: pool NAME: [T; K] [gen B] { ... } */
        n = new_node(p, ON_POOL, t);
        if (n < 0) return -1;
        adv(p);
        if (parse_name_tok(p, n)) return -1;
        if (expect(p, OT_COLON)) return -1;
        if (expect(p, OT_LBRACK)) return -1;
        if (parse_type(p, &N(n)->ty, OSC_TYPE_SCALAR, OSC_REF_NONE)) return -1;
        if (expect(p, OT_SEMI)) return -1;
        if (!at(p, OT_INT)) return syntax(p, "a slot count INT");
        const OscToken *kt = cur(p);
        if (kt->ival == 0 || kt->ival > OSC_POOL_MAX_SLOTS) {
            char nm[64];
            osc_node_name(p->ast, N(n), nm, sizeof nm);
            osc_diag_set(p->d, OSC_DIAG_POOL_CAPACITY, kt->line, kt->col, nm, t->line, NULL,
                         "pool size outside 1..16", "pool size %llu outside 1..%d slots",
                         (unsigned long long)kt->ival, OSC_POOL_MAX_SLOTS);
            return -1;
        }
        N(n)->ival = kt->ival;
        adv(p);
        if (expect(p, OT_RBRACK)) return -1;
        N(n)->lo = 0;
        if (at(p, OT_NAME) && tok_eq(p, cur(p), "gen")) { /* declared generation base */
            adv(p);
            if (!at(p, OT_INT)) return syntax(p, "gen INT (the generation base)");
            N(n)->lo = (int64_t)cur(p)->ival;
            adv(p);
        }
        int b = parse_block(p);
        if (b < 0) return -1;
        N(n)->b = b;
        return n;
    }
    case OT_ARENA: { /* OSC-2 arenas: arena NAME bound K { ... } */
        n = new_node(p, ON_ARENA, t);
        if (n < 0) return -1;
        adv(p);
        if (parse_name_tok(p, n)) return -1;
        if (parse_bound(p, n, t)) return -1;
        int b = parse_block(p);
        if (b < 0) return -1;
        N(n)->b = b;
        return n;
    }
    case OT_IF:
        return parse_if(p);
    case OT_WHILE: {
        n = new_node(p, ON_WHILE, t);
        if (n < 0) return -1;
        adv(p);
        int c = parse_expr(p);
        if (c < 0) return -1;
        N(n)->a = c;
        if (parse_bound(p, n, t)) return -1;
        N(n)->flag = 1;
        int b = parse_block(p);
        if (b < 0) return -1;
        N(n)->b = b;
        return n;
    }
    case OT_FOR: {
        n = new_node(p, ON_FOR, t);
        if (n < 0) return -1;
        adv(p);
        if (parse_for_range(p, n, t)) return -1;
        int b = parse_block(p);
        if (b < 0) return -1;
        N(n)->b = b;
        return n;
    }
    case OT_LBRACE:
        return parse_block(p);
    default:
        return syntax(p, "a statement");
    }
}

static int parse_if(P *p)
{
    if (enter(p)) return -1;
    int n = new_node(p, ON_IF, cur(p));
    if (n < 0) return -1;
    adv(p);
    int c = parse_expr(p);
    if (c < 0) return -1;
    N(n)->a = c;
    int b = parse_block(p);
    if (b < 0) return -1;
    N(n)->b = b;
    if (at(p, OT_ELSE)) {
        adv(p);
        int e = at(p, OT_IF) ? parse_if(p) : parse_block(p);
        if (e < 0) return -1;
        N(n)->c = e;
    }
    leave(p);
    return n;
}

static int parse_block(P *p)
{
    if (enter(p)) return -1;
    int n = new_node(p, ON_BLOCK, cur(p));
    if (n < 0) return -1;
    if (expect(p, OT_LBRACE)) return -1;
    int last = -1;
    while (!at(p, OT_RBRACE)) {
        if (at(p, OT_EOF)) return syntax(p, "'}'");
        int s = parse_stmt(p);
        if (s < 0) return -1;
        if (last < 0) N(n)->a = s; else N(last)->next = s;
        last = s;
    }
    N(n)->ival = cur(p)->line; /* closing brace line */
    adv(p);
    leave(p);
    return n;
}

/* clause: one expression (OSC-2, docs/osc/OSC-2-DESIGN.md section 1). The
 * source text is still recorded (token spellings joined by single spaces,
 * none after '(' or before ')') and carried into the IR; the expression node
 * is checked and lowered into runtime checks by the checker / lowerer. */
_Static_assert(OSC_CLAUSE_MAX == 256 && sizeof(OscToken) == 32 && offsetof(OscToken, kind) == 0 &&
               offsetof(OscToken, off) == 12 && offsetof(OscToken, len) == 16, "OSC clause spelling layout");
static int parse_clause(P *p, char *out, const OscToken *kw, int32_t *node)
{
    uint32_t start = p->pos;
    out[0] = 0;
    if (at(p, OT_LBRACE) || at(p, OT_ENSURES) || at(p, OT_EOF)) return syntax(p, "a contract expression");
    int e = parse_expr(p);
    if (e < 0) return -1;
    if (!at(p, OT_LBRACE) && !at(p, OT_ENSURES))
        return syntax(p, "'ensures' or a function body '{' after the contract expression");
    const OscToken *last = &p->ast->toks[p->pos - 1];
    size_t source_end = (size_t)last->off + last->len;
    size_t token_bytes = (size_t)(p->pos - start) * sizeof(OscToken);
    if (osc_clause_text((uint8_t *)out, (const uint8_t *)&p->ast->toks[start], token_bytes,
                        (const uint8_t *)p->ast->src, source_end) == OSC_CLAUSE_MAX) {
        osc_diag_set(p->d, OSC_DIAG_CAPACITY, kw->line, kw->col, osc_tok_kind_name(kw->kind), 0, NULL,
                     "contract text length", "contract clause longer than %d bytes", OSC_CLAUSE_MAX - 1);
        return -1;
    }
    *node = e;
    return 0;
}

static int parse_fn(P *p)
{
    OscAst *a = p->ast;
    const OscToken *ft = cur(p);
    if (expect(p, OT_FN)) return -1;
    if (a->nfns >= OSC_MAX_FUNCS) {
        osc_diag_set(p->d, OSC_DIAG_CAPACITY, ft->line, ft->col, "unit", 0, NULL, "function capacity",
                     "more than %d functions", OSC_MAX_FUNCS);
        return -1;
    }
    int f = new_node(p, ON_FN, ft);
    if (f < 0) return -1;
    if (parse_name_tok(p, f)) return -1;
    N(f)->line = a->toks[N(f)->tok].line;
    N(f)->col = a->toks[N(f)->tok].col;
    char fname[64];
    osc_node_name(a, N(f), fname, sizeof fname);
    if (expect(p, OT_LPAREN)) return -1;
    int last = -1, np = 0, nslice = 0;
    if (!at(p, OT_RPAREN)) {
        for (;;) {
            int pn = new_node(p, ON_PARAM, cur(p));
            if (pn < 0) return -1;
            if (parse_name_tok(p, pn)) return -1;
            if (expect(p, OT_COLON)) return -1;
            if (parse_type(p, &N(pn)->ty, OSC_TYPE_PARAM, OSC_REF_NONE)) return -1;
            int is_slice = N(pn)->ty.s == OSC_T_BYTES || N(pn)->ty.s == OSC_T_CELLS;
            nslice += is_slice;
            np += is_slice ? 2 : 1; /* parameter registers: a slice is pointer + length */
            if (np > OSC_MAX_PARAMS && nslice) {
                osc_diag_set(p->d, OSC_DIAG_SLICE_PARAMS, N(pn)->line, N(pn)->col, fname, N(f)->line, NULL,
                             "parameter registers", "function '%s' needs %d parameter registers (a slice takes two); at most %d",
                             fname, np, OSC_MAX_PARAMS);
                return -1;
            }
            if (np > OSC_MAX_PARAMS) {
                osc_diag_set(p->d, OSC_DIAG_CAPACITY, N(pn)->line, N(pn)->col, fname, N(f)->line, NULL,
                             "parameter count", "function '%s' has more than %d parameters", fname, OSC_MAX_PARAMS);
                return -1;
            }
            if (last < 0) N(f)->a = pn; else N(last)->next = pn;
            last = pn;
            if (at(p, OT_COMMA)) { adv(p); continue; }
            break;
        }
    }
    if (expect(p, OT_RPAREN)) return -1;
    N(f)->ty.s = OSC_T_VOID;
    if (at(p, OT_ARROW)) {
        adv(p);
        {
            uint32_t q = p->pos;
            while (q < a->ntok && (a->toks[q].kind == OT_OWN || a->toks[q].kind == OT_AMP || a->toks[q].kind == OT_MUT)) q++;
            if (a->toks[q].kind == OT_NAME && find_struct(p, &a->toks[q]) >= 0)
                return struct_by_value(p, &a->toks[q], "struct return type");
        }
        if (at(p, OT_HANDLE) || at(p, OT_POOL)) return local_only(p);
        if (at(p, OT_OWN) || at(p, OT_AMP) || at(p, OT_LBRACK)) {
            const OscToken *t = cur(p);
            osc_diag_set(p->d, OSC_DIAG_UNSUPPORTED, t->line, t->col, fname, N(f)->line, NULL,
                         "array return type", "OSC-1 functions return a scalar only");
            return -1;
        }
        if (parse_type(p, &N(f)->ty, OSC_TYPE_SCALAR, OSC_REF_NONE)) return -1;
    }
    uint32_t fi = a->nfns;
    a->req[fi][0] = a->ens[fi][0] = 0;
    a->reqn[fi] = a->ensn[fi] = a->res_sym[fi] = -1;
    a->req_elide[fi] = a->ens_elide[fi] = 0;
    if (at(p, OT_REQUIRES)) {
        const OscToken *kw = cur(p);
        adv(p);
        if (parse_clause(p, a->req[fi], kw, &a->reqn[fi])) return -1;
    }
    if (at(p, OT_ENSURES)) {
        const OscToken *kw = cur(p);
        adv(p);
        if (parse_clause(p, a->ens[fi], kw, &a->ensn[fi])) return -1;
    }
    int b = parse_block(p);
    if (b < 0) return -1;
    N(f)->b = b;
    a->fns[a->nfns++] = f;
    return 0;
}

static int parse_import(P *p)
{
    OscAst *a = p->ast;
    const OscToken *kw = cur(p);
    const OscToken *nm = kw + 1; /* The import token always precedes another token or EOF. */
    size_t slots = a->nimports < OSC_MAX_IMPORTS ? a->nimports + 1u : 0u;
    OscImportParse entry = {.started = a->nstructs || a->nfns, .stride = sizeof(OscImport),
                            .nameoff = offsetof(OscImport, name), .nextkind = peek_kind(p, 2)};
    uint64_t status = osc_read_import(&entry, nm->kind,
                                      (const uint8_t *)a->src + nm->off, nm->len,
                                      (uint8_t *)a->imports, slots * sizeof(OscImport));
    if (status == OSC_IMPORT_POSITION) {
        osc_diag_set(p->d, OSC_DIAG_SYNTAX, kw->line, kw->col, "import", 0, NULL, "import position",
                     "imports must come before any struct or function");
        return -1;
    }
    adv(p);
    if (status == OSC_IMPORT_NAME) return syntax(p, "NAME");
    if (status == OSC_IMPORT_FULL) {
        osc_diag_set(p->d, OSC_DIAG_CAPACITY, kw->line, kw->col, "unit", 0, NULL, "import capacity",
                     "more than %d imports", OSC_MAX_IMPORTS);
        return -1;
    }
    OscImport *im = &a->imports[a->nimports];
    im->line = nm->line;
    im->col = nm->col;
    if (status == OSC_IMPORT_DUP) {
        osc_diag_set(p->d, OSC_DIAG_REDEFINED_NAME, nm->line, nm->col, im->name, a->imports[entry.match].line, NULL,
                     "import", "import '%s' is listed twice", im->name);
        return -1;
    }
    adv(p);
    if (status == OSC_IMPORT_SEMI) return syntax(p, osc_tok_kind_name(OT_SEMI));
    if (status != 0) abort();
    adv(p);
    a->nimports++;
    return 0;
}

int osc_parse(OscAst *ast, OscDiag *d)
{
    P p = {ast, d, 0, 0};
    ast->nnodes = 0;
    ast->nfns = 0;
    ast->nrel = 0;
    ast->nstructs = 0;
    ast->nimports = 0;
    while (!at(&p, OT_EOF)) {
        if (at(&p, OT_IMPORT)) {
            if (parse_import(&p)) return -1;
            continue;
        }
        if (at(&p, OT_STRUCT)) { if (parse_struct(&p)) return -1; continue; }
        if (parse_fn(&p)) return -1;
    }
    return 0;
}
