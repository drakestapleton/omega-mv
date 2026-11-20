/* SPDX-License-Identifier: Apache-2.0 */
#include "osc_ir.h"
#include "omega_native.h"

#include <errno.h>
#include <stdio.h>
#include <sys/mman.h>

static unsigned map_attempts;

/* Standalone IR validation used to need only the caller's allocator. */
void *__wrap_mmap(void *addr, size_t len, int prot, int flags, int fd, off_t offset)
{
    (void)addr; (void)len; (void)prot; (void)flags; (void)fd; (void)offset;
    map_attempts++;
    errno = ENOMEM;
    return MAP_FAILED;
}

int main(void)
{
    static OscUnit unit;
    OscFunc *f = &unit.funcs[0];
    unit.nfuncs = 1;
    f->ninsns = f->nblocks = f->blocks[0].count = 1;
    f->insns[0].op = OSC_I_RET;
    f->insns[0].a = -1;
    char error[128] = {0};
    if (osc_ir_validate(&unit, error, sizeof error) || map_attempts) {
        fprintf(stderr, "standalone validation: %s, mmap attempts %u\n", error, map_attempts);
        return 1;
    }

    /* The scratch arrays have capacity for 512 blocks. Only block 0 is active. */
    static uint64_t source[24576], dest[24576];
    uint32_t blocks[1024] = {0};
    uint64_t result = 42;
    int16_t tags[] = {0, 1};
    uint32_t status = omega2_osc_layout_blocks(&result, tags, 2, source, 24576, dest, 24576, blocks, 1024, 1);
    if (status != 3 || result != 42 || blocks[1] || blocks[3]) {
        fprintf(stderr, "inactive block tag: status %u, block counts %u %u\n", status, blocks[1], blocks[3]);
        return 1;
    }
    puts("OSC_FLOW_PASS standalone validation without mmap; inactive block refused before mutation");
    return 0;
}
