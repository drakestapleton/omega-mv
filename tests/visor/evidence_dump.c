/* SPDX-License-Identifier: Apache-2.0
 * evidence_dump.c -- REFERENCE-ONLY C dumper for tests/visor/evidence_parity.sh. It links the C
 * Visor evidence lane at main commit 3f2c70dc5 (src/visor/visor_evidence.c) and prints, for every
 * command of a corpus on stdin, what the OM-2 dumper tests/visor/evidence_dump.om prints from the
 * shipped src/visor/visor_evidence.om. Committed once with the goldens it generated
 * (tests/visor/evidence_golden), then removed from the tree. Run in the directory that holds the
 * corpus trees (evidence_parity.sh builds them), so every path is relative.
 * Commands (one per line; tree lines F Z B N H K D of the corpus are skipped here):
 *   S root        visor_evidence_scan
 *   I root hex64  visor_evidence_for_id
 *   L path        visor_evidence_load, the record shown as a one-item view when it loads
 *   M cap         visor_evidence_set_max_files; prints the previous cap
 * Each view prints "== <cmd> rc=R t=T j=J", the text, "--json", the JSON, then the lengths of
 * both renderings at the exact size, one more, 1 and 0 bytes. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "omega_canonical.h"
#include "visor_evidence.h"

static VisorEvidenceView V;
static char tb[65536], jb[65536], small[65536];

static void show(char c, int rc) {
    int t = visor_evidence_format_text(&V, tb, sizeof tb);
    int j = visor_evidence_format_json(&V, jb, sizeof jb);
    printf("== %c rc=%d t=%d j=%d\n", c, rc, t, j);
    if (t > 0) fputs(tb, stdout);
    printf("--json\n");
    if (j > 0) fputs(jb, stdout);
    printf("\n");
    if (t > 0)
        printf("tn: %d %d %d %d\n", visor_evidence_format_text(&V, small, (size_t)t),
               visor_evidence_format_text(&V, small, (size_t)t + 1), visor_evidence_format_text(&V, small, 1),
               visor_evidence_format_text(&V, small, 0));
    if (j > 0)
        printf("jn: %d %d %d %d\n", visor_evidence_format_json(&V, small, (size_t)j),
               visor_evidence_format_json(&V, small, (size_t)j + 1), visor_evidence_format_json(&V, small, 1),
               visor_evidence_format_json(&V, small, 0));
}

int main(void) {
    static char line[8192];
    static VisorEvidenceRecord rec;
    while (fgets(line, sizeof line, stdin)) {
        size_t n = strlen(line);
        while (n && (line[n - 1] == '\n' || line[n - 1] == '\r')) line[--n] = 0;
        if (n < 1 || line[0] == '#') continue;
        char c = line[0];
        char *arg = n > 2 ? line + 2 : line + n;
        int rc;
        if (c == 'S') {
            rc = visor_evidence_scan(arg, &V);
            show(c, rc);
        } else if (c == 'I') {
            char *sp = strrchr(arg, ' ');
            SemanticId id;
            if (!sp || omega_parse_hex_semantic_id(sp + 1, &id) != 0) { printf("== I badid\n"); continue; }
            *sp = 0;
            rc = visor_evidence_for_id(arg, &id, &V);
            show(c, rc);
        } else if (c == 'L') {
            rc = visor_evidence_load(arg, &rec);
            memset(&V, 0, sizeof V);
            if (rc == 0) { V.matched++; V.items[V.count++] = rec; }
            show(c, rc);
        } else if (c == 'M') {
            printf("M %zu\n", visor_evidence_set_max_files((size_t)strtoull(arg, NULL, 10)));
        }
        fflush(stdout);
    }
    return 0;
}
