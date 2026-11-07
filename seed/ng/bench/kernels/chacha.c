/* bench oracle: plain RFC 8439 ChaCha20 in portable C, same input as chacha.om (key=0..31, nonce=32..43, ctr=1) */
#include <stdint.h>
#include <unistd.h>
#define RL(x,n) (((x)<<(n))|((x)>>(32-(n))))
#define QR(a,b,c,d) a+=b;d^=a;d=RL(d,16);c+=d;b^=c;b=RL(b,12);a+=b;d^=a;d=RL(d,8);c+=d;b^=c;b=RL(b,7);
static uint32_t ld(const uint8_t *p) { return p[0] | (uint32_t)p[1]<<8 | (uint32_t)p[2]<<16 | (uint32_t)p[3]<<24; }
static void xorbuf(const uint8_t kn[44], uint32_t ctr, uint8_t *b, size_t n) {
    uint32_t s[16] = {0x61707865,0x3320646e,0x79622d32,0x6b206574};
    for (int i = 0; i < 8; i++) s[4+i] = ld(kn + 4*i);
    s[12] = ctr; for (int i = 0; i < 3; i++) s[13+i] = ld(kn + 32 + 4*i);
    for (size_t o = 0; o < n; o += 64) {
        uint32_t x[16]; for (int i = 0; i < 16; i++) x[i] = s[i];
        for (int i = 0; i < 10; i++) { QR(x[0],x[4],x[8],x[12]) QR(x[1],x[5],x[9],x[13]) QR(x[2],x[6],x[10],x[14]) QR(x[3],x[7],x[11],x[15])
            QR(x[0],x[5],x[10],x[15]) QR(x[1],x[6],x[11],x[12]) QR(x[2],x[7],x[8],x[13]) QR(x[3],x[4],x[9],x[14]) }
        for (int i = 0; i < 16; i++) { uint32_t v = x[i] + s[i];
            for (int j = 0; j < 4 && o + 4*i + j < n; j++) b[o + 4*i + j] ^= (uint8_t)(v >> (8*j)); }
        s[12]++;
    }
}
static uint8_t b[1048576];
int main(void) {
    uint8_t kn[44]; for (int i = 0; i < 44; i++) kn[i] = (uint8_t)i;
    for (uint64_t i = 0; i < sizeof b; i++) b[i] = (uint8_t)((i * 31 + 7) & 255);
    for (int r = 0; r < 64; r++) xorbuf(kn, 1, b, sizeof b);
    return write(1, b, sizeof b) == (ssize_t)sizeof b ? 0 : 1;
}
