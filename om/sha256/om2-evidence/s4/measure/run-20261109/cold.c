/* Throwaway cold-call driver (not delivered code), L835 run 300: times the first sha256_hash call
 * after process start on N bytes, prints "cold N ns hex". Usage: cold N */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include "sha256.h"
static double now_ns(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (double)t.tv_sec*1e9 + (double)t.tv_nsec; }
int main(int argc, char **argv) {
    size_t n = argc > 1 ? strtoul(argv[1], 0, 10) : 64;
    uint8_t *b = malloc(n ? n : 1), d[SHA256_DIGEST_SIZE];
    for (size_t i = 0; i < n; i++) b[i] = (uint8_t)(i*31u + 7u);
    double t0 = now_ns(); sha256_hash(b, n, d); double t = now_ns() - t0;
    printf("cold %zu %.1f ", n, t);
    for (int i = 0; i < SHA256_DIGEST_SIZE; i++) printf("%02x", d[i]);
    printf("\n");
    return 0;
}
