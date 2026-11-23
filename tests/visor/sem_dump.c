/* SPDX-License-Identifier: Apache-2.0
 * sem_dump.c -- reference-only C dumper for tests/visor/sem_parity.sh: reads the corpus of
 * one-letter graph and query commands on stdin and prints what the C semantic lane
 * (src/visor/visor_semantic.c at main 3f2c70dc5) returns. It generates the goldens once; it is
 * committed with them and removed from the tree in the next commit. */
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "omega_canonical.h"
#include "omega_core.h"
#include "visor_semantic.h"

static OmegaGraph g;
static char ob[65536], ob2[65536];
static VisorObjectView view;
static int cur = -1;
static char key[64];
static uint8_t val[1024];
static size_t vlen;

static void hexb(const uint8_t *b, size_t n) { for (size_t i = 0; i < n; i++) printf("%02x", b[i]); }

static void target(uint64_t t, SemanticId *id) {
    if (t < 1000) *id = g.objects[t].id;
    else memset(id->bytes, (int)((t - 1000) & 255), 32);
}

int main(void) {
    static char line[16384];
    unsigned long ln = 0;
    while (fgets(line, sizeof line, stdin)) {
        ln++;
        char c = line[0];
        if (c == '#' || c == '\n' || c == '\0') continue;
        uint64_t a[64];
        int na = 0;
        memset(a, 0, sizeof a);
        char *p = line + 1;
        while (na < 64) {
            while (*p == ' ') p++;
            if (*p < '0' || *p > '9') break;
            a[na++] = strtoull(p, &p, 10);
        }
        OmegaObject *o = cur >= 0 ? &g.objects[cur] : NULL;
        SemanticId id;
        switch (c) {
        case 'R': memset(&g, 0, sizeof g); cur = -1; vlen = 0; key[0] = 0; break;
        case 'O': {
            OmegaObject *n = omega_graph_add_object(&g, (SemanticKind)a[0]);
            if (!n) printf("L%lu O full\n", ln); else cur = (int)(n - g.objects);
            break;
        }
        case 'L': if (o) o->payload_len = (uint32_t)a[0]; break;
        case 'B': if (o) o->payload[a[0]] = (uint8_t)a[1]; break;
        case 'E': if (o) for (uint64_t i = 0; i < a[1]; i++) o->payload[a[0] + i] = (uint8_t)(a[2] >> (8 * (a[1] - 1 - i))); break;
        case 'W': if (o) for (uint64_t i = 0; i < a[1]; i++) o->payload[a[0] + i] = (uint8_t)(a[2] >> (8 * i)); break;
        case 'F': if (o) memcpy(o->payload + a[0], g.objects[a[1]].id.bytes, 32); break;
        case 'X': if (o) memset(o->payload + a[0], (int)a[1], 32); break;
        case 'T': if (o && omega_object_add_relation(o, (RelationKind)a[0], &g.objects[a[1]].id) != 0) printf("L%lu T full\n", ln); break;
        case 'Y': memset(id.bytes, (int)a[1], 32);
            if (o && omega_object_add_relation(o, (RelationKind)a[0], &id) != 0) printf("L%lu T full\n", ln);
            break;
        case 'I': if (o && omega_compute_semantic_id(o) != 0) printf("L%lu I rc=-1\n", ln); break;
        case 'K': for (int i = 0; i < na && i < 63; i++) key[i] = (char)a[i]; key[na < 63 ? na : 63] = 0; break;
        case 'V': for (int i = 0; i < na && vlen < sizeof val; i++) val[vlen++] = (uint8_t)a[i]; break;
        case 'G': for (uint64_t i = 0; i < a[0] && vlen < sizeof val; i++) val[vlen++] = (uint8_t)(a[1] + i * a[2]); break;
        case 'A':
            if (o && omega_object_add_attribute(o, key, val, (uint16_t)vlen) != 0) printf("L%lu A full\n", ln);
            vlen = 0;
            break;
        case 'Q':
            if (o && omega_object_add_constraint(o, (ConstraintKind)a[0], val, (uint16_t)vlen) != 0) printf("L%lu Q full\n", ln);
            vlen = 0;
            break;
        case 'P':
            if (!o) break;
            switch (a[0]) {
            case 0: o->attr_count = (uint16_t)a[2]; break;
            case 1: o->rel_count = (uint16_t)a[2]; break;
            case 2: o->const_count = (uint16_t)a[2]; break;
            case 3: o->attributes[a[1]].val_len = (uint16_t)a[2]; break;
            case 4: o->constraints[a[1]].payload_len = (uint16_t)a[2]; break;
            case 5: o->has_id = a[2] != 0; break;
            }
            break;
        case 'S': {
            target(a[0], &id);
            int rc = visor_semantic_inspect(&g, &id, &view);
            printf("L%lu S %" PRIu64 " rc=%d\n", ln, a[0], rc);
            if (rc == -1) break;
            int t = visor_semantic_format_text(&view, ob, sizeof ob);
            if (t >= 0) fputs(ob, stdout);
            int j = visor_semantic_format_json(&view, ob2, sizeof ob2);
            if (j >= 0) printf("%s\n", ob2);
            printf("L%lu T=%d J=%d", ln, t, j);
            if (t >= 0 && j >= 0)
                printf(" B=%d %d %d %d %d %d %d", visor_semantic_format_text(&view, ob, 0),
                       visor_semantic_format_json(&view, ob, 0), visor_semantic_format_text(&view, ob, (size_t)t),
                       visor_semantic_format_text(&view, ob, (size_t)t + 1),
                       visor_semantic_format_json(&view, ob, (size_t)j),
                       visor_semantic_format_json(&view, ob, (size_t)j + 1),
                       visor_semantic_format_text(&view, ob, 1));
            printf("\n");
            break;
        }
        case 'U': {
            SemanticId t;
            char txt[VISOR_SEM_TYPE_TEXT];
            target(a[0], &id);
            int rc = visor_semantic_type_of(&g, &id, &t, txt, sizeof txt);
            printf("L%lu U %" PRIu64 " rc=%d", ln, a[0], rc);
            if (rc == 0) { printf(" id="); hexb(t.bytes, 32); printf(" text=%s", txt); }
            printf("\n");
            break;
        }
        case 'H': {
            SemanticId op, ops[4];
            size_t n = 0;
            target(a[0], &id);
            int rc = visor_semantic_apply_parts(&g, &id, &op, ops, &n);
            printf("L%lu H %" PRIu64 " rc=%d", ln, a[0], rc);
            if (rc == 0) {
                printf(" op="); hexb(op.bytes, 32); printf(" n=%zu", n);
                for (size_t i = 0; i < n; i++) { printf(" "); hexb(ops[i].bytes, 32); }
            }
            printf("\n");
            break;
        }
        case 'Z': {
            uint64_t v = 0;
            target(a[0], &id);
            int rc = visor_semantic_value_u64(&g, &id, &v);
            printf("L%lu Z %" PRIu64 " rc=%d", ln, a[0], rc);
            if (rc == 0) printf(" v=%" PRIu64, v);
            printf("\n");
            break;
        }
        case 'J': {
            uint64_t v = 0;
            target(a[0], &id);
            int rc = visor_semantic_eval_u64(&g, &id, &v);
            printf("L%lu J %" PRIu64 " rc=%d", ln, a[0], rc);
            if (rc == 0) printf(" v=%" PRIu64, v);
            printf("\n");
            break;
        }
        case 'M': {
            size_t n = a[1] ? (size_t)a[1] : sizeof ob;
            target(a[0], &id);
            int rc = visor_semantic_graph_text(&g, &id, ob, n);
            printf("L%lu M %" PRIu64 " %" PRIu64 " rc=%d\n", ln, a[0], a[1], rc);
            if (rc >= 0) fputs(ob, stdout);
            break;
        }
        case 'C': {
            const char *s = "?";
            unsigned x = (unsigned)a[1];
            switch (a[0]) {
            case 0: s = visor_semantic_opcode_name(x); break;
            case 1: s = visor_semantic_overflow_name(x); break;
            case 2: s = visor_semantic_relation_name(x); break;
            case 3: s = visor_semantic_constraint_name(x); break;
            case 4: s = visor_semantic_shape_name((VisorShape)x); break;
            }
            printf("L%lu C %" PRIu64 " %u %s\n", ln, a[0], x, s);
            break;
        }
        default: printf("L%lu ? %c\n", ln, c); break;
        }
    }
    return 0;
}
