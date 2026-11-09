#include <stdint.h>
#include <unistd.h>
static uint8_t src[65536], dst[65536];
int main(void) {
    for (uint64_t i = 0; i < 65536; i++) src[i] = (uint8_t)((i * 7) & 255);
    for (uint64_t r = 0; r < 8000; r++) { uint8_t k = (uint8_t)(r & 255);
        for (uint64_t i = 0; i < 65536; i++) dst[65535 - i] = src[i] ^ k; }
    return write(1, dst, 65536) == 65536 ? 0 : 1;
}
