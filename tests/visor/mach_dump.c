/* SPDX-License-Identifier: Apache-2.0
 * mach_dump.c -- reference-only C dumper for tests/visor/mach_parity.sh: reads the corpus of
 * one-letter machine-graph and query commands on stdin and prints what the C machine lane
 * (src/visor/visor_machine.c at main 3f2c70dc5, with the Blackwell realize object linked as in
 * the omega binary) returns. It generates the goldens once; it is committed with them and
 * removed from the tree in the next commit. */
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "visor_machine.h"

static OmegaMachineGraph mg;
static VisorMachineView v;
static VisorHostFacts f;
static char buf[65536];

static void show(unsigned long ln, const char *w, int rc) {
    printf("L%lu %s rc=%d\n", ln, w, rc);
    int t = visor_machine_format_text(&v, buf, sizeof buf);
    if (t >= 0) fputs(buf, stdout);
    printf("L%lu T=%d\n", ln, t);
    int j = visor_machine_format_json(&v, buf, sizeof buf);
    if (j >= 0) printf("%s\n", buf);
    printf("L%lu J=%d", ln, j);
    if (t >= 0 && j >= 0)
        printf(" B=%d %d %d %d %d %d %d", visor_machine_format_text(&v, buf, 0), visor_machine_format_json(&v, buf, 0),
               visor_machine_format_text(&v, buf, (size_t)t), visor_machine_format_text(&v, buf, (size_t)t + 1),
               visor_machine_format_json(&v, buf, (size_t)j), visor_machine_format_json(&v, buf, (size_t)j + 1),
               visor_machine_format_text(&v, buf, 1));
    printf("\n");
}

static void fact(char *dst, size_t cap, const uint64_t *a, int na) {
    size_t k = strlen(dst);
    for (int i = 0; i < na && k + 1 < cap; i++) dst[k++] = (char)a[i];
    dst[k] = 0;
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
        switch (c) {
        case 'B': {
            int rc = a[0] ? omega_machine_build_qemu_virt(&mg) : omega_machine_build_dgx_spark(&mg);
            if (rc != 0) printf("L%lu B rc=%d\n", ln, rc);
            break;
        }
        case 'F':
            switch (a[0]) {
            case 0: mg.pipeline.issue_width = (uint32_t)a[1]; break;
            case 1: mg.pipeline.max_in_flight = (uint32_t)a[1]; break;
            case 2: mg.pipeline.out_of_order = a[1] != 0; break;
            case 3: mg.pipeline.unit_count = (size_t)a[1]; break;
            case 4: mg.registers.gpr_count = (uint32_t)a[1]; break;
            case 5: mg.registers.gpr_width_bits = (uint32_t)a[1]; break;
            case 6: mg.registers.vector_count = (uint32_t)a[1]; break;
            case 7: mg.registers.vector_width_bits = (uint32_t)a[1]; break;
            case 8: mg.cache_count = (size_t)a[1]; break;
            case 9: mg.dram_base = a[1]; break;
            case 10: mg.dram_size = a[1]; break;
            case 11: mg.is_physics_authorized = a[1] != 0; break;
            case 12: mg.target_profile = (uint8_t)a[1]; break;
            }
            break;
        case 'U': {
            MachineComputeUnit *u = &mg.pipeline.units[a[0]];
            switch (a[1]) {
            case 0: u->type = (ComputeUnitType)a[2]; break;
            case 1: u->count = (uint32_t)a[2]; break;
            case 2: u->latency_cycles = (uint32_t)a[2]; break;
            case 3: u->throughput_per_cycle = (uint32_t)a[2]; break;
            }
            break;
        }
        case 'C': {
            MachineCacheLevel *k = &mg.caches[a[0]];
            switch (a[1]) {
            case 0: k->level = (uint32_t)a[2]; break;
            case 1: k->is_instruction = a[2] != 0; break;
            case 2: k->size_bytes = a[2]; break;
            case 3: k->line_size_bytes = (uint32_t)a[2]; break;
            case 4: k->associativity = (uint32_t)a[2]; break;
            case 5: k->latency_cycles = (uint32_t)a[2]; break;
            }
            break;
        }
        case 'S': mg.physics_receipt_seal[a[0]] = (uint8_t)a[1]; break;
        case 'N':
            memset(mg.name, 0, sizeof mg.name);
            for (int i = 0; i < na && i < 63; i++) mg.name[i] = (char)a[i];
            break;
        case 'K': if (omega_machine_compute_id(&mg) != 0) printf("L%lu K rc=-1\n", ln); break;
        case 'V': show(ln, "V", visor_machine_view(&mg, &v)); break;
        case 'A':
            if (a[0] == 0) fact(f.uname_machine, sizeof f.uname_machine, a + 1, na - 1);
            if (a[0] == 1) fact(f.dmi_product, sizeof f.dmi_product, a + 1, na - 1);
            if (a[0] == 2) fact(f.cpu_parts, sizeof f.cpu_parts, a + 1, na - 1);
            break;
        case 'Z': memset(&f, 0, sizeof f); break;
        case 'P': show(ln, "P", visor_machine_from_facts(&f, &mg, &v)); break;
        case 'Q': show(ln, "Q", visor_machine_current(&mg, &v)); break;
        case 'H': {
            int rc = visor_machine_host_facts(&f);
            printf("L%lu H rc=%d u=%s d=%s c=%s\n", ln, rc, f.uname_machine, f.dmi_product, f.cpu_parts);
            break;
        }
        case 'X': printf("L%lu X %" PRIu64 " %s\n", ln, a[0], visor_machine_unit_name((ComputeUnitType)a[0])); break;
        case 'W': {
            SemanticId id;
            int rc = visor_machine_blackwell_id(&id);
            printf("L%lu W rc=%d", ln, rc);
            if (rc == 0) { printf(" id="); for (int i = 0; i < 32; i++) printf("%02x", id.bytes[i]); }
            printf("\n");
            break;
        }
        default: printf("L%lu ? %c\n", ln, c); break;
        }
    }
    return 0;
}
