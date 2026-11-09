/* linear.c -- REFERENCE TWIN ONLY (gcc oracle) of linear.om: omega-bridge pytorch/kernels/linear.om
   (o[M,N] = c[N] + a[M,K] @ w[N,K]^T, each sum in double from the bias, rounded once to float) at
   M 64, K 256, N 256, with the same inputs, 40 passes and the same checksum line. */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#define M 64
#define K 256
#define N 256
static float c[N], a[M * K], w[N * K], o[M * N];
static double lindot(uint64_t i, uint64_t j) {
    double s = (double)c[j];
    uint64_t ia = i * K, iw = j * K;
    for (uint64_t k = 0; k < K; k++) { s += (double)a[ia] * (double)w[iw]; ia++; iw++; }
    return s;
}
static void linear(void) {
    for (uint64_t i = 0; i < M; i++) for (uint64_t j = 0; j < N; j++) o[i * N + j] = (float)lindot(i, j);
}
int main(void) {
    for (uint64_t i = 0; i < N; i++) c[i] = (float)((int64_t)((i * 5) % 11) - 5) / 4.0f;
    for (uint64_t i = 0; i < M * K; i++) a[i] = (float)((int64_t)((i * 7) % 13) - 6) / 8.0f;
    for (uint64_t i = 0; i < N * K; i++) w[i] = (float)((int64_t)((i * 3) % 17) - 8) / 16.0f;
    uint64_t s = 0;
    for (uint64_t r = 0; r < 40; r++) {
        c[r % 256] += 1.0f;
        linear();
        for (uint64_t i = 0; i < M * N; i++) { uint32_t b; memcpy(&b, &o[i], 4); s += (uint64_t)b * (i + 1); }
    }
    printf("%llu\n", (unsigned long long)s);
    return 0;
}
