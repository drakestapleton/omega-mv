/* SPDX-License-Identifier: Apache-2.0
 * Stdin adapter for the repository's independent C scoreboard oracle.
 * Host test only. The program has no device or dispatch interface. */
#include "omega_bw_hazard.h"
#include <stdint.h>
#include <stdio.h>

int main(void) {
    uint8_t code[16384 + 1];
    OmegaBwHazardReport report;
    size_t size = fread(code, 1, sizeof code, stdin);
    if (size == 0 || size == sizeof code || ferror(stdin)) return 2;
    if (omega_bw_hazard_check(code, size, &report) != 0) return 2;
    printf("scoreboard: %zu instructions, %zu reachable, %zu hazards\n",
           report.insns, report.reachable, report.count);
    return report.count != 0;
}
