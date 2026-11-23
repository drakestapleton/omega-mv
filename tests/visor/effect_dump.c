/* SPDX-License-Identifier: Apache-2.0
 * effect_dump.c -- REFERENCE-ONLY C side of tests/visor/effect_parity.sh. It is committed once,
 * used to generate tests/visor/effect_golden/ from the C at main commit 3f2c70dc5, and removed
 * from the tree in the next commit (the MANIFEST records its blob and sha256). Not built by any
 * make target.
 *
 * Reads a corpus of one-letter graph commands on stdin (see tests/visor/effect_parity.sh), builds
 * the graph with the C OmegaGraph store and prints what visor_effect_request_build, _classify,
 * _format_text, _format_json and visor_world_unattached + visor_world_format_* return.
 * tests/visor/effect_dump.om prints the same lines from the OM-2 lane.
 */
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "omega_canonical.h"
#include "omega_core.h"
#include "visor_effect_request.h"
#include "visor_world.h"

static OmegaGraph g;
static char ob[65536];
static int cur = -1;

static void hexid(const uint8_t *b) {
    for (int i = 0; i < 32; i++) printf("%02x", b[i]);
}

static OmegaObject *curobj(void) { return cur >= 0 ? &g.objects[cur] : NULL; }

int main(void) {
    static char line[8192];
    unsigned long ln = 0;
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
        OmegaObject *o = curobj();
        switch (c) {
        case 'R':
            memset(&g, 0, sizeof g);
            cur = -1;
            break;
        case 'O': {
            OmegaObject *n = omega_graph_add_object(&g, (SemanticKind)a[0]);
            if (!n) printf("L%lu O full\n", ln);
            else cur = (int)(n - g.objects);
            break;
        }
        case 'L': if (o) o->payload_len = (uint32_t)a[0]; break;
        case 'B': if (o) o->payload[a[0]] = (uint8_t)a[1]; break;
        case 'E':
            if (o) for (uint64_t i = 0; i < a[1]; i++)
                o->payload[a[0] + i] = (uint8_t)(a[2] >> (8 * (a[1] - 1 - i)));
            break;
        case 'W':
            if (o) for (uint64_t i = 0; i < a[1]; i++) o->payload[a[0] + i] = (uint8_t)(a[2] >> (8 * i));
            break;
        case 'F': if (o) memcpy(o->payload + a[0], g.objects[a[1]].id.bytes, 32); break;
        case 'X': if (o) memset(o->payload + a[0], (int)a[1], 32); break;
        case 'T':
            if (o && omega_object_add_relation(o, (RelationKind)a[0], &g.objects[a[1]].id) != 0)
                printf("L%lu T full\n", ln);
            break;
        case 'Y': {
            SemanticId id;
            memset(id.bytes, (int)a[1], 32);
            if (o && omega_object_add_relation(o, (RelationKind)a[0], &id) != 0) printf("L%lu T full\n", ln);
            break;
        }
        case 'I':
            if (o && omega_compute_semantic_id(o) != 0) printf("L%lu I rc=-1\n", ln);
            break;
        case 'D':
            printf("L%lu D %" PRIu64 " kind=%u has=%d id=", ln, a[0], (unsigned)g.objects[a[0]].kind,
                   g.objects[a[0]].has_id ? 1 : 0);
            hexid(g.objects[a[0]].id.bytes);
            printf("\n");
            break;
        case 'C': {
            bool needs = false;
            int rc = visor_effect_request_classify(&g, &g.objects[a[0]].id, &needs);
            printf("L%lu C %" PRIu64 " rc=%d needs=%d\n", ln, a[0], rc, needs ? 1 : 0);
            break;
        }
        case 'M': {
            VisorEffectRequest r;
            int rc = visor_effect_request_build(&g, &g.objects[a[0]].id, &r);
            printf("L%lu M %" PRIu64 " rc=%d\n", ln, a[0], rc);
            if (rc == 0) {
                if (visor_effect_request_format_text(&r, ob, sizeof ob) == 0) printf("%s", ob);
                else printf("L%lu text -1\n", ln);
                if (visor_effect_request_format_json(&r, ob, sizeof ob) == 0) printf("%s\n", ob);
                else printf("L%lu json -1\n", ln);
            }
            break;
        }
        case 'G': {
            VisorWorldView v;
            visor_world_unattached(&v);
            printf("L%lu G\n", ln);
            if (visor_world_format_text(&v, ob, sizeof ob) >= 0) printf("%s", ob);
            else printf("L%lu text -1\n", ln);
            if (visor_world_format_json(&v, ob, sizeof ob) >= 0) printf("%s\n", ob);
            else printf("L%lu json -1\n", ln);
            break;
        }
        default:
            printf("L%lu ? %c\n", ln, c);
            break;
        }
    }
    return 0;
}
