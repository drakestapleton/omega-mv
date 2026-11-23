/* SPDX-License-Identifier: Apache-2.0 */
/* lang_dump.c -- C reference dumper for the Omega language V0 lane (tests/language/lang_parity.sh).
 *
 * Reads source lines on stdin and runs each through omega_language_eval_line on one session,
 * the way the console's `source` command does. For every line it prints the return code, the
 * error text, the result, every graph object the line added, the binding/program counts and,
 * for a program result, the whole stored OmegaProgram. tests/language/lang_dump.om prints the
 * same lines from the pure OM-2 lane; the parity script compares the two byte for byte.
 * A line `#!clear` clears the session. After a successful line the last result (`_`) is set
 * as the console's `source` command sets it. */
#include "omega_lower.h"
#include "omega_canonical.h"
#include <stdio.h>
#include <string.h>

static void hex(const uint8_t *b, size_t n) {
    for (size_t i = 0; i < n; i++) printf("%02x", b[i]);
}

static const char *op_name(uint8_t op) {
    switch (op) {
    case OP_ADD: return "add";
    case OP_SUB: return "sub";
    case OP_MUL: return "mul";
    case OP_AND: return "and";
    case OP_OR: return "or";
    default: return "?";
    }
}

int main(void) {
    static VisorSession s;
    if (visor_session_init(&s) != 0) return 2;
    static char line[8192];
    unsigned long n = 0;
    while (fgets(line, sizeof line, stdin)) {
        size_t len = strlen(line);
        if (len && line[len - 1] == '\n') line[--len] = '\0';
        n++;
        if (strcmp(line, "#!clear") == 0) {
            visor_session_clear(&s);
            printf("L %lu clear\n", n);
            continue;
        }
        uint16_t before = s.graph->object_count;
        OmegaLangResult r;
        char err[512] = {0};
        int rc = omega_language_eval_line(&s, line, &r, err, sizeof err);
        printf("L %lu rc=%d err=%s\n", n, rc, err);
        if (rc == 0) {
            printf("R kind=%d id=", (int)r.kind);
            hex(r.id.bytes, 32);
            printf(" name=%s pidx=%d type=%s tid=", r.name, r.program_index, r.type_text);
            hex(r.type_id.bytes, 32);
            printf("\n");
            /* the console's visor_set_last after a successful line */
            if (r.kind != OMEGA_LANG_NONE) {
                VisorBinding b;
                memset(&b, 0, sizeof b);
                snprintf(b.name, sizeof b.name, "%s", r.kind == OMEGA_LANG_EXPRESSION ? "_" : r.name);
                b.kind = r.kind == OMEGA_LANG_PROGRAM ? VISOR_BIND_PROGRAM : VISOR_BIND_OBJECT;
                b.id = r.id;
                b.index = r.kind == OMEGA_LANG_PROGRAM ? r.program_index : -1;
                visor_set_last(&s, &b);
            }
        }
        for (uint16_t i = before; i < s.graph->object_count; i++) {
            printf("O %u kind=%d id=", (unsigned)i, (int)s.graph->objects[i].kind);
            hex(s.graph->objects[i].id.bytes, 32);
            printf("\n");
        }
        printf("C objs=%u binds=%zu progs=%zu\n", (unsigned)s.graph->object_count, s.bindings.count,
               s.program_count);
        if (rc == 0 && r.kind == OMEGA_LANG_PROGRAM && r.program_index >= 0) {
            const OmegaProgram *p = &s.programs[r.program_index];
            printf("P name=%s id=", p->name);
            hex(p->program_id.bytes, 32);
            printf(" pre=%s post=%s preid=", p->contract.precondition, p->contract.postcondition);
            hex(p->contract.precondition_id.bytes, 32);
            printf(" postid=");
            hex(p->contract.postcondition_id.bytes, 32);
            printf(" steps=");
            for (uint16_t i = 0; i < p->body.step_count; i++)
                printf("%s%s:%llu", i ? "," : "", op_name(p->body.steps[i].op),
                       (unsigned long long)p->body.steps[i].imm);
            printf(" realized=%d verified=%d code=", p->is_realized, p->is_verified);
            hex(p->realization.code_bytes, p->realization.code_len);
            printf(" rid=");
            hex(p->realization.realization_id.bytes, 32);
            printf("\n");
        }
    }
    visor_session_destroy(&s);
    return 0;
}
