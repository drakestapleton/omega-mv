// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#pragma once
// Column-order FP8 reference used by the device check in time_fp8gemv.cpp.
// The decode and the bound are the ones check.om checks: fnuz / allow / order.
// FNUZ NaN is only 0x80. 0xFF is -240. No epilogue and no bf16: the device
// arms that this compares against leave those flags clear.

#include <cstdint>
#include <cstring>
#include <cmath>

inline uint32_t f32_bits(float x) {
  uint32_t u = 0;
  std::memcpy(&u, &x, sizeof(u));
  return u;
}

inline float bits_f32(uint32_t u) {
  float x = 0.f;
  std::memcpy(&x, &u, sizeof(x));
  return x;
}

// check.om fnuzden, then the normal path (exp + 119, mantissa in bits 22:20).
inline uint32_t fnuz_bits(uint8_t b) {
  if (b == 0x80) return 0x7fc00000u;
  uint32_t sign = static_cast<uint32_t>(b & 0x80u) << 24;
  uint32_t mag = b & 0x7fu;
  if (mag == 0) return sign;
  uint32_t exp = mag >> 3;
  uint32_t mant = mag & 7u;
  if (exp == 0) {
    static const uint32_t den[8] = {
        0,           0x3a800000u, 0x3b000000u, 0x3b400000u,
        0x3b800000u, 0x3ba00000u, 0x3bc00000u, 0x3be00000u};
    return sign | den[mant];
  }
  return sign | ((exp + 119u) << 23) | (mant << 20);
}

// check.om i2f. n has to fit in 24 bits, which K+1 does for the listed shapes.
inline uint32_t i2f_bits(uint32_t n) {
  if (n == 0) return 0;
  uint32_t exp = 0;
  uint32_t t = n;
  while (t >= 2u && exp < 24u) {
    t >>= 1;
    exp += 1;
  }
  uint32_t frac = n - (1u << exp);
  uint32_t mant = frac << (23u - exp);
  return ((exp + 127u) << 23) | mant;
}

struct PlainRow {
  uint32_t bits;
  uint32_t sumabs;
};

// s = fma(decode(w[c]), x[c], s) for c in 0..k-1, then one scale multiply.
// sumabs is the f32 sum of |product| before that scale, which is what allow()
// multiplies by |scale|.
inline PlainRow plain_row(const uint8_t* w, const uint32_t* x, uint32_t k,
                          uint32_t scale) {
  float s = 0.f;
  float ab = 0.f;
  for (uint32_t c = 0; c < k; ++c) {
    float wv = bits_f32(fnuz_bits(w[c]));
    float xv = bits_f32(x[c]);
    float prod = std::fmaf(wv, xv, 0.f);
    ab = std::fmaf(ab, 1.f, bits_f32(f32_bits(prod) & 0x7fffffffu));
    s = std::fmaf(wv, xv, s);
  }
  s = std::fmaf(s, bits_f32(scale), 0.f);
  PlainRow row;
  row.bits = f32_bits(s);
  row.sumabs = f32_bits(ab);
  return row;
}

// allow(), then the 8 ulps of |got|+|plain| that order() adds. No fuse.
inline uint32_t tolerance_bits(uint32_t sumabs, uint32_t k, uint32_t scale,
                               uint32_t got, uint32_t plain) {
  float b = bits_f32(sumabs);
  b = std::fmaf(b, bits_f32(i2f_bits(k + 1u)), 0.f);
  b = std::fmaf(b, bits_f32(0x34000000u), 0.f);
  b = std::fmaf(b, bits_f32(scale & 0x7fffffffu), 0.f);
  b = std::fmaf(b, bits_f32(0x40000000u), 0.f);
  float span = std::fmaf(bits_f32(got & 0x7fffffffu), 1.f,
                         bits_f32(plain & 0x7fffffffu));
  float slack = std::fmaf(span, bits_f32(0x35800000u), 0.f);
  b = std::fmaf(b, 1.f, slack);
  return f32_bits(b);
}

// Non-finite results must be the same bits. Finite results must sit inside
// tolerance_bits. A NaN bound does not come out of the expression above for
// a finite sumabs.
inline bool within_plain(uint32_t got, uint32_t plain, uint32_t bound) {
  uint32_t ga = got & 0x7fffffffu;
  uint32_t pa = plain & 0x7fffffffu;
  if (ga >= 0x7f800000u || pa >= 0x7f800000u) return got == plain;
  uint32_t diff = f32_bits(std::fmaf(bits_f32(got), 1.f,
                                     bits_f32(plain ^ 0x80000000u))) &
                  0x7fffffffu;
  return !(bits_f32(diff) > bits_f32(bound));
}
