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

/* test_smmu_svc.c -- host test of ck_dma_unconfine's refusals (#480).
 * The service's instance table is static, so the source is included here and
 * the table is laid out directly; no SMMU register is touched, because both
 * refusals return before any command is issued. A stream held by one SMMU
 * (the abort path) needs real registers and is covered by the stage tests
 * through their mock. Host only, not hardware. */
#include "ck_test.h"
#include "../core/smmu_svc.c"

/* Platform hooks the service links against. The refusals under test reach none
 * of them; each one counts, so a refusal that touches the platform fails. */
static int platform_calls;
void ck_printf(const char *fmt, ...) { (void)fmt; }
void *ck_dma_alloc(size_t bytes, size_t align, uint64_t *phys) { (void)bytes; (void)align; (void)phys; platform_calls++; return 0; }
volatile void *ck_mmio_map(uint64_t phys, size_t len) { (void)phys; (void)len; platform_calls++; return 0; }
void ck_mb(void) { platform_calls++; }
const void *ck_acpi_find(const char sig[4]) { (void)sig; platform_calls++; return 0; }

static void hold(unsigned k, int slot, uint32_t sid)
{
    g.inst[k].state = 1;
    g.inst[k].used[slot] = 1;
    g.inst[k].sid[slot] = sid;
}

static void test_not_confined(void)
{
    memset(&g, 0, sizeof g);
    CHECK(ck_dma_unconfine(0x40) == CK_SMMU_EARG);       /* no SMMU up at all */
    hold(0, 0, 0x41);
    CHECK(ck_dma_unconfine(0x40) == CK_SMMU_EARG);       /* up, but another stream */
    CHECK(g.inst[0].used[0] == 1 && g.inst[0].sid[0] == 0x41);
    g.inst[1].state = CK_SMMU_FAILED;                    /* a failed instance holds nothing */
    g.inst[1].used[0] = 1;
    g.inst[1].sid[0] = 0x40;
    CHECK(ck_dma_unconfine(0x40) == CK_SMMU_EARG);
}

static void test_ambiguous(void)
{
    memset(&g, 0, sizeof g);
    hold(0, 2, 0x40);
    hold(1, 0, 0x40);
    int rc = ck_dma_unconfine(0x40);
    CHECK(rc == CK_SMMU_AMBIGUOUS);
    CHECK(rc != CK_SMMU_EARG && rc != 0);
    /* fail closed: both holders keep the stream confined */
    CHECK(g.inst[0].used[2] == 1 && g.inst[0].sid[2] == 0x40);
    CHECK(g.inst[1].used[0] == 1 && g.inst[1].sid[0] == 0x40);
    CHECK(ck_dma_unconfine(0x40) == CK_SMMU_AMBIGUOUS);  /* stays refused on retry */
}

int main(void)
{
    test_not_confined();
    test_ambiguous();
    CHECK(platform_calls == 0); /* refusals issue no command and map nothing */
    return ck_t_verdict("test_smmu_svc");
}
