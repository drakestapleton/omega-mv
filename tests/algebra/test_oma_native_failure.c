/* Exercise consumer behavior when the native runtime refuses entry. */
#include "algebra/oma_pack.h"
#include "omega_native.h"
#include <string.h>

uint32_t __wrap_omega2_oma_om_block_deserialize(uint64_t *result,
    const uint8_t *src, uint64_t len, uint64_t *dst, uint64_t dst_len) {
    (void)result; (void)src; (void)len; (void)dst; (void)dst_len;
    return OMEGA_REENTRY;
}

uint32_t __wrap_omega2_oma_om_pack_dense_byte(uint64_t *result,
    const uint8_t *src, uint64_t len, uint64_t start, uint64_t n) {
    (void)src; (void)len; (void)n;
    if (start) return OMEGA_NO_STACK;
    *result = 0;
    return OMEGA_OK;
}

int main(void) {
    uint8_t serialized[OMA_BLOCK_BYTES] = {0};
    oma_block out = {123, 456};
    int8_t trits[6] = {0};
    uint8_t packed[2] = {12, 34};
    size_t size = 42;
    if (oma_block_deserialize(serialized, &out) != OMA_E_NATIVE ||
        out.pos != 123 || out.neg != 456) return 1;
    if (oma_pack_dense(trits, 6, packed, 2, &size) != OMA_E_NATIVE ||
        packed[0] != 12 || packed[1] != 34 || size != 42) return 2;
    return 0;
}
