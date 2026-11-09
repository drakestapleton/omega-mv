/* Throwaway measurement driver (not delivered code), L835 run 300. Same cases and timing as
 * om/sha256/om2-evidence/s4/measure/bench.c; adds: every timed call's full digest is compared
 * (outside the timed window) with the case's reference digest, and the full hex is printed so the
 * harness compares it with sha256sum. Exit 1 if any timed digest differs. Usage: bench2 REPS */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "sha256.h"

static double now_ns(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (double)t.tv_sec*1e9 + (double)t.tv_nsec; }
static int cmp(const void*a,const void*b){ double x=*(const double*)a, y=*(const double*)b; return x<y?-1:(x>y); }
static void hex(const uint8_t *d) { for (int i = 0; i < SHA256_DIGEST_SIZE; i++) printf("%02x", d[i]); }

static const size_t sizes[] = {0,1,31,32,55,56,63,64,65,127,128,1024,4096,65536,1048576,16777216};
static const size_t chunk[] = {1,7,64,4096};

int main(int argc, char** argv) {
    int reps = argc > 1 ? atoi(argv[1]) : 31;
    size_t bigcap = 1u<<24;
    uint8_t *big = malloc(bigcap);
    for (size_t i = 0; i < bigcap; i++) big[i] = (uint8_t)(i*31u + 7u);
    uint8_t d[SHA256_DIGEST_SIZE], ref[SHA256_DIGEST_SIZE];
    int bad = 0;
    double *v = malloc((size_t)reps * sizeof(double));
    for (unsigned s = 0; s < sizeof sizes/sizeof *sizes; s++) {
        size_t n = sizes[s];
        sha256_hash(big, n, ref);
        for (int w = 0; w < 3; w++) sha256_hash(big, n, d);
        for (int r = 0; r < reps; r++) {
            double t0 = now_ns(); sha256_hash(big, n, d); v[r] = now_ns() - t0;
            if (memcmp(d, ref, sizeof d)) bad = 1;
        }
        qsort(v, (size_t)reps, sizeof(double), cmp);
        printf("hash %zu %.1f %.1f %.1f %.1f %.1f %.1f ", n, v[0], v[reps/10], v[reps/2], v[(reps*9)/10], v[reps-1],
               v[reps/2] / (n ? (double)n : 1.0));
        hex(ref); printf("\n");
    }
    for (unsigned c = 0; c < sizeof chunk/sizeof *chunk; c++) {
        size_t cs = chunk[c], total = 1u<<20;
        sha256_ctx ctx;
        sha256_init(&ctx); for (size_t o = 0; o < total; o += cs) sha256_update(&ctx, big+o, cs); sha256_final(&ctx, ref);
        for (int w = 0; w < 3; w++) { sha256_init(&ctx); for (size_t o = 0; o < total; o += cs) sha256_update(&ctx, big+o, cs); sha256_final(&ctx, d); }
        for (int r = 0; r < reps; r++) {
            double t0 = now_ns();
            sha256_init(&ctx);
            for (size_t o = 0; o < total; o += cs) sha256_update(&ctx, big+o, cs);
            sha256_final(&ctx, d);
            v[r] = now_ns() - t0;
            if (memcmp(d, ref, sizeof d)) bad = 1;
        }
        qsort(v, (size_t)reps, sizeof(double), cmp);
        printf("stream %zu %zu %.1f %.1f %.1f %.1f %.1f ", cs, total, v[0], v[reps/10], v[reps/2], v[(reps*9)/10], v[reps-1]);
        hex(ref); printf("\n");
    }
    if (bad) fprintf(stderr, "DIGEST MISMATCH in a timed call\n");
    return bad;
}
