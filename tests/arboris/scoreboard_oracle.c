/* SPDX-License-Identifier: Apache-2.0
 * Stdin adapter for the repository's independent C scoreboard oracle.
 * Host test only. The program has no device or dispatch interface. */
#include "omega_bw_hazard.h"
#include "omega_api_decl.h"
#include <stdint.h>
#include <stdio.h>

int main(void) {
    static uint8_t code[32768];
    static uint64_t wire[3203584];
    uint64_t result;
    OmegaBwHazardReport report;
    size_t size = fread(code, 1, sizeof code, stdin);
    if (size == 0 || size == sizeof code || ferror(stdin)) return 2;
    if (omega_bw_hazard_check(code, size, &report) != 0) return 2;
    if (omega2_hz_chk(&result, code, sizeof code, size, wire, 3203584) != 0 ||
        result != 0 || wire[0] != report.insns || wire[1] != report.reachable ||
        wire[2] != report.count) {
        fputs("OM-2 and C scoreboards disagree\n", stderr);
        return 2;
    }
    printf("scoreboard: %zu instructions, %zu reachable, %zu hazards\n",
           report.insns, report.reachable, report.count);
    return report.count != 0;
}
